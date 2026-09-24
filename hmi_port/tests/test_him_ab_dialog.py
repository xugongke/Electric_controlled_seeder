# -*- coding: utf-8 -*-
"""HIM工程 AB线对话框(jobrun)集成测试 (lupa, Lua 5.3)。

覆盖 2026-09-24 重构:
  - 画面通知 LW.ABP.req(1保存/2查看) -> 开窗模式 + 发0x23采集
  - 0x23应答全局路由 -> 填 ab_cache 与 LW.AB 显示区
  - 确认(LW.ABP.confirm) -> 以对话框输入名绑定地图(#AB) + 存RW
  - 取消 -> 不保存
  - 保存不再依赖"停止时已采集过缓存"(用户报告的保存失败bug)

运行: python hmi_port/tests/test_him_ab_dialog.py
"""
import os
import pathlib
import sys

from lupa import lua53 as lupa_lua

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = pathlib.Path(ROOT, 'HIMproject', 'Project')

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


MOCK = r'''
__W = { writes = {}, rw = {}, txs = {}, pages = {}, always = {} }
__APP = {}
function __APP.register(p) __W.pages[#__W.pages + 1] = p end
function __APP.sub_always(f, h) __W.always[f] = h end
function __APP.set_always_poll(f) __W.poll = f end
function __APP.feed_frame(f)
    local h = __W.always[f.fnc]
    if h then h(f) end
end
function __W.w16(a, v) __W.writes[a] = v end
function __W.w32(a, v) __W.writes[a] = v end
function __W.wstr(a, v) __W.writes[a] = v end
function __W.r16(a) return __W.writes[a] end
function __W.rw16(a) return __W.rw[a] or 0xFFFF end
function __W.rw16w(a, v) __W.rw[a] = v end
function __W.tx(fr) __W.txs[#__W.txs + 1] = fr end
__STORE = { maps = {}, saved = {} }
function __STORE.map_save(n) __STORE.saved[n] = true return true end
function __RSTR(a) return "\ cele" end
'''


