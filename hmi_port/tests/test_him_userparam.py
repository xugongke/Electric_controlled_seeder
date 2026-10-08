# -*- coding: utf-8 -*-
r"""用户参数页(画面3)回归: 2026-09-30 QT模式单轨(config.txt)。

被测: HIMproject/Project/page_userparam.lua
  1. QT模式: 进页不发0x28(显示只从本地配置读, QT同款getUserParameter未用)
  2. 表单预填来自config(parastore桩)
  3. pu_write: 只写config不下发0x27(启动链统一下发)+范围校验
  4. pu_reset 恢复QT默认值(不下发不写文件)
  5. 密码对话框确认: 515516正确->PWD.ok=1+切画面4; 错误->ok=0
  6. 过道打点三态随[保存]写入config

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

    lua.execute(r'''
__T = { writes = {}, txs = {}, gotos = {} }
function __T.w16(a, v) __T.writes[a] = v end
function __T.w32(a, v) __T.writes[a] = v & 0xFFFF __T.writes[a + 1] = v >> 16 end
function __T.wstr(a, v) __T.writes[a] = v end
function __T.r16(a) return __T.writes[a] or 0 end
function __T.r32(a) return (__T.writes[a + 1] or 0) * 0x10000 + (__T.writes[a] or 0) end
function __T.send(fnc, data) __T.txs[#__T.txs + 1] = fnc end
function __T.ntx() return #__T.txs end
function __T.goto_screen(id) __T.gotos[#__T.gotos + 1] = id end
''')
    T = lua.globals().__T
    prot['send'] = T['send']
    PU, SCREEN = lw['PU'], lw['SCREEN']
    PWD = lw['PWD']
    gotos = []

    def goto_screen(sid):
        gotos.append(sid)

    saved = {}                      # parastore桩: 记录save调用
    stub_user = {'DZTime': 1600, 'HJ': 70, 'RMP': 40, 'AntennaType': 1,
                 'AntennaDistance': 25}
    stub_gap = [2]

    stub_fine = [{'origin': 4000, 'specified': 4000, 'enabled': 0},
                 {'origin': 4500, 'specified': 4600, 'enabled': 1},
                 {'origin': 5000, 'specified': 5000, 'enabled': 0},
                 {'origin': 5500, 'specified': 5500, 'enabled': 0},
                 {'origin': 6000, 'specified': 6000, 'enabled': 0}]
    saved_fine = []

    class PS:
        @staticmethod
        def load_user():
            return stub_user

        @staticmethod
        def load_fine():
            lt = lua.table()
            for i, ft in enumerate(stub_fine):
                e = lua.table()
                e['origin'] = ft['origin']
                e['specified'] = ft['specified']
                e['enabled'] = ft['enabled']
                lt[i + 1] = e
            return lt

        @staticmethod
        def save_fine(t):
            saved_fine.append(t)
            return True

        @staticmethod
        def load_gap():
            return stub_gap[0]

        @staticmethod
        def save_user(u, gp):
            saved['user'] = dict(u)
            saved['gp'] = gp
            return True

    page = factory({'APP': {'goto_screen': goto_screen},
                    'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                    'PARASTORE': PS,
                    'w16': T['w16'], 'w32': T['w32'], 'wstr': T['wstr'],
                    'r16': T['r16'], 'r32': T['r32']})

    def set_form(**over):
        base = dict(dztime=1600, hj=70, antennatype=1, antennadist=25,
                    gappoint=2)
        base.update(over)
        for k, v in base.items():
            T['w16'](PU[k], v)
        T['w32'](PU['rmp'], 40)

    ntx = T['ntx']

    print('1) QT模式进页: 不发0x28, 表单从config预填')
    page['on_enter'](page)
    check(ntx() == 0, '进页零发送(0x28能力保留在协议层但页面不用)')
    check(T['writes'][PU['dztime']] == 1600 and T['writes'][PU['hj']] == 70
          and T['writes'][PU['rmp']] == 40
          and T['writes'][PU['antennatype']] == 1,
          'config值预填表单')
    check(T['writes'][PU['gappoint']] == 2, '过道打点从config预填=2(间隔)')

    print('2) pu_write: 只写config不下发0x27')
    set_form(dztime=1700, gappoint=1)
    page['on_update'](page, PU['write'])
    check(ntx() == 0, '不发0x27(启动链统一下发)')
    check(saved.get('user', {}).get('DZTime') == 1700
          and saved.get('user', {}).get('HJ') == 70,
          '表单值写入config')
    check(saved.get('gp') == 1, '过道打点=1随保存写入')

    print('3) pu_reset: 恢复QT默认值(不下发不写文件)')
    set_form(dztime=999, hj=99, gappoint=0)
    lua.execute('__T.writes[0x1623] = 35')   # 模拟u32高字残留(旧bug现场)
    saved.clear()
    page['on_update'](page, PU['reset'])
    defaults = dict(dztime=1500, hj=60, antennatype=0, antennadist=0,
                    gappoint=1)
    check(all(T['writes'][PU[k]] == v for k, v in defaults.items()),
          '倒种1.5s/行间距60cm/单天线/天线间距0/过道开')
    check(T['writes'][PU['rmp']] == 36 and T['writes'][PU['rmp'] + 1] == 0,
          '转速36(u32双字: 高字清零, 2026-10-08修复前残留旧值显示2359326)')
    check(ntx() == 0 and 'user' not in saved, '重置不发帧不写文件(需再点保存)')

    print('4) 范围校验: HJ低于下限拒绝写')
    set_form(hj=5)
    saved.clear()
    page['on_update'](page, PU['write'])
    check('user' not in saved, 'HJ=5<10 不写config')

    print("4b) 株距微调表: 预填/保存/重置")
    page['on_enter'](page)
    check(T['writes'][PU['ft_d2']] == 4600 and T['writes'][PU['ft_e2']] == 1,
          '档2预填4600+启用')
    check(T['writes'][PU['ft_d1']] == 4000 and T['writes'][PU['ft_e1']] == 0,
          '档1预填恒等未启用')
    T['w16'](PU['ft_d3'], 5300)
    T['w16'](PU['ft_e3'], 1)
    set_form()                      # 其余参数合法
    saved_fine.clear()              # 节2的保存也写过fine, 只看本次
    page['on_update'](page, PU['write'])
    check(len(saved_fine) == 1, '保存写入微调表')
    sf = saved_fine[0]
    check(sf[3]['specified'] == 5300 and sf[3]['enabled'] == 1,
          '档3=5300启用进config')
    check(sf[2]['specified'] == 4600, '档2保持4600')
    page['on_update'](page, PU['reset'])
    check(T['writes'][PU['ft_d2']] == 4500 and T['writes'][PU['ft_e2']] == 0,
          '重置: 微调=原密度+全不启用(QT formconfig:188-193)')

    print('5) 密码对话框确认')
    T['w32'](lw['PF']['pass'], 515516)
    page['on_update'](page, PWD['confirm'])
    check(T['writes'][PWD['ok']] == 1 and gotos == [SCREEN['MANUPARAM']],
          '密码正确 -> PWD.ok=1 + 切画面4')
    T['w32'](lw['PF']['pass'], 123456)
    page['on_update'](page, PWD['confirm'])
    check(T['writes'][PWD['ok']] == 0 and gotos == [SCREEN['MANUPARAM']],
          '密码错误 -> PWD.ok=0 不切画面')

    print('6) config缺失时gappoint按关处理')
    stub_gap[0] = 7                  # 非法值
    page['on_enter'](page)
    check(T['writes'][PU['gappoint']] == 0, '非法gap -> 显示0=关')

    print()
    if FAIL:
        print('用户参数页: %d项失败' % FAIL)
        return 1
    print('用户参数页: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
