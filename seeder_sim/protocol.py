# -*- coding: utf-8 -*-
"""帧层协议：与上位机 communication.cpp / 下位机 protocol.c 完全一致。

帧格式(双向相同, 多字节小端):
    [0]    0x68        帧头
    [1]    FNC         功能码
    [2..3] len         数据域长度 u16 小端
    [4..4+len-1] data  数据域
    [4+len..5+len]     CRC16 小端 (Kermit: 反射0x8408查表, 初值0, 无异或)
                      校验范围 = 帧头..数据域末尾 (共 4+len 字节)
    [6+len] 0x0D       帧尾
总帧长 = len + 7
"""

FRAME_START = 0x68
FRAME_END = 0x0D
FRAME_MAX_DATA_LEN = 1400

# 功能码 (与 hd3005a1/Inc/protocol.h 一致)
FNC_GET__RTC         = 0x04   # 名字照抄固件 protocol.h (双下划线)
FNC_SET_RTC          = 0x05
FNC_GET_TEST_STATUS  = 0x08
FNC_CMD_SVCTRL       = 0x09
FNC_CMD_START_BZ     = 0x0A
FNC_CMD_STOP_BZ      = 0x0B
FNC_RESTART_TER      = 0x10
FNC_CMD_START_LXBZ   = 0x11
FNC_CMD_STOP_LXBZ    = 0x12
FNC_START_TEST       = 0x0E
FNC_STOP_TEST        = 0x0F
FNC_SET_BZ_PARA      = 0x20
FNC_GET_BZ_STATUS    = 0x21
FNC_RD_DEBUG_INFO    = 0x22
FNC_STORE_AB         = 0x23
FNC_SET_AB           = 0x24
FNC_SET_TER_PARA     = 0x25
FNC_GET_TER_PARA     = 0x26
FNC_SET_USER_PARA    = 0x27
FNC_GET_USER_PARA    = 0x28
FNC_QZDD_ENABLE      = 0x29
FNC_GET_QZDD_STATE   = 0x30   # 固件未实现 -> 不应答
FNC_GDDD_ENABLE      = 0x31
FNC_GET_GDDD_STATE   = 0x32   # 固件未实现 -> 不应答
FNC_UPDATE_START     = 0xA0
FNC_UPDATE_BIN       = 0xA1
FNC_UPDATE_END       = 0xA2
FNC_GET_SOFT_VER     = 0xA3

FNC_CMD_NULL         = 0x0000  # 无待处理命令

FNC_NAMES = {
    FNC_GET__RTC: 'GET_RTC', FNC_SET_RTC: 'SET_RTC',
    FNC_GET_TEST_STATUS: 'GET_TEST_STATUS', FNC_CMD_SVCTRL: 'SVCTRL',
    FNC_CMD_START_BZ: 'START_BZ', FNC_CMD_STOP_BZ: 'STOP_BZ',
    FNC_RESTART_TER: 'RESTART_TER',
    FNC_CMD_START_LXBZ: 'START_LXBZ', FNC_CMD_STOP_LXBZ: 'STOP_LXBZ',
    FNC_START_TEST: 'START_TEST', FNC_STOP_TEST: 'STOP_TEST',
    FNC_SET_BZ_PARA: 'SET_BZ_PARA', FNC_GET_BZ_STATUS: 'GET_BZ_STATUS',
    FNC_RD_DEBUG_INFO: 'RD_DEBUG_INFO', FNC_STORE_AB: 'STORE_AB',
    FNC_SET_AB: 'SET_AB', FNC_SET_TER_PARA: 'SET_TER_PARA',
    FNC_GET_TER_PARA: 'GET_TER_PARA', FNC_SET_USER_PARA: 'SET_USER_PARA',
    FNC_GET_USER_PARA: 'GET_USER_PARA', FNC_QZDD_ENABLE: 'QZDD_ENABLE',
    FNC_GET_QZDD_STATE: 'GET_QZDD_STATE(未实现)', FNC_GDDD_ENABLE: 'GDDD_ENABLE',
    FNC_GET_GDDD_STATE: 'GET_GDDD_STATE(未实现)',
    FNC_UPDATE_START: 'UPDATE_START', FNC_UPDATE_BIN: 'UPDATE_BIN',
    FNC_UPDATE_END: 'UPDATE_END', FNC_GET_SOFT_VER: 'GET_SOFT_VER',
}

