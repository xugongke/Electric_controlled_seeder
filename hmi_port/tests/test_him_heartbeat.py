# -*- coding: utf-8 -*-
"""HIM工程 链路心跳子系统测试 (lupa, Lua 5.3, 真实 protocol.lua 全栈)。

设计(2026-09-23与用户商定):
  - 任意页面每~1s发0x22(探测兼调试串刷新), 平时不轮询0xA3
  - 连续3个周期无0x22应答 -> 掉线(LW.A.link=0+"×通信中断"), 探测继续
  - 收到0x22应答 -> 在线(link=1)并补发一次0xA3(固件升级后取新版本)

运行: python hmi_port/tests/test_him_heartbeat.py
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


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)

    def load(name):
        lua.globals().__P = (HIM / name).as_posix()
        return lua.execute('local f = assert(loadfile(__P)); return f()')

    prot = load('protocol.lua')
    lw = load('lwmap.lua')
    app = load('app.lua')
    app['wire']({'PROTOCOL': prot, 'CODEC': None, 'LW': lw})

    # 桩ENV: 记录w16/wstr, tx捕获发送帧
    lua.execute('''
__ENV = { writes = {}, txs = {} }
function __ENV.w16(a, v) __ENV.writes[a] = v end
function __ENV.w32(a, v) __ENV.writes[a] = v end
function __ENV.wstr(a, v) __ENV.writes[a] = v end
function __ENV.r16(a) return __ENV.writes[a] or 0 end
function __ENV.tx(frame) __ENV.txs[#__ENV.txs + 1] = frame end
''')
    env = lua.globals().__ENV
    app['init']({'w16': env['w16'], 'w32': env['w32'], 'wstr': env['wstr'],
                 'r16': env['r16'], 'tx': env['tx'], 'poll_ms': 200})
    lua.execute('''
function __NTX() return #__ENV.txs end
function __FNCOF(i) return string.byte(__ENV.txs[i], 2) end
function __STRHEX(a)
    local s = __ENV.writes[a]
    if type(s) ~= "string" then return nil end
    local h = {}
    for i = 1, #s do h[i] = string.format("%02X", string.byte(s, i)) end
    return table.concat(h)
end
''')

    def strhex(addr):
        return lua.globals().__STRHEX(addr)

    def tip_is(text):
        return strhex(A['tip']) == text.encode('gb2312').hex().upper()
    lua.globals().__PROT = prot

    A = lw['A']
    FNC = prot['FNC']

    def fncs():
        return [lua.globals().__FNCOF(i) for i in
                range(1, lua.globals().__NTX() + 1)]

    def feed(fnc, data=b''):
        lua.globals().__F = fnc
        lua.globals().__D = data
        env['txs'] = lua.table()              # 清空发送记录
        lua.execute('__PROT.feed_bytes(__PROT.build_frame(__F, __D))')
        return fncs()

    print('1) 装配与首探测')
    check(env['writes'][A['link']] == 0 and app['hb']['period'] == 5,
          'init: link=0(上电离线), 周期=5tick(1s)')
    for _ in range(5):
        app['tick']()
    sent = fncs()
    check(sent == [FNC['RD_DEBUG_INFO']], '第5tick发出首探测0x22: %s'
          % [hex(f) for f in sent])

    print('2) 首个应答 -> 在线 + 补发0xA3')
    sent = feed(FNC['RD_DEBUG_INFO'], b'idle')
    check(env['writes'][A['link']] == 1 and sent == [FNC['GET_SOFT_VER']],
          '0x22应答: link=1 + 补发0xA3: %s' % [hex(f) for f in sent])
    feed(FNC['GET_SOFT_VER'], b'hd3005a2 v2.0')
    check(env['writes'][A['ver']] == 'hd3005a2 v2.0', '0xA3应答更新版本显示')

    print('3) 页面转发保持')
    lua.execute('''
__PAGE = { id = 99, hits = 0 }
function __PAGE:on_frame(f) self.hits = self.hits + 1 end
''')
    page = lua.globals().__PAGE
    app['register'](page)
    app['set_screen'](99)
    feed(FNC['RD_DEBUG_INFO'], b'dbg2')
    check(page['hits'] == 1, '0x22应答仍转发当前页(主页/测试页显示不受影响)')

    print('4) 掉线判定与持续探测')
    for _ in range(30):                        # 6个周期无应答
        app['tick']()
    probes = fncs().count(FNC['RD_DEBUG_INFO'])
    check(env['writes'][A['link']] == 0, '3个周期无应答 -> 掉线: link=0')
    check(probes >= 5, '掉线期间0x22探测持续(%d次/30tick)' % probes)

    print('5) 重连恢复')
    feed(FNC['RD_DEBUG_INFO'], b'back')
    check(env['writes'][A['link']] == 1
          and FNC['GET_SOFT_VER'] in fncs(),
          '恢复在线: link=1 且再次补发0xA3')

    print('6) 在线期间不再发0xA3')
    env['txs'] = lua.table()
    for _ in range(10):
        app['tick']()
        feed(FNC['RD_DEBUG_INFO'], b'x')       # 持续应答保持在线
    check(FNC['GET_SOFT_VER'] not in fncs(),
          '在线稳定后0xA3零发送(仅开机/重连各一次)')

    print('7) register防nil截断(2026-10-08回归)')
    lua.execute('''
__PG2 = { id = 98, addrs = { nil, 7777 }, hits = 0 }
function __PG2:on_update(a) self.hits = self.hits + 1 end
''')
    app['register'](lua.globals().__PG2)
    hit2 = app['on_button'](7777)
    check(hit2 and lua.globals().__PG2['hits'] == 1,
          'addrs含nil项不再截断后续地址注册(page_task按钮无反应根因)')
    # v=2(查看AB线等功能通知值)也路由(2026-10-08: 曾被v~=1过滤丢弃)
    lua.globals().__PG2['hits'] = 0
    hit3 = app['on_button'](7777, 2)
    check(hit3 and lua.globals().__PG2['hits'] == 1,
          'on_button携带模式值2路由(查看AB线不再丢事件)')

    print()
    if FAIL:
        print('心跳子系统: %d项失败' % FAIL)
    else:
        print('心跳子系统: 全部通过 (%d项)' % PASS)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
