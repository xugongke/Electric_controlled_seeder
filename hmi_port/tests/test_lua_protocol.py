# -*- coding: utf-8 -*-
"""组态屏 Lua 协议层 M0-M1 验收测试 (PC 侧, lupa 驱动, 锁定 Lua 5.3)。

验证 hmi_port/lua/sow_protocol.lua + sow_layout.lua:
  1) CRC16-Kermit 标准向量与查表(与 seeder_sim/protocol.py 逐项比对)
  2) 帧构造/增量解析(分包/粘包/垃圾前缀/CRC错重同步)
  3) 8种结构体与 layout.py 逐字段互证(含 double/float 位级往返)
  4) 与模拟器 Simulator 无串口进程内全链路联测:
     Lua构帧 -> 模拟器 process_frame -> 应答回 Lua 解析器 -> 字段断言
     (0xA3/0x21/0x22/0x26/0x28/0x25/0x27/0x20)

运行: python hmi_port/tests/test_lua_protocol.py
"""
import os
import shutil
import sys
import tempfile

from lupa import lua53 as lupa_lua    # 屏内为 Lua 5.3, 测试锁定同版本

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIM_DIR = os.path.join(ROOT, 'seeder_sim')
LUA_DIR = os.path.join(ROOT, 'hmi_port', 'lua')
sys.path.insert(0, SIM_DIR)

import protocol as PP                     # noqa: E402  模拟器帧层(基准)
import layout as PL                       # noqa: E402  模拟器结构体(基准)
from main import Simulator                # noqa: E402  无串口模式

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


def load_lua():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    for f in ('sow_protocol.lua', 'sow_layout.lua'):
        with open(os.path.join(LUA_DIR, f), encoding='utf-8') as fp:
            lua.execute(fp.read())
    return lua


def lua_fn(lua, path):
    obj = lua.globals().SOW
    for seg in path.split('.'):
        obj = obj[seg]
    return obj


def tbl_bytes(t):
    """Lua字节数组表 -> python bytes"""
    return bytes(bytearray(t[i] for i in range(1, len(t) + 1)))


