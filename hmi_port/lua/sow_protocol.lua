-- ============================================================================
-- sow_protocol.lua : 播种机串口协议 帧层 (大彩 VisualHMI Lua 5.3)
--
-- 帧格式(双向一致, 多字节小端):
--   [0] 0x68 帧头 | [1] FNC | [2..3] len(u16小端) | [4..] data
--   | CRC16小端(Kermit: 反射0x8408查表, 初值0, 无异或, 范围=帧头..data末尾)
--   | 0x0D 帧尾        总帧长 = len + 7
--
-- 与上位机 communication.cpp / 下位机 protocol.c / seeder_sim protocol.py
-- 逐字节一致。纯 Lua 5.3: 不用 string.pack/rep/gmatch, 不用 io/os,
-- 双端可运行(VisualHMI 屏内 / PC 测试)。
-- ============================================================================

if not SOW then SOW = {} end
if not SOW.protocol then SOW.protocol = {} end
local P = SOW.protocol

P.FRAME_START = 0x68
P.FRAME_END = 0x0D
P.FRAME_MAX_DATA_LEN = 1400

-- 功能码 (与固件 protocol.h 一致)
P.FNC = {
  GET_RTC         = 0x04,
  SET_RTC         = 0x05,
  GET_TEST_STATUS = 0x08,
  CMD_SVCTRL      = 0x09,
  CMD_START_BZ    = 0x0A,
  CMD_STOP_BZ     = 0x0B,
  START_TEST      = 0x0E,
  STOP_TEST       = 0x0F,
  RESTART_TER     = 0x10,
  CMD_START_LXBZ  = 0x11,
  CMD_STOP_LXBZ   = 0x12,
  SET_BZ_PARA     = 0x20,
  GET_BZ_STATUS   = 0x21,
  RD_DEBUG_INFO   = 0x22,
  STORE_AB        = 0x23,
  SET_AB          = 0x24,
  SET_TER_PARA    = 0x25,
  GET_TER_PARA    = 0x26,
  SET_USER_PARA   = 0x27,
  GET_USER_PARA   = 0x28,
  QZDD_ENABLE     = 0x29,
  GET_QZDD_STATE  = 0x30,   -- 固件未实现, 不应答
  GDDD_ENABLE     = 0x31,
  GET_GDDD_STATE  = 0x32,   -- 固件未实现, 不应答
  UPDATE_START    = 0xA0,
  UPDATE_BIN      = 0xA1,
  UPDATE_END      = 0xA2,
  GET_SOFT_VER    = 0xA3,
}

-- CRC-16/KERMIT 查表 (反射 0x8408, 初值 0, 无异或)
-- 加载时按标准算法生成; 与上位机 communication.cpp 手抄表逐项一致(PC 测试逐项比对)
local CRC_T = {}
for i = 0, 255 do
  local r = i
  for _ = 1, 8 do
    if (r & 1) ~= 0 then r = (r >> 1) ~ 0x8408 else r = r >> 1 end
  end
  CRC_T[i] = r
end
P.CRC_TABLE = CRC_T           -- 仅供测试比对

function P.crc16_kermit(data)
  local r = 0
  for i = 1, #data do
    r = ((r >> 8) ~ CRC_T[(r ~ string.byte(data, i)) & 0xFF]) & 0xFFFF
  end
  return r
end

local SYNC = string.char(P.FRAME_START)

-- 构造帧: build_frame(fnc, payload) -> 完整帧字符串
function P.build_frame(fnc, payload)
  payload = payload or ''
  assert(#payload <= P.FRAME_MAX_DATA_LEN, 'payload too large: ' .. #payload)
  local body = string.char(P.FRAME_START, fnc & 0xFF,
                           #payload & 0xFF, (#payload >> 8) & 0xFF) .. payload
  local crc = P.crc16_kermit(body)
  return body .. string.char(crc & 0xFF, (crc >> 8) & 0xFF, P.FRAME_END)
end

-- 新建增量解析器: new_parser() -> {buf=...}
function P.new_parser()
  return { buf = '' }
end

-- 喂入串口原始字节(字符串), 返回本批次完整帧列表 {{fnc=..,payload=..},...}
-- 容错与上位机 readyRead 解析一致: 找 0x68 同步丢弃其前字节;
-- 长度非法或 CRC/帧尾错误 -> 只丢 1 字节重试; 帧不完整 -> 保留等待。
function P.feed(p, chunk)
  if chunk and #chunk > 0 then p.buf = p.buf .. chunk end
  local frames = {}
  while true do
    local s = string.find(p.buf, SYNC, 1, true)
    if not s then
      p.buf = ''
      break
    end
    if s > 1 then p.buf = string.sub(p.buf, s) end
    if #p.buf < 5 then break end
    local b2, b3 = string.byte(p.buf, 3, 4)
    local dlen = b2 | (b3 << 8)
    if dlen > P.FRAME_MAX_DATA_LEN then
      p.buf = string.sub(p.buf, 2)
    else
      local total = dlen + 7
      if #p.buf < total then break end
      local frame = string.sub(p.buf, 1, total)
      -- CRC在帧内偏移 4+len/5+len (0基) -> Lua 1基为 5+len/6+len, 帧尾 7+len
      local c1, c2, tail = string.byte(frame, 5 + dlen, 7 + dlen)
      local crc_recv = c1 | (c2 << 8)
      if crc_recv ~= P.crc16_kermit(string.sub(frame, 1, 4 + dlen))
         or tail ~= P.FRAME_END then
        p.buf = string.sub(p.buf, 2)
      else
        frames[#frames + 1] = {
          fnc = string.byte(frame, 2),
          payload = string.sub(frame, 5, 4 + dlen),
        }
        p.buf = string.sub(p.buf, total + 1)
      end
    end
  end
  return frames
end

-- 便于调试: 十六进制串
function P.hex(s)
  local t = {}
  for i = 1, #s do t[#t + 1] = string.format('%02X', string.byte(s, i)) end
  return table.concat(t, ' ')
end

-- 字符串 -> 字节数组表 (仅PC侧lupa测试用: 规避返回二进制字符串的编码问题)
function P.tobytes(s)
  local t = {}
  for i = 1, #s do t[i] = string.byte(s, i) end
  return t
end

-- PC测试辅助: 构帧直接返回字节数组表
function P.build_frame_bytes(fnc, payload)
  return P.tobytes(P.build_frame(fnc, payload))
end

-- PC测试辅助: 调用任意返回字符串的函数并转字节数组表 (如 layout.pack_*)
function P.call_bytes(fn, ...)
  return P.tobytes(fn(...))
end

-- PC测试辅助: feed()结果表的payload转字节数组表
function P.frames_to_pairs(frames)
  local r = {}
  for i = 1, #frames do
    r[i] = { fnc = frames[i].fnc, payload = P.tobytes(frames[i].payload) }
  end
  return r
end
