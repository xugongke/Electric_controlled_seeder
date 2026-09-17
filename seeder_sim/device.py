# -*- coding: utf-8 -*-
"""虚拟设备参数与持久化(模拟 EEPROM)。

- 参数默认值对齐 hd3005a1/Src/para.c ParaInit()/ParaLegalCheck()
- 0x25/0x27 设置参数后应用相同合法化检查并保存到 JSON 文件
- 行数(4/6)由 0x25 厂家参数偏移23的 U8Resv2 通知(上位机 config.ini 的 DeviceType)
"""

import json
import os
import zlib

from layout import (TerPara, UserPara, BdPara, LxbzPara)

# CRC32Calc(PARA_CRC_SEED, ...) —— 固件 PARA_CRC_SEED = 0x04C11DB7 大端按字节处理,
# 这里仅用于回读时填充 CrcCheck 字段, 上位机不解校验, 用标准 CRC32 即可。
PARA_CRC_SEED = 0x04C11DB7


def para_crc(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


class Device:
    """设备级状态: 厂家/用户/AB线参数、行数、电压、版本串。"""

    def __init__(self, state_file=None, rows=6,
                 version_str='hd3005a2_sim v1.7 20260820_2'):
        self.state_file = state_file
        self.ter = TerPara()
        self.user = UserPara()
        self.bd = BdPara()
        self.lxbz = LxbzPara()
        self.rows = rows                    # 4 或 6, 可被 0x25 U8Resv2 运行时更新
        self.voltage_tenths = 121           # 12.1V, 仅出现在版本串中
        self.version_str = version_str
        self.qzdd_enable = False            # 0x29 清种时刻打点
        self.gddd_enable = False            # 0x31 过道中间打点
        if state_file and os.path.exists(state_file):
            self._load()
            self.para_legal_check()
            if self.ter.U8Resv2 in (4, 6):       # 已持久化的行数优先
                self.rows = self.ter.U8Resv2
        else:
            self.ter.U8Resv2 = rows              # 无存档时以启动参数为准
            self.para_legal_check()

    # ------------------------------------------------------------ 参数合法化
    def para_legal_check(self):
        """对齐 para.c ParaLegalCheck()。"""
        t, u = self.ter, self.user
        if t.GearRatio < 2:
            t.GearRatio = 10
        if t.HoleNum == 0:
            t.HoleNum = 9
        if u.HJ < 10 or u.HJ > 5000:
            u.HJ = 60
        if u.DZTime < 100 or u.DZTime > 10000:
            u.DZTime = 1500
        if u.Rpm < 5 or u.Rpm > 70:
            u.Rpm = 20
        if t.TapperTime > 1000:
            t.TapperTime = 60
        if t.MicroStepValue > 6400:
            t.MicroStepValue = 800
        if t.EncodeNum == 0:
            t.EncodeNum = 700

    def lxbz_para_check(self):
        """对齐 work_proc.c LXBZParaCheck()。"""
        p = self.lxbz
        if p.Density < 100:
            p.Density = 1000
        if p.Hju < 5:
            p.Hju = 60
        if p.CellLen < 10:
            p.CellLen = 500

    # ------------------------------------------------------------ 设置参数(0x25/0x27)
    def set_ter_para(self, ter: TerPara):
        self.ter = ter
        if ter.U8Resv2 in (4, 6):
            self.rows = ter.U8Resv2
        self.para_legal_check()
        self.save()

    def set_user_para(self, user: UserPara):
        self.user = user
        self.para_legal_check()
        self.save()

    def set_bd_para(self, bd: BdPara):
        """0x24: StartState != 1 时固件把整包清零后仍然 ACK 成功。"""
        if bd.StartState != 1:
            bd = BdPara()
        self.bd = bd
        # 固件 WriteBDPara 不再落 EEPROM(#if 0), 上位机每次开始前都会重新下发

    def set_lxbz_para(self, lxbz: LxbzPara):
        self.lxbz = lxbz
        self.lxbz_para_check()

    # ------------------------------------------------------------ 持久化
    def save(self):
        if not self.state_file:
            return
        try:
            data = {
                'ter': vars(self.ter).copy(),
                'user': vars(self.user).copy(),
                'bd': vars(self.bd).copy(),
                'lxbz': vars(self.lxbz).copy(),
            }
            data['ter']['CrcCheck'] = para_crc(self.ter.pack()[:36])
            data['user']['CrcCheck'] = para_crc(self.user.pack()[:12])
            with open(self.state_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=1)
        except OSError:
            pass

    def _load(self):
        try:
            with open(self.state_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            for key, target in (('ter', self.ter), ('user', self.user),
                                ('bd', self.bd), ('lxbz', self.lxbz)):
                if key in data:
                    for k, v in data[key].items():
                        if hasattr(target, k):
                            setattr(target, k, v)
        except (OSError, ValueError):
            pass

    # ------------------------------------------------------------ 版本串(0xA3)
    def version_payload(self) -> bytes:
        """固件格式: "版本,vol:%d.%d" + NUL。"""
        text = '%s,vol:%d.%d' % (self.version_str,
                                 self.voltage_tenths // 10, self.voltage_tenths % 10)
        return text.encode('gb2312') + b'\x00'
