# -*- coding: utf-8 -*-
"""协议数据域结构体 —— 布局与上位机 AgricultureMachine/common/protocol.h 完全一致。

注意: 上位机(新版, 支持6行机)的数组元素为[6]; 仓库里的 hd3005a1 固件是[4]的老版布局,
两者不兼容, 而上位机按 sizeof(本机结构体) 直接 memcpy 解析, 因此这里统一采用上位机的
新版布局, 4行机只是第5/6路恒为0。

所有多字节字段小端; 本模块用 struct 显式声明, 无隐式对齐填充, 各结构体总长在导入时断言。
"""

import struct
from dataclasses import dataclass, field, asdict


# ---------------------------------------------------------------- 常量尺寸
SZ_LXBZ_PARA      = 12   # LXBZParaType
SZ_TEST_CMD       = 4    # TestCMDType
SZ_BZ_CELL_PARA   = 92   # BZCellParaType  (Density[6] 新版)
SZ_BD_PARA        = 56   # BDParaType
SZ_TER_PARA       = 40   # TerParaType
SZ_USER_PARA      = 16   # UserParaType
SZ_BZ_STATUS      = 84   # BZStatusType    (hd3005a2: Resv2[4], 总长不变仍为84)
SZ_TEST_STATUS    = 68   # TestModeStateType (Cnt[6] 新版)


# ---------------------------------------------------------------- LXBZParaType
_LXBZ = struct.Struct('<IIHH')          # u32 Density, u32 CellLen, u16 Hju, u16 ZhuShu
assert _LXBZ.size == SZ_LXBZ_PARA


@dataclass
class LxbzPara:
    Density: int = 1000     # 株/亩
    CellLen: int = 500      # 行长 cm
    Hju: int = 60           # 行间距 cm
    ZhuShu: int = 0         # 株数, 0=自动计算

    def pack(self):
        return _LXBZ.pack(self.Density, self.CellLen, self.Hju, self.ZhuShu)

    @staticmethod
    def unpack(data):
        v = _LXBZ.unpack(data)
        return LxbzPara(v[0], v[1], v[2], v[3])


# ---------------------------------------------------------------- TestCMDType
_TEST_CMD = struct.Struct('<HH')         # u16 CtrlNo, u16 State
assert _TEST_CMD.size == SZ_TEST_CMD


def pack_test_cmd(ctrl_no, state):
    return _TEST_CMD.pack(ctrl_no, state)


def unpack_test_cmd(data):
    return _TEST_CMD.unpack(data)


# ---------------------------------------------------------------- BZCellParaType
# u8 TXFlag, u8 FinalFlag, u8 NextFinalFlag, u8 isAfterNextZoneSow,
# s32 RowNum, s32 InS, s32 Density[6], s32 CellLen, s32 StartPOS, s32 DisplayRowNum,
# s32 NextRowNum, s32 NextInS, s32 NextDensity[6], s32 NextCellLen, s32 NextStartPOS,
# s32 NextDisplayRowNum
_BZ_CELL = struct.Struct('<4B ii 6i iii ii 6i iii')
assert _BZ_CELL.size == SZ_BZ_CELL_PARA, _BZ_CELL.size


@dataclass
class BzCellPara:
    TXFlag: int = 1             # 0:与AB反向 1:同向
    FinalFlag: int = 0
    NextFinalFlag: int = 0
    isAfterNextZoneSow: int = 0
    RowNum: int = 0
    InS: int = 0                # 过道长度 cm
    Density: list = field(default_factory=lambda: [0] * 6)
    CellLen: int = 0            # 小区长度 cm
    StartPOS: int = 0           # 当前小区起始行程 cm
    DisplayRowNum: int = 0
    NextRowNum: int = 0
    NextInS: int = 0
    NextDensity: list = field(default_factory=lambda: [0] * 6)
    NextCellLen: int = 0
    NextStartPOS: int = 0
    NextDisplayRowNum: int = 0

    def pack(self):
        return _BZ_CELL.pack(
            self.TXFlag & 0xFF, self.FinalFlag & 0xFF, self.NextFinalFlag & 0xFF,
            self.isAfterNextZoneSow & 0xFF,
            self.RowNum, self.InS, *self.Density[:6],
            self.CellLen, self.StartPOS, self.DisplayRowNum,
            self.NextRowNum, self.NextInS, *self.NextDensity[:6],
            self.NextCellLen, self.NextStartPOS, self.NextDisplayRowNum)

    @staticmethod
    def unpack(data):
        v = _BZ_CELL.unpack(data)
        return BzCellPara(
            TXFlag=v[0], FinalFlag=v[1], NextFinalFlag=v[2], isAfterNextZoneSow=v[3],
            RowNum=v[4], InS=v[5], Density=list(v[6:12]),
            CellLen=v[12], StartPOS=v[13], DisplayRowNum=v[14],
            NextRowNum=v[15], NextInS=v[16], NextDensity=list(v[17:23]),
            NextCellLen=v[23], NextStartPOS=v[24], NextDisplayRowNum=v[25])


# ---------------------------------------------------------------- BDParaType
# double StartN/StartE/EndBN/EndBE, float StartDir/CalcDir,
# u16 StartState/CalcDirFlag/OffLen/BDOffTime, u32 Resv, u32 CrcCheck
_BD_PARA = struct.Struct('<dddd ff HHHH II')
assert _BD_PARA.size == SZ_BD_PARA, _BD_PARA.size