# CRC 查表 —— 逐字照抄上位机 communication.cpp 中 CrctableCCITTRefl
_CRC_TABLE = [
    0x0000, 0x1189, 0x2312, 0x329B, 0x4624, 0x57AD, 0x6536, 0x74BF,
    0x8C48, 0x9DC1, 0xAF5A, 0xBED3, 0xCA6C, 0xDBE5, 0xE97E, 0xF8F7,
    0x1081, 0x0108, 0x3393, 0x221A, 0x56A5, 0x472C, 0x75B7, 0x643E,
    0x9CC9, 0x8D40, 0xBFDB, 0xAE52, 0xDAED, 0xCB64, 0xF9FF, 0xE876,
    0x2102, 0x308B, 0x0210, 0x1399, 0x6726, 0x76AF, 0x4434, 0x55BD,
    0xAD4A, 0xBCC3, 0x8E58, 0x9FD1, 0xEB6E, 0xFAE7, 0xC87C, 0xD9F5,
    0x3183, 0x200A, 0x1291, 0x0318, 0x77A7, 0x662E, 0x54B5, 0x453C,
    0xBDCB, 0xAC42, 0x9ED9, 0x8F50, 0xFBEF, 0xEA66, 0xD8FD, 0xC974,
    0x4204, 0x538D, 0x6116, 0x709F, 0x0420, 0x15A9, 0x2732, 0x36BB,
    0xCE4C, 0xDFC5, 0xED5E, 0xFCD7, 0x8868, 0x99E1, 0xAB7A, 0xBAF3,
    0x5285, 0x430C, 0x7197, 0x601E, 0x14A1, 0x0528, 0x37B3, 0x263A,
    0xDECD, 0xCF44, 0xFDDF, 0xEC56, 0x98E9, 0x8960, 0xBBFB, 0xAA72,
    0x6306, 0x728F, 0x4014, 0x519D, 0x2522, 0x34AB, 0x0630, 0x17B9,
    0xEF4E, 0xFEC7, 0xCC5C, 0xDDD5, 0xA96A, 0xB8E3, 0x8A78, 0x9BF1,
    0x7387, 0x620E, 0x5095, 0x411C, 0x35A3, 0x242A, 0x16B1, 0x0738,
    0xFFCF, 0xEE46, 0xDCDD, 0xCD54, 0xB9EB, 0xA862, 0x9AF9, 0x8B70,
    0x8408, 0x9581, 0xA71A, 0xB693, 0xC22C, 0xD3A5, 0xE13E, 0xF0B7,
    0x0840, 0x19C9, 0x2B52, 0x3ADB, 0x4E64, 0x5FED, 0x6D76, 0x7CFF,
    0x9489, 0x8500, 0xB79B, 0xA612, 0xD2AD, 0xC324, 0xF1BF, 0xE036,
    0x18C1, 0x0948, 0x3BD3, 0x2A5A, 0x5EE5, 0x4F6C, 0x7DF7, 0x6C7E,
    0xA50A, 0xB483, 0x8618, 0x9791, 0xE32E, 0xF2A7, 0xC03C, 0xD1B5,
    0x2942, 0x38CB, 0x0A50, 0x1BD9, 0x6F66, 0x7EEF, 0x4C74, 0x5DFD,
    0xB58B, 0xA402, 0x9699, 0x8710, 0xF3AF, 0xE226, 0xD0BD, 0xC134,
    0x39C3, 0x284A, 0x1AD1, 0x0B58, 0x7FE7, 0x6E6E, 0x5CF5, 0x4D7C,
    0xC60C, 0xD785, 0xE51E, 0xF497, 0x8028, 0x91A1, 0xA33A, 0xB2B3,
    0x4A44, 0x5BCD, 0x6956, 0x78DF, 0x0C60, 0x1DE9, 0x2F72, 0x3EFB,
    0xD68D, 0xC704, 0xF59F, 0xE416, 0x90A9, 0x8120, 0xB3BB, 0xA232,
    0x5AC5, 0x4B4C, 0x79D7, 0x685E, 0x1CE1, 0x0D68, 0x3FF3, 0x2E7A,
    0xE70E, 0xF687, 0xC41C, 0xD595, 0xA12A, 0xB0A3, 0x8238, 0x93B1,
    0x6B46, 0x7ACF, 0x4854, 0x59DD, 0x2D62, 0x3CEB, 0x0E70, 0x1FF9,
    0xF78F, 0xE606, 0xD49D, 0xC514, 0xB1AB, 0xA022, 0x92B9, 0x8330,
    0x7BC7, 0x6A4E, 0x58D5, 0x495C, 0x3DE3, 0x2C6A, 0x1EF1, 0x0F78,
]


def crc16_kermit(data):
    """CRC-16/KERMIT, 与 CRC16_CCITTCalc 逐位一致。"""
    r = 0
    for b in data:
        r = ((r >> 8) ^ _CRC_TABLE[(r ^ b) & 0xFF]) & 0xFFFF
    return r


def build_frame(fnc, payload=b''):
    """构造应答帧, 对应 FrameConstruct。"""
    if len(payload) > FRAME_MAX_DATA_LEN:
        raise ValueError('payload too large: %d' % len(payload))
    body = bytes([FRAME_START, fnc & 0xFF]) + len(payload).to_bytes(2, 'little') + payload
    crc = crc16_kermit(body)
    return body + crc.to_bytes(2, 'little') + bytes([FRAME_END])


class FrameParser:
    """增量式帧解析。

    容错行为对齐上位机 readyRead 解析: 找 0x68 同步并丢弃其前的字节;
    长度域非法或 CRC/帧尾错误 -> 只丢 1 字节重新尝试; 帧不完整 -> 保留等待。
    """

    def __init__(self):
        self._buf = bytearray()

    def feed(self, chunk):
        """喂入串口原始字节, 返回本批次完整帧列表 [(fnc, payload), ...]。"""
        if chunk:
            self._buf.extend(chunk)
        frames = []
        while True:
            idx = self._buf.find(bytes([FRAME_START]))
            if idx < 0:
                self._buf.clear()
                break
            if idx > 0:
                del self._buf[:idx]
            if len(self._buf) < 5:
                break
            data_len = self._buf[2] | (self._buf[3] << 8)
            if data_len > FRAME_MAX_DATA_LEN:
                del self._buf[:1]
                continue
            total = data_len + 7
            if len(self._buf) < total:
                break
            frame = bytes(self._buf[:total])
            crc_recv = frame[4 + data_len] | (frame[5 + data_len] << 8)
            if crc_recv != crc16_kermit(frame[:4 + data_len]) or frame[6 + data_len] != FRAME_END:
                del self._buf[:1]
                continue
            frames.append((frame[1], frame[4:4 + data_len]))
            del self._buf[:total]
        return frames
