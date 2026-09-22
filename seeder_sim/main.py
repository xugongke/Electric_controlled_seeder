# -*- coding: utf-8 -*-
"""电控播种机下位机模拟器 (hd3005a1)

复刻真实播种机与 QT 上位机(SowSystem)之间的全部串口通信行为, 支持 4行机/6行机。

用法:
    python main.py --list                 列出可用串口
    python main.py --port COM60           打开串口开始模拟 (115200-8N1)
    python main.py --port COM60 --rows 6  以6行机启动
    python main.py --selftest             自测(CRC/结构体/帧/状态机)

联调: 用虚拟串口对(如 com0com)创建两个互通的 COM 口, 本模拟器打开一端,
上位机 config.ini 的 [Application] SerialPort 指向另一端。
"""

import argparse
import os
import struct
import sys
import threading
import time

import protocol as P
import layout as L
from layout import (BzCellPara, BdPara, TerPara, UserPara, LxbzPara,
                    pack_bz_status, pack_test_status, unpack_test_cmd)
from device import Device
from workproc import WorkProc, cal_ab_dir, WORK_MODE_NAMES, SEED_MODE_NAMES
from recorder import Recorder

ACK_OK = b'\x01'
ACK_FAIL = b'\x00'

_print_lock = threading.Lock()


def log(msg):
    with _print_lock:
        print(msg)
        sys.stdout.flush()


def now_ms():
    return int(time.monotonic() * 1000)