def main():
    lua = load_lua()
    build = lua_fn(lua, 'protocol.build_frame_bytes')   # 返回字节数组表
    feed_raw = lua_fn(lua, 'protocol.feed')
    to_pairs = lua_fn(lua, 'protocol.frames_to_pairs')
    call_bytes = lua_fn(lua, 'protocol.call_bytes')
    unpack = lambda name, s: lua_fn(lua, 'layout.' + name)(s)
    pack = lambda name, t: tbl_bytes(call_bytes(lua_fn(lua, 'layout.' + name), t))

    def feed(parser, chunk):
        fs = to_pairs(feed_raw(parser, chunk))
        out = []
        for i in range(1, len(fs) + 1):
            out.append({'fnc': fs[i]['fnc'], 'payload': tbl_bytes(fs[i]['payload'])})
        return out

    print('1) CRC16-Kermit')
    crc = lua_fn(lua, 'protocol.crc16_kermit')
    check(crc(b'123456789') == 0x2189, '标准向量 "123456789" -> 0x2189')
    tbl = lua_fn(lua, 'protocol.CRC_TABLE')
    check(all(tbl[i] == PP._CRC_TABLE[i] for i in range(256)),
          '查表256项与上位机表逐项一致')

    print('2) 帧构造与增量解析')
    f = tbl_bytes(build(0xA3, b'hd3005a2_sim v1.7'))
    check(f == PP.build_frame(0xA3, b'hd3005a2_sim v1.7'),
          'build_frame 与 Python 版逐字节一致')
    # 分包+垃圾前缀+粘包
    wire = b'\x00\xFF\x11' + f + tbl_bytes(build(0x21, b'x' * 84))
    parser = lua_fn(lua, 'protocol.new_parser')()
    got = []
    for i in range(0, len(wire), 7):            # 极限分包
        got.extend(feed(parser, wire[i:i + 7]))
    check(len(got) == 2 and got[0]['fnc'] == 0xA3
          and got[0]['payload'] == b'hd3005a2_sim v1.7'
          and got[1]['fnc'] == 0x21 and len(got[1]['payload']) == 84,
          '垃圾前缀+分包+粘包下解析出2帧且负载正确')
    # CRC 损坏 -> 丢1字节重同步, 后一帧仍可解出
    bad = bytearray(f)
    bad[-3] ^= 0xFF                              # 破坏CRC
    wire2 = bytes(bad) + tbl_bytes(build(0x22, b'dbg'))
    parser2 = lua_fn(lua, 'protocol.new_parser')()
    got2 = feed(parser2, wire2)
    check(len(got2) == 1 and got2[0]['fnc'] == 0x22,
          'CRC错误丢1字节重同步后解出后续帧')

    print('3) 结构体与 layout.py 互证')
    cases = [
        ('LxbzPara', PL.LxbzPara(Density=4500, CellLen=500, Hju=60, ZhuShu=0),
         'lxbz', ['Density', 'CellLen', 'Hju', 'ZhuShu'], 'unpack_lxbz'),
        ('TerPara', PL.TerPara(A=-60, B=91, EncodeNum=2000, EncoderDir=1, HoleNum=9,
                               GearRatio=5, MicroStepValue=800, X1=-150, BDiroff=-3,
                               TappTrigOff=20, TapperTime=100, ZeroPosEn=1, GZEn=1,
                               PrePercent=70, U8Resv2=6, U32Resv1=0x12345678,
                               U32Resv2=0x7FFFFFFF, U32Resv3=5, CrcCheck=3415616650),
         'ter', ['A', 'B', 'EncodeNum', 'EncoderDir', 'HoleNum', 'GearRatio',
                 'MicroStepValue', 'X1', 'BDiroff', 'TappTrigOff', 'TapperTime',
                 'ZeroPosEn', 'GZEn', 'PrePercent', 'U8Resv2',
                 'U32Resv1', 'U32Resv2', 'U32Resv3', 'CrcCheck'], 'unpack_ter'),
        ('UserPara', PL.UserPara(DZTime=1500, HJ=60, Rpm=36, AntennaType=1, U8Resv=0,
                                 AntennaDistance=-25249, CrcCheck=7),
         'user', ['DZTime', 'HJ', 'Rpm', 'AntennaType', 'U8Resv',
                  'AntennaDistance', 'CrcCheck'], 'unpack_user'),
        ('BdPara', PL.BdPara(StartN=36.4, StartE=117.0, EndBN=-3.75, EndBE=1e-7,
                             StartDir=123.5, CalcDir=-300.25, StartState=1,
                             CalcDirFlag=1, OffLen=60, BDOffTime=100, Resv=9,
                             CrcCheck=0xDEADBEEF),
         'bd', ['StartN', 'StartE', 'EndBN', 'EndBE', 'StartDir', 'CalcDir',
                'StartState', 'CalcDirFlag', 'OffLen', 'BDOffTime', 'Resv',
                'CrcCheck'], 'unpack_bd'),
    ]
    for name, obj, pkname, fields, upkname in cases:
        raw = obj.pack()                            # Python 打包
        lt = unpack(upkname, raw)                   # Lua 解包
        bad_f = [k for k in fields
                 if abs(float(lt[k]) - float(getattr(obj, k))) > 1e-6
                 and int(lt[k]) != getattr(obj, k)]
        lt2 = lua.table()
        for k in fields:
            lt2[k] = getattr(obj, k)
        repack = pack('pack_' + pkname, lt2)        # Lua 重打包
        check(not bad_f and repack == raw,
              '%s: Lua解包字段全对 + Lua重打包位级一致' % name)

    cell = PL.BzCellPara(TXFlag=1, FinalFlag=0, NextFinalFlag=1, isAfterNextZoneSow=1,
                         RowNum=-3, InS=100, Density=[4000] * 6, CellLen=500,
                         StartPOS=12345, DisplayRowNum=-2, NextRowNum=-4,
                         NextInS=100, NextDensity=[4500, 0, -1, 4000, 5000, 6000],
                         NextCellLen=500, NextStartPOS=-12945,
                         NextDisplayRowNum=-3)
    raw = cell.pack()
    lt = unpack('unpack_bz_cell', raw)
    check(lt['TXFlag'] == 1 and lt['RowNum'] == -3 and lt['CellLen'] == 500
          and lt['StartPOS'] == 12345 and lt['NextStartPOS'] == -12945
          and [lt['Density'][i] for i in range(1, 7)] == [4000] * 6
          and [lt['NextDensity'][i] for i in range(1, 7)]
          == [4500, 0, -1, 4000, 5000, 6000],
          'BZCellPara: Lua解包字段/数组/负数全对')
    lt2 = lua.table(TXFlag=1, FinalFlag=0, NextFinalFlag=1, isAfterNextZoneSow=1,
                    RowNum=-3, InS=100, CellLen=500, StartPOS=12345,
                    DisplayRowNum=-2, NextRowNum=-4, NextInS=100, NextCellLen=500,
                    NextStartPOS=-12945, NextDisplayRowNum=-3)
    lt2['Density'] = lua.table(*[4000] * 6)
    lt2['NextDensity'] = lua.table(*[4500, 0, -1, 4000, 5000, 6000])
    check(pack('pack_bz_cell', lt2) == raw, 'BZCellPara: Lua重打包位级一致')

    st = PL.pack_bz_status(0x81, 1, -1234, -10000000, -98765, -360,
                           [1, 2, 3, 4, 5, 6], [24, 23, 23, 23, 23, 24])
    lt = unpack('unpack_bz_status', st)
    check(lt['run_state'] == 0x81 and lt['speed'] == -1234
          and lt['row_num'] == -10000000 and lt['off_len'] == -98765
          and lt['vertical_off'] == -360
          and [lt['louzh'][i] for i in range(1, 7)] == [24, 23, 23, 23, 23, 24],
          'BZStatus: Lua解包字段/计数数组/负数全对')

    print('4) 与模拟器进程内全链路联测 (无串口)')
    tmpdir = tempfile.mkdtemp()
    state = os.path.join(tmpdir, 'state.json')
    shutil.copy(os.path.join(SIM_DIR, 'seeder_sim_state.json'), state)  # 用副本, 不碰原件
    sim = Simulator(port=None, rows=6, state_file=state)
    parser = lua_fn(lua, 'protocol.new_parser')()

    def ask(fnc, payload=b''):
        """应答帧经 Lua 解析器解出, 返回(fnc, payload bytes)。"""
        resp = sim.process_frame(fnc, payload)
        if resp is None:
            return None, None
        for fr in feed(parser, PP.build_frame(fnc, resp)):
            return fr['fnc'], fr['payload']
        return None, None

    fnc, pl = ask(0xA3)
    check(fnc == 0xA3 and pl.startswith(b'hd3005a2_sim'),
          '0xA3 版本: %r' % pl.split(b'\x00')[0])
    fnc, pl = ask(0x21)
    stt = unpack('unpack_bz_status', pl)
    check(fnc == 0x21 and len(pl) == 84 and stt['bd_state'] == 1,
          '0x21 状态帧: 84字节, 北斗正常, run=%d' % stt['run_state'])
    fnc, pl = ask(0x22)
    check(fnc == 0x22 and len(pl.decode('gb2312')) > 0,
          '0x22 调试串(GB2312): %s' % pl.decode('gb2312'))
    fnc, pl = ask(0x26)
    ter = unpack('unpack_ter', pl)
    check(fnc == 0x26 and len(pl) == 40,
          '0x26 厂家参数: A=%d B=%d 行数=%d GearRatio=%d' %
          (ter['A'], ter['B'], ter['U8Resv2'], ter['GearRatio']))
    fnc, pl = ask(0x28)
    usr = unpack('unpack_user', pl)
    check(fnc == 0x28 and len(pl) == 16,
          '0x28 用户参数: DZTime=%d HJ=%d Rpm=%d' %
          (usr['DZTime'], usr['HJ'], usr['Rpm']))

    # 0x25/0x27 下发: Lua打包 -> 模拟器ACK -> 回读校验 (写入的是临时副本)
    lt = lua.table(A=61, B=91, EncodeNum=2000, EncoderDir=0, HoleNum=9,
                   GearRatio=6, MicroStepValue=800, X1=150, BDiroff=4,
                   TappTrigOff=20, TapperTime=100, ZeroPosEn=1, GZEn=1,
                   PrePercent=70, U8Resv2=6, CrcCheck=0)
    fnc, pl = ask(0x25, pack('pack_ter', lt))
    check(fnc == 0x25 and pl == b'\x01', '0x25 下发厂家参数 ACK=1')
    lt2 = lua.table(DZTime=1200, HJ=55, Rpm=30, AntennaType=1, U8Resv=0,
                    AntennaDistance=100, CrcCheck=0)
    fnc, pl = ask(0x27, pack('pack_user', lt2))
    check(fnc == 0x27 and pl == b'\x01', '0x27 下发用户参数 ACK=1')
    _, pl = ask(0x26)
    ter2 = unpack('unpack_ter', pl)
    _, pl = ask(0x28)
    usr2 = unpack('unpack_user', pl)
    check(ter2['A'] == 61 and ter2['B'] == 91 and ter2['GearRatio'] == 6
          and ter2['U8Resv2'] == 6 and usr2['DZTime'] == 1200
          and usr2['HJ'] == 55 and usr2['Rpm'] == 30,
          '参数回读=下发值 (0x25/0x27 全链路)')

    # 0x20 下发小区参数: Lua构包 -> ACK
    z = lua.table(TXFlag=1, FinalFlag=0, NextFinalFlag=0, isAfterNextZoneSow=1,
                  RowNum=4, InS=100, CellLen=500, StartPOS=2900,
                  DisplayRowNum=1, NextRowNum=3, NextInS=100, NextCellLen=500,
                  NextStartPOS=2300, NextDisplayRowNum=2)
    z['Density'] = lua.table(*[4000] * 6)
    z['NextDensity'] = lua.table(*[4000] * 6)
    fnc, pl = ask(0x20, pack('pack_bz_cell', z))
    check(fnc == 0x20 and pl == b'\x01', '0x20 下发小区参数(92B) ACK=1')

    print()
    if FAIL:
        print('M0-M1 验收: %d项失败' % FAIL)
    else:
        print('M0-M1 验收: 全部通过 (%d项)' % PASS)
    shutil.rmtree(tmpdir, ignore_errors=True)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
