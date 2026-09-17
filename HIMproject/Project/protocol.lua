--[[
protocol.lua —— 电控播种机 0x68 协议帧引擎（纯逻辑，无平台依赖）
=================================================================
移植自两侧源码（已字节级核对，2026-08-27）：
  下位机: hd3005a1/Src/protocol.c   (FrameConstruct / FrameAnalysis / CRC16_MODBUS)
  上位机: SowSystem/tool/communication.cpp (addCrc / checkCrc / FrameAnalysis)

帧格式（总长 = DataLen + 7）:
  +------+-----+-------------+------+---------------+------+
  | 0x68 | FNC | Len (u16LE) | Data | CRC16 (u16LE) | 0x0D |
  +------+-----+-------------+------+---------------+------+
  CRC: CRC-16/CCITT 反射式（KERMIT 变体，初值 0x0000，无异或输出）
       计算范围: 从帧头 0x68 到 Data 末尾（不含 CRC 与 0x0D）
       标准校验值: CRC16("123456789") == 0x31C3

用法（大彩 VisualHMI 屏端，副串口 ch1）:
    -- main.lua:
    --   require("protocol")
    --   PROTOCOL.io.tx = function(bytes) uart_send(1, str_to_bytes(bytes)) end
    --   function on_uart_recv(ch, packet)
    --       if ch == 1 then PROTOCOL.feed_bytes(bytes_to_str(packet)) end
    --   end
    -- （str<->byte数组 转换函数见文件尾部 PROTOCOL.util）

用法（PC 标准 Lua 5.3+ 自测）:
    --   直接 require 后调 PROTOCOL.feed_bytes(string)，见 test_protocol.lua
--]]

local string = string
local table  = table

local PROTOCOL = {}

-- 协议常量（与 hd3005a1/Inc/protocol.h 同步）
PROTOCOL.FRAME_START     = 0x68
PROTOCOL.FRAME_END       = 0x0D
PROTOCOL.MAX_DATA_LEN    = 1400        -- FRAME_MAX_DATA_LEN

-- 功能码（两侧 protocol.h 并集，以注释标注来源）
PROTOCOL.FNC = {
    GET_RTC          = 0x04,   -- 下位机: 回 u32 时间
    SET_RTC          = 0x05,   -- 下位机: 收 u32 时间, 回 ack
    GET_TEST_STATUS  = 0x08,   -- 回 TestModeStateType
    CMD_SVCTRL       = 0x09,   -- 收 TestCMDType, 回 ack
    CMD_START_BZ     = 0x0A,   -- 启动小区播种, 空域, 回 ack
    CMD_STOP_BZ      = 0x0B,   -- 停止播种, 空域, 回 ack
    RESTART_TER      = 0x10,   -- 重启设备, 回 ack（仅下位机协议表有）
    CMD_START_TEST   = 0x0E,   -- 进入测试模式, 空域, 回 ack
    CMD_STOP_TEST    = 0x0F,   -- 退出测试模式, 空域, 回 ack
    CMD_START_LXBZ   = 0x11,   -- 连续播种, 收 LXBZParaType, 回 ack
    CMD_STOP_LXBZ    = 0x12,   -- 停止连续播种, 空域, 回 ack
    SET_BZ_PARA      = 0x20,   -- 收 BZCellParaType, 回 ack(1/0)
    GET_BZ_STATUS    = 0x21,   -- 回 BZStatusType
    RD_DEBUG_INFO    = 0x22,   -- 回调试字符串(GB2312, 不含NUL; D5决策后固件改UTF-8)
    STORE_AB         = 0x23,   -- 空域, 回 BDParaType(当前AB线)
    SET_AB           = 0x24,   -- 收 BDParaType, 回 ack
    SET_TER_PARA     = 0x25,   -- 收 TerParaType, 回 ack
    GET_TER_PARA     = 0x26,   -- 空域, 回 TerParaType
    SET_USER_PARA    = 0x27,   -- 收 UserParaType, 回 ack
    GET_USER_PARA    = 0x28,   -- 空域, 回 UserParaType
    QZDD_ENABLE      = 0x29,   -- 收1字节(0/1), 回 ack
    GET_QZDD_STATE   = 0x30,   -- 空域, 回1字节（仅下位机协议表有）
    GDDD_ENABLE      = 0x31,   -- 收1字节(0/1), 回 ack
    GET_GDDD_STATE   = 0x32,   -- 空域, 回1字节（仅下位机协议表有）
    UPDATE_START     = 0xA0,   -- IAP 升级（屏端不实现，仅识别）
    UPDATE_BIN       = 0xA1,
    UPDATE_END       = 0xA2,
    GET_SOFT_VER     = 0xA3,   -- 回 "xxx,vol:n.n" + NUL (strlen+1)
}

--------------------------------------------------------------------
-- CRC-16/CCITT 反射式（KERMIT 变体, poly 0x8408, init 0x0000, xorout 0x0000）
-- 与下位机 CRC16_MODBUS() / 上位机 CRC16_CCITTCalc() 的查表完全等价
--------------------------------------------------------------------
local crc_table
local function crc_init()
    crc_table = {}
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if crc & 1 == 1 then crc = (crc >> 1) ~ 0x8408
            else                 crc =  crc >> 1
            end
        end
        crc_table[i] = crc & 0xFFFF
    end
