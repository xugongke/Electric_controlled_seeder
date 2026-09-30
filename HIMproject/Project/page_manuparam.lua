--[[
page_manuparam.lua -- 厂家参数页(画面4, 2026-09-28自原参数页拆分;
2026-09-16对齐QT formconfig.cpp厂家参数组布局/控件/默认值)
================================================================================
进入条件: 用户参数页密码弹窗校验通过(LW.PWD.ok=1), 未解锁进入则踢回画面3。
厂家参数(TerParaType 40B): 进页自动0x26读快照(QT无读按钮, 对齐), 0x25 保存。
行数字段Resv1(=U8Resv2 4/6)由[设备类型]pf_devtype下拉设置(2026-09-30用户要求:
结构体字段应可设置; QT global.cpp:78同款下发); 0x26回显固件当前值作初始值,
控件值非4/6时兜底快照值/6(2026-09-23曾硬编码0下发把行数冲掉, 用户实测暴露)。
[重置]仅把表单恢复QT默认值(formconfig.cpp:204~221, 不下发, 需再点保存)。
范围表(hd3005a1/Src/para.c ParaLegalCheck, 2026-09核对):
  GearRatio<2回落10 | HoleNum==0回落9 | EncodeNum==0回落700
  MicroStepValue>6400回落800 | TapperTime>1000回落60 | PrePercent按[0,100]
LW单位约定: 距离存cm(控件2位小数显m); TapperTime存0.01s(控件2位小数显s),
pack时*10->ms, show时四舍五入//10(QT formconfig.cpp:88 以s显示/155以ms存储)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16

    local last_ter = nil       -- 最近一次0x26快照(写回保留固件侧字段: 行数Resv1)

    -- QT重置默认值(formconfig.cpp:204~221; tappertime为LW单位0.01s)
    local DEFAULTS = {
        a = 60, b = 90, encodenum = 2000, encoderdir = 0,
        holenum = 9, gearratio = 5, microstep = 800,
        x1 = 150, bdiroff = 0, tapptrigoff = 20, tappertime = 10,
        zeroposen = 1, gzen = 1, prepercent = 70, devtype = 4,
    }

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
        local rows = r16(P.devtype)                    -- 设备类型下拉(0x26回显初值)
        if rows ~= 4 and rows ~= 6 then                -- 非法值兜底快照/6
            rows = last_ter and last_ter.Resv1
            if rows ~= 4 and rows ~= 6 then rows = 6 end
        end
        return {
            A = s16(r16(P.a)), B = s16(r16(P.b)),
            EncodeNum = r16(P.encodenum), EncoderDir = r16(P.encoderdir),
            HoleNum = r16(P.holenum), GearRatio = r16(P.gearratio),
            MicroStepValue = s16(r16(P.microstep)),
            X1 = s16(r16(P.x1)), BDiroff = s16(r16(P.bdiroff)),
            TappTrigOff = s16(r16(P.tapptrigoff)),
            TapperTime = r16(P.tappertime) * 10,       -- 0.01s单位 -> ms
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
        w16(P.tappertime, (p.TapperTime + 5) // 10)    -- ms -> 0.01s单位
        w16(P.zeroposen, p.ZeroPosEn)
        w16(P.gzen, p.GZEn);             w16(P.prepercent, p.PrePercent)
        w16(P.devtype, p.Resv1)                        -- 行数回显到设备类型下拉
    end

    local page = {
        id = LW.SCREEN.MANUPARAM,
        poll_cmds = {},
        addrs = { LW.PF.write, LW.PF.reset },
    }

    function page:on_enter()
        if (r16(LW.PWD.ok) or 0) ~= 1 then
            APP.goto_screen(LW.SCREEN.USERPARAM)  -- 物理踢回画面3          -- 未解锁踢回
            return
        end
        -- 副本预填(2026-09-30): 下位机离线/屏重启后表单不显示0;
        -- 在线时随后被0x26应答覆盖; tappertime按LW单位0.01s换算
        if ctx.PARASTORE then
            local sv = ctx.PARASTORE.load_ter()
            if sv then
                local P0 = LW.PF
                w16(P0.a, sv.A & 0xFFFF);         w16(P0.b, sv.B & 0xFFFF)
                w16(P0.encodenum, sv.EncodeNum);  w16(P0.encoderdir, sv.EncoderDir)
                w16(P0.holenum, sv.HoleNum);      w16(P0.gearratio, sv.GearRatio)
                w16(P0.microstep, sv.MicroStepValue & 0xFFFF)
                w16(P0.x1, sv.X1 & 0xFFFF);       w16(P0.bdiroff, sv.BDiroff & 0xFFFF)
                w16(P0.tapptrigoff, sv.TappTrigOff & 0xFFFF)
                w16(P0.tappertime, ((sv.TapperTime or 0) + 5) // 10)
                w16(P0.zeroposen, sv.ZeroPosEn);  w16(P0.gzen, sv.GZEn)
                w16(P0.prepercent, sv.PrePercent)
                w16(P0.devtype, sv.Resv1)
            end
        end
        -- QT模式: 不向下位机读取(0x26能力保留在协议层但页面不使用)
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
        if addr == LW.PF.write then
            local t = read_ter_form()
            local bad, msg = check(t, RANGE_T)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            -- QT模式: [保存]只写config.txt(启动任务/测试/连播时参数链统一下发)
            if ctx.PARASTORE and ctx.PARASTORE.save_ter(t) then
                wstr(LW.A.log, "× 已保存(作业/测试启动时下发)")
            elseif ctx.PARASTORE then
                wstr(LW.A.log, "× 配置写入失败")
            end
        elseif addr == LW.PF.reset then
            -- 重置: 仅恢复表单QT默认值, 不下发(需再点保存)
            local P = LW.PF
            for k, v in pairs(DEFAULTS) do w16(P[k], v) end
            wstr(LW.A.log, "√ 已恢复默认值, 保存后生效")
        end
    end

    return page
end
