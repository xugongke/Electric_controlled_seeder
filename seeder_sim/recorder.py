# -*- coding: utf-8 -*-
"""联调记录与导出: 收发帧记录、调试信息/状态变化记录、导出为文本文件。

导出文件为 UTF-8(带BOM) 纯文本, 可直接用记事本/Excel 打开, 方便回传排查问题。
"""

import datetime
import struct
import threading
import time

import protocol as P

ACK_FNCS = {P.FNC_SET_RTC, P.FNC_RESTART_TER, P.FNC_UPDATE_START, P.FNC_UPDATE_BIN,
            P.FNC_UPDATE_END, P.FNC_CMD_SVCTRL, P.FNC_CMD_START_BZ, P.FNC_CMD_STOP_BZ,
            P.FNC_START_TEST, P.FNC_STOP_TEST, P.FNC_CMD_START_LXBZ, P.FNC_CMD_STOP_LXBZ,
            P.FNC_SET_BZ_PARA, P.FNC_SET_AB, P.FNC_SET_TER_PARA, P.FNC_SET_USER_PARA,
            P.FNC_QZDD_ENABLE, P.FNC_GDDD_ENABLE}


def _ts(t):
    return datetime.datetime.fromtimestamp(t).strftime('%H:%M:%S.%f')[:-3]


def describe_frame(direction, fnc, payload):
    """生成一帧的摘要文字。direction: 'RX'=上位机->模拟器, 'TX'=模拟器->上位机。"""
    try:
        if len(payload) == 1 and fnc in ACK_FNCS:
            return 'ACK 成功(1)' if payload[0] else 'ACK 失败(0)'
        if fnc == P.FNC_GET_SOFT_VER and direction == 'TX':
            return '版本: ' + payload.rstrip(b'\x00').decode('gb2312', errors='replace')
        if fnc == P.FNC_RD_DEBUG_INFO and direction == 'TX':
            return '调试: ' + payload.decode('gb2312', errors='replace')
        if fnc == P.FNC_GET_BZ_STATUS and direction == 'TX' and len(payload) >= 52:
            run, bd = payload[0], payload[1]
            speed, rownum, off, vert = struct.unpack_from('<iiii', payload, 4)
            louzh = struct.unpack_from('<6I', payload, 44)
            return ('Run=0x%02X 北斗=%d 速度=%dmm/s 行号=%d 行程=%dcm 垂直=%dcm 漏种=%s'
                    % (run, bd, speed, rownum, off, vert,
                       '/'.join(str(x) for x in louzh)))
        if fnc == P.FNC_GET_TEST_STATUS and direction == 'TX' and len(payload) >= 68:
            enc, bd = struct.unpack_from('<II', payload, 0)
            inp, warn, ctrl = struct.unpack_from('<III', payload, 56)
            return ('编码器=%d 北斗开关=%d 输入=0x%X 报警=0x%X 控制=0x%X'
                    % (enc, bd, inp, warn, ctrl))
        if fnc == P.FNC_GET_TER_PARA and direction == 'TX' and len(payload) >= 24:
            a, b, enc = struct.unpack_from('<hhH', payload, 0)
            hole = payload[7]
            gear, micro = struct.unpack_from('<HH', payload, 8)
            return ('A=%d B=%d 编码比=%d 孔数=%d 减速比=%d 细分=%d 行数=%d'
                    % (a, b, enc, hole, gear, micro, payload[23]))
        if fnc == P.FNC_SET_TER_PARA and direction == 'RX' and len(payload) >= 24:
            a, b, enc = struct.unpack_from('<hhH', payload, 0)
            return ('A=%d B=%d 编码比=%d 孔数=%d 行数=%d'
                    % (a, b, enc, payload[7], payload[23]))
        if fnc in (P.FNC_GET_USER_PARA, P.FNC_SET_USER_PARA) and len(payload) >= 12:
            dz, hj, rpm = struct.unpack_from('<HhI', payload, 0)
            return '倒种时间=%dms 行距=%dcm 转速=%dr/min' % (dz, hj, rpm)
        if fnc in (P.FNC_SET_AB, P.FNC_STORE_AB) and len(payload) >= 48:
            vals = struct.unpack_from('<ddddff', payload, 0)
            ss, cdf, off, off_t = struct.unpack_from('<HHHH', payload, 40)
            return ('A(%f,%f) B(%f,%f) 方向=%.1f A有效=%d B有效=%d 偏移=%dcm'
                    % (vals[1], vals[0], vals[3], vals[2], vals[5], ss, cdf, off))
        if fnc == P.FNC_SET_BZ_PARA and direction == 'RX' and len(payload) >= 92:
            tx = payload[0]
            row, ins = struct.unpack_from('<ii', payload, 4)
            dens = struct.unpack_from('<6i', payload, 12)
            cell, start = struct.unpack_from('<ii', payload, 36)
            nrow = struct.unpack_from('<i', payload, 48)[0]
            return ('方向=%s 行号=%d->%d 行长=%dcm 过道=%dcm 起点=%dcm 密度=%s'
                    % ('同向' if tx else '反向', row, nrow, cell, ins, start,
                       '/'.join(str(x) for x in dens)))
        if fnc == P.FNC_CMD_START_LXBZ and direction == 'RX' and len(payload) >= 12:
            dens, cell = struct.unpack_from('<II', payload, 0)
            hju = struct.unpack_from('<H', payload, 8)[0]
            return ('密度=%d株/亩 行长=%dcm 行距=%dcm' % (dens, cell, hju))
        if fnc == P.FNC_CMD_SVCTRL and direction == 'RX' and len(payload) >= 4:
            no, st = struct.unpack_from('<HH', payload, 0)
            return '控制单元%d %s' % (no, '开' if st else '关')
        if fnc in (P.FNC_QZDD_ENABLE, P.FNC_GDDD_ENABLE) and len(payload) >= 1:
            return '使能' if payload[0] else '关闭'
        if fnc == P.FNC_GET__RTC and direction == 'TX' and len(payload) >= 4:
            return '时间戳=%d' % struct.unpack('<I', payload[:4])[0]
    except Exception:
        pass
    return ''