# ================================================================ 帧分发 (对齐 protocol.c FrameProcess)
class Simulator:
    def __init__(self, port=None, rows=6, speed=1000, hex_dump=False,
                 state_file=None, version_str=None, baud=115200):
        state = state_file or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                           'seeder_sim_state.json')
        self.dev = Device(state_file=state, rows=rows,
                          version_str=version_str or 'hd3005a2_sim v1.7 20260820_2')
        self.wp = WorkProc(self.dev, speed_mm_s=speed)
        self.lock = threading.RLock()
        self.hex_dump = hex_dump
        self.port = port
        self.baud = baud
        self.ser = None
        self.parser = P.FrameParser()
        self.running = False
        self.log_fn = log                     # GUI 模式下替换为信号发射
        self.recorder = Recorder()
        self.recorder.meta['行数'] = self.dev.rows
        self.recorder.meta['版本串'] = self.dev.version_str

    def log(self, msg):
        self.log_fn(msg)

    # ------------------------------------------------------------ 命令分发
    def process_frame(self, fnc, data):
        """返回应答数据域(bytes)或 None(不应答)。"""
        with self.lock:
            n = len(data)
            if fnc == P.FNC_GET_SOFT_VER:
                return self.dev.version_payload() if n == 0 else None
            if fnc == P.FNC_GET_BZ_STATUS:
                return pack_bz_status(**self.wp.get_bz_status()) if n == 0 else None
            if fnc == P.FNC_RD_DEBUG_INFO:
                # 固件按 strlen 发送, 不含 NUL, 中文 GB2312
                return self.wp.debug.encode('gb2312', errors='replace') if n == 0 else None
            if fnc == P.FNC_GET_TEST_STATUS:
                return pack_test_status(**self.wp.get_test_status()) if n == 0 else None
            if fnc == P.FNC_GET_TER_PARA:
                return self.dev.ter.pack() if n == 0 else None
            if fnc == P.FNC_GET_USER_PARA:
                return self.dev.user.pack() if n == 0 else None
            if fnc == P.FNC_GET__RTC:
                return struct.pack('<I', int(time.time()) & 0xFFFFFFFF) if n == 0 else None
            if fnc == P.FNC_SET_BZ_PARA:
                if n == L.SZ_BZ_CELL_PARA:
                    self.wp.set_bz_para(BzCellPara.unpack(data))
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_CMD_SVCTRL:
                if n == L.SZ_TEST_CMD:
                    ctrl_no, state = unpack_test_cmd(data)
                    self.wp.test_ctrl(ctrl_no, state)
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_CMD_START_BZ:
                if n == 0:
                    self.wp.cmd_start_bz()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_CMD_STOP_BZ:
                if n == 0:
                    self.wp.cmd_stop_bz()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_START_TEST:
                if n == 0:
                    self.wp.cmd_start_test()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_STOP_TEST:
                if n == 0:
                    self.wp.cmd_stop_test()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_CMD_START_LXBZ:
                if n == L.SZ_LXBZ_PARA:
                    self.dev.set_lxbz_para(LxbzPara.unpack(data))
                    self.wp.cmd_start_lxbz()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_CMD_STOP_LXBZ:
                if n == 0:
                    self.wp.cmd_stop_lxbz()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_STORE_AB:
                if n == 0:
                    self._store_ab()
                    return self.dev.bd.pack()
                return ACK_FAIL
            if fnc == P.FNC_SET_AB:
                if n == L.SZ_BD_PARA:
                    self.dev.set_bd_para(BdPara.unpack(data))
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_SET_TER_PARA:
                if n == L.SZ_TER_PARA:
                    ter = TerPara.unpack(data)
                    if ter.U8Resv2 in (4, 6) and ter.U8Resv2 != self.dev.rows:
                        self.recorder.meta['行数'] = ter.U8Resv2
                        self.recorder.note('上位机通知行数: %d行机' % ter.U8Resv2)
                        self.log('[模拟器] 上位机通知行数: %d行机' % ter.U8Resv2)
                    self.dev.set_ter_para(ter)
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_SET_USER_PARA:
                if n == L.SZ_USER_PARA:
                    self.dev.set_user_para(UserPara.unpack(data))
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_QZDD_ENABLE:
                if n == 1:
                    self.dev.qzdd_enable = data[0] != 0
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_GDDD_ENABLE:
                if n == 1:
                    self.dev.gddd_enable = data[0] != 0
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_SET_RTC:
                if n == 4:
                    return ACK_OK                    # 固件同样忽略内容直接成功
                return ACK_FAIL
            if fnc == P.FNC_RESTART_TER:
                if n == 0:
                    self.wp.cmd_restart()
                    return ACK_OK
                return ACK_FAIL
            if fnc == P.FNC_UPDATE_START:
                return ACK_OK if n == 8 else ACK_FAIL
            if fnc == P.FNC_UPDATE_BIN:
                return ACK_OK if n >= 8 else ACK_FAIL
            if fnc == P.FNC_UPDATE_END:
                return ACK_FAIL                      # 模拟器无固件可升级, CRC 必然不符
            # 0x30 / 0x32 固件未实现, 未知功能码: 均不应答
            return None

    def _store_ab(self):
        """0x23: 有效定位且已有A点时, 用模拟的当前位置作为B点并计算AB方向。"""
        bd = self.dev.bd
        if self.wp.bd_ok and bd.StartState == 1:
            dist_m = abs(self.wp._off_len()) / 100.0
            ang = bd.CalcDir if bd.CalcDirFlag == 1 else bd.StartDir
            if dist_m > 0:
                import math
                rad = math.radians(ang)
                end_n = bd.StartN + math.cos(rad) * dist_m / 6371393.0 * 180 / math.pi
                rn = 6371393.0 * math.cos(math.radians(bd.StartN))
                end_e = bd.StartE + math.sin(rad) * dist_m / rn * 180 / math.pi
                calc, _ = cal_ab_dir(bd.StartN, bd.StartE, end_n, end_e)
                bd.EndBN, bd.EndBE = end_n, end_e
                bd.CalcDir = calc
                bd.CalcDirFlag = 1

    # ------------------------------------------------------------ 串口收发
    def _reader(self):
        while self.running:
            try:
                chunk = self.ser.read(4096)
            except (OSError, ValueError):
                self.log('[模拟器] 串口读取异常, 退出接收线程')
                return
            if not chunk:
                continue
            for fnc, payload in self.parser.feed(chunk):
                self.recorder.add_frame('RX', fnc, payload)
                self._log_frame('RX', fnc, payload)
                try:
                    resp = self.process_frame(fnc, payload)
                except Exception as exc:               # 单帧异常不应终止接收线程
                    import traceback
                    self.log('[模拟器] 处理帧 0x%02X 异常: %s\n%s'
                             % (fnc, exc, traceback.format_exc()))
                    continue
                if resp is not None:
                    self.recorder.add_frame('TX', fnc, resp)
                    self._log_frame('TX', fnc, resp)
                    self._enqueue_tx(P.build_frame(fnc, resp))

    def _enqueue_tx(self, frame):
        """应答入发送队列(与接收线程解耦): 上位机接收阻塞导致串口写满时,
        接收线程不会被冻死; 队列满时丢弃最旧应答并告警。"""
        import queue as _q
        try:
            self._tx_queue.put_nowait(frame)
        except _q.Full:
            try:
                self._tx_queue.get_nowait()            # 丢最旧
            except _q.Empty:
                pass
            self._tx_dropped += 1
            try:
                self._tx_queue.put_nowait(frame)
            except _q.Full:
                pass

    def _writer(self):
        import serial
        while self.running:
            try:
                frame = self._tx_queue.get(timeout=0.2)
            except Exception:
                continue
            try:
                self.ser.write(frame)
            except serial.SerialTimeoutException:
                # 上位机长时间不读串口 -> 虚拟串口缓冲满 -> 写超时(诊断信号!)
                self._tx_timeouts += 1
                self.log('[模拟器] 警告: 上位机接收阻塞, 应答写入超时(第%d次) '
                         '——上位机侧卡顿的证据' % self._tx_timeouts)
            except (OSError, ValueError):
                self.log('[模拟器] 串口写入异常')
                return

    def _ticker(self):
        last_debug = None
        last_sig = None
        while self.running:
            with self.lock:
                self.wp.step(now_ms())
                wp = self.wp
                if wp.debug != last_debug:
                    last_debug = wp.debug
                    self.recorder.add_event('调试', wp.debug)
                sig = (wp.work_mode, wp.run_state, wp.seed_mode, wp.bd_ok, wp.paused)
                if sig != last_sig:
                    last_sig = sig
                    self.recorder.add_event('状态', self._state_line())
            time.sleep(0.01)

    def _state_line(self):
        wp = self.wp
        return ('模式=%s RunState=%s 阶段=%s 北斗=%s 行进=%s'
                % (WORK_MODE_NAMES[wp.work_mode],
                   {0: '停止', 1: '运行'}.get(wp.run_state, wp.run_state),
                   SEED_MODE_NAMES.get(wp.seed_mode, wp.seed_mode),
                   '正常' if wp.bd_ok else '丢失',
                   '暂停' if wp.paused else '正常'))

    def _log_frame(self, direction, fnc, payload):
        if not self.hex_dump:
            return
        head = P.build_frame(fnc, payload)
        self.log('%s %s(0x%02X) len=%d: %s'
                 % ('<<收' if direction == 'RX' else '>>发',
                    P.FNC_NAMES.get(fnc, '?'), fnc, len(payload), head.hex(' ').upper()))

    # ------------------------------------------------------------ 生命周期
    def start(self):
        import queue as _q
        import serial
        self._tx_queue = _q.Queue(maxsize=1000)
        self._tx_dropped = 0
        self._tx_timeouts = 0
        self.ser = serial.Serial(self.port, self.baud, bytesize=8,
                                 parity=serial.PARITY_NONE, stopbits=1,
                                 timeout=0.05, write_timeout=1.0)
        self.running = True
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._writer, daemon=True).start()
        threading.Thread(target=self._ticker, daemon=True).start()
        self.recorder.meta['串口'] = str(self.port)
        self.recorder.meta['波特率'] = '115200-8N1'
        self.recorder.meta['行数'] = self.dev.rows
        self.recorder.note('打开串口 %s, %d行机, 速度%dmm/s'
                           % (self.port, self.dev.rows, self.wp.speed_mm_s))
        self.log('[模拟器] 已打开 %s @115200-8N1, %d行机, 速度 %d mm/s'
                 % (self.port, self.dev.rows, self.wp.speed_mm_s))
        self.log('[模拟器] 输入 help 查看控制命令')

    def stop(self):
        self.running = False
        if self.ser:
            try:
                self.ser.close()
            except OSError:
                pass