@dataclass
class BdPara:
    StartN: float = 0.0
    StartE: float = 0.0
    EndBN: float = 0.0
    EndBE: float = 0.0
    StartDir: float = 0.0
    CalcDir: float = 0.0
    StartState: int = 0         # 0:无效 1:有效
    CalcDirFlag: int = 0        # 0:无效 1:有效
    OffLen: int = 0             # 起始偏移 cm
    BDOffTime: int = 0          # 北斗延迟 ms
    Resv: int = 0
    CrcCheck: int = 0

    def pack(self):
        return _BD_PARA.pack(self.StartN, self.StartE, self.EndBN, self.EndBE,
                             self.StartDir, self.CalcDir,
                             self.StartState, self.CalcDirFlag, self.OffLen,
                             self.BDOffTime, self.Resv, self.CrcCheck)

    @staticmethod
    def unpack(data):
        v = _BD_PARA.unpack(data)
        return BdPara(*v)


# ---------------------------------------------------------------- TerParaType
# s16 A, s16 B, u16 EncodeNum, u8 EncoderDir, u8 HoleNum, u16 GearRatio,
# u16 MicroStepValue, s16 X1, s16 BDiroff, s16 TappTrigOff, u16 TapperTime,
# u8 ZeroPosEn, u8 GZEn, u8 PrePercent, u8 U8Resv2(行数4/6),
# u32 U32Resv1..3, u32 CrcCheck
_TER = struct.Struct('<hhHBBHHhhhH BBBB IIII')
assert _TER.size == SZ_TER_PARA, _TER.size


@dataclass
class TerPara:
    A: int = 0
    B: int = 0
    EncodeNum: int = 600        # 编码器变送比 脉冲/m
    EncoderDir: int = 0
    HoleNum: int = 9            # 播种盘孔数
    GearRatio: int = 0          # <2 时合法化检查改为 10
    MicroStepValue: int = 800   # 步进细分
    X1: int = 244
    BDiroff: int = 0
    TappTrigOff: int = 0
    TapperTime: int = 60        # ms
    ZeroPosEn: int = 0
    GZEn: int = 0
    PrePercent: int = 0
    U8Resv2: int = 4            # 行数: 4 或 6 (上位机 DeviceType 下发)
    U32Resv1: int = 0
    U32Resv2: int = 0
    U32Resv3: int = 0
    CrcCheck: int = 0

    def pack(self):
        return _TER.pack(self.A, self.B, self.EncodeNum, self.EncoderDir,
                         self.HoleNum, self.GearRatio, self.MicroStepValue,
                         self.X1, self.BDiroff, self.TappTrigOff, self.TapperTime,
                         self.ZeroPosEn, self.GZEn, self.PrePercent, self.U8Resv2,
                         self.U32Resv1, self.U32Resv2, self.U32Resv3, self.CrcCheck)

    @staticmethod
    def unpack(data):
        v = _TER.unpack(data)
        return TerPara(*v)


# ---------------------------------------------------------------- UserParaType
# u16 DZTime, s16 HJ, u32 Rpm, u8 AntennaType, u8 U8Resv, s16 AntennaDistance,
# u32 CrcCheck
_USER = struct.Struct('<HhIBBhI')
assert _USER.size == SZ_USER_PARA, _USER.size


@dataclass
class UserPara:
    DZTime: int = 1500          # 倒(投)种时间 ms
    HJ: int = 60                # 行间距 cm
    Rpm: int = 20               # 播种盘转速 r/min
    AntennaType: int = 0        # 0:单天线 1:双天线
    U8Resv: int = 0
    AntennaDistance: int = 0
    CrcCheck: int = 0

    def pack(self):
        return _USER.pack(self.DZTime, self.HJ, self.Rpm, self.AntennaType,
                          self.U8Resv, self.AntennaDistance, self.CrcCheck)

    @staticmethod
    def unpack(data):
        v = _USER.unpack(data)
        return UserPara(*v)


# ---------------------------------------------------------------- BZStatusType (0x21 应答)
# u8 RunState, u8 BdState, u8 Resv[2], s32 Speed, s32 RowNum, s32 OffLen,
# s32 VerticalOff, u32 LoufeiCnt[6], u32 LouZHCnt[6], s32 Resv2[4]
# 注: hd3005a2 的 Resv2[8-(LINE_NUM-4)*2] = [4], 总长 84 字节;
# 常用字段偏移与上位机(protocol.h Resv2[8])完全一致, 上位机 memcpy 超读的部分不使用。
_BZ_STATUS = struct.Struct('<BB2x iiii 6I 6I 4i')
assert _BZ_STATUS.size == SZ_BZ_STATUS, _BZ_STATUS.size


def pack_bz_status(run_state, bd_state, speed, row_num, off_len, vertical_off,
                   loufei, louzh):
    assert len(loufei) == 6 and len(louzh) == 6
    return _BZ_STATUS.pack(run_state & 0xFF, bd_state & 0xFF, speed, row_num,
                           off_len, vertical_off, *loufei[:6], *louzh[:6],
                           *([0] * 4))


# ---------------------------------------------------------------- TestModeStateType (0x08 应答)
# u32 EncoderCnt, u32 BdCnt, u32 LoufeiCnt[6], u32 LouZHCnt[6],
# u32 InputState, u32 WarningState, u32 CtrlState
_TEST_STATUS = struct.Struct('<II 6I 6I III')
assert _TEST_STATUS.size == SZ_TEST_STATUS, _TEST_STATUS.size


def pack_test_status(encoder_cnt, bd_cnt, loufei, louzh,
                     input_state, warning_state, ctrl_state):
    assert len(loufei) == 6 and len(louzh) == 6
    return _TEST_STATUS.pack(encoder_cnt, bd_cnt, *loufei[:6], *louzh[:6],
                             input_state, warning_state, ctrl_state)


def dc(obj):
    """dataclass -> dict (控制台打印用)。"""
    return asdict(obj)
