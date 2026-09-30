--[[
page_userparam.lua -- 用户参数页(画面3, 2026-09-28自原参数页拆分)
================================================================================
用户参数(UserParaType 16B): 0x28 进页读快照, 0x27 写入+前端校验。
[厂家参数]按钮 = 画面侧功能按钮(打开对话框画面23, 密码数值输入绑 pf_pass,
确认=关闭对话框+执行通知写 LW.PWD.confirm=1) -> 本页校验密码(515516, 与
QT formconfig.cpp:172 同源), 正确则置 PWD.ok 并切换到画面4厂家参数页。
[重置]仅把表单恢复QT默认值(formconfig.cpp:187~199, 不下发, 需再点保存)。
范围表(下位机强制, hd3005a1/Src/para.c ParaLegalCheck):
  HJ 10~5000 回落60; DZTime 100~10000 回落1500; RMP 5~70 回落20
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16, r32 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16, ctx.r32

    local PASSWORD = 515516

    local RANGE_U = {
        { "HJ",     10, 5000,  "行间距HJ" },
        { "DZTime", 100, 10000, "点滞时间" },
        { "RMP",    5,  70,    "播种盘转速RMP" },
    }

    -- QT重置默认值(formconfig.cpp:187~199): 1.5s/0.6m/36r/单天线/0m/过道开
    local DEFAULTS_U = {
        dztime = 1500, hj = 60, rmp = 36,
        antennatype = 0, antennadist = 0, gappoint = 1,
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

    -- 读表单 -> userpara 表
    local function read_user_form()
        local U = LW.PU
        return {
            DZTime = r16(U.dztime), HJ = s16(r16(U.hj)), RMP = r32(U.rmp),
            AntennaType = r16(U.antennatype), U8Resv = 0,
            AntennaDistance = s16(r16(U.antennadist)), CrcCheck = 0,
        }
    end

    -- 0x28 应答 -> LW 表单回显
    local function show_user(p)
        local U = LW.PU
        w16(U.dztime, p.DZTime)
        w16(U.hj, p.HJ & 0xFFFF)
        w32(U.rmp, p.RMP)
        w16(U.antennatype, p.AntennaType)
        w16(U.antennadist, p.AntennaDistance & 0xFFFF)
    end

    local page = {
        id = LW.SCREEN.USERPARAM,
        poll_cmds = {},
        addrs = { LW.PU.write, LW.PU.reset, LW.PWD.confirm, LW.PWD.cancel },
    }

    local function gappoint_rw_load()
        -- RW掉电保持三态: 0=关 1=开 2=间隔(非法值按关处理)
        local v = 0
        if ctx.rw16 and LW.RW then
            v = ctx.rw16(LW.RW.gap_point)
            if v ~= 0 and v ~= 1 and v ~= 2 then v = 0 end
        end
        w16(LW.PU.gappoint, v)
    end

    function page:on_enter()                     -- 进页读用户参数快照
        PROTOCOL.send(FNC.GET_USER_PARA)
        gappoint_rw_load()
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == FNC.GET_USER_PARA then
            local ok2, u = pcall(CODEC.userpara.unpack, f.data)
            if ok2 then show_user(u); gappoint_rw_load()
            else wstr(LW.A.log, "userpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        if addr == LW.PU.write then
            -- 过道打点持久化RW(三态原值, 不进0x27协议; QT原设计在用户参数页)
            if ctx.rw16w and LW.RW then
                local gp = r16(LW.PU.gappoint) or 0
                if gp ~= 0 and gp ~= 1 and gp ~= 2 then gp = 0 end
                ctx.rw16w(LW.RW.gap_point, gp)
            end
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_USER_PARA, CODEC.userpara.pack(t))
        elseif addr == LW.PU.reset then
            -- 重置: 仅恢复表单QT默认值, 不下发(需再点保存; gappoint随下次保存持久化RW)
            local U = LW.PU
            for k, v in pairs(DEFAULTS_U) do w16(U[k], v) end
            wstr(LW.A.log, "√ 已恢复默认值, 保存后生效")
        elseif addr == LW.PWD.confirm then
            -- 密码对话框确认(关闭对话框按钮执行通知)
            local pw = r32(LW.PF.pass) or 0
            if pw == PASSWORD then
                w16(LW.PWD.ok, 1)
                wstr(LW.A.log, "√ 密码正确")
                APP.goto_screen(LW.SCREEN.MANUPARAM)   -- 物理切画面4
            else
                w16(LW.PWD.ok, 0)
                wstr(LW.A.log, "× 密码错误")
            end
        elseif addr == LW.PWD.cancel then
            w16(LW.PWD.ok, 0)
        end
    end

    return page
end
