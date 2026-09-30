# -*- coding: utf-8 -*-
"""用户参数页(画面3)回归: 2026-09-30删pu_read加pu_reset引入的逻辑。

被测: HIMproject/Project/page_userparam.lua + codec.userpara
  1. 进页自动0x28快照(对齐QT无读按钮)
  2. pu_reset 重置默认值 = QT formconfig.cpp:187~199 (不下发)
  3. pu_write: 0x27下发+范围校验+过道打点gappoint三态持久化RW
  4. 密码对话框确认: 515516正确->PWD.ok=1+切画面4; 错误->ok=0
  5. RW非法gappoint值(3)按0=关处理

运行: python hmi_port/tests/test_him_userparam.py
"""
import os
import sys

from lupa import lua53 as lupa_lua

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = os.path.join(ROOT, 'HIMproject', 'Project')

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
        lua.globals().__P = os.path.join(HIM, name).replace('\\', '/')
        return lua.execute('local f = assert(loadfile(__P)); return f()')

    prot = load('protocol.lua')
    lw = load('lwmap.lua')
    codec = load('codec.lua')
    factory = load('page_userparam.lua')
    lua.globals().__CODEC = codec

    lua.execute(r'''
__T = { writes = {}, txs = {}, rw = {}, gotos = {} }
function __T.w16(a, v) __T.writes[a] = v end
function __T.w32(a, v) __T.writes[a] = v end
function __T.wstr(a, v) __T.writes[a] = v end
function __T.r16(a) return __T.writes[a] or 0 end
function __T.r32(a) return __T.writes[a] or 0 end
function __T.rw16(a) return __T.rw[a] end
function __T.rw16w(a, v) __T.rw[a] = v end
function __T.send(fnc, data) __T.txs[#__T.txs + 1] = { fnc = fnc, data = data } end
function __T.goto_screen(id) __T.gotos[#__T.gotos + 1] = id end
function __T.ntx() return #__T.txs end
function __T.txfnc(i) return __T.txs[i].fnc end
function __T.txfield(i, name) return __CODEC.userpara.unpack(__T.txs[i].data)[name] end
function __T.feed_user(page, fnc, lt)
    page:on_frame({ fnc = fnc, data = __CODEC.userpara.pack(lt) })
end
''')
    T = lua.globals().__T
    prot['send'] = T['send']
    PU, SCREEN = lw['PU'], lw['SCREEN']
    PWD, RW = lw['PWD'], lw['RW']
    FNC = prot['FNC']
    gotos = []

    def goto_screen(sid):
        gotos.append(sid)

    def make_page():
        return factory({'APP': {'goto_screen': goto_screen},
                        'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                        'w16': T['w16'], 'w32': T['w32'], 'wstr': T['wstr'],
                        'r16': T['r16'], 'r32': T['r32'],
                        'rw16': T['rw16'], 'rw16w': T['rw16w']})

    page = make_page()

    def lua_user(**kw):
        t = dict(DZTime=1600, HJ=70, RMP=40, AntennaType=1,
                 AntennaDistance=25, CrcCheck=0)
        # userpara布局含U8Resv, lua侧unpack会带回; pack需含
        t['U8Resv'] = 0
        t.update(kw)
        lt = lua.table()
        for k, v in t.items():
            lt[k] = v
        return lt

    def set_form(**over):
        base = dict(dztime=1600, hj=70, rmp=40, antennatype=1,
                    antennadist=25, gappoint=2)
        base.update(over)
        for k, v in base.items():
            T['w16'](PU[k], v)
        T['w32'](PU['rmp'], base['rmp'])

    ntx, txfnc, txfield = T['ntx'], T['txfnc'], T['txfield']

    print('1) 进页自动0x28快照(对齐QT无读按钮)')
    page['on_enter'](page)
    check(ntx() == 1 and txfnc(1) == FNC['GET_USER_PARA'], 'on_enter自动发0x28')

    print('2) 0x28应答回显')
    T['feed_user'](page, FNC['GET_USER_PARA'], lua_user())
    check(T['writes'][PU['dztime']] == 1600 and T['writes'][PU['hj']] == 70,
          'DZTime/HJ回显')

    print('3) pu_write: 0x27下发 + gappoint持久化RW')
    set_form(gappoint=2)
    n0 = ntx()
    page['on_update'](page, PU['write'])
    check(ntx() == n0 + 1 and txfnc(ntx()) == FNC['SET_USER_PARA'], '发出0x27')
    check(txfield(ntx(), 'DZTime') == 1600 and txfield(ntx(), 'RMP') == 40
          and txfield(ntx(), 'AntennaType') == 1, '表单值进报文')
    check(T['rw'][RW['gap_point']] == 2, '过道打点=2(间隔)写入RW掉电区')

    print('4) pu_reset: 表单恢复QT默认值(formconfig.cpp:187~199), 不下发')
    set_form(dztime=999, hj=99, rmp=9)
    n0 = ntx()
    page['on_update'](page, PU['reset'])
    defaults = dict(dztime=1500, hj=60, antennatype=0, antennadist=0,
                    gappoint=1)
    check(all(T['writes'][PU[k]] == v for k, v in defaults.items()),
          '倒种1.5s/行间距60cm/单天线/天线间距0/过道开')
    check(T['writes'][PU['rmp']] == 36, '转速36')
    check(ntx() == n0 and T['rw'][RW['gap_point']] == 2,
          '重置不发0x27且不立即改RW(仍为第3节的2, 随下次保存)')

    print('5) 范围校验: HJ低于下限拒绝下发')
    set_form(hj=5)
    n0 = ntx()
    page['on_update'](page, PU['write'])
    check(ntx() == n0, 'HJ=5<10 不发0x27')

    print('6) 密码对话框确认')
    T['w32'](lw['PF']['pass'], 515516)
    page['on_update'](page, PWD['confirm'])
    check(T['writes'][PWD['ok']] == 1 and gotos == [SCREEN['MANUPARAM']],
          '密码正确 -> PWD.ok=1 + 切画面4')
    T['w32'](lw['PF']['pass'], 123456)
    page['on_update'](page, PWD['confirm'])
    check(T['writes'][PWD['ok']] == 0 and gotos == [SCREEN['MANUPARAM']],
          '密码错误 -> PWD.ok=0 不切画面')

    print('7) RW非法gappoint按关处理')
    T['rw'][RW['gap_point']] = 3
    page['on_enter'](page)
    check(T['writes'][PU['gappoint']] == 0, 'RW=3(非法) -> 显示0=关')

    print()
    if FAIL:
        print('用户参数页: %d项失败' % FAIL)
        return 1
    print('用户参数页: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
