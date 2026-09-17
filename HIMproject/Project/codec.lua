--[[
codec.lua —— 协议结构体 <-> Lua table 编解码（string.pack 实现）
=================================================================
字节布局已与两侧源码逐一核对（2026-08-27）：
  上位机: AgricultureMachine/common/protocol.h        （6行机版本）
  下位机: hd3005a1/Inc/protocol.h + Inc/para.h         （4行机版本）

!! 重要发现 !! 两侧源码结构体存在行数差异（其余字段完全一致）：
  结构体              4行机(下位机源码)  6行机(平板源码)
  BZCellParaType            76 B            92 B     Density[4|6]
  BZStatusType              84 B           100 B     LoufeiCnt/LouZHCnt[4|6]
  TestModeStateType         52 B            68 B     LoufeiCnt/LouZHCnt[4|6]
  其余 5 个结构体两侧完全一致（12/16/40/56/4 B）
  => 实机 POC 必须先确认现场固件行数（codec.init{rows=?}），
     判别方法: 发 0x20 分别用 76/92 字节试，看回 ack 是否为 1。
  => C 结构体均为自然对齐无填充，string.pack 紧凑排列与其内存镜像一致。

用法:
    local codec = require("codec")
    codec.init{ rows = 4 }                  -- 默认 4（对手头下位机源码）
    local s  = codec.bzcell.pack{ RowNum = 1, ... }
    local t  = codec.bzcell.unpack(s)
--]]

local string = string
local codec = {}

local ROWS = 4   -- 当前变体行数，init() 可改

function codec.init(cfg)
    cfg = cfg or {}
    if cfg.rows ~= 4 and cfg.rows ~= 6 then
        error("rows must be 4 or 6")
    end
    ROWS = cfg.rows
    codec.ROWS = ROWS
    -- 重建依赖行数的格式串
    codec.bzcell.size  = 44 + 8 * ROWS
    codec.bzcell.fmt   = "<BBBB" .. "ii" .. ("i"):rep(ROWS) .. "iii"
                                  .. "ii" .. ("i"):rep(ROWS) .. "iii"
    codec.bzstatus.size  = 52 + 8 * ROWS
    codec.bzstatus.fmt   = "<BBBBiiii" .. ("I"):rep(2 * ROWS) .. "iiiiiiii"
    codec.teststate.size = 20 + 8 * ROWS
    codec.teststate.fmt  = "<II" .. ("I"):rep(2 * ROWS) .. "III"
end
codec.ROWS = ROWS

