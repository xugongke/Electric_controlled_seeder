# -*- coding: utf-8 -*-
"""HIMproject 工程协议层/编解码 与模拟器基准的等效性验证 (lupa, Lua 5.3)。

被测: HIMproject/Project/protocol.lua + codec.lua
基准: seeder_sim/protocol.py + layout.py (hd3005a2 六行机, 已与QT联调验证)

重点核对项:
  - CRC16-Kermit 向量 (工程注释声称 0x31C3, 实际算法应为 0x2189)
  - build_frame / feed_bytes 与基准逐字节一致 (含容错序列)
  - codec 各结构体 rows=6 时与 layout.py 位级一致
  - bzstatus: 工程按"平板协议.h"假定6行=100B, 而 hd3005a2 真机=84B(Resv2[4])
  - 与模拟器 Simulator 无串口全链路

运行: python hmi_port/tests/test_him_equivalence.py
"""
import os
import shutil
import sys
import tempfile

from lupa import lua53 as lupa_lua

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIM_DIR = os.path.join(ROOT, 'seeder_sim')
HIM_DIR = os.path.join(ROOT, 'HIMproject', 'Project')
sys.path.insert(0, SIM_DIR)

import protocol as PP                     # noqa: E402
import layout as PL                       # noqa: E402
from main import Simulator                # noqa: E402

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


