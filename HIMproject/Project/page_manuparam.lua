--[[
page_manuparam.lua -- 厂家参数页(画面4, 2026-09-28自原参数页拆分)
================================================================================
进入条件: 用户参数页密码弹窗校验通过(LW.PWD.ok=1), 未解锁进入则踢回画面3。
厂家参数(TerParaType 40B): 0x26 进页读快照(jobrun的0x26全局路由转发到本页,
并按行数字段动态切换codec变体), 0x25 写入+范围校验。
写时保留固件侧行数字段: Resv1(=U8Resv2 4/6)取自最近0x26快照, 无快照兜底6
(2026-09-23曾硬编码0下发把行数冲掉, 用户实测暴露)。
范围表(hd3005a1/Src/para.c ParaLegalCheck, 2026-09核对):
  GearRatio<2回落10 | HoleNum==0回落9 | EncodeNum==0回落700
  MicroStepValue>6400回落800 | TapperTime>1000回落60 | PrePercent按[0,100]
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16

    local last_ter = nil       -- 最近一次0x26快照(写回保留固件侧字段: 行数Resv1)

    local RANGE_T = {
        { "GearRatio",      2,     65535, "传动比" },
        { "HoleNum",        1,     255,   "排种盘孔数" },
        { "EncodeNum",      1,     65535, "编码器脉冲" },
        { "MicroStepValue", 0,     6400,  "细分值" },
        { "TapperTime",     0,     1000,  "打点时间" },
        { "PrePercent",     0,     100,   "预压比" },
    }

    local function s16(v)
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

    -- 读表单(LW) -> terpara 表(i16符号扩展, 行数字段保留快照值)
    local function read_ter_form()
        local P = LW.PF
        local rows = last_ter and last_ter.Resv1
        if rows ~= 4 and rows ~= 6 then rows = 6 end   -- 无快照兜底6行
        return {
            A = s16(r16(P.a)), B = s16(r16(P.b)),
            EncodeNum = r16(P.encodenum), EncoderDir = r16(P.encoderdir),
            HoleNum = r16(P.holenum), GearRatio = r16(P.gearratio),
            MicroStepValue = s16(r16(P.microstep)),
            X1 = s16(r16(P.x1)), BDiroff = s16(r16(P.bdiroff)),
            TappTrigOff = s16(r16(P.tapptrigoff)), TapperTime = r16(P.tappertime),
            ZeroPosEn = r16(P.zeroposen), GZEn = r16(P.gzen),
            PrePercent = r16(P.prepercent),
            Resv1 = rows, Resv0 = 0, Resv1_ = 0, Resv2 = 0, CrcCheck = 0,
        }
    end

    -- 0x26 应答 -> LW 表单回显
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

    local page = {
        id = LW.SCREEN.MANUPARAM,
        poll_cmds = {},
        addrs = { LW.PF.read, LW.PF.write },
    }

    function page:on_enter()
        if (r16(LW.PWD.ok) or 0) ~= 1 then
            APP.set_screen(LW.SCREEN.USERPARAM)          -- 未解锁踢回
            return
        end
        PROTOCOL.send(FNC.GET_TER_PARA)
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == FNC.GET_TER_PARA then
            local ok, p = pcall(CODEC.terpara.unpack, f.data)
            if ok then show_ter(p); last_ter = p
            else wstr(LW.A.log, "terpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        if addr == LW.PF.read then
            PROTOCOL.send(FNC.GET_TER_PARA)
        elseif addr == LW.PF.write then
            local t = read_ter_form()
            local bad, msg = check(t, RANGE_T)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_TER_PARA, CODEC.terpara.pack(t))
        end
    end

    return page
end