class Recorder:
    """线程安全的收发帧/事件记录器。"""

    def __init__(self, max_frames=20000, max_events=10000):
        self._lock = threading.Lock()
        self.max_frames = max_frames
        self.max_events = max_events
        self.frames = []            # (t, dir, fnc, payload)
        self.events = []            # (t, kind, text)
        self.dropped = 0
        self.rx_cnt = 0
        self.tx_cnt = 0
        self.recording = True
        self.session_start = time.time()
        self.meta = {}              # 串口/行数等会话信息, 由调用方更新

    # ------------------------------------------------------------ 记录
    def add_frame(self, direction, fnc, payload):
        with self._lock:
            self.rx_cnt += direction == 'RX'
            self.tx_cnt += direction == 'TX'
            if not self.recording:
                return
            if len(self.frames) >= self.max_frames:
                del self.frames[:self.max_frames // 10]
                self.dropped += self.max_frames // 10
            self.frames.append((time.time(), direction, fnc, bytes(payload)))

    def add_event(self, kind, text):
        with self._lock:
            if len(self.events) >= self.max_events:
                del self.events[:self.max_events // 10]
            self.events.append((time.time(), kind, text))

    def note(self, text):
        self.add_event('注记', text)

    def clear(self):
        with self._lock:
            self.frames.clear()
            self.events.clear()
            self.dropped = 0
            self.session_start = time.time()

    # ------------------------------------------------------------ 读取(GUI轮询用)
    def snapshot_frames(self, after=0):
        with self._lock:
            return list(self.frames[after:]), len(self.frames)

    def snapshot_events(self, after=0):
        with self._lock:
            return list(self.events[after:]), len(self.events)

    # ------------------------------------------------------------ 导出
    def _header(self, title):
        lines = ['=' * 64,
                 '电控播种机下位机模拟器 %s' % title,
                 '导出时间: %s' % datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                 '会话开始: %s' % datetime.datetime.fromtimestamp(
                     self.session_start).strftime('%Y-%m-%d %H:%M:%S')]
        for k, v in self.meta.items():
            lines.append('%s: %s' % (k, v))
        lines.append('=' * 64)
        return lines

    def export_frames(self, path):
        """导出全部收发帧(含完整HEX与摘要)。"""
        with self._lock:
            frames = list(self.frames)
        lines = self._header('收发帧记录')
        lines.append('帧数: 收%d 发%d%s' % (
            self.rx_cnt, self.tx_cnt,
            ' (缓冲已裁剪%d帧, 仅含最近部分)' % self.dropped if self.dropped else ''))
        lines.append('-' * 64)
        for t, d, fnc, payload in frames:
            frame = P.build_frame(fnc, payload)
            arrow = '收 上位机->模拟器' if d == 'RX' else '发 模拟器->上位机'
            lines.append('[%s] %s 0x%02X %s len=%d'
                         % (_ts(t), arrow, fnc, P.FNC_NAMES.get(fnc, '?'), len(payload)))
            lines.append('  HEX  ' + frame.hex(' ').upper())
            desc = describe_frame(d, fnc, payload)
            if desc:
                lines.append('  摘要  ' + desc)
        with open(path, 'w', encoding='utf-8-sig') as f:
            f.write('\n'.join(lines) + '\n')
        return len(frames)

    def export_events(self, path):
        """导出调试信息与状态变化时间线。"""
        with self._lock:
            events = list(self.events)
        lines = self._header('调试信息/状态变化记录')
        lines.append('事件数: %d' % len(events))
        lines.append('-' * 64)
        for t, kind, text in events:
            lines.append('[%s] %s  %s' % (_ts(t), kind, text))
        with open(path, 'w', encoding='utf-8-sig') as f:
            f.write('\n'.join(lines) + '\n')
        return len(events)
