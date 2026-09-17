# -*- coding: utf-8 -*-
"""上位机流程端到端联测脚本。

在本机另一端串口上扮演 QT 上位机(SowSystem), 按真实流程收发帧并校验应答,
用于不启动 QT 程序即可验证模拟器/虚拟串口环境是否正常。

用法:
    1. 先启动模拟器:  python main.py --port COM8 --rows 4
    2. 再运行本脚本:  python test_uc_flow.py --port COM9
"""

import argparse
import struct
import sys
import time

import serial

import protocol as P
from layout import (BzCellPara, BdPara, TerPara, UserPara, LxbzPara,
                    SZ_BZ_STATUS, SZ_BZ_CELL_PARA, SZ_TEST_STATUS)

PASS, FAIL = 0, 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


class UcSide:
    """扮演上位机: 发帧/收帧。"""

    def __init__(self, port, baud=115200):
        self.ser = serial.Serial(port, baud, timeout=0.2)
        self.parser = P.FrameParser()

    def send(self, fnc, payload=b''):
        self.ser.write(P.build_frame(fnc, payload))

    def recv(self, want_fnc=None, timeout=2.0):
        """收一帧; want_fnc 指定时跳过其他功能码(如异步心跳应答)。"""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            frames = self.parser.feed(self.ser.read(4096))
            for fnc, payload in frames:
                if want_fnc is None or fnc == want_fnc:
                    return fnc, payload
        return None, None

    def ask(self, fnc, payload=b'', timeout=2.0):
        self.send(fnc, payload)
        return self.recv(fnc, timeout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', required=True, help='虚拟串口对中上位机一侧, 如 COM9')
    args = ap.parse_args()

    uc = UcSide(args.port)

    print('1) 心跳/版本 (0xA3)')
    fnc, data = uc.ask(P.FNC_GET_SOFT_VER)
    check(fnc == P.FNC_GET_SOFT_VER and data.endswith(b'\x00'),
          '版本串: %r' % data)

    print('2) 参数读写 (0x26/0x28/0x25/0x27)')
    fnc, data = uc.ask(P.FNC_GET_TER_PARA)
    check(fnc == P.FNC_GET_TER_PARA and len(data) == 40, '厂家参数 40 字节')
    fnc, data = uc.ask(P.FNC_GET_USER_PARA)
    check(fnc == P.FNC_GET_USER_PARA and len(data) == 16, '用户参数 16 字节')
    fnc, data = uc.ask(P.FNC_SET_TER_PARA, TerPara(U8Resv2=6, GearRatio=10, HoleNum=9).pack())
    check(data == b'\x01', '0x25 设置6行机 ACK=1')
    fnc, data = uc.ask(P.FNC_SET_USER_PARA, UserPara(DZTime=1500, HJ=60, Rpm=20).pack())
    check(data == b'\x01', '0x27 设置用户参数 ACK=1')

    print('3) AB线与小区参数 (0x24/0x20)')
    fnc, data = uc.ask(P.FNC_SET_AB,
                       BdPara(StartN=36.5, StartE=117.0, StartState=1, CalcDirFlag=1,
                              CalcDir=90.0).pack())
    check(data == b'\x01', '0x24 设置AB线 ACK=1')
    fnc, data = uc.ask(P.FNC_STORE_AB)
    check(fnc == P.FNC_STORE_AB and len(data) == 56 and BdPara.unpack(data).CalcDirFlag == 1,
          '0x23 读回AB线 56 字节 且 B点/方向有效')

    zone = BzCellPara(TXFlag=1, RowNum=1, InS=100, Density=[5000] * 4 + [0, 0],
                      CellLen=2000, StartPOS=0, DisplayRowNum=1,
                      NextRowNum=2, NextInS=100, NextDensity=[5000] * 4 + [0, 0],
                      NextCellLen=2000, NextStartPOS=2100, NextDisplayRowNum=2,
                      isAfterNextZoneSow=1)
    fnc, data = uc.ask(P.FNC_SET_BZ_PARA, zone.pack())
    check(data == b'\x01', '0x20 下发小区参数(92字节) ACK=1')

    print('4) 启动小区播种 (0x0A) 并轮询状态 (0x21/0x22)')
    fnc, data = uc.ask(P.FNC_CMD_START_BZ)
    check(data == b'\x01', '0x0A ACK=1')
    time.sleep(0.2)                       # 600ms 无效行号窗口内
    fnc, data = uc.ask(P.FNC_GET_BZ_STATUS)
    rownum_invalid_seen = len(data) == SZ_BZ_STATUS \
        and struct.unpack_from('<i', data, 8)[0] == -10000000
    print('     (轮询到 RunState/行号/计数...)')
    ok81, okrow, okcnt = False, False, False
    t0 = time.monotonic()
    last_cnt = None
    while time.monotonic() - t0 < 40:
        fnc, data = uc.ask(P.FNC_GET_BZ_STATUS)
        if not data or len(data) != SZ_BZ_STATUS:
            check(False, '0x21 应答 %d 字节' % len(data or b''))
            break
        run = data[0]
        speed, rownum, off = struct.unpack_from('<iii', data, 4)
        louzh = list(struct.unpack_from('<6I', data, 44))
        if run == 0x81 and speed == 1000:
            ok81 = True
        if rownum == 1:
            okrow = True
        if last_cnt is not None and sum(louzh) > last_cnt:
            okcnt = True
        last_cnt = sum(louzh)
        fnc, dbg = uc.ask(P.FNC_RD_DEBUG_INFO)
        if rownum == 2:
            break
        time.sleep(0.2)
    check(ok81, '出现 RunState=0x81 速度1000mm/s')
    check(okrow, '行号=1')
    check(okcnt, '漏种计数增长')
    fnc, dbg = uc.ask(P.FNC_RD_DEBUG_INFO)
    check(fnc == P.FNC_RD_DEBUG_INFO and len(dbg) > 0, '调试信息: %s'
          % (dbg.decode('gb2312', errors='replace') if dbg else ''))
    check(rownum_invalid_seen, '启动初期行号=-10000000 (上位机判定未播种窗口)')

    print('5) 停止播种 (0x0B)')
    fnc, data = uc.ask(P.FNC_CMD_STOP_BZ)
    check(data == b'\x01', '0x0B ACK=1')
    time.sleep(0.3)
    fnc, data = uc.ask(P.FNC_GET_BZ_STATUS)
    check(data[0] == 0, '停止后 RunState=0')

    print('6) 测试模式 (0x0E/0x09/0x08/0x0F)')
    fnc, data = uc.ask(P.FNC_START_TEST)
    check(data == b'\x01', '0x0E 进入测试模式 ACK=1')
    fnc, data = uc.ask(P.FNC_CMD_SVCTRL, struct.pack('<HH', 0, 1))   # 预落种开
    check(data == b'\x01', '0x09 控制预落种 ACK=1')
    time.sleep(0.2)
    fnc, data = uc.ask(P.FNC_GET_TEST_STATUS)
    ok_len = len(data) == SZ_TEST_STATUS
    ctrl = struct.unpack_from('<I', data, 64)[0] if ok_len else 0
    check(ok_len and (ctrl & 1), '0x08 CtrlState bit0(预落种)=1, ctrl=0x%X' % ctrl)
    fnc, data = uc.ask(P.FNC_STOP_TEST)
    check(data == b'\x01', '0x0F 退出测试模式 ACK=1')

    print('7) 连续播种 (0x11/0x12)')
    fnc, data = uc.ask(P.FNC_CMD_START_LXBZ,
                       LxbzPara(Density=8000, CellLen=500, Hju=60).pack())
    check(data == b'\x01', '0x11 启动连续播种 ACK=1')
    ok81, okcnt = False, False
    last = None
    t0 = time.monotonic()
    while time.monotonic() - t0 < 8:
        fnc, data = uc.ask(P.FNC_GET_BZ_STATUS)
        run = data[0]
        louzh = list(struct.unpack_from('<6I', data, 44))
        if run == 0x81:
            ok81 = True
        if last is not None and sum(louzh) > last:
            okcnt = True
        last = sum(louzh)
        time.sleep(0.2)
    check(ok81, '连续播种 RunState=0x81')
    check(okcnt, '连续播种计数增长')
    fnc, data = uc.ask(P.FNC_CMD_STOP_LXBZ)
    check(data == b'\x01', '0x12 停止 ACK=1')

    print('8) 未实现命令静默 (0x30)')
    uc.send(P.FNC_GET_QZDD_STATE)
    fnc, data = uc.recv(timeout=0.6)
    check(fnc is None, '0x30 无应答')

    print()
    print('联测结果: %d 通过, %d 失败' % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
