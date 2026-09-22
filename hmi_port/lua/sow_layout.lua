-- ============================================================================
-- sow_layout.lua : 协议数据域结构体 pack/unpack (大彩 VisualHMI Lua 5.3)
--
-- 布局与上位机 protocol.h (新版[6]数组) / seeder_sim layout.py 完全一致:
--   LXBZPara 12 | TestCmd 4 | BZCellPara 92 | BDPara 56 | TerPara 40
--   UserPara 16 | BZStatus 84 | TestStatus 68
-- 全部小端, 无隐式对齐填充。加载时对每个结构体做尺寸自检。
-- 纯 Lua 5.3: 不用 string.pack/rep/gmatch, 不用 io/os。
-- ============================================================================

if not SOW then SOW = {} end
if not SOW.layout then SOW.layout = {} end
local L = SOW.layout

-- ------------------------------------------------ 基础小端写(追加到 out 表)
local function u8(out, v)
  out[#out + 1] = string.char(v & 0xFF)
end
local function u16(out, v)
  out[#out + 1] = string.char(v & 0xFF, (v >> 8) & 0xFF)
end
local function u32(out, v)
  v = v & 0xFFFFFFFF
  out[#out + 1] = string.char(v & 0xFF, (v >> 8) & 0xFF,
                              (v >> 16) & 0xFF, (v >> 24) & 0xFF)
end
local function i16(out, v)
  if v < 0 then v = v + 0x10000 end
  u16(out, v)
end
local function i32(out, v)
  if v < 0 then v = v + 0x100000000 end
  u32(out, v)
end

-- ------------------------------------------------ 基础小端读(s=字符串, o=1基偏移)
local function rd_u8(s, o)  return string.byte(s, o) end
local function rd_u16(s, o)
  local a, b = string.byte(s, o, o + 1)
  return a | (b << 8)
end
local function rd_i16(s, o)
  local v = rd_u16(s, o)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end
local function rd_u32(s, o)
  local a, b, c, d = string.byte(s, o, o + 4)
  return a | (b << 8) | (c << 16) | (d << 24)
end
local function rd_i32(s, o)
  local v = rd_u32(s, o)
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end

-- ------------------------------------------------ IEEE754 纯 Lua 编解码
-- f64: 1+11+52, 偏移1023; f32: 1+8+23, 偏移127。仅支持规格化数与 0
-- (协议中的经纬度/角度均为常规范围值, 满足需要)。
local ZERO8 = string.char(0, 0, 0, 0, 0, 0, 0, 0)

-- 自实现 frexp (v = m * 2^e, 0.5 <= m < 1): 不依赖运行时是否提供 math.frexp
local function frexp(v)
  local e = 0
  if v < 0.5 then
    while v < 0.5 do v = v * 2 e = e - 1 end
  else
    while v >= 1.0 do v = v / 2 e = e + 1 end
  end
  return v, e
end

local function f64(out, v)
  if v == 0 then out[#out + 1] = ZERO8 return end
  local sign = 0
  if v < 0 then sign = 1 v = -v end
  local m, e = frexp(v)
  m = m * 2                       -- -> 1 <= m < 2
  e = e - 1
  local ebits = e + 1023
  assert(ebits > 0 and ebits < 2047, 'f64 非规格化/溢出不支持')
  local frac = math.floor((m - 1) * 2 ^ 52 + 0.5) & 0xFFFFFFFFFFFFF
  u32(out, frac & 0xFFFFFFFF)
  u32(out, ((frac >> 32) & 0xFFFFF) | ((ebits & 0x7FF) << 20) | (sign << 31))
end

local function rd_f64(s, o)
  local lo = rd_u32(s, o)
  local hi = rd_u32(s, o + 4)
  local sign = (hi >> 31) & 1
  local ebits = (hi >> 20) & 0x7FF
  if ebits == 0 then return 0.0 end
  local frac = (hi & 0xFFFFF) * 2 ^ 32 + lo
  local v = (frac / 2 ^ 52 + 1.0) * 2.0 ^ (ebits - 1023)
  if sign == 1 then v = -v end
  return v
end

local function f32(out, v)
  if v == 0 then out[#out + 1] = string.char(0, 0, 0, 0) return end
  local sign = 0
  if v < 0 then sign = 1 v = -v end
  local m, e = frexp(v)
  m = m * 2
  e = e - 1
  local ebits = e + 127
  assert(ebits > 0 and ebits < 255, 'f32 非规格化/溢出不支持')
  local frac = math.floor((m - 1) * 2 ^ 23 + 0.5) & 0x7FFFFF
  u32(out, frac | ((ebits & 0xFF) << 23) | (sign << 31))
end

local function rd_f32(s, o)
  local v = rd_u32(s, o)
  local sign = (v >> 31) & 1
  local ebits = (v >> 23) & 0xFF
  if ebits == 0 then return 0.0 end
  local frac = v & 0x7FFFFF
  local r = (frac / 2 ^ 23 + 1.0) * 2.0 ^ (ebits - 127)
  if sign == 1 then r = -r end
  return r
end

local function fin(out) return table.concat(out) end

-- ================================================================ LXBZParaType 12
L.SZ_LXBZ_PARA = 12

function L.pack_lxbz(t)
  local o = {}
  u32(o, t.Density or 1000)
  u32(o, t.CellLen or 500)
  u16(o, t.Hju or 60)
  u16(o, t.ZhuShu or 0)
  return fin(o)
end

function L.unpack_lxbz(s)
  return { Density  = rd_u32(s, 1),
           CellLen  = rd_u32(s, 5),
           Hju      = rd_u16(s, 9),
           ZhuShu   = rd_u16(s, 11) }
end

-- ================================================================ TestCMDType 4
L.SZ_TEST_CMD = 4

function L.pack_test_cmd(ctrl_no, state)
  local o = {}
  u16(o, ctrl_no)
  u16(o, state and 1 or 0)
  return fin(o)
end

function L.unpack_test_cmd(s)
  return rd_u16(s, 1), rd_u16(s, 3)
end

-- ================================================================ BZCellParaType 92
-- u8 TXFlag, u8 FinalFlag, u8 NextFinalFlag, u8 isAfterNextZoneSow,
-- s32 RowNum, InS, Density[6], CellLen, StartPOS, DisplayRowNum,
-- s32 NextRowNum, NextInS, NextDensity[6], NextCellLen, NextStartPOS, NextDisplayRowNum
L.SZ_BZ_CELL_PARA = 92

function L.pack_bz_cell(t)
  local o = {}
  u8(o, t.TXFlag or 1)
  u8(o, t.FinalFlag or 0)
  u8(o, t.NextFinalFlag or 0)
  u8(o, t.isAfterNextZoneSow or 0)
  i32(o, t.RowNum or 0)
  i32(o, t.InS or 0)
  for i = 1, 6 do i32(o, (t.Density or {})[i] or 0) end
  i32(o, t.CellLen or 0)
  i32(o, t.StartPOS or 0)
  i32(o, t.DisplayRowNum or 0)
  i32(o, t.NextRowNum or 0)
  i32(o, t.NextInS or 0)
  for i = 1, 6 do i32(o, (t.NextDensity or {})[i] or 0) end
  i32(o, t.NextCellLen or 0)
  i32(o, t.NextStartPOS or 0)
  i32(o, t.NextDisplayRowNum or 0)
  return fin(o)
end

function L.unpack_bz_cell(s)
  local o = 1
  local t = {}
  t.TXFlag = rd_u8(s, o)
  t.FinalFlag = rd_u8(s, o + 1)
  t.NextFinalFlag = rd_u8(s, o + 2)
  t.isAfterNextZoneSow = rd_u8(s, o + 3)
  o = o + 4
  t.RowNum, t.InS = rd_i32(s, o), rd_i32(s, o + 4)
  o = o + 8
  t.Density = {}
  for i = 1, 6 do t.Density[i] = rd_i32(s, o) o = o + 4 end
  t.CellLen, t.StartPOS, t.DisplayRowNum =
      rd_i32(s, o), rd_i32(s, o + 4), rd_i32(s, o + 8)
  o = o + 12
  t.NextRowNum, t.NextInS = rd_i32(s, o), rd_i32(s, o + 4)
  o = o + 8
  t.NextDensity = {}
  for i = 1, 6 do t.NextDensity[i] = rd_i32(s, o) o = o + 4 end
  t.NextCellLen, t.NextStartPOS, t.NextDisplayRowNum =
      rd_i32(s, o), rd_i32(s, o + 4), rd_i32(s, o + 8)
  return t
end

-- ================================================================ BDParaType 56
-- f64 StartN/StartE/EndBN/EndBE, f32 StartDir/CalcDir,
-- u16 StartState/CalcDirFlag/OffLen/BDOffTime, u32 Resv, u32 CrcCheck
L.SZ_BD_PARA = 56

function L.pack_bd(t)
  local o = {}
  f64(o, t.StartN or 0.0)
  f64(o, t.StartE or 0.0)
  f64(o, t.EndBN or 0.0)
  f64(o, t.EndBE or 0.0)
  f32(o, t.StartDir or 0.0)
  f32(o, t.CalcDir or 0.0)
  u16(o, t.StartState or 0)
  u16(o, t.CalcDirFlag or 0)
  u16(o, t.OffLen or 0)
  u16(o, t.BDOffTime or 0)
  u32(o, t.Resv or 0)
  u32(o, t.CrcCheck or 0)
  return fin(o)
end

function L.unpack_bd(s)
  return { StartN = rd_f64(s, 1),  StartE = rd_f64(s, 9),
           EndBN  = rd_f64(s, 17), EndBE  = rd_f64(s, 25),
           StartDir = rd_f32(s, 33), CalcDir = rd_f32(s, 37),
           StartState = rd_u16(s, 41), CalcDirFlag = rd_u16(s, 43),
           OffLen = rd_u16(s, 45), BDOffTime = rd_u16(s, 47),
           Resv = rd_u32(s, 49), CrcCheck = rd_u32(s, 53) }
end

-- ================================================================ TerParaType 40
-- i16 A, i16 B, u16 EncodeNum, u8 EncoderDir, u8 HoleNum, u16 GearRatio,
-- u16 MicroStepValue, i16 X1, i16 BDiroff, i16 TappTrigOff, u16 TapperTime,
-- u8 ZeroPosEn, u8 GZEn, u8 PrePercent, u8 U8Resv2(行数4/6),
-- u32 U32Resv1..3, u32 CrcCheck
L.SZ_TER_PARA = 40

function L.pack_ter(t)
  local o = {}
  i16(o, t.A or 0)
  i16(o, t.B or 0)
  u16(o, t.EncodeNum or 600)
  u8(o, t.EncoderDir or 0)
  u8(o, t.HoleNum or 9)
  u16(o, t.GearRatio or 0)
  u16(o, t.MicroStepValue or 800)
  i16(o, t.X1 or 244)
  i16(o, t.BDiroff or 0)
  i16(o, t.TappTrigOff or 0)
  u16(o, t.TapperTime or 60)
  u8(o, t.ZeroPosEn or 0)
  u8(o, t.GZEn or 0)
  u8(o, t.PrePercent or 0)
  u8(o, t.U8Resv2 or 4)
  u32(o, t.U32Resv1 or 0)
  u32(o, t.U32Resv2 or 0)
  u32(o, t.U32Resv3 or 0)
  u32(o, t.CrcCheck or 0)
  return fin(o)
end

function L.unpack_ter(s)
  local o = 1
  local t = {}
  t.A, t.B = rd_i16(s, o), rd_i16(s, o + 2)
  t.EncodeNum = rd_u16(s, o + 4)
  t.EncoderDir, t.HoleNum = rd_u8(s, o + 6), rd_u8(s, o + 7)
  t.GearRatio = rd_u16(s, o + 8)
  t.MicroStepValue = rd_u16(s, o + 10)
  t.X1, t.BDiroff, t.TappTrigOff = rd_i16(s, o + 12), rd_i16(s, o + 14), rd_i16(s, o + 16)
  t.TapperTime = rd_u16(s, o + 18)
  t.ZeroPosEn, t.GZEn = rd_u8(s, o + 20), rd_u8(s, o + 21)
  t.PrePercent, t.U8Resv2 = rd_u8(s, o + 22), rd_u8(s, o + 23)
  t.U32Resv1 = rd_u32(s, o + 24)
  t.U32Resv2 = rd_u32(s, o + 28)
  t.U32Resv3 = rd_u32(s, o + 32)
  t.CrcCheck = rd_u32(s, o + 36)
  return t
end

-- ================================================================ UserParaType 16
-- u16 DZTime, i16 HJ, u32 Rpm, u8 AntennaType, u8 U8Resv, i16 AntennaDistance,
-- u32 CrcCheck
L.SZ_USER_PARA = 16

function L.pack_user(t)
  local o = {}
  u16(o, t.DZTime or 1500)
  i16(o, t.HJ or 60)
  u32(o, t.Rpm or 20)
  u8(o, t.AntennaType or 0)
  u8(o, t.U8Resv or 0)
  i16(o, t.AntennaDistance or 0)
  u32(o, t.CrcCheck or 0)
  return fin(o)
end

function L.unpack_user(s)
  return { DZTime = rd_u16(s, 1), HJ = rd_i16(s, 3), Rpm = rd_u32(s, 5),
           AntennaType = rd_u8(s, 9), U8Resv = rd_u8(s, 10),
           AntennaDistance = rd_i16(s, 11), CrcCheck = rd_u32(s, 13) }
end

-- ================================================================ BZStatusType 84 (0x21)
-- u8 RunState, u8 BdState, u8 Resv[2], i32 Speed, RowNum, OffLen, VerticalOff,
-- u32 LoufeiCnt[6], u32 LouZHCnt[6], i32 Resv2[4]
L.SZ_BZ_STATUS = 84

function L.pack_bz_status(t)
  local o = {}
  u8(o, t.run_state or 0)
  u8(o, t.bd_state or 1)
  u8(o, 0) u8(o, 0)
  i32(o, t.speed or 0)
  i32(o, t.row_num or 0)
  i32(o, t.off_len or 0)
  i32(o, t.vertical_off or 0)
  for i = 1, 6 do u32(o, (t.loufei or {})[i] or 0) end
  for i = 1, 6 do u32(o, (t.louzh or {})[i] or 0) end
  u32(o, 0) u32(o, 0) u32(o, 0) u32(o, 0)
  return fin(o)
end

function L.unpack_bz_status(s)
  local o = 5
  local t = {}
  t.run_state = rd_u8(s, 1)
  t.bd_state = rd_u8(s, 2)
  t.speed, t.row_num = rd_i32(s, o), rd_i32(s, o + 4)
  t.off_len, t.vertical_off = rd_i32(s, o + 8), rd_i32(s, o + 12)
  o = o + 16
  t.loufei, t.louzh = {}, {}
  for i = 1, 6 do t.loufei[i] = rd_u32(s, o) o = o + 4 end
  for i = 1, 6 do t.louzh[i] = rd_u32(s, o) o = o + 4 end
  return t
end

-- ================================================================ TestModeStateType 68 (0x08)
-- u32 EncoderCnt, BdCnt, LoufeiCnt[6], LouZHCnt[6], InputState, WarningState, CtrlState
L.SZ_TEST_STATUS = 68

function L.pack_test_status(t)
  local o = {}
  u32(o, t.encoder_cnt or 0)
  u32(o, t.bd_cnt or 0)
  for i = 1, 6 do u32(o, (t.loufei or {})[i] or 0) end
  for i = 1, 6 do u32(o, (t.louzh or {})[i] or 0) end
  u32(o, t.input_state or 0)
  u32(o, t.warning_state or 0)
  u32(o, t.ctrl_state or 0)
  return fin(o)
end

function L.unpack_test_status(s)
  local o = 1
  local t = {}
  t.encoder_cnt, t.bd_cnt = rd_u32(s, o), rd_u32(s, o + 4)
  o = o + 8
  t.loufei, t.louzh = {}, {}
  for i = 1, 6 do t.loufei[i] = rd_u32(s, o) o = o + 4 end
  for i = 1, 6 do t.louzh[i] = rd_u32(s, o) o = o + 4 end
  t.input_state = rd_u32(s, o)
  t.warning_state = rd_u32(s, o + 4)
  t.ctrl_state = rd_u32(s, o + 8)
  return t
end

-- ================================================================ 加载时尺寸自检
local function selfcheck(name, got, want)
  assert(got == want, name .. ' 尺寸错误: ' .. got .. ' != ' .. want)
end
selfcheck('LXBZPara',   #L.pack_lxbz({}),        L.SZ_LXBZ_PARA)
selfcheck('TestCmd',    #L.pack_test_cmd(0, 0),  L.SZ_TEST_CMD)
selfcheck('BZCellPara', #L.pack_bz_cell({}),     L.SZ_BZ_CELL_PARA)
selfcheck('BDPara',     #L.pack_bd({}),          L.SZ_BD_PARA)
selfcheck('TerPara',    #L.pack_ter({}),         L.SZ_TER_PARA)
selfcheck('UserPara',   #L.pack_user({}),        L.SZ_USER_PARA)
selfcheck('BZStatus',   #L.pack_bz_status({}),   L.SZ_BZ_STATUS)
selfcheck('TestStatus', #L.pack_test_status({}), L.SZ_TEST_STATUS)