GLUE = '''
__H = {}
-- 模块加载(规避二进制字符串跨lupa边界)
function __H.load(path)
    local f = assert(loadfile(path))
    return f()
end
function __H.str_bytes(s)
    local t = {}
    for i = 1, #s do t[i] = string.byte(s, i) end
    return t
end
function __H.build_bytes(mod, fnc, data)
    return __H.str_bytes(mod.build_frame(fnc, data))
end
function __H.send_bytes(mod, fnc, data)
    return __H.str_bytes(mod.send(fnc, data))
end
function __H.feed_pairs(mod, bytes)
    local fs = mod.feed_bytes(bytes)
    local r = {}
    for i = 1, #fs do
        r[i] = { fnc = fs[i].fnc, payload = __H.str_bytes(fs[i].data) }
    end
    return r
end
function __H.pack_bytes(fn, t)
    return __H.str_bytes(fn(t))
end
'''


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(GLUE)
    H = lua.globals().__H
    tb = lambda t: bytes(bytearray(t[i] for i in range(1, len(t) + 1)))

    prot = H['load'](os.path.join(HIM_DIR, 'protocol.lua'))
    codec = H['load'](os.path.join(HIM_DIR, 'codec.lua'))
    codec['init']({'rows': 6})

    print('1) CRC16-Kermit')
    check(prot['crc16'](b'123456789') == 0x2189,
          'CRC16("123456789")=0x2189 (工程文件头注释写的0x31C3是错的)')

    print('2) 帧构造/解析与基准一致性')
    for fnc, data in ((0xA3, b''), (0x21, b''), (0x20, b'\x01' * 92),
                      (0x22, b'GB2312' + b'\xd6\xd0\xce\xc4')):
        f_him = tb(H['build_bytes'](prot, fnc, data))
        check(f_him == PP.build_frame(fnc, data),
              'build_frame(0x%02X,%dB) 逐字节一致' % (fnc, len(data)))
    wire = b'\x00\xFF' + PP.build_frame(0xA3, b'ver') + PP.build_frame(0x21, b'y' * 84)
    bad = bytearray(PP.build_frame(0xA3, b'ver'))
    bad[-3] ^= 0xFF
    wire2 = bytes(bad) + PP.build_frame(0x22, b'dbg')
    for name, w, want in (('垃圾前缀+粘包', wire, [0xA3, 0x21]),
                          ('CRC损坏重同步', wire2, [0x22])):
        got = H['feed_pairs'](prot, w)
        fncs = [got[i]['fnc'] for i in range(1, len(got) + 1)]
        ok = fncs == want and tb(got[1]['payload']) == (
            b'ver' if want[0] == 0xA3 else b'dbg')
        check(ok, '%s: 解出%s' % (name, ['0x%02X' % f for f in fncs]))

    print('3) codec rows=6 与 layout.py 位级一致')
    cell = PL.BzCellPara(TXFlag=1, FinalFlag=1, NextFinalFlag=0, isAfterNextZoneSow=1,
                         RowNum=4, InS=100, Density=[4000] * 6, CellLen=500,
                         StartPOS=2900, DisplayRowNum=1, NextRowNum=3, NextInS=100,
                         NextDensity=[4500, 0, -1, 4000, 5000, 6000], NextCellLen=500,
                         NextStartPOS=2300, NextDisplayRowNum=2)
    lt = lua.table(TXFlag=1, FinalFlag=1, NextFinalFlag=0, isAfterNextZoneSow=1,
                   RowNum=4, InS=100, CellLen=500, StartPOS=2900, DisplayRowNum=1,
                   NextRowNum=3, NextInS=100, NextCellLen=500,
                   NextCellStartPOS=2300, NextDisplayRowNum=2)  # 工程字段名
    lt['Density'] = lua.table(*[4000] * 6)
    lt['NextDensity'] = lua.table(*[4500, 0, -1, 4000, 5000, 6000])
    check(tb(H['pack_bytes'](codec['bzcell']['pack'], lt)) == cell.pack(),
          'bzcell 92B 位级一致 (注意: 工程字段名 NextCellStartPOS=基准 NextStartPOS)')
    back = codec['bzcell']['unpack'](cell.pack())
    check(back['NextCellStartPOS'] == 2300 and back['RowNum'] == 4
          and [back['Density'][i] for i in range(1, 7)] == [4000] * 6,
          'bzcell 解包往返一致')

    ter = PL.TerPara(A=60, B=90, EncodeNum=2000, EncoderDir=0, HoleNum=9,
                     GearRatio=5, MicroStepValue=800, X1=150, BDiroff=4,
                     TappTrigOff=20, TapperTime=100, ZeroPosEn=1, GZEn=1,
                     PrePercent=70, U8Resv2=6, U32Resv1=1, U32Resv2=2, U32Resv3=3,
                     CrcCheck=3415616650)
    lt = lua.table(A=60, B=90, EncodeNum=2000, EncoderDir=0, HoleNum=9,
                   GearRatio=5, MicroStepValue=800, X1=150, BDiroff=4,
                   TappTrigOff=20, TapperTime=100, ZeroPosEn=1, GZEn=1,
                   PrePercent=70, Resv1=6, Resv0=1, Resv1_=2, Resv2=3,
                   CrcCheck=3415616650)          # 工程把行数字段命名为 Resv1
    check(tb(H['pack_bytes'](codec['terpara']['pack'], lt)) == ter.pack(),
          'terpara 40B 位级一致 (工程字段名 Resv1=基准 U8Resv2 行数)')

    usr = PL.UserPara(DZTime=1500, HJ=60, Rpm=36, AntennaType=1, U8Resv=0,
                      AntennaDistance=-25249, CrcCheck=7)
    lt = lua.table(DZTime=1500, HJ=60, RMP=36, AntennaType=1, U8Resv=0,
                   AntennaDistance=-25249, CrcCheck=7)
    check(tb(H['pack_bytes'](codec['userpara']['pack'], lt)) == usr.pack(),
          'userpara 16B 位级一致')

    bd = PL.BdPara(StartN=36.4, StartE=117.0, EndBN=-3.75, EndBE=1e-7,
                   StartDir=123.5, CalcDir=-300.25, StartState=1, CalcDirFlag=1,
                   OffLen=60, BDOffTime=100, Resv=9, CrcCheck=0xDEADBEEF)
    lt = lua.table(StartN=36.4, StartE=117.0, EndBN=-3.75, EndBE=1e-7,
                   StartDir=123.5, CalcDir=-300.25, StartState=1, CalcDirFlag=1,
                   OffLen=60, BDOffTime=100, Resv=9, CrcCheck=0xDEADBEEF)
    check(tb(H['pack_bytes'](codec['bdpara']['pack'], lt)) == bd.pack(),
          'bdpara 56B 位级一致 (string.pack double)')

    lx = PL.LxbzPara(Density=4500, CellLen=500, Hju=60, ZhuShu=0)
    lt = lua.table(Density=4500, CellLen=500, Hju=60, ZhuShu=0)
    check(tb(H['pack_bytes'](codec['lxbz']['pack'], lt)) == lx.pack(),
          'lxbz 12B 位级一致')

    print('4) bzstatus 与 hd3005a2 真机兼容性 (关键)')
    st84 = PL.pack_bz_status(0x81, 1, -1234, -10000000, -98765, -360,
                             [1, 2, 3, 4, 5, 6], [24, 23, 23, 23, 23, 24])
    try:
        t = codec['bzstatus']['unpack'](st84)
        okv = (t['RunState'] == 0x81 and t['RowNum'] == -10000000
               and [t['LouZHCnt'][i] for i in range(1, 7)] == [24, 23, 23, 23, 23, 24])
        check(okv, 'bzstatus 84B(a2真机) 可解包且字段正确')
    except Exception as e:
        check(False, 'bzstatus 84B(a2真机帧) 解包失败: %s' % str(e)[:80])
    lt = lua.table(RunState=0x81, BdState=1, ResvA=0, ResvB=0, Speed=-1234,
                   RowNum=-10000000, OffLen=-98765, VerticalOff=-360)
    lt['LoufeiCnt'] = lua.table(*[1, 2, 3, 4, 5, 6])
    lt['LouZHCnt'] = lua.table(*[24, 23, 23, 23, 23, 24])
    lt['Resv2'] = lua.table(*([0] * 8))
    try:
        packed = tb(H['pack_bytes'](codec['bzstatus']['pack'], lt))
        check(len(packed) == 84 and packed == st84,
              'bzstatus rows=6 打包为84B(a2口径) 且与基准逐字节一致')
    except Exception as e:
        check(False, 'bzstatus rows=6 打包异常: %s' % str(e)[:80])

    ts68 = PL.pack_test_status(7, 9, [1] * 6, [2] * 6, 0x1234, 0x5678, 0x9ABC)
    t = codec['teststate']['unpack'](ts68)
    lt = lua.table(EncoderCnt=7, BdCnt=9, InputState=0x1234,
                   WarningState=0x5678, CtrlState=0x9ABC)
    lt['LoufeiCnt'] = lua.table(*[1] * 6)
    lt['LouZHCnt'] = lua.table(*[2] * 6)
    check(t['InputState'] == 0x1234
          and tb(H['pack_bytes'](codec['teststate']['pack'], lt)) == ts68,
          'teststate 68B 位级一致')

    print('5) 与模拟器无串口全链路')
    tmpdir = tempfile.mkdtemp()
    state = os.path.join(tmpdir, 'state.json')
    shutil.copy(os.path.join(SIM_DIR, 'seeder_sim_state.json'), state)
    sim = Simulator(port=None, rows=6, state_file=state)

    def ask(fnc, payload=b''):
        resp = sim.process_frame(fnc, payload)
        if resp is None:
            return None, None
        got = H['feed_pairs'](prot, PP.build_frame(fnc, resp))
        if len(got) == 0:
            return None, None
        return got[1]['fnc'], tb(got[1]['payload'])

    fnc, pl_ = ask(0xA3)
    check(fnc == 0xA3 and pl_.startswith(b'hd3005a2_sim'), '0xA3 版本链路: %r'
          % pl_.split(b'\x00')[0])
    fnc, pl_ = ask(0x26)
    ter2 = codec['terpara']['unpack'](pl_)
    check(fnc == 0x26 and ter2['Resv1'] == 6,
          '0x26 厂家参数: 行数字段(工程名Resv1)=%d' % ter2['Resv1'])
    fnc, pl_ = ask(0x21)
    if fnc == 0x21:
        try:
            st = codec['bzstatus']['unpack'](pl_)
            check(st['BdState'] == 1, '0x21 状态解包正常')
        except Exception as e:
            check(False, '0x21 状态解包失败(6行a2=84B vs 工程100B): %s' % str(e)[:70])
    lt = lua.table(TXFlag=1, FinalFlag=0, NextFinalFlag=0, isAfterNextZoneSow=1,
                   RowNum=4, InS=100, CellLen=500, StartPOS=2900, DisplayRowNum=1,
                   NextRowNum=3, NextInS=100, NextCellLen=500,
                   NextCellStartPOS=2300, NextDisplayRowNum=2)
    lt['Density'] = lua.table(*[4000] * 6)
    lt['NextDensity'] = lua.table(*[4000] * 6)
    fnc, pl_ = ask(0x20, tb(H['pack_bytes'](codec['bzcell']['pack'], lt)))
    check(fnc == 0x20 and pl_ == b'\x01', '0x20 小区参数92B下发 ACK=1')

    print()
    if FAIL:
        print('HIM工程等效性: %d项失败' % FAIL)
    else:
        print('HIM工程等效性: 全部通过 (%d项)' % PASS)
    shutil.rmtree(tmpdir, ignore_errors=True)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
