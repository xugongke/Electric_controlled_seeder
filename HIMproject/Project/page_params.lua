--[[
page_params.lua —— 厂家/用户参数页: 0x26/0x28 读快照, 0x25/0x27 写入+前端校验
================================================================================
范围表来源(下位机强制, hd3005a1/Src/para.c ParaLegalCheck, 2026-09 核对):
  GearRatio      <2  回落10   => [2, 65535]        para.c:168
  HoleNum        ==0 回落9    => [1, 255]          para.c:171
  HJ             10~5000 回落60                   para.c:174
  DZTime         100~10000 回落1500                para.c:177
  RMP            5~70 回落20                        para.c:180
  TapperTime     >1000 回落60 => [0, 1000]          para.c:183
  MicroStepValue >6400 回落800 => [0, 6400]          para.c:187
  EncodeNum      ==0 回落700  => [1, 65535]         para.c:191
  PrePercent     无校验, 按注释 [0,100]              para.h:165
  其余字段无下位机校验, 放行(负值经 LW i16 控件语义)
密码锁: 厂家参数写入前须解锁, 密码与 Qt 端一致 formconfig.cpp:172 ("515516")
CrcCheck: 传 0 占位, 下位机写 EEPROM 前重算(Qt 同此行为)
返回 creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16, r32 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16, ctx.r32

    local PASSWORD = 515516
    local unlocked = false

    -- 范围表: { 字段, 下限, 上限, 中文名 }  nil 下限/上限 = 不检
    local RANGE_T = {
        { "GearRatio",      2,     65535, "传动比" },
        { "HoleNum",        1,     255,   "排种盘孔数" },
        { "EncodeNum",      1,     65535, "编码器脉冲" },
        { "MicroStepValue", 0,     6400,  "细分值" },
        { "TapperTime",     0,     1000,  "打点时间" },
        { "PrePercent",     0,     100,   "预压比" },
    }
    local RANGE_U = {
        { "HJ",     10, 5000,  "行间距HJ" },
        { "DZTime", 100, 10000, "点滞时间" },
        { "RMP",    5,  70,    "播种盘转速RMP" },
    }

    local function s16(v)                       -- u16 -> i16 符号扩展
        v = v & 0xFFFF
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end

    local function check(t, ranges)
        for _, r in ipairs(ranges) do
            local name, lo, hi, cn = r[1], r[2], r[3], r[4]
            local v = t[name]
            if lo and v < lo then return name, ("参数%s=%d 低于下限%d"):format(cn, v, lo) end
            if hi and v > hi then return name, ("参数%s=%d 超过上限%d"):format(cn, v, hi) end
        end
        return nil
    end

    -- 读表单(LW) -> terpara 表(i16 字段符号扩展, Crc 占位0)
    local function read_ter_form()
        local P = LW.PF
        return {
            A = s16(r16(P.a)), B = s16(r16(P.b)),
            EncodeNum = r16(P.encodenum), EncoderDir = r16(P.encoderdir),
            HoleNum = r16(P.holenum), GearRatio = r16(P.gearratio),
            MicroStepValue = s16(r16(P.microstep)),
            X1 = s16(r16(P.x1)), BDiroff = s16(r16(P.bdiroff)),
            TappTrigOff = s16(r16(P.tapptrigoff)), TapperTime = r16(P.tappertime),
            ZeroPosEn = r16(P.zeroposen), GZEn = r16(P.gzen),
            PrePercent = r16(P.prepercent),
            Resv1 = 0, Resv0 = 0, Resv1_ = 0, Resv2 = 0, CrcCheck = 0,
        }
    end

    -- 读表单 -> userpara 表
    local function read_user_form()
        local U = LW.PU
        return {
            DZTime = r16(U.dztime), HJ = s16(r16(U.hj)), RMP = r32(U.rmp),
            AntennaType = r16(U.antennatype), U8Resv = 0,
            AntennaDistance = s16(r16(U.antennadist)), CrcCheck = 0,
        }
    end

    -- 0x26/0x28 应答 -> LW 表单回显
    local function show_ter(p)
        local P = LW.PF
        w16(P.a, p.A & 0xFFFF);          w16(P.b, p.B & 0xFFFF)
        w16(P.encodenum, p.EncodeNum);   w16(P.encoderdir, p.EncoderDir)
        w16(P.holenum, p.HoleNum);       w16(P.gearratio, p.GearRatio)
        w16(P.microstep, p.MicroStepValue & 0xFFFF)
        w16(P.x1, p.X1 & 0xFFFF);        w16(P.bdiroff, p.BDiroff & 0xFFFF)
        w16(P.tapptrigoff, p.TappTrigOff & 0xFFFF)
        w16(P.tappertime, p.TapperTime); w16(P.zeroposen, p.ZeroPosEn)
        w16(P.gzen, p.GZEn);             w16(P.prepercent, p.PrePercent)
    end

    local function show_user(p)
        local U = LW.PU
        w16(U.dztime, p.DZTime);         w16(U.hj, p.HJ & 0xFFFF)
        w32(U.rmp, p.RMP);               w16(U.antennatype, p.AntennaType)
        w16(U.antennadist, p.AntennaDistance & 0xFFFF)
    end

    local page = {
        id        = LW.SCREEN.PARAMS,
        poll_cmds = {},                          -- 快照式: 进页/手动读, 不轮询
        addrs     = {
            LW.PF.read, LW.PF.write, LW.PF.pass, LW.PF.unlock,
            LW.PU.read, LW.PU.write,
        },
    }

    function page:on_enter()                     -- 进页读双份快照
        PROTOCOL.send(FNC.GET_TER_PARA)
        PROTOCOL.send(FNC.GET_USER_PARA)
    end

    function page:on_frame(f)
        local ok, p = pcall(CODEC.terpara.unpack, f.data)
        if f.fnc == FNC.GET_TER_PARA then
            if ok then show_ter(p)
            else wstr(LW.A.log, "terpara unpack err: len=" .. #f.data) end
        elseif f.fnc == FNC.GET_USER_PARA then
            local ok2, u = pcall(CODEC.userpara.unpack, f.data)
            if ok2 then show_user(u)
            else wstr(LW.A.log, "userpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        local P, U = LW.PF, LW.PU
        if addr == P.read then
            PROTOCOL.send(FNC.GET_TER_PARA)
        elseif addr == U.read then
            PROTOCOL.send(FNC.GET_USER_PARA)
        elseif addr == P.unlock then
            local pw = r32(P.pass)
            if pw == PASSWORD then
                unlocked = true
                wstr(LW.A.tip, "√ 厂家参数已解锁")
            else
                unlocked = false
                wstr(LW.A.tip, "× 密码错误")
            end
        elseif addr == P.write then
            if not unlocked then
                wstr(LW.A.tip, "× 请先输入密码解锁")
                return
            end
            local t = read_ter_form()
            local bad, msg = check(t, RANGE_T)
            if bad then wstr(LW.A.tip, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_TER_PARA, CODEC.terpara.pack(t))
        elseif addr == U.write then
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.tip, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_USER_PARA, CODEC.userpara.pack(t))
        end
    end

    return page
end