# ================================================================ 自测
def selftest():
    ok = [0]

    def check(cond, msg):
        print('  [%s] %s' % ('通过' if cond else '失败', msg))
        if not cond:
            ok[0] += 1

    print('1) CRC-16/Kermit')
    # CRC-16/KERMIT 标准检验值 (RevEng 目录): "123456789" -> 0x2189
    check(P.crc16_kermit(b'123456789') == 0x2189, '标准向量 "123456789" -> 0x2189')
    # 查表法与逐位法一致性
    def bitwise(data):
        r = 0
        for b in data:
            r ^= b
            for _ in range(8):
                r = (r >> 1) ^ 0x8408 if r & 1 else r >> 1
        return r
    import random
    random.seed(42)
    data_sets = [bytes(random.randrange(256) for _ in range(23)) for _ in range(200)]
    check(all(P.crc16_kermit(d) == bitwise(d) for d in data_sets),
          '查表与逐位算法 200 组随机数据一致')

    print('2) 结构体尺寸与偏移 (对齐上位机 protocol.h)')
    for name, size in (('LXBZParaType', 12), ('TestCMDType', 4),
                       ('BZCellParaType', 92), ('BDParaType', 56), ('TerParaType', 40),
                       ('UserParaType', 16), ('BZStatusType', 84),
                       ('TestModeStateType', 68)):
        check(getattr(L, 'SZ_' + {'LXBZParaType': 'LXBZ_PARA', 'TestCMDType': 'TEST_CMD',
                                  'BZCellParaType': 'BZ_CELL_PARA', 'BDParaType': 'BD_PARA',
                                  'TerParaType': 'TER_PARA', 'UserParaType': 'USER_PARA',
                                  'BZStatusType': 'BZ_STATUS',
                                  'TestModeStateType': 'TEST_STATUS'}[name]) == size,
              '%s == %d 字节' % (name, size))
    ter = TerPara(U8Resv2=6, A=-12, EncodeNum=700)
    check(ter.pack()[23] == 6 and ter.pack()[0:2] == struct.pack('<h', -12),
          'TerPara 偏移23=行数U8Resv2, 偏移0=s16 A')
    bz = BzCellPara(RowNum=5, Density=[1, 2, 3, 4, 5, 6], NextDensity=[7, 8, 9, 10, 11, 12])
    rt = BzCellPara.unpack(bz.pack())
    check(rt.Density == [1, 2, 3, 4, 5, 6] and rt.NextDensity[5] == 12
          and rt.RowNum == 5, 'BZCellPara pack/unpack 往返')
    bd = BdPara(StartN=36.5, StartState=1, CrcCheck=0xDEADBEEF)
    rt = BdPara.unpack(bd.pack())
    check(rt.StartN == 36.5 and rt.StartState == 1 and rt.CrcCheck == 0xDEADBEEF,
          'BDPara 往返(double/float/u32)')

    print('3) 帧构造/解析')
    f1 = P.build_frame(P.FNC_GET_SOFT_VER)
    f2 = P.build_frame(P.FNC_SET_BZ_PARA, BzCellPara(RowNum=9).pack())
    parser = P.FrameParser()
    frames = parser.feed(b'\x00\x01\x02' + f1 + f2[:5]) + parser.feed(f2[5:] + b'\xff')
    check(len(frames) == 2 and frames[0][0] == P.FNC_GET_SOFT_VER
          and frames[1][1] == BzCellPara(RowNum=9).pack(),
          '垃圾前缀+半帧跨feed重组')
    bad = bytearray(f1)
    bad[5] ^= 0xFF
    parser2 = P.FrameParser()
    frames = parser2.feed(bytes(bad) + f1)
    check(len(frames) == 1, 'CRC错误帧被丢弃后恢复同步')

    print('4) 行数切换 (0x25 U8Resv2)')
    dev = Device(state_file=None, rows=4)
    sim = Simulator.__new__(Simulator)
    sim.dev, sim.wp, sim.lock, sim.hex_dump = dev, WorkProc(dev), threading.RLock(), False
    sim.recorder = Recorder()
    sim.log_fn = lambda s: None
    sim.process_frame(P.FNC_SET_TER_PARA, TerPara(U8Resv2=6).pack())
    check(dev.rows == 6, 'U8Resv2=6 -> rows=6')
    sim.process_frame(P.FNC_SET_TER_PARA, TerPara(U8Resv2=4, GearRatio=1).pack())
    check(dev.rows == 4 and dev.ter.GearRatio == 10, 'U8Resv2=4 -> rows=4, GearRatio<2 被纠正为10')

    print('5) ACK/静默规则')
    check(sim.process_frame(P.FNC_CMD_START_BZ, b'') == ACK_OK, '0x0A 空数据域 ACK 1')
    check(sim.process_frame(P.FNC_CMD_START_BZ, b'\x01') == ACK_FAIL, '0x0A 带数据 ACK 0')
    check(sim.process_frame(P.FNC_GET_BZ_STATUS, b'\x01') is None, '0x21 带数据 -> 静默')
    check(sim.process_frame(P.FNC_GET_QZDD_STATE, b'') is None, '0x30 未实现 -> 静默')
    r21 = sim.process_frame(P.FNC_GET_BZ_STATUS, b'')
    check(isinstance(r21, bytes) and len(r21) == L.SZ_BZ_STATUS,
          '0x21 应答 %d 字节 (hd3005a2: Resv2[4])' % L.SZ_BZ_STATUS)
    rA3 = sim.process_frame(P.FNC_GET_SOFT_VER, b'')
    check(rA3.startswith(b'hd3005a2_sim'), '版本串: %r' % rA3.rstrip(b'\x00'))
    r08 = sim.process_frame(P.FNC_GET_TEST_STATUS, b'')
    check(isinstance(r08, bytes) and len(r08) == 68, '0x08 应答 68 字节')
    check(struct.unpack_from('<I', r08, 0)[0] == 0, '0x08 EncoderCnt=0 (hd3005a2已删编码器)')
    sim.wp.zerofail = True
    r08 = sim.process_frame(P.FNC_GET_TEST_STATUS, b'')
    warn = struct.unpack_from('<I', r08, 60)[0]
    inp = struct.unpack_from('<I', r08, 56)[0]
    check(warn == 0x0F and (inp & 0xF) == 0,
          '零位故障: 报警位置1(0x%X) 零位输入位清0' % warn)
    sim.wp.zerofail = False
    r22 = sim.process_frame(P.FNC_RD_DEBUG_INFO, b'')
    check(isinstance(r22, bytes) and len(r22) > 0, '0x22 调试串非空(%d字节)' % len(r22 or b''))

    print('6) 小区播种状态机全流程')
    dev2 = Device(state_file=None, rows=4)
    wp = WorkProc(dev2)
    wp.speed_mm_s = 1000
    sim.dev, sim.wp = dev2, wp
    t = 100000

    def tick(ms=100):
        nonlocal t
        for _ in range(ms // 10):
            t += 10
            wp.step(t)

    # 真实上位机流程: 设置AB线(有效A点) -> 下发第一小区参数 -> 启动播种
    sim.process_frame(P.FNC_SET_AB, BdPara(StartN=36.5, StartE=117.0, StartState=1).pack())
    zone = BzCellPara(TXFlag=1, RowNum=1, InS=100, Density=[5000, 5000, 5000, 5000, 0, 0],
                      CellLen=2000, StartPOS=0, DisplayRowNum=1,
                      NextRowNum=2, NextInS=100, NextDensity=[5000, 5000, 5000, 5000, 0, 0],
                      NextCellLen=2000, NextStartPOS=2100, NextDisplayRowNum=2,
                      isAfterNextZoneSow=1)
    sim.process_frame(P.FNC_SET_BZ_PARA, zone.pack())
    sim.process_frame(P.FNC_CMD_START_BZ, b'')
    tick(50)
    st = wp.get_bz_status()
    check(st['run_state'] == 1, '启动后 RunState=1(准备)')
    tick(500)
    check(wp.bz_curr.RowNum == -10000000, '600ms窗口内行号=-10000000')
    check(wp.get_bz_status()['vertical_off'] == -240,
          '600ms窗口内垂直偏差=-240 (4行x60cm)')
    tick(300)                                        # 越过600ms窗口, 行进开始
    check(wp.bz_curr.RowNum == 1, '窗口结束后行号=1')
    tick(10000)                                      # 预充种 + 行进 800cm 至小区起点
    st = wp.get_bz_status()
    check(st['run_state'] == 0x81, '行进播种中 RunState=0x81, 实际=%#x' % st['run_state'])
    check(st['speed'] == 1000 and st['bd_state'] == 1, '速度1000mm/s 北斗正常')
    check(st['vertical_off'] == 0, '首排垂直偏差=0 (初始-行数x行距, 启动+行数x行距)')
    tick(25000)                                      # 走完小区+过道 -> 换排
    check(wp.bz_curr.RowNum == 2, '换排后 RowNum=2, 实际=%r' % wp.bz_curr.RowNum)
    check(sum(wp.louzh[:4]) > 0, '漏种计数增长: %r' % wp.louzh[:4])
    check(wp.debug.startswith(('等待清种', '播种结束', '开始', '跳过'))
          or '刮种' in wp.debug or '倒种' in wp.debug, '调试信息: %s' % wp.debug)
    # 二次启动 -> 掉头一次, 垂直偏差 +240 (4行x60cm)
    sim.process_frame(P.FNC_CMD_START_BZ, b'')
    tick(1000)
    check(wp.get_bz_status()['vertical_off'] == 240, '二次启动后垂直偏差=+240')
    # 一键初始化 -> 垂直偏差复位, 再次启动回到0
    wp.press_init()
    check(wp.vertical_off == -240, '一键初始化后垂直偏差复位为-240')
    sim.process_frame(P.FNC_CMD_START_BZ, b'')
    tick(1000)
    check(wp.get_bz_status()['vertical_off'] == 0, '初始化后再启动垂直偏差=0')

    print('7) 连续播种')
    dev3 = Device(state_file=None, rows=6)
    wp3 = WorkProc(dev3)
    sim.wp = wp3
    sim.dev = dev3
    wp3.bd_tx_flag = False      # 模拟上一趟反向小区任务的方向残留
    sim.process_frame(P.FNC_CMD_START_LXBZ,
                      LxbzPara(Density=8000, CellLen=500, Hju=60).pack())
    tick3 = 0
    t3 = 500000
    for _ in range(600):                             # 6s
        t3 += 10
        wp3.step(t3)
    st = wp3.get_bz_status()
    check(st['run_state'] == 0x81, '连续播种 RunState=0x81')
    check(st['speed'] == 1000 and st['off_len'] > 0,
          '连续播种固定同向: 排行程正向递增(速度%d 行程%d)' % (st['speed'], st['off_len']))
    check(wp3.debug.startswith('连续播种模式'), '调试: %s' % wp3.debug)
    check(min(wp3.louzh[:6]) > 0, '6行机6路计数全部增长: %r' % wp3.louzh)

    print('8) 测试模式电机位映射 (6行机, CtrlNo 16-22)')
    wp3.cmd_stop_lxbz()                              # 先停止连续播种, 电机停转
    for _ in range(20):
        t3 += 10
        wp3.step(t3)
    wp3.test_ctrl(20, True)                           # 自动供种电机 -> bit4
    st8 = wp3.get_test_status()
    check(bool(wp3.dj_bits & (1 << 4)) and bool(st8['input_state'] & (1 << 4)),
          'CtrlNo20=供种电机: DJ bit4置位, 接近开关输入bit4亮')
    check((st8['input_state'] & 0xF) == 0xF,
          '仅开供种电机时零位开关1-4仍触发(供种位不在disc_mask内)')
    wp3.test_ctrl(22, True)                           # 播种盘6 -> bit6
    check(bool(wp3.dj_bits & (1 << 6)) and wp3.disc_mask == 0x6F,
          'CtrlNo22=播种盘6(bit6), 6行机disc_mask=0x6F')
    st8 = wp3.get_test_status()
    check(st8['ctrl_state'] & (1 << 20) and st8['ctrl_state'] & (1 << 22),
          'CtrlState bit20(供种)/bit22(盘6) 正确回显')

    print('9) 测试模式计数粒度 (计数跟随各自的播种盘电机)')
    wp3.cmd_start_test()                             # 进入测试模式(会清电机位)
    for _ in range(20):
        t3 += 10
        wp3.step(t3)
    wp3.test_ctrl(20, True)                           # 仅开供种电机
    wp3._clear_lz_cnt()
    for _ in range(100):
        t3 += 10
        wp3.step(t3)
    check(sum(wp3.louzh) == 0, '仅开供种电机(bit4)时计数不增长: %r' % wp3.louzh)
    wp3.test_ctrl(16, True)                           # 仅播种盘1
    wp3._clear_lz_cnt()
    for _ in range(200):
        t3 += 10
        wp3.step(t3)
    check(wp3.louzh[0] > 0 and wp3.louzh[1:] == [0] * 5,
          '仅播种盘1转动 -> 只有第1路计数: %r' % wp3.louzh)
    check(wp3.loufei[1:] == [0] * 5, '漏肥同样只有第1路: %r' % wp3.loufei)
    wp3.test_ctrl(17, True)                           # 加开播种盘2
    wp3._clear_lz_cnt()
    for _ in range(200):
        t3 += 10
        wp3.step(t3)
    check(wp3.louzh[0] > 0 and wp3.louzh[1] > 0 and wp3.louzh[2:] == [0] * 4,
          '开盘1+盘2 -> 只有第1/2路计数: %r' % wp3.louzh)

    print('10) hd3005a2 行为复刻 (6行机)')
    wp3.louzh = [10] * 6
    wp3.loufei = [10] * 6
    wp3._clear_lz_cnt()
    check(wp3.louzh == [0] * 6,
          'ClearLzCnt 全部6路清零 (固件已修复为 i<LINE_NUM): %r' % wp3.louzh)
    wp3.bz_curr.Density = [1] * 6
    wp3.bz_curr.NextDensity = [2] * 6
    wp3.bz_curr.RowNum = 1
    wp3.bz_curr.NextRowNum = 1
    wp3.bz_cell.RowNum = 1
    wp3.bz_cell.NextRowNum = 2
    wp3.bz_cell.NextDensity = [3] * 6
    upd = wp3._update_row_num_check()
    check(upd and wp3.bz_curr.Density == [3] * 6,
          '换排密度拷贝全6路更新 (固件已修复为sizeof): %r' % wp3.bz_curr.Density)

    print('11) 反向趟(掉头)计数窗口回归')
    # 紧凑地图: 行长200cm 过道50cm, 同向 row0->2 一趟, 反向 row2->0 一趟,
    # 校验反向趟第一排计数不缩短(曾因反向换排阈值符号错误被截短)
    RL, AI = 200, 50

    def z4(row, d, nr):
        z = BzCellPara()
        z.TXFlag = 1 if d else 0
        z.RowNum, z.NextRowNum = row, nr
        z.CellLen = z.NextCellLen = RL
        z.InS = z.NextInS = AI
        z.Density = z.NextDensity = [5000] * 6
        z.isAfterNextZoneSow = 1
        near = lambda r: r * (RL + AI)
        z.StartPOS = near(row) if d else near(row) + RL
        z.NextStartPOS = near(nr) if d else near(nr) + RL
        return z

    def trip(order, d, t4, wp4):
        nxt = {r: order[i + 1] for i, r in enumerate(order[:-1])}
        wp4.set_bz_para(z4(order[0], d, nxt[order[0]]))
        wp4.cmd_start_bz()
        res, seen, last = {}, {}, None
        n = 0
        while n < 4000:
            t4[0] += 10
            wp4.step(t4[0])
            n += 1
            if n % 20:
                continue
            st = wp4.get_bz_status()
            rn = st['row_num']
            if rn <= -10000000:
                continue
            if rn != last:
                if last is not None:
                    res[last] = seen.get(last, 0)
                last = rn
                if rn in nxt:
                    wp4.set_bz_para(z4(rn, d, nxt[rn]))
            seen[rn] = sum(st['louzh'][:4])
        res[last] = seen.get(last, 0)
        wp4.cmd_stop_bz()
        for _ in range(30):
            t4[0] += 10
            wp4.step(t4[0])
        return res

    dev4 = Device(state_file=None, rows=4)
    dev4.ter.A, dev4.ter.B = 60, 90
    dev4.bd.StartState = 1
    wp4 = WorkProc(dev4)
    t4 = [1000]
    fwd = trip([0, 1, 2], True, t4, wp4)
    rev = trip([2, 1, 0], False, t4, wp4)
    vals = list(fwd.values()) + list(rev.values())
    check(min(vals) >= max(vals) * 0.8,
          '同向/反向各排计数一致 (同向%s 反向%s)' %
          (sorted(fwd.values()), sorted(rev.values())))

    print()
    if ok[0]:
        print('自测完成: %d 项失败' % ok[0])
        sys.exit(1)
    print('自测全部通过')


# ================================================================ 入口
def main():
    ap = argparse.ArgumentParser(description='电控播种机下位机模拟器')
    ap.add_argument('--gui', action='store_true', help='启动图形界面')
    ap.add_argument('--port', help='串口名, 如 COM60')
    ap.add_argument('--rows', type=int, default=6, choices=(4, 6), help='行数(默认6, 对应hd3005a2)')
    ap.add_argument('--speed', type=int, default=1000, help='模拟行进速度 mm/s(默认1000)')
    ap.add_argument('--state', help='参数持久化JSON路径(默认脚本目录)')
    ap.add_argument('--hex', action='store_true', help='启动时打开原始帧打印')
    ap.add_argument('--version-str', help='覆盖版本串(0xA3应答)')
    ap.add_argument('--list', action='store_true', help='列出可用串口')
    ap.add_argument('--selftest', action='store_true', help='运行自测')
    ap.add_argument('--export-frames', metavar='FILE',
                    help='退出时导出收发帧记录到文件')
    ap.add_argument('--export-debug', metavar='FILE',
                    help='退出时导出调试信息/状态变化到文件')
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return
    if args.list:
        from serial.tools import list_ports
        for p in list_ports.comports():
            print('%s  %s' % (p.device, p.description))
        return
    if args.gui:
        from gui import run_gui
        run_gui(args)
        return
    if not args.port:
        ap.print_help()
        return

    try:
        import serial  # noqa: F401
    except ImportError:
        print('缺少 pyserial, 请先执行: pip install pyserial')
        sys.exit(1)

    sim = Simulator(port=args.port, rows=args.rows, speed=args.speed,
                    hex_dump=args.hex, state_file=args.state,
                    version_str=args.version_str)
    from console import Console, HELP
    con = Console(sim)
    try:
        sim.start()
        print(HELP)
        while True:
            try:
                line = input('模拟器> ')
            except EOFError:
                # 无控制台输入(后台运行)时保持运行
                print('[模拟器] 无控制台输入, 后台运行中 (Ctrl+C 退出)')
                while True:
                    time.sleep(1)
            if not con.handle(line):
                break
    except KeyboardInterrupt:
        pass
    finally:
        sim.stop()
        _cli_export(sim, args)
        print('[模拟器] 已退出')


def _cli_export(sim, args):
    if args.export_frames:
        n = sim.recorder.export_frames(args.export_frames)
        print('[模拟器] 收发帧记录已导出: %s (%d帧)' % (args.export_frames, n))
    if args.export_debug:
        n = sim.recorder.export_events(args.export_debug)
        print('[模拟器] 调试信息已导出: %s (%d条)' % (args.export_debug, n))


if __name__ == '__main__':
    main()
