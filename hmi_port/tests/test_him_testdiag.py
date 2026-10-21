# -*- coding: utf-8 -*-
r"""测试诊断页(画面5)回归: 2026-10-21重设计对齐QT formtest + 自动进出测试模式。

守(用户要求: 进页面自动进测试模式/离页面自动退出, 不再点按钮):
  1) 自动进入: on_enter -> 参数链0x27 -> ACK -> 0x25 -> ACK -> 0x0E
     (对齐QT mainwindow:88切页enterTestMode=formtest.cpp构造链)
  2) 自动退出: on_leave -> 0x0F(QT mainwindow:71)
  3) 链完成前离页: 会话令牌作废回调, 不再补发0x0E
  4) 作业进行中: 禁止进入(不发0x27)
  5) 输出17路: sw9(CtrlNo9运行指示灯)一键翻转0x09(新增第17路, 对齐QT)
运行: python hmi_port/tests/test_him_testdiag.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = os.path.join(ROOT, 'HIMproject', 'Project').replace('\\', '/')

from lupa import lua53 as lupa_lua          # noqa: E402

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


HARNESS = r'''
LW   = assert(loadfile("__HIM/lwmap.lua"))()
CD   = assert(loadfile("__HIM/codec.lua"))()
PS   = assert(loadfile("__HIM/parastore.lua"))()
PAGE = assert(loadfile("__HIM/page_testdiag.lua"))
CD.init { rows = 6 }

__SENT = {}
__PROTO = {
    FNC = { GET_TEST_STATUS = 0x08, SET_USER_PARA = 0x27,
            SET_TER_PARA = 0x25, CMD_START_TEST = 0x0E,
            CMD_STOP_TEST = 0x0F, CMD_SVCTRL = 0x09 },
    send = function(fnc, payload)
        payload = payload or ""
        __SENT[#__SENT + 1] = { fnc = fnc, n = #payload,
                                hex = (payload:gsub(".", function(c)
            return string.format("%02x", string.byte(c)) end)) }
    end,
}
__APP = { sub_always = function() end, register = function() end,
          set_always_poll = function() end, cur = nil }
REG = {}
function w16(a, v) REG[a] = v end
function w32(a, v) REG[a] = v end
function wstr(a, s) LOG = s end
PS.init { APP = __APP, PROTOCOL = __PROTO, CODEC = CD, LW = LW,
          LOGGER = nil, wstr = wstr }
__JOB = { active = function() return false end }
TD = LW.TD

function FNS()
    local out = {}
    for i = 1, #__SENT do out[i] = __SENT[i].fnc end
    return out
end
function CLEAR() __SENT = {} end
function PAGE_NEW()
    local ctx = { APP = __APP, PROTOCOL = __PROTO, CODEC = CD, LW = LW,
                  w16 = w16, w32 = w32, wstr = wstr,
                  PARASTORE = PS, JOBRUN = __JOB }
    return PAGE()(ctx)
end
function ACK(fnc)
    __FR = { fnc = fnc, data = string.char(1) }
    PS.on_frame(__FR)
end
function TESTFRAME(ctrl, inp)
    return CD.teststate.pack { EncoderCnt = 11, BdCnt = 22,
        LoufeiCnt = { 0, 0, 0, 0, 0, 0 }, LouZHCnt = { 0, 0, 0, 0, 0, 0 },
        InputState = inp or 0, WarningState = 0, CtrlState = ctrl }
end
'''.replace('__HIM', HIM)


def fns(lua):
    t = lua.eval('FNS()')
    return [t[i] for i in range(1, len(t) + 1)]


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)

    print('1) 自动进入: on_enter -> 0x27 -> ACK -> 0x25 -> ACK -> 0x0E')
    page = lua.execute('return PAGE_NEW()')
    lua.execute('CLEAR()')
    page['on_enter'](page)
    check(fns(lua) == [0x27], '进页面即发参数链0x27(实有%s)' % fns(lua))
    lua.globals().__FR = {'fnc': 0x27, 'data': lua.execute(
        'return string.char(1)')}
    lua.execute('PS.on_frame(__FR)')
    check(fns(lua) == [0x27, 0x25], '0x27 ACK后发0x25')
    lua.globals().__FR = {'fnc': 0x25, 'data': lua.execute(
        'return string.char(1)')}
    lua.execute('PS.on_frame(__FR)')
    check(fns(lua) == [0x27, 0x25, 0x0E], '0x25 ACK后发0x0E进入测试(实有%s)'
          % fns(lua))

    print('2) 自动退出: on_leave -> 0x0F')
    lua.execute('CLEAR()')
    page['on_leave'](page)
    check(fns(lua) == [0x0F], '离页面即发0x0F退出测试(实有%s)' % fns(lua))

    print('3) 链完成前离页: 令牌作废, 不补发0x0E')
    lua.execute('CLEAR()')
    page['on_enter'](page)
    check(fns(lua) == [0x27], '再次进入发0x27')
    page['on_leave'](page)
    lua.execute('CLEAR()')
    lua.globals().__FR = {'fnc': 0x27, 'data': lua.execute(
        'return string.char(1)')}
    lua.execute('PS.on_frame(__FR)')
    check(fns(lua) == [0x25], '离页后0x27 ACK仍推进链(0x25)')
    lua.globals().__FR = {'fnc': 0x25, 'data': lua.execute(
        'return string.char(1)')}
    lua.execute('PS.on_frame(__FR)')
    check(fns(lua) == [0x25], '0x25 ACK后令牌失效, 不发0x0E(实有%s)' % fns(lua))

    print('4) 作业进行中禁止进入')
    lua.execute('__JOB.active = function() return true end')
    lua.execute('CLEAR()')
    page['on_enter'](page)
    check(fns(lua) == [], '作业中on_enter不发0x27(实有%s)' % fns(lua))
    lua.execute('__JOB.active = function() return false end')

    print('5) 输出17路: sw9(CtrlNo9)一键翻转0x09')
    lua.execute('CLEAR()')
    lua.globals().__F08 = {'fnc': 0x08, 'data': lua.execute(
        'return TESTFRAME(0)')}
    page['on_frame'](page, lua.globals().__F08)
    page['on_update'](page, lua.eval('TD.sw9'))
    n = lua.eval('#__SENT')
    fr = lua.eval('__SENT[%d]' % n)
    check(fr['fnc'] == 0x09 and fr['hex'] == '0900' + '0100',
          'CtrlState bit9=0 -> 翻转为1下发(实有%s %s)' % (fr['fnc'], fr['hex']))
    lua.execute('CLEAR()')
    lua.globals().__F08 = {'fnc': 0x08, 'data': lua.execute(
        'return TESTFRAME(512)')}
    page['on_frame'](page, lua.globals().__F08)
    page['on_update'](page, lua.eval('TD.sw9'))
    n = lua.eval('#__SENT')
    fr = lua.eval('__SENT[%d]' % n)
    check(fr['fnc'] == 0x09 and fr['hex'] == '0900' + '0000',
          'CtrlState bit9=1 -> 翻转为0下发(实有%s %s)' % (fr['fnc'], fr['hex']))
    # 0x08应答落TD寄存器(计数/位图)
    lua.execute('__F08.data = TESTFRAME(0)')
    page['on_frame'](page, lua.globals().__F08)
    enc = lua.eval('REG[TD.encodercnt]')
    check(enc == 11, '0x08编码器计数写入TD(实有%s)' % enc)

    print('6) 进/出测试按钮(手动兜底, 与自动并存)')
    lua.execute('CLEAR()')
    page['on_update'](page, lua.eval('TD.enter'))
    check(fns(lua) == [0x27], '进入测试按钮发0x27(实有%s)' % fns(lua))
    lua.globals().__FR = {'fnc': 0x27, 'data': lua.execute(
        'return string.char(1)')}
    lua.execute('PS.on_frame(__FR)')
    check(fns(lua) == [0x27, 0x25], '按钮链0x27 ACK推进0x25')
    lua.globals().__FR = {'fnc': 0x25, 'data': lua.execute(
        'return string.char(1)')}
    lua.execute('PS.on_frame(__FR)')
    check(fns(lua) == [0x27, 0x25, 0x0E], '按钮链完成进入测试')
    lua.execute('CLEAR()')
    page['on_update'](page, lua.eval('TD.exit'))
    check(fns(lua) == [0x0F], '退出测试按钮发0x0F(实有%s)' % fns(lua))

    print('7) 位分解显示字: InputState按位0/1写lamp_in0~14/lamp_wa0~14')
    check(lua.eval('TD.lamp_in0') + 15 == lua.eval('TD.lamp_wa0')
          and lua.eval('TD.lamp_wa0') + 15 == lua.eval('TD.lamp_hi0'),
          '位灯显示字区不重叠(in0+15=wa0, wa0+15=hi0)——杜绝td_warning14/'
          'td_warning_hi0同址串扰(M34实测)')
    lua.execute('CLEAR()')
    lua.globals().__F08 = {'fnc': 0x08, 'data': lua.execute(
        'return TESTFRAME(0, 0x730F)')}
    page['on_frame'](page, lua.globals().__F08)
    # 0x730F = bit0~3(零位1~4)+bit8(压力)+bit9(风机)+bit12(北斗)
    ok_zero = all(lua.eval('REG[TD.lamp_in0 + %d]' % k) == 1
                  for k in (0, 1, 2, 3))
    check(ok_zero, '零位开关1~4显示字=1')
    check(lua.eval('REG[TD.lamp_in0 + 8]') == 1
          and lua.eval('REG[TD.lamp_in0 + 9]') == 1, '压力/风机显示字=1')
    ok_idle = all(lua.eval('REG[TD.lamp_in0 + %d]' % k) == 0
                  for k in (4, 5, 6, 7, 10, 11))
    check(ok_idle, '未触发位显示字=0(4~7/10/11)')
    ok_bei = all(lua.eval('REG[TD.lamp_in0 + %d]' % k) == 1
                 for k in (12, 13, 14))
    check(ok_bei, '北斗/零位5/零位6显示字=1(bit12/13/14)')
    check(lua.eval('REG[TD.lamp_wa0 + 12]') == 0, '报警显示字=0(无报警)')
    check(lua.eval('REG[TD.lamp_hi0]') == 0, '电机报警显示字=0(bit16无报警)')
    # 使能字区lua永不写(勾选可保持, 对齐QT TestWarning=本地设置)
    lua.execute('REG[0x17B5] = 5; REG[0x17C4] = 6')
    lua.globals().__F08 = {'fnc': 0x08, 'data': lua.execute(
        'return TESTFRAME(0, 0x730F)')}
    page['on_frame'](page, lua.globals().__F08)
    check(lua.eval('REG[0x17B5]') == 5 and lua.eval('REG[0x17C4]') == 6,
          '使能勾选字不被0x08覆盖(勾选可保持)')

    print()
    print('测试诊断页回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
