# -*- coding: utf-8 -*-
"""参数副本(RW)+启动参数链(parastore)回归: 2026-09-30对齐QT启动链。

被测: HIMproject/Project/parastore.lua
  1. 副本读写round-trip(协议原值, 含i16负值/u32双字) + magic无效兜底默认
  2. 启动链: 0x27(载荷含override的HJ) -> ACK -> 0x25(载荷=副本) -> ACK -> 回调
  3. ACK=0中止不回调; 超时(10tick)中止; 链外应答不影响
  4. 无副本时0x27/0x25用QT默认值

QT依据: 固件0x27纯RAM不持久化(hd3005a1/Src/protocol.c:351) -> QT在每次
进入工作模式前重发0x27->0x25->动作(formtest.cpp:43-49等三处)。
运行: python hmi_port/tests/test_him_parastore.py
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
    ps = load('parastore.lua')
    lua.globals().__CODEC = codec

    lua.execute(r'''
__T = { writes = {}, rw = {}, txs = {} }
function __T.w16(a, v) __T.writes[a] = v end
function __T.wstr(a, v) __T.writes[a] = v end
function __T.rw16(a) return __T.rw[a] end
function __T.rw16w(a, v) __T.rw[a] = v end
function __T.tx(frame) __T.txs[#__T.txs + 1] = frame end
function __T.ntx() return #__T.txs end
function __T.txfnc(i) return string.byte(__T.txs[i], 2) end
function __T.txfield(i, name, which)
    local d = __T.txs[i]:sub(5)
    local t
    if which == 'u' then t = __CODEC.userpara.unpack(d)
    else t = __CODEC.terpara.unpack(d) end
    return t[name]
end
''')
    T = lua.globals().__T
    FNC = prot['FNC']
    prot['io']['tx'] = T['tx']             # 仅替换发送函数, 保留计数器
    RW = lw['RW']

    ps['init']({'APP': {'sub_always': lambda f, h: None},
                'PROTOCOL': prot, 'CODEC': codec, 'LW': lw, 'LOGGER': None,
                'rw16': T['rw16'], 'rw16w': T['rw16w'],
                'wstr': T['wstr']})

    def pack_frame(fnc, data):
        # 构造应答帧: 头2字节FNC在位置2, data从第5字节起(与txfield解析对齐)
        return prot['build_frame'](fnc, data)

    def feed_ack(fnc, ok=True):
        # 直接调parastore.on_frame(绕开APP路由, 单测关注状态机本身)
        lua.globals().__FNCV = fnc
        lua.globals().__OKV = 1 if ok else 0
        lua.execute('__FR = { fnc = __FNCV, data = string.char(__OKV) }')
        ps['on_frame'](lua.globals().__FR)

    ntx, txfnc, txfield = T['ntx'], T['txfnc'], T['txfield']

    print('1) 副本读写round-trip')
    ok = ps['save_user']({'DZTime': 1600, 'HJ': -25, 'RMP': 0x12345,
                          'AntennaType': 1, 'AntennaDistance': 30})
    u = ps['load_user']()
    check(ok and u['DZTime'] == 1600 and u['HJ'] == -25
          and u['RMP'] == 0x12345 and u['AntennaType'] == 1
          and u['AntennaDistance'] == 30, 'user 5字段含负HJ/大RMP')
    ok = ps['save_ter']({'A': 61, 'B': 91, 'EncodeNum': 2001, 'EncoderDir': 1,
                         'HoleNum': 8, 'GearRatio': 6, 'MicroStepValue': 801,
                         'X1': 151, 'BDiroff': 1, 'TappTrigOff': 21,
                         'TapperTime': 130, 'ZeroPosEn': 0, 'GZEn': 0,
                         'PrePercent': 71, 'Resv1': 6})
    t = ps['load_ter']()
    check(ok and t['TapperTime'] == 130 and t['Resv1'] == 6 and t['A'] == 61,
          'ter 15字段(协议原值ms/Resv1)')

    print('2) magic无效 -> 默认值兜底')
    T['rw'][RW['cfg_magic']] = 0
    u2 = ps['load_user']()
    t2 = ps['load_ter']()
    check(u2 is None and t2 is None, 'magic破坏后load返回nil')

    done = []

    def on_done():
        done.append(1)

    print('3) 启动链: 0x27(HJ覆盖) -> ACK -> 0x25 -> ACK -> 回调')
    over = lua.table()
    over['HJ'] = 75
    ps['begin']('SOW', over, on_done)
    check(ntx() == 1 and txfnc(1) == FNC['SET_USER_PARA'], '先发0x27')
    check(txfield(1, 'HJ', 'u') == 75, '0x27载荷HJ=75(地图行距覆盖)')
    check(txfield(1, 'RMP', 'u') == 36, '无副本时RMP=QT默认36')
    feed_ack(FNC['SET_USER_PARA'], ok=True)
    check(ntx() == 2 and txfnc(2) == FNC['SET_TER_PARA'], '0x27 ACK -> 发0x25')
    check(txfield(2, 'TapperTime') == 100, '0x25载荷TapperTime=QT默认100ms')
    feed_ack(FNC['SET_TER_PARA'], ok=True)
    check(done == [1], '0x25 ACK -> 回调(原启动逻辑)')
    check(not ps['active'](), '链结束复位')

    print('4) ACK=0中止')
    done.clear()
    ps['begin']('TEST', None, on_done)
    feed_ack(FNC['SET_USER_PARA'], ok=False)
    check(done == [] and not ps['active'](), '0x27被拒 -> 中止不回调')

    print('5) 超时中止')
    ps['begin']('LXBZ', None, on_done)
    for _ in range(11):
        ps['tick']()
    check(done == [] and not ps['active'](), '11tick无应答 -> 超时中止')
    ps['begin']('LXBZ', None, on_done)
    for _ in range(9):
        ps['tick']()
    feed_ack(FNC['SET_USER_PARA'], ok=True)
    check(ps['active'](), '第10tick内应答仍有效(链未超时)')

    print('6) 副本在链中的使用')
    ps['save_user']({'DZTime': 1800, 'HJ': 55, 'RMP': 40,
                     'AntennaType': 1, 'AntennaDistance': 20})
    ps['save_ter']({'A': 62, 'B': 92, 'EncodeNum': 2002, 'EncoderDir': 0,
                    'HoleNum': 10, 'GearRatio': 7, 'MicroStepValue': 802,
                    'X1': 152, 'BDiroff': 2, 'TappTrigOff': 22,
                    'TapperTime': 150, 'ZeroPosEn': 1, 'GZEn': 1,
                    'PrePercent': 72, 'Resv1': 4})
    done.clear()
    ps['begin']('TEST', None, on_done)
    check(txfield(ntx(), 'DZTime', 'u') == 1800
          and txfield(ntx(), 'HJ', 'u') == 55, '0x27用RW副本')
    feed_ack(FNC['SET_USER_PARA'], ok=True)
    check(txfield(ntx(), 'TapperTime') == 150 and txfield(ntx(), 'Resv1') == 4,
          '0x25用RW副本')
    feed_ack(FNC['SET_TER_PARA'], ok=True)
    check(done == [1], '链完成')

    print('7) jobrun.start 端到端冒烟: 0x27->0x25->0x24/0x31/0x0A')
    app = load('app.lua')
    app['wire']({'PROTOCOL': prot, 'CODEC': codec, 'LW': lw})
    app['init']({'w16': T['w16'], 'w32': T['w16'], 'wstr': T['wstr'],
                 'r16': lambda a: 0, 'r32': lambda a: 0,
                 'tx': T['tx'], 'poll_ms': 200})
    ps2 = load('parastore.lua')
    ps2['init']({'APP': app, 'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                 'LOGGER': None, 'rw16': T['rw16'], 'rw16w': T['rw16w'],
                 'wstr': T['wstr']})
    jobrun = load('jobrun.lua')
    lua.execute(r'''
__STORE = { tasks = { demo = { map = "m1", path_type = 0, positive = 1,
                                sow_exceed = 0, blocks = {} } },
            maps = { m1 = { name = "m1", rows = 4, cols = 2, col_gap = 75 } },
            results = {} }
__PATHALGO = {
  create_path = function(m, pt, pos)
    return { {row=0, column=1, positive=true}, {row=3, column=1, positive=false} }
  end,
  block_each_trip = function(m) return 1 end,
  start_node = function(tsk, m, path, row, col, ab, fine)
    return { TXFlag=1, FinalFlag=0, NextFinalFlag=0, isAfterNextZoneSow=1,
             RowNum=row, InS=100, CellLen=500, StartPOS=0, DisplayRowNum=1,
             Density={4000,4000,4000,4000,4000,4000},
             NextRowNum=1, NextInS=100, NextCellLen=500,
             NextCellStartPOS=600, NextDisplayRowNum=2,
             NextDensity={4000,4000,4000,4000,4000,4000} }
  end,
}
''')
    jobrun['init']({'APP': app, 'PROTOCOL': prot, 'CODEC': codec,
                    'STORE': lua.globals().__STORE,
                    'PATHALGO': lua.globals().__PATHALGO,
                    'LOGGER': None, 'LW': lw,
                    'w16': T['w16'], 'w32': T['w16'], 'wstr': T['wstr'],
                    'now': lambda: 'T+0s',
                    'rw16': lambda a: None, 'rw16w': T['rw16w'],
                    'rstr': lambda a: '', 'r16': lambda a: 0,
                    'parastore': ps2})
    T['txs'] = lua.table()   # 清帧记录
    lua.globals().__PROT = prot

    def fnc_list():
        return [txfnc(i) for i in range(1, ntx() + 1)]

    def feed_ack_frame(fnc_val):
        lua.globals().__FV = fnc_val
        lua.execute('__PROT.feed_bytes('
                    '__PROT.build_frame(__FV, string.char(1)))')

    r = jobrun['start']('demo', None)
    seq = fnc_list()
    check(r and seq == [FNC['SET_USER_PARA']],
          'start只触发链首帧0x27(不再直发0x24): %s' % [hex(f) for f in seq])
    check(txfield(1, 'HJ', 'u') == 75, '0x27载荷HJ=地图col_gap 75')
    feed_ack_frame(FNC['SET_USER_PARA'])
    seq = fnc_list()
    check(seq[1:2] == [FNC['SET_TER_PARA']], '0x27 ACK后发0x25')
    feed_ack_frame(FNC['SET_TER_PARA'])
    seq = fnc_list()
    check(seq[2:] == [FNC['SET_AB'], FNC['SET_BZ_PARA'], FNC['GDDD_ENABLE'],
                      FNC['CMD_START_BZ']],
          '0x25 ACK后原启动段完整执行 0x24/0x20/0x31/0x0A: %s'
          % [hex(f) for f in seq[2:]])

    print('8) 虚拟屏离线复现: RW访问抛错+无下位机, 进测试仍应发0x27')
    lua2 = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    g = lua2.globals()
    g.__MAINP = HIM.replace(chr(92), '/') + '/main.lua'
    # 平台桩: VT_RW读抛错(复现虚拟屏), LW返回预设, 无文件API(B档降级)
    lua2.execute(r'''
__SIM = { lw = {}, txs = {} }
VT_LW, VT_RW = 0, 2
function get_uint16(vt, addr)
    if vt == VT_RW then error("virtual screen: RW unsupported") end
    return __SIM.lw[addr] or 0
end
function set_uint16(vt, addr, v)
    if vt == VT_RW then error("virtual screen: RW unsupported") end
    __SIM.lw[addr] = v
end
function set_string(vt, addr, s) __SIM.lw[addr] = s end
function get_string(vt, addr) return __SIM.lw[addr] or "" end
function uart_send(ch, bytes)
    local s = ""
    for i = 0, #bytes do if bytes[i] then s = s .. string.char(bytes[i]) end end
    __SIM.txs[#__SIM.txs + 1] = s
end
uart_send_data = uart_send
function print(...) end          -- 静音装载日志
function set_run_cycle(ms) end   -- 平台轮询设置桩
function uart_set_timeout(ch, ms) end
''')
    lua2.execute('dofile(__MAINP)')      # main.lua顶层定义全局回调, 无返回值
    lua2.execute('on_init()')
    # 模拟切到画面5后按[进入测试]: LW.TD.enter 写1 -> on_update
    SIM = g.__SIM
    SCREEN_TEST, TD_ENTER = 5, 0x1740      # lwmap: SCREEN.TESTDIAG / TD.enter
    lua2.execute('on_screen_change(%d)' % SCREEN_TEST)
    SIM['lw'][TD_ENTER] = 1
    lua2.execute('on_update(0, VT_LW, %d)' % TD_ENTER)
    lua2.execute('__FNC2 = {} '
                 'for i = 1, #__SIM.txs do __FNC2[i] = string.byte(__SIM.txs[i], 2) end')
    n2 = lua2.eval('#__SIM.txs')
    fncs2 = [lua2.globals().__FNC2[i] for i in range(1, n2 + 1)]
    check(FNC['SET_USER_PARA'] in fncs2,
          'RW抛错下进测试仍发0x27(修复前整个回调被吞): %s'
          % [hex(f) for f in fncs2])
    check(FNC['CMD_START_TEST'] not in fncs2,
          'ACK未回 -> 不发0x0E(链等待中)')

    print('9) config.txt双轨: 写文件/自愈恢复/U盘导出')
    files = {}                      # FILEIO桩: 内存文件系统

    class FIO:
        @staticmethod
        def _p(path):
            return str(path)
        @staticmethod
        def write_all(path, data):
            files[str(path)] = str(data)
            return True
        @staticmethod
        def read_all(path):
            return files.get(str(path))
        @staticmethod
        def read_lines(path):
            d = files.get(str(path))
            if d is None:
                return None
            lt = lua.table()          # lua侧需真table(ipairs/type检查)
            n = 0
            for l in d.splitlines():
                if l != '':
                    n += 1
                    lt[n] = l
            return lt

    ps['set_fileio'](FIO)
    T['rw'][RW['gap_point']] = 2           # 过道打点须在save前就位(随副本进文件)
    ps['save_user']({'DZTime': 1600, 'HJ': 66, 'RMP': 41, 'AntennaType': 1,
                     'AntennaDistance': 25})
    ps['save_ter']({'A': 61, 'B': 91, 'EncodeNum': 2001, 'EncoderDir': 1,
                    'HoleNum': 8, 'GearRatio': 6, 'MicroStepValue': 801,
                    'X1': 151, 'BDiroff': 1, 'TappTrigOff': 21,
                    'TapperTime': 130, 'ZeroPosEn': 0, 'GZEn': 1,
                    'PrePercent': 71, 'Resv1': 6})
    cfg = files.get('3:config.txt')
    check(cfg is not None, '保存后生成3:config.txt')
    check('[Application]' in cfg and 'DropSeedTime=1600' in cfg
          and 'SeedColumnGap=66' in cfg and 'Rpm=41' in cfg,
          '用户参数键值=协议原值')
    check('[Device]' in cfg and 'TapperTime=130' in cfg
          and 'EncoderDirection=1' in cfg and 'MicroStepValue=801' in cfg,
          '厂家参数键值(QT键名)')
    check('ZeroSwitch=0' in cfg and 'ScrapeSeed=2' in cfg,
          '开关按QT checkState 2勾/0空')
    check('DeviceType=6' in cfg.replace('行机', '行机')
          or '行' in repr(cfg), 'DeviceType=6行机(UTF-8)')
    check('GapPoint=' in cfg, 'GapPoint中文值存在')
    # 自愈: 清RW后recover应从文件恢复
    lua.execute('__T.rw = {}')          # lupa表无clear, lua侧清空
    ok = ps['recover']()
    u3 = ps['load_user']()
    t3 = ps['load_ter']()
    check(ok and u3['DZTime'] == 1600 and u3['HJ'] == 66 and u3['RMP'] == 41,
          'recover恢复用户参数到RW')
    check(t3['TapperTime'] == 130 and t3['Resv1'] == 6
          and t3['ZeroPosEn'] == 0, 'recover恢复厂家参数(含行数/开关)')
    check(T['rw'][RW['gap_point']] == 2, 'recover恢复过道打点=2')
    # 导出U盘
    ok = ps['export_usb']()
    check(ok and '2:config.txt' in files
          and files['2:config.txt'] == files['3:config.txt'],
          '导出U盘: 2:config.txt与3:一致')

    print()
    if FAIL:
        print('参数链: %d项失败' % FAIL)
        return 1
    print('参数链: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