--------------------------------------------------------------------
-- 通用: 按字段表 + 格式串生成 pack/unpack
--   fields: 有序字段名; fmt: string.pack 格式串; size: 字节数
--------------------------------------------------------------------
local function make_struct(fields, fmt, size)
    local S = { fields = fields, fmt = fmt, size = size }
    function S.pack(t)
        local args = {}
        for i = 1, #fields do
            local v = t[fields[i]]
            if v == nil then error("missing field: " .. tostring(fields[i])) end
            args[i] = v
        end
        return string.pack(fmt, table.unpack(args))
    end
    function S.unpack(s)
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(fmt, s) }
        vals[#vals] = nil                       -- 去掉 string.unpack 尾部游标
        local t = {}
        for i = 1, #fields do t[fields[i]] = vals[i] end
        return t
    end
    return S
end

--------------------------------------------------------------------
-- LXBZParaType 连续播种参数（12B，两侧一致）
-- hd3005a1/Inc/protocol.h:108
--------------------------------------------------------------------
codec.lxbz = make_struct(
    { "Density", "CellLen", "Hju", "ZhuShu" },
    "<iihH", 12)

--------------------------------------------------------------------
-- TerParaType 厂家参数（40B，两侧一致）
-- hd3005a1/Inc/para.h:147 / common/protocol.h
--------------------------------------------------------------------
codec.terpara = make_struct(
    { "A", "B", "EncodeNum", "EncoderDir", "HoleNum",
      "GearRatio", "MicroStepValue", "X1", "BDiroff", "TappTrigOff",
      "TapperTime", "ZeroPosEn", "GZEn", "PrePercent", "Resv1",
      "Resv0", "Resv1_", "Resv2", "CrcCheck" },
    "<hhHBBHHhhhHBBBBiiiI", 40)
-- 注: Resv[3] 拆为 Resv0/Resv1_/Resv2（避免与 u8 Resv1 重名）

--------------------------------------------------------------------
-- UserParaType 用户参数（16B，两侧一致）
-- hd3005a1/Inc/para.h:172
--------------------------------------------------------------------
codec.userpara = make_struct(
    { "DZTime", "HJ", "RMP", "AntennaType", "U8Resv", "AntennaDistance", "CrcCheck" },
    "<HhIBBhI", 16)

--------------------------------------------------------------------
-- BDParaType AB线参数（56B，两侧一致）
-- hd3005a1/Inc/para.h:183
--------------------------------------------------------------------
codec.bdpara = make_struct(
    { "StartN", "StartE", "EndBN", "EndBE",        -- double x4
      "StartDir", "CalcDir",                        -- float  x2
      "StartState", "CalcDirFlag", "OffLen", "BDOffTime",  -- u16 x4
      "Resv", "CrcCheck" },                         -- u32 x2
    "<ddddffHHHHII", 56)

--------------------------------------------------------------------
-- TestCMDType 测试控制命令（4B，两侧一致）
--------------------------------------------------------------------
codec.testcmd = make_struct({ "CtrlNo", "State" }, "<HH", 4)

--------------------------------------------------------------------
-- BZCellParaType 小区播种参数（4行76B / 6行92B）
-- hd3005a1/Inc/protocol.h:73  Density[4] vs 平板 Density[6]
--------------------------------------------------------------------
local function bzcell_fields(rows)
    local f = { "TXFlag", "FinalFlag", "NextFinalFlag", "isAfterNextZoneSow" }
    local function seg(prefix)
        f[#f+1] = prefix .. "RowNum"
        f[#f+1] = prefix .. "InS"
        for i = 1, rows do f[#f+1] = prefix .. "Density" .. i end
        f[#f+1] = prefix .. "CellLen"
        f[#f+1] = (prefix == "") and "StartPOS" or "NextCellStartPOS"
        f[#f+1] = prefix .. "DisplayRowNum"
    end
    seg("")           -- 当前排
    seg("Next")       -- 下一排
    return f
end

codec.bzcell = {
    fields_of = bzcell_fields,
    pack = function(t)
        -- 把 Density/NextDensity 数组摊平进有序参数
        local rows = ROWS
        local flat = {}
        local function push(v) flat[#flat+1] = v end
        push(t.TXFlag); push(t.FinalFlag); push(t.NextFinalFlag); push(t.isAfterNextZoneSow)
        for _, p in ipairs({ "", "Next" }) do
            push(t[p .. "RowNum"]); push(t[p .. "InS"])
            local key = (p == "") and "Density" or "NextDensity"
            local d = t[key]
            assert(type(d) == "table" and #d == rows,
                   key .. " must be array of " .. rows)
            for i = 1, rows do push(d[i]) end
            push(t[p .. "CellLen"])
            push(p == "" and t.StartPOS or t.NextCellStartPOS)
            push(t[p .. "DisplayRowNum"])
        end
        return string.pack(codec.bzcell.fmt, table.unpack(flat))
    end,
    unpack = function(s)
        local size = codec.bzcell.size
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(codec.bzcell.fmt, s) }
        vals[#vals] = nil
        local names = bzcell_fields(ROWS)
        local t = {}
        for i = 1, #names do
            local n = names[i]
            local base = n:gsub("%d+$", "")
            if base == "Density" or base == "NextDensity" then
                local key = (base == "Density") and "Density" or "NextDensity"
                t[key] = t[key] or {}
                t[key][#t[key] + 1] = vals[i]
            else
                t[n] = vals[i]
            end
        end
        return t
    end,
}

--------------------------------------------------------------------
-- BZStatusType 播种状态（4行84B / 6行100B）
-- hd3005a1/Inc/protocol.h:94
--------------------------------------------------------------------
codec.bzstatus = {
    pack = function(t)
        local flat = { t.RunState, t.BdState, t.ResvA, t.ResvB,
                       t.Speed, t.RowNum, t.OffLen, t.VerticalOff }
        for _, key in ipairs({ "LoufeiCnt", "LouZHCnt" }) do
            local a = t[key]
            assert(type(a) == "table" and #a == ROWS, key .. " must be array of " .. ROWS)
            for i = 1, ROWS do flat[#flat+1] = a[i] end
        end
        for i = 1, 8 do flat[#flat+1] = t.Resv2[i] or 0 end
        return string.pack(codec.bzstatus.fmt, table.unpack(flat))
    end,
    unpack = function(s)
        local size = codec.bzstatus.size
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(codec.bzstatus.fmt, s) }
        vals[#vals] = nil
        local t = {
            RunState = vals[1], BdState = vals[2], ResvA = vals[3], ResvB = vals[4],
            Speed = vals[5], RowNum = vals[6], OffLen = vals[7], VerticalOff = vals[8],
            LoufeiCnt = {}, LouZHCnt = {}, Resv2 = {},
        }
        local k = 9
        for i = 1, ROWS do t.LoufeiCnt[i] = vals[k]; k = k + 1 end
        for i = 1, ROWS do t.LouZHCnt[i]  = vals[k]; k = k + 1 end
        for i = 1, 8    do t.Resv2[i]     = vals[k]; k = k + 1 end
        return t
    end,
}

--------------------------------------------------------------------
-- TestModeStateType 测试模式状态（4行52B / 6行68B）
-- hd3005a1/Inc/protocol.h:118
--------------------------------------------------------------------
codec.teststate = {
    pack = function(t)
        local flat = { t.EncoderCnt, t.BdCnt }
        for _, key in ipairs({ "LoufeiCnt", "LouZHCnt" }) do
            local a = t[key]
            assert(type(a) == "table" and #a == ROWS, key .. " must be array of " .. ROWS)
            for i = 1, ROWS do flat[#flat+1] = a[i] end
        end
        flat[#flat+1] = t.InputState
        flat[#flat+1] = t.WarningState
        flat[#flat+1] = t.CtrlState
        return string.pack(codec.teststate.fmt, table.unpack(flat))
    end,
    unpack = function(s)
        local size = codec.teststate.size
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(codec.teststate.fmt, s) }
        vals[#vals] = nil
        local t = { EncoderCnt = vals[1], BdCnt = vals[2],
                    LoufeiCnt = {}, LouZHCnt = {} }
        local k = 3
        for i = 1, ROWS do t.LoufeiCnt[i] = vals[k]; k = k + 1 end
        for i = 1, ROWS do t.LouZHCnt[i]  = vals[k]; k = k + 1 end
        t.InputState   = vals[k]; k = k + 1
        t.WarningState = vals[k]; k = k + 1
        t.CtrlState    = vals[k]
        return t
    end,
}

--------------------------------------------------------------------
-- 调试字符串(0x22): 固件现状 GB2312；D5 决策后改 UTF-8
-- Lua/LUA 屏端字符串即字节流，直接透传；显示中文需编码转换（见评估报告 C4）
--------------------------------------------------------------------
function codec.debug_str(data)
    return data
end

-- 初始化默认变体（4行，对手头下位机源码）
codec.init{ rows = 4 }

return codec
