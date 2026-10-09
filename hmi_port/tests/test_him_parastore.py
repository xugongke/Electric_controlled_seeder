# -*- coding: utf-8 -*-
r"""配置文件(3:config.txt)+启动参数链(parastore)回归: 2026-09-30 QT模式单轨。

被测: HIMproject/Project/parastore.lua
  1. config.txt读写round-trip: QSettings字节级兼容格式
     (\xXXXX转义中文/开关1/0/[ContinuousSowMode]Density/MachineColumnCount占位)
  2. 首次保存自动建骨架; 保留QT写出的其他键(SerialPort/Alpha等)
  3. 启动链: 0x27(载荷含override的HJ) -> ACK -> 0x25(载荷=config) -> ACK -> 回调
  4. ACK=0中止; 超时(10tick)中止
  5. 密度/过道打点持久化
  6. 无文件系统(B档降级): 链用QT默认值

QT依据: QT设置页纯本地ini(formconfig.cpp:66~91), getUserParameter()声明
未用; 固件0x27纯RAM不持久化(protocol.c:351) -> 参数链进工作模式前统一下发。
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
__T = { writes = {}, txs = {} }
function __T.w16(a, v) __T.writes[a] = v end
function __T.wstr(a, v) __T.writes[a] = v end
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
    prot['io']['tx'] = T['tx']

    ps['init']({'APP': {'sub_always': lambda f, h: None},
                'PROTOCOL': prot, 'CODEC': codec, 'LW': lw, 'LOGGER': None,
                'wstr': T['wstr']})

    files = {}                      # FILEIO桩: 内存文件系统

    class FIO:
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
            lt = lua.table()
            n = 0
            for l in d.splitlines():
                if l != '':
                    n += 1
                    lt[n] = l
            return lt

    ps['set_fileio'](FIO)
    ntx, txfnc, txfield = T['ntx'], T['txfnc'], T['txfield']

    def feed_ack(fnc, ok=True):
        lua.globals().__FNCV = fnc
        lua.globals().__OKV = 1 if ok else 0
        lua.execute('__FR = { fnc = __FNCV, data = string.char(__OKV) }')
        ps['on_frame'](lua.globals().__FR)

    print('1) config.txt写入: QSettings字节级兼容格式')
    check(ps['save_user']({'DZTime': 1600, 'HJ': 66, 'RMP': 41,
                           'AntennaType': 1, 'AntennaDistance': 25}, 2),
          '首次保存自动建文件')
    cfg = files['3:config.txt']
    check('[Application]' in cfg and 'DropSeedTime=1600' in cfg
          and 'SeedColumnGap=66' in cfg and 'Rpm=41' in cfg
          and 'NavigationAntenna=1' in cfg and 'AntennaDistance=25' in cfg,
          '用户参数键值=协议原值(QT键名)')
    check('GapPoint=间隔' in cfg, 'GapPoint=UTF-8字节直写(lupa侧解码为中文)')
    check(ps['save_ter']({'A': 61, 'B': 91, 'EncodeNum': 2001, 'EncoderDir': 1,
                          'HoleNum': 8, 'GearRatio': 6, 'MicroStepValue': 801,
                          'X1': 151, 'BDiroff': 1, 'TappTrigOff': 21,
                          'TapperTime': 130, 'ZeroPosEn': 0, 'GZEn': 1,
                          'PrePercent': 71, 'Resv1': 6}),
          '厂家参数保存')
    cfg = files['3:config.txt']
    check('[Device]' in cfg and 'TransmissionRatio=2001' in cfg
          and 'TapperTime=130' in cfg and 'MicroStepValue=801' in cfg,
          '厂家参数键值')
    check('ZeroSwitch=0' in cfg and 'ScrapeSeed=1' in cfg,
          '开关=1/0(实际config.ini格式, 非checkState的2)')
    check('DeviceType=6行机' in cfg, 'DeviceType=6行机(UTF-8直写)')
    check('MachineColumnCount=6' in cfg, 'MachineColumnCount跟随DeviceType占位')
    check('[ContinuousSowMode]' in cfg and 'Density=4000' in cfg,
          '连播密度组存在')

    print('2) load round-trip')
    u = ps['load_user']()
    t = ps['load_ter']()
    check(u['DZTime'] == 1600 and u['HJ'] == 66 and u['RMP'] == 41
          and u['AntennaType'] == 1 and u['AntennaDistance'] == 25,
          'load_user读回')
    check(t['TapperTime'] == 130 and t['Resv1'] == 6 and t['ZeroPosEn'] == 0
          and t['GZEn'] == 1 and t['EncodeNum'] == 2001, 'load_ter读回(含行数)')
    check(ps['load_gap']() == 2, 'load_gap=2(间隔)')

    print('3) 保留QT写出的其他键')
    qt_ini = ('[Application]\r\nSerialPort=COM8\r\nAlpha=176\r\n'
              'BlockColumnCount=1\r\nDropSeedTime=1500\r\nGapPoint=\\x5f00\r\n'
              '[Device]\r\nDeviceType=4\\x884c\\x673a\r\nGearRatio=5\r\n')
    files['3:config.txt'] = qt_ini
    check(ps['save_user']({'DZTime': 1700, 'HJ': 70, 'RMP': 44,
                           'AntennaType': 0, 'AntennaDistance': 0}, 1),
          '在QT文件上保存')
    cfg = files['3:config.txt']
    check('SerialPort=COM8' in cfg and 'Alpha=176' in cfg,
          'QT本地键SerialPort/Alpha保留')
    bs = chr(92)
    check('DropSeedTime=1700' in cfg
          and ('DeviceType=4' + bs + 'x884c' + bs + 'x673a') in cfg,
          '参数键更新, 其他组不动')
    check(ps['load_gap']() == 1, 'QT写的GapPoint=开可读回')

    print('4) 密度持久化')
    check(ps['save_density'](5200), 'save_density')
    check(ps['load_density']() == 5200, 'load_density读回')

    print("4b) 株距微调表: QSettings数组键格式")
    fine = lua.table()
    for i, org in enumerate([4000, 4500, 5000, 5500, 6000]):
        ft = lua.table()
        ft['origin'] = org
        ft['specified'] = org + 100 if i == 1 else org
        ft['enabled'] = 1 if i == 1 else 0
        fine[i + 1] = ft
    check(ps['save_fine'](fine), 'save_fine')
    cfg = files['3:config.txt']
    bs = chr(92)
    check(('SeedGapFineTuning' + bs + '2' + bs + 'OriginDensity=4500') in cfg
          and ('SeedGapFineTuning' + bs + '2' + bs + 'SpecifiedDensity=4600') in cfg
          and ('SeedGapFineTuning' + bs + '2' + bs + 'Enabled=1') in cfg,
          'QT QSettings数组键格式(反斜杠子键)')
    lf = ps['load_fine']()
    check(len(lf) == 5 and lf[2]['specified'] == 4600 and lf[2]['enabled'] == 1,
          'load_fine读回档2=4600启用')
    check(lf[1]['specified'] == 4000 and lf[1]['enabled'] == 0,
          '未启用档恒等')
    files['3:config.txt'] = (
        '[Application]' + chr(13) + chr(10)
        + 'SeedGapFineTuning' + bs + '3' + bs + 'OriginDensity=5000' + chr(13) + chr(10)
        + 'SeedGapFineTuning' + bs + '3' + bs + 'SpecifiedDensity=5300' + chr(13) + chr(10)
        + 'SeedGapFineTuning' + bs + '3' + bs + 'Enabled=1' + chr(13) + chr(10))
    lf2 = ps['load_fine']()
    check(lf2[3]['specified'] == 5300 and lf2[3]['enabled'] == 1,
          'QT写的微调数组可读回')
    # pathalgo.density微调生效(end-to-end)
    lua.globals().__P2 = HIM.replace(chr(92), '/') + '/pathalgo.lua'
    lua.globals().__M2 = lua.table()
    lua.globals().__M2['blocks'] = lua.table()
    lua.globals().__M2['blocks'][0] = lua.table()
    lua.globals().__M2['blocks'][0][1] = {'density': 4500}
    lua.globals().__M2['rows'] = 1
    lua.globals().__M2['cols'] = 1
    lua.globals().__M2['machine_cols'] = 1
    tsk = lua.table()
    tsk['blocks'] = lua.table()
    tsk['blocks'][0] = lua.table()
    tb = lua.table()
    tb['sow'] = 1
    tb['state'] = 0
    tsk['blocks'][0][1] = tb
    lua.globals().__TSK = tsk
    lua.globals().__FT = ps['load_fine']()
    dens = lua.execute(
        "local f = assert(loadfile(__P2)); "
        "local pa = f(); "
        "return pa.density(__TSK, __M2, 0, 1, true, __FT)")
    check(dens == 4500, 'QT文件版fine(仅档3启用): 4500未启用档恒等')
    lua.globals().__M2['blocks'][0][1] = {'density': 5000}
    dens2 = lua.execute(
        "local f = assert(loadfile(__P2)); "
        "local pa = f(); "
        "return pa.density(__TSK, __M2, 0, 1, true, __FT)")
    check(dens2 == 5300, '5000命中QT启用档3 -> 5300(微调生效)')
    dens0 = lua.execute(
        "local f = assert(loadfile(__P2)); "
        "local pa = f(); "
        "return pa.density(__TSK, __M2, 0, 1, true, nil)")
    check(dens0 == 5000, '无微调表 -> 原密度5000')
    # 起点语义(2026-10-09修): 正向首节点row=0; outset_row定位起点
    lua.globals().__M5 = lua.table()
    lua.globals().__M5['rows'] = 5
    lua.globals().__M5['cols'] = 2
    lua.globals().__M5['machine_cols'] = 1
    p0 = lua.execute(
        "local f = assert(loadfile(__P2)); local pa = f(); "
        "local p = pa.create_path(__M5, 0, true); "
        "return p[1].row, p[1].positive")
    check(p0[0] == 0 and p0[1] is True,
          '正向(positive=1)首节点row=0(QT createPath同款)')
    p1 = lua.execute(
        "local f = assert(loadfile(__P2)); local pa = f(); "
        "local p = pa.create_path(__M5, 0, false); "
        "return p[1].row")
    check(p1 == 4, '反向首节点row=4(末排)')
    # 起始排定位(jobrun.start同款扫描): outset={r=0}在正向路径首次出现=index1
    idx = lua.execute(
        "local f = assert(loadfile(__P2)); local pa = f(); "
        "local p = pa.create_path(__M5, 0, true); "
        "for i, pn in ipairs(p) do if pn.row == 0 then return i end end")
    check(idx == 1, '起始排0(1基排1)+正向 -> 起点即首节点(实际从(1,1)出发)')
    idx2 = lua.execute(
        "local f = assert(loadfile(__P2)); local pa = f(); "
        "local p = pa.create_path(__M5, 0, true); "
        "for i, pn in ipairs(p) do if pn.row == 2 then return i end end")
    check(idx2 == 3, '起始排3(0基2)+正向 -> 起点index3(该排首节点)')

    print('5) 启动链: 0x27(HJ覆盖) -> ACK -> 0x25 -> ACK -> 回调')
    done = []

    def on_done():
        done.append(1)

    files['3:config.txt'] = ('[Application]\r\nDropSeedTime=1800\r\n'
                             'SeedColumnGap=55\r\nRpm=40\r\n'
                             'NavigationAntenna=1\r\nAntennaDistance=20\r\n'
                             'GapPoint=\\x5f00\r\n'
                             '[Device]\r\nDropPortDistance=62\r\n'
                             'TransmissionRatio=2002\r\nTapperTime=150\r\n'
                             'DeviceType=4\\x884c\\x673a\r\n')
    over = lua.table()
    over['HJ'] = 75
    ps['begin']('SOW', over, on_done)
    check(ntx() == 1 and txfnc(1) == FNC['SET_USER_PARA'], '先发0x27')
    check(txfield(1, 'HJ', 'u') == 75, '0x27载荷HJ=75(地图行距覆盖)')
    check(txfield(1, 'DZTime', 'u') == 1800
          and txfield(1, 'AntennaType', 'u') == 1, '其余字段来自config')
    feed_ack(FNC['SET_USER_PARA'], ok=True)
    check(ntx() == 2 and txfnc(2) == FNC['SET_TER_PARA'], '0x27 ACK -> 发0x25')
    check(txfield(2, 'TapperTime') == 150 and txfield(2, 'Resv1') == 4,
          '0x25载荷来自config(缺键按QT默认补)')
    feed_ack(FNC['SET_TER_PARA'], ok=True)
    check(done == [1], '0x25 ACK -> 回调(原启动逻辑)')
    check(not ps['active'](), '链结束复位')

    print('6) ACK=0中止 / 超时中止')
    done.clear()
    ps['begin']('TEST', None, on_done)
    feed_ack(FNC['SET_USER_PARA'], ok=False)
    check(done == [] and not ps['active'](), '0x27被拒 -> 中止不回调')
    ps['begin']('LXBZ', None, on_done)
    for _ in range(11):
        ps['tick']()
    check(done == [] and not ps['active'](), '11tick无应答 -> 超时中止')

    print('7) 无文件系统(B档降级): 链用QT默认值')
    ps['set_fileio'](None)
    ps['begin']('TEST', None, on_done)
    check(txfield(ntx(), 'RMP', 'u') == 36 and txfield(ntx(), 'HJ', 'u') == 60,
          '无config -> QT默认36r/60cm')
    feed_ack(FNC['SET_USER_PARA'], ok=True)
    check(txfield(ntx(), 'TapperTime') == 100, '0x25默认TapperTime=100ms')
    feed_ack(FNC['SET_TER_PARA'], ok=True)
    check(done == [1], '链完成')

    print('8) 导出U盘')
    ps['set_fileio'](FIO)
    files['2:config.txt'] = ''
    check(ps['export_usb'](), 'export_usb')
    check(files['2:config.txt'] == files['3:config.txt'], '2:与3:一致')

    print("8b) AB线功能删除: 0x24恒全零(StartState=0行程开关触发)")
    jr = load('jobrun.lua')
    lua.globals().__JRB = jr
    lua.globals().__PROT = prot
    jr['init']({'APP': {'sub_always': lambda f, h: None,
                    'register': lambda pg: None},
                'PROTOCOL': prot, 'CODEC': codec, 'LW': lw,
                'STORE': None, 'PATHALGO': None, 'LOGGER': None,
                'w32': T['w16'], 'rw16': lambda a: 0,
                'rw16w': lambda a, v: None, 'parastore': None,
                'w16': T['w16'], 'wstr': T['wstr'],
                'now': lambda: 'T+0s', 'rstr': lambda a: '',
                'r16': lambda a: 0})
    lua.execute(r'''
__FTX = {}
local old_tx = __PROT.io.tx
__PROT.io.tx = function(fr) __FTX[#__FTX + 1] = fr end
__JRB.ab_send_map()
__PROT.io.tx = old_tx
__ABF = __CODEC.bdpara.unpack(__FTX[1]:sub(5))
''')
    n_f = lua.eval('#__FTX')
    fnc0 = lua.execute('return string.byte(__FTX[1], 2)')
    abz = lua.globals().__ABF
    check(n_f == 1 and fnc0 == FNC['SET_AB'], 'ab_send_map发出单帧0x24')
    check(abz['StartState'] == 0 and abz['StartN'] == 0
          and abz['BDOffTime'] == 0 and abz['OffLen'] == 0,
          '0x24载荷全零(地头行程开关触发设A点, 2026-10-09)')

    print()
    if FAIL:
        print('参数链: %d项失败' % FAIL)
        return 1
    print('参数链: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
