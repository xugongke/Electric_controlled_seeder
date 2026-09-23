--[[
codec.lua —— 协议结构体 <-> Lua table 编解码（string.pack 实现）
================================================================================
字节布局以 hd3005a2 固件(Inc/protocol.h, LINE_NUM=6 编译)为准, 2026-09-23 真机
联调修正: 三个行数相关结构体恒为 [6] 数组版本, **与4行机/6行机运行模式无关**:
  BZCellParaType 92B / BZStatusType 84B(Resv2[4]) / TestModeStateType 68B
  4行机只是 U8Resv2=4 的运行参数(上位机 protocol.h 同口径), 数组第5/6路恒0。
  (旧版按 hd3005a1 固件[4]布局在4行模式发76B包, hd3005a2/模拟器按92B校验
   直接 ACK=0, 播种空跑"播种结束[0]" —— 真机实测复现)
其余结构体: LXBZ 12 / TestCmd 4 / TerPara 40 / UserPara 16 / BDPara 56 B。
C 结构体自然对齐无填充, string.pack 紧凑排列与其内存镜像一致。

用法:
    local codec = require("codec")
    codec.init{ rows = 4 }                  -- rows 只作业务语义(有效路数), 默认4
    local s  = codec.bzcell.pack{ RowNum = 1, Density = {4000,4000,4000,4000} }
    local t  = codec.bzcell.unpack(s)       -- Density 恒为6元素(4行机末2路为0)
--]]

local string = string
local codec = {}

local ROWS = 4   -- 业务有效行数(4/6), 不影响结构体布局

-- 平台兼容: string.rep 屏端不可用(文档LUA/000_Lua_Api), 手写等价实现
-- (定义须在 codec.init 之前, init 的函数体词法引用本局部)
local function reps(c, n)
    local t = {}
    for i = 1, n do t[i] = c end
    return table.concat(t)
end

function codec.init(cfg)
    cfg = cfg or {}
    if cfg.rows ~= nil and cfg.rows ~= 4 and cfg.rows ~= 6 then
        error("rows must be 4 or 6")
    end
    ROWS = cfg.rows or ROWS
    codec.ROWS = ROWS
    -- 布局恒为[6]数组版本(hd3005a2 编译期 LINE_NUM=6), rows 只影响业务语义
    codec.bzcell.size  = 92
    codec.bzcell.fmt   = "<BBBB" .. "ii" .. reps("i", 6) .. "iii"
                               .. "ii" .. reps("i", 6) .. "iii"
    -- BZStatus: Resv2[4] 恒 84B (hd3005a2 para.h: Resv2[8-(LINE_NUM-4)*2], LINE_NUM=6)
    codec.bzstatus.size  = 84
    codec.bzstatus.resv2 = 4
    codec.bzstatus.fmt   = "<BBBBiiii" .. reps("I", 12) .. reps("i", 4)
    codec.teststate.size = 68
    codec.teststate.fmt  = "<II" .. reps("I", 12) .. "III"
end
codec.ROWS = ROWS

--------------------------------------------------------------------
-- 通用: 按字段表 + 格式串生成 pack/unpack
--   fields: 有序字段名; fmt: string.pack 格式串; size: 字节数
--------------------------------------------------------------------
-- 等价于 s:gsub("%d+$", ""): 去掉字符串尾部连续数字 (string.gsub 屏端不可用)
local function strip_digits(s)
    local e = #s
    while e >= 1 do
        local c = string.byte(s, e)
        if c >= 48 and c <= 57 then e = e - 1 else break end
    end
    if e == 0 then return "" end
    return string.sub(s, 1, e)
end

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
        -- 把 Density/NextDensity 数组摊平进有序参数(恒6元素, 不足补0)
        local flat = {}
        local function push(v) flat[#flat+1] = v end
        push(t.TXFlag); push(t.FinalFlag); push(t.NextFinalFlag); push(t.isAfterNextZoneSow)
        for _, p in ipairs({ "", "Next" }) do
            push(t[p .. "RowNum"]); push(t[p .. "InS"])
            local key = (p == "") and "Density" or "NextDensity"
            local d = t[key]
            assert(type(d) == "table" and #d >= 1 and #d <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do push(d[i] or 0) end
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
        local names = bzcell_fields(6)
        local t = {}
        for i = 1, #names do
            local n = names[i]
            local base = strip_digits(n)
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
            assert(type(a) == "table" and #a >= 1 and #a <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do flat[#flat+1] = a[i] or 0 end   -- 恒6路, 不足补0
        end
        for i = 1, codec.bzstatus.resv2 do flat[#flat+1] = t.Resv2[i] or 0 end
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
        for i = 1, 6 do t.LoufeiCnt[i] = vals[k]; k = k + 1 end
        for i = 1, 6 do t.LouZHCnt[i]  = vals[k]; k = k + 1 end
        for i = 1, codec.bzstatus.resv2 do t.Resv2[i] = vals[k]; k = k + 1 end
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
            assert(type(a) == "table" and #a >= 1 and #a <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do flat[#flat+1] = a[i] or 0 end   -- 恒6路, 不足补0
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
        for i = 1, 6 do t.LoufeiCnt[i] = vals[k]; k = k + 1 end
        for i = 1, 6 do t.LouZHCnt[i]  = vals[k]; k = k + 1 end
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