def lstr(lua, addr):
    """读Lua侧记录的字符串(转hex避免编码问题), 返回bytes。"""
    lua.globals().__A = addr
    h = lua.execute('''
local s = __W.writes[__A]
if type(s) ~= "string" then return nil end
local t = {}
for i = 1, #s do t[i] = string.format("%02X", string.byte(s, i)) end
return table.concat(t)
''')
    return bytes.fromhex(h) if h else b''


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK.replace('\\ cele', ''))
    # rstr桩: 返回预设名称
    lua.execute('function __RSTR(a) return __NAME end')
    lua.globals().__NAME = '我的AB线'

    def load(name):
        lua.globals().__P = (HIM / name).as_posix()
        return lua.execute('local f = assert(loadfile(__P)); return f()')

    prot = load('protocol.lua')
    codec = load('codec.lua')
    lw = load('lwmap.lua')
    jobrun = load('jobrun.lua')
    g = lua.globals()
    W, STORE, APP = g.__W, g.__STORE, g.__APP

    jobrun['init']({
        'APP': APP, 'PROTOCOL': prot, 'CODEC': codec, 'STORE': STORE,
        'PATHALGO': None, 'LOGGER': None, 'LW': lw,
        'w16': W['w16'], 'w32': W['w32'], 'wstr': W['wstr'],
        'now': None, 'rw16': W['rw16'], 'rw16w': W['rw16w'],
        'rstr': g.__RSTR, 'r16': W['r16'],
    })
    prot['io']['tx'] = W['tx']
    prot['on_frame'] = APP['feed_frame']

    # 一张无AB线的演示地图
    lua.execute('__STORE.maps["demo"] = { name = "demo", rows = 4, cols = 2, ab = nil }')
    jobrun['ab_hint_map'] = 'demo'
    ABP, A = lw['ABP'], lw['A']
    FNC = prot['FNC']

    def tx_fncs():
        return [g.__FNCOF(i) for i in range(1, g.__NTX() + 1)]

    lua.execute('''
function __NTX() return #__W.txs end
function __FNCOF(i) return string.byte(__W.txs[i], 2) end
''')

    def feed(fnc, data):
        g.__F = fnc
        g.__D = data
        W['txs'] = lua.table()
        lua.execute('__PROT.feed_bytes(__PROT.build_frame(__F, __D))')
        return tx_fncs()

    g.__PROT = prot

    print('1) 影子页注册与请求开窗')
    reg = [W['pages'][i] for i in range(1, len(W['pages']) + 1)]
    dlg_page = reg[-1] if reg else None
    addrs = dlg_page and [dlg_page['addrs'][i]
                           for i in range(1, len(dlg_page['addrs']) + 1)]
    check(addrs and set(int(a) for a in addrs) ==
          {int(ABP['req']), int(ABP['confirm']), int(ABP['cancel'])},
          'ABP通知地址注册到影子页')
    W['writes'][ABP['req']] = 1                     # 画面功能按钮通知: 保存
    jobrun['_ab_dlg_on_update'](ABP['req'])
    check(W['writes'][ABP['mode']] == 0 and tx_fncs() == [FNC['STORE_AB']],
          '保存模式(mode=0) + 发0x23采集: %s' % [hex(x) for x in tx_fncs()])

    print('2) 0x23应答 -> 填显示与缓存')
    lua.globals().__CODEC = codec
    lua.execute('''
function __PK(t)
    local s = __CODEC.bdpara.pack(t)
    local o = {}
    for i = 1, #s do o[i] = string.byte(s, i) end
    return o
end
''')
    bd_t = lua.table(StartN=36.4, StartE=117.0, EndBN=36.41, EndBE=117.01,
                     StartDir=0.5, CalcDir=0.6, StartState=1, CalcDirFlag=1,
                     OffLen=0, BDOffTime=100, Resv=0, CrcCheck=0)
    t = lua.globals().__PK(bd_t)
    bd = bytes(bytearray(t[i] for i in range(1, len(t) + 1)))
    feed(FNC['STORE_AB'], bd)
    check(jobrun['ab_cache'] is not None
          and lstr(lua, lw['AB']['endbn']).startswith(b'36.41'),
          'cache更新 + LW.AB显示区填充(B点纬度=%s)' % lstr(lua, lw['AB']['endbn']))

    print('3) 确认 -> 命名保存到地图 + RW')
    jobrun['_ab_dlg_on_update'](ABP['confirm'])
    m_ab = STORE['maps']['demo']['ab']
    rw_magic = W['rw'][lw['RW']['ab_magic']]
    check(m_ab is not None and m_ab['name'] == '我的AB线' and m_ab['has']
          and m_ab['a_row'] == 0 and rw_magic == 0x55AA
          and STORE['saved']['demo'],
          '地图#AB绑定(名=%s) + RW落盘(magic=0x55AA)' % m_ab['name'])

    print('4) 保存bug回归: 无缓存时确认(采集无应答场景)')
    jobrun['ab_cache'] = None
    lua.execute('__STORE.maps["demo2"] = { name = "demo2", rows = 4, cols = 2, ab = nil }')
    jobrun['ab_hint_map'] = 'demo2'
    W['writes'][ABP['req']] = 1
    jobrun['_ab_dlg_on_update'](ABP['req'])          # 开窗并发0x23
    jobrun['ab_cache'] = None                         # 模拟应答未到即确认
    jobrun['_ab_dlg_on_update'](ABP['confirm'])
    check(STORE['maps']['demo2']['ab'] is None
          and '采集无应答'.encode('gb2312') in lstr(lua, A['tip']),
          '无应答时不误存并提示(bug修复: 保存=先采集后落盘)')
    # 应答到达后再确认 -> 成功(重开窗因上次确认已清模式)
    W['writes'][ABP['req']] = 1
    jobrun['_ab_dlg_on_update'](ABP['req'])
    feed(FNC['STORE_AB'], bd)
    jobrun['_ab_dlg_on_update'](ABP['confirm'])
    check(STORE['maps']['demo2']['ab'] is not None,
          '应答到达后确认成功绑定')

    print('5) 查看模式与取消')
    W['writes'][ABP['req']] = 2
    jobrun['_ab_dlg_on_update'](ABP['req'])
    check(W['writes'][ABP['mode']] == 1, '查看模式(mode=1)')
    W['writes'][ABP['req']] = 1
    jobrun['_ab_dlg_on_update'](ABP['req'])
    jobrun['_ab_dlg_on_update'](ABP['cancel'])
    n_before = len([k for k in STORE['saved'].keys()])
    check('未保存'.encode('gb2312') in lstr(lua, A['tip']), '取消提示未保存')

    print()
    if FAIL:
        print('AB对话框: %d项失败' % FAIL)
    else:
        print('AB对话框: 全部通过 (%d项)' % PASS)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