end
crc_init()

function PROTOCOL.crc16(data, from, to)
    from = from or 1
    to   = to   or #data
    local crc = 0
    for i = from, to do
        crc = (crc >> 8) ~ crc_table[(crc ~ string.byte(data, i)) & 0xFF]
    end
    return crc & 0xFFFF
end

--------------------------------------------------------------------
-- 组帧: build_frame(fnc, data) -> 完整帧二进制字符串
--------------------------------------------------------------------
function PROTOCOL.build_frame(fnc, data)
    data = data or ""
    local n = #data
    assert(n <= PROTOCOL.MAX_DATA_LEN, "data too long: " .. n)
    local head = string.pack("<BB I2", PROTOCOL.FRAME_START, fnc, n)
    local crc  = PROTOCOL.crc16(head .. data)
    return head .. data .. string.pack("<I2", crc) .. string.char(PROTOCOL.FRAME_END)
end

--------------------------------------------------------------------
-- 发送接口: send(fnc, data)
-- io.tx 注入实际传输层；未注入时缓存到 io.pending（PC 自测可断言）
--------------------------------------------------------------------
PROTOCOL.io = { tx = nil, pending = nil, tx_count = 0 }

function PROTOCOL.send(fnc, data)
    local frame = PROTOCOL.build_frame(fnc, data)
    PROTOCOL.io.tx_count = PROTOCOL.io.tx_count + 1
    if PROTOCOL.io.tx then
        PROTOCOL.io.tx(frame)
    else
        PROTOCOL.io.pending = PROTOCOL.io.pending or {}
        PROTOCOL.io.pending[#PROTOCOL.io.pending + 1] = frame
    end
    return frame
end

--------------------------------------------------------------------
-- 收包状态机: feed_bytes(bytes) -> 解出的帧列表 {{fnc=..,data=..},...]
-- 语义复刻下位机 FrameAnalysis（do-while 逐帧提取 + 丢帧头重同步）：
--   1. 找不到 0x68         -> 丢弃全部（纯噪声）
--   2. 累计不足 7 字节      -> 等待更多数据
--   3. Len > 1400          -> 丢弃该 0x68 重找（防长度域损坏）
--   4. 累计不足整帧         -> 等待更多数据
--   5. CRC 不符 或 帧尾错   -> 丢弃该 0x68 重找（比上位机多验帧尾）
--   6. 校验通过            -> 派发回调, 继续处理剩余（粘包）
--------------------------------------------------------------------
PROTOCOL.rxbuf = ""
PROTOCOL.on_frame = nil          -- function(frame_table) 由上层注册

function PROTOCOL.feed_bytes(bytes)
    local rx = PROTOCOL.rxbuf .. bytes
    local frames = {}
    while true do
        -- 1) 找帧头
        local head = string.find(rx, string.char(PROTOCOL.FRAME_START), 1, true)
        if not head then rx = ""; break end
        if head > 1 then rx = string.sub(rx, head) end
        -- 2) 最小帧长 7 字节
        if #rx < 7 then break end
        -- 3) 长度域合法性
        local dlen = string.unpack("<I2", rx, 3)
        if dlen > PROTOCOL.MAX_DATA_LEN then
            rx = string.sub(rx, 2)          -- 丢掉伪帧头，重找
        else
            local total = dlen + 7
            -- 4) 等待整帧
            if #rx < total then break end
            -- 5) CRC + 帧尾校验
            local body   = string.sub(rx, 1, dlen + 4)        -- 0x68..Data
            local crc_rx = string.unpack("<I2", rx, dlen + 5)
            local tail   = string.byte(rx, dlen + 7)
            if PROTOCOL.crc16(body) == crc_rx and tail == PROTOCOL.FRAME_END then
                local f = {
                    fnc  = string.byte(rx, 2),
                    data = string.sub(rx, 5, dlen + 4),
                    raw  = string.sub(rx, 1, total),
                }
                frames[#frames + 1] = f
                if PROTOCOL.on_frame then PROTOCOL.on_frame(f) end
                rx = string.sub(rx, total + 1)                -- 处理粘包：继续
            else
                rx = string.sub(rx, 2)      -- 丢帧头重同步（复刻 buf.remove(0,1)）
            end
        end
    end
    PROTOCOL.rxbuf = rx
    return frames
end

--------------------------------------------------------------------
-- 工具: 字符串 <-> 大彩 packet 字节数组（屏端适配用）
-- 注意: 大彩文档标注 packet 下标从 1 起，与 string.byte 一致；POC 实测确认
--------------------------------------------------------------------
PROTOCOL.util = {}

function PROTOCOL.util.bytes_to_str(packet)
    local t = {}
    for i = 1, #packet do t[i] = string.char(packet[i] & 0xFF) end
    return table.concat(t)
end

function PROTOCOL.util.str_to_bytes(s)
    local t = {}
    for i = 1, #s do t[i] = string.byte(s, i) end
    return t
end

function PROTOCOL.util.hex(s, sep)
    sep = sep or " "
    local t = {}
    for i = 1, #s do t[#t + 1] = string.format("%02X", string.byte(s, i)) end
    return table.concat(t, sep)
end

return PROTOCOL
