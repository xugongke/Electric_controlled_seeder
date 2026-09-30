# -*- coding: utf-8 -*-
"""厂家参数页(画面4)回归: 2026-09-16对齐QT formconfig厂家参数组引入的逻辑。

被测: HIMproject/Project/page_manuparam.lua + codec.terpara
  1. TapperTime单位换算: LW存0.01s(控件2位小数显s), 协议/固件ms
     show: ms四舍五入//10 -> LW; pack: LW*10 -> ms (QT formconfig.cpp:88/155)
  2. pf_reset 重置默认值 = QT formconfig.cpp:204~221 (不下发)
  3. pf_write 0x25下发: 行数字段Resv1保留0x26快照值(2026-09-23冲行数事故回归)
  4. 未解锁进页被踢回画面3 (PWD.ok=0)
  5. 进页自动0x26快照(2026-09-16删读按钮, 对齐QT)

二进制payload全程lua侧解包(规避lupa字符串边界)。
运行: python hmi_port/tests/test_him_manuparam.py
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
    factory = load('page_manuparam.lua')
    lua.globals().__CODEC = codec

    # 桩: LW写入记录(lua侧); 发送帧lua侧捕获; goto_screen走python闭包
    lua.execute('''
__T = { writes = {}, txs = {} }
function __T.w16(a, v) __T.writes[a] = v end
function __T.wstr(a, v) __T.writes[a] = v end
function __T.r16(a) return __T.writes[a] or 0 end
function __T.send(fnc, data) __T.txs[#__T.txs + 1] = { fnc = fnc, data = data } end
function __T.ntx() return #__T.txs end
function __T.txfnc(i) return __T.txs[i].fnc end
function __T.txfield(i, name) return __CODEC.terpara.unpack(__T.txs[i].data)[name] end
function __T.feed_ter(page, fnc, lt)
    page:on_frame({ fnc = fnc, data = __CODEC.terpara.pack(lt) })
end
''')
    T = lua.globals().__T
    prot['send'] = T['send']
    PF, SCREEN = lw['PF'], lw['SCREEN']
    FNC = prot['FNC']
    gotos = []

    def goto_screen(sid):
        gotos.append(sid)

    page = factory({'APP': {'goto_screen': goto_screen},
                    'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                    'w16': T['w16'], 'wstr': T['wstr'], 'r16': T['r16']})

    def _lua_dict(t):
        lt = lua.table()
        for k, v in t.items():
            lt[k] = v
        return lt

    def set_form(**over):
        base = dict(a=61, b=91, encodenum=2001, encoderdir=0, holenum=8,
                    gearratio=6, microstep=801, x1=151, bdiroff=1,
                    tapptrigoff=21, tappertime=11, zeroposen=0, gzen=0,
                    prepercent=71)
        base.update(over)
        for k, v in base.items():
            T['w16'](PF[k], v)

    ntx, txfnc, txfield = T['ntx'], T['txfnc'], T['txfield']

    print('1) 未解锁进页踢回画面3')
    page['on_enter'](page)
    check(gotos == [SCREEN['USERPARAM']], 'PWD.ok=0 -> goto_screen(画面3)')
    check(ntx() == 0, '未解锁不发0x26')

    print('2) 解锁进页自动0x26快照(对齐QT无读按钮)')
    T['w16'](lw['PWD']['ok'], 1)
    page['on_enter'](page)
    check(ntx() == 1 and txfnc(1) == FNC['GET_TER_PARA'],
          'on_enter自动发0x26, 无需读按钮')

    print('3) 0x26应答回显: TapperTime ms->0.01s换算')
    T['feed_ter'](page, FNC['GET_TER_PARA'], _lua_dict(
        dict(A=60, B=90, EncodeNum=2000, EncoderDir=1, HoleNum=9,
             GearRatio=5, MicroStepValue=800, X1=150, BDiroff=0,
             TappTrigOff=20, TapperTime=100, ZeroPosEn=1, GZEn=1,
             PrePercent=70, Resv1=4, Resv0=0, Resv1_=0, Resv2=0,
             CrcCheck=0)))
    check(T['writes'][PF['tappertime']] == 10, '100ms -> LW=10 (显示0.10s)')
    check(T['writes'][PF['x1']] == 150 and T['writes'][PF['gzen']] == 1,
          '距离cm/开关位原样回显')
    check(T['writes'][PF['devtype']] == 4, '行数Resv1回显到设备类型下拉=4')

    print('4) pf_reset: 表单恢复QT默认值(formconfig.cpp:204~221), 不下发')
    set_form(a=99, tappertime=50)
    n0 = ntx()
    page['on_update'](page, PF['reset'])
    defaults = dict(a=60, b=90, encodenum=2000, encoderdir=0, holenum=9,
                    gearratio=5, microstep=800, x1=150, bdiroff=0,
                    tapptrigoff=20, tappertime=10, zeroposen=1, gzen=1,
                    prepercent=70, devtype=4)
    check(all(T['writes'][PF[k]] == v for k, v in defaults.items()),
          '15字段全部恢复默认(tappertime=10即0.10s, devtype=4行机)')
    check(ntx() == n0, '重置不触发0x25下发(需再点保存)')

    print('5) pf_write: 0x25下发, TapperTime*10->ms, Resv1保留快照行数')
    set_form(tappertime=13)                     # 用户输入0.13s
    page['on_update'](page, PF['write'])
    check(ntx() == n0 + 1 and txfnc(ntx()) == FNC['SET_TER_PARA'], '发出0x25')
    check(txfield(ntx(), 'TapperTime') == 130, 'LW=13(0.13s) -> 协议130ms')
    check(txfield(ntx(), 'Resv1') == 4, 'Resv1=devtype控件值(0x26回显的4, 未动即原样发回)')
    T['w16'](PF['devtype'], 6)                  # 用户切6行机
    page['on_update'](page, PF['write'])
    check(txfield(ntx(), 'Resv1') == 6, '改设备类型=6 -> 0x25下发Resv1=6')
    check(txfield(ntx(), 'A') == 61 and txfield(ntx(), 'X1') == 151,
          '其余表单值正常带回')

    print('6) 无0x26快照时Resv1兜底6行')
    factory2 = load('page_manuparam.lua')
    page2 = factory2({'APP': {'goto_screen': goto_screen},
                      'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                      'w16': T['w16'], 'wstr': T['wstr'], 'r16': T['r16']})
    T['w16'](lw['PWD']['ok'], 1)
    page2['on_enter'](page2)
    set_form(tappertime=5)
    page2['on_update'](page2, PF['write'])
    check(txfield(ntx(), 'Resv1') == 6,
          'devtype非法(0)且无快照 -> 兜底Resv1=6')

    print('7) 范围校验: 打点时间超限拒绝下发')
    set_form(tappertime=101)                    # 1.01s > 1000ms上限
    n0 = ntx()
    page2['on_update'](page2, PF['write'])
    check(ntx() == n0, '101(1.01s=1010ms)超限不发0x25')

    print()
    if FAIL:
        print('厂家参数页: %d项失败' % FAIL)
        return 1
    print('厂家参数页: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
