# -*- coding: utf-8 -*-
r"""厂家参数页(画面4)回归: 2026-09-30 QT模式单轨(config.txt)。

被测: HIMproject/Project/page_manuparam.lua
  1. 未解锁进页被踢回画面3 (PWD.ok=0)
  2. QT模式进页: 不发0x26, 表单从config预填(tappertime ms->0.01s换算)
  3. pf_reset: 表单恢复QT默认值(不下发不写文件)
  4. pf_write: 只写config不下发0x25; TapperTime 0.01s->ms; Resv1=devtype
  5. 范围校验: 打点时间超限拒绝写

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

    lua.execute(r'''
__T = { writes = {}, txs = {}, gotos = {} }
function __T.w16(a, v) __T.writes[a] = v end
function __T.wstr(a, v) __T.writes[a] = v end
function __T.r16(a) return __T.writes[a] or 0 end
function __T.send(fnc, data) __T.txs[#__T.txs + 1] = fnc end
function __T.ntx() return #__T.txs end
function __T.goto_screen(id) __T.gotos[#__T.gotos + 1] = id end
''')
    T = lua.globals().__T
    prot['send'] = T['send']
    PF, SCREEN = lw['PF'], lw['SCREEN']
    gotos = []

    def goto_screen(sid):
        gotos.append(sid)

    saved = {}
    stub_ter = {'A': 60, 'B': 90, 'EncodeNum': 2000, 'EncoderDir': 1,
                'HoleNum': 9, 'GearRatio': 5, 'MicroStepValue': 800,
                'X1': 150, 'BDiroff': 0, 'TappTrigOff': 20, 'TapperTime': 100,
                'ZeroPosEn': 1, 'GZEn': 1, 'PrePercent': 70, 'Resv1': 4}

    class PS:
        @staticmethod
        def load_ter():
            return stub_ter

        @staticmethod
        def save_ter(t):
            saved['ter'] = dict(t)
            return True

    page = factory({'APP': {'goto_screen': goto_screen},
                    'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                    'PARASTORE': PS,
                    'w16': T['w16'], 'wstr': T['wstr'], 'r16': T['r16']})

    def set_form(**over):
        base = dict(a=61, b=91, encodenum=2001, encoderdir=0, holenum=8,
                    gearratio=6, microstep=801, x1=151, bdiroff=1,
                    tapptrigoff=21, tappertime=11, zeroposen=0, gzen=0,
                    prepercent=71, devtype=4)
        base.update(over)
        for k, v in base.items():
            T['w16'](PF[k], v)

    ntx = T['ntx']

    print('1) 未解锁进页踢回画面3')
    page['on_enter'](page)
    check(gotos == [SCREEN['USERPARAM']], 'PWD.ok=0 -> goto_screen(画面3)')
    check(ntx() == 0, '未解锁零发送')

    print('2) QT模式进页: 不发0x26, 表单从config预填')
    gotos.clear()
    T['w16'](lw['PWD']['ok'], 1)
    page['on_enter'](page)
    check(gotos == [] and ntx() == 0, '解锁进页零发送(0x26不用)')
    check(T['writes'][PF['tappertime']] == 10, 'TapperTime 100ms -> LW=10(0.10s)')
    check(T['writes'][PF['x1']] == 150 and T['writes'][PF['gzen']] == 1
          and T['writes'][PF['devtype']] == 4,
          '距离/开关/设备类型预填')

    print('3) pf_reset: 表单恢复QT默认值')
    set_form(a=99, tappertime=50)
    page['on_update'](page, PF['reset'])
    defaults = dict(a=60, b=90, encodenum=2000, encoderdir=0, holenum=9,
                    gearratio=5, microstep=800, x1=150, bdiroff=0,
                    tapptrigoff=20, tappertime=10, zeroposen=1, gzen=1,
                    prepercent=70, devtype=4)
    check(all(T['writes'][PF[k]] == v for k, v in defaults.items()),
          '15字段全部恢复默认')
    check(ntx() == 0 and 'ter' not in saved, '重置不发帧不写文件')

    print('4) pf_write: 只写config; TapperTime*10->ms; Resv1=devtype')
    set_form(tappertime=13)                     # 用户输入0.13s
    page['on_update'](page, PF['write'])
    check(ntx() == 0, '不发0x25(启动链统一下发)')
    t = saved.get('ter', {})
    check(t.get('TapperTime') == 130, 'LW=13(0.13s) -> config存130ms')
    check(t.get('A') == 61 and t.get('X1') == 151, '其余表单值写入')
    check(t.get('Resv1') == 4, 'Resv1=devtype控件值')
    T['w16'](PF['devtype'], 6)
    page['on_update'](page, PF['write'])
    check(saved['ter'].get('Resv1') == 6, '改设备类型=6 -> Resv1=6')

    print('5) 范围校验: 打点时间超限拒绝写')
    set_form(tappertime=101)                    # 1.01s > 1000ms上限
    saved.clear()
    page['on_update'](page, PF['write'])
    check('ter' not in saved, '101(1.01s=1010ms)超限不写config')

    print()
    if FAIL:
        print('厂家参数页: %d项失败' % FAIL)
        return 1
    print('厂家参数页: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
