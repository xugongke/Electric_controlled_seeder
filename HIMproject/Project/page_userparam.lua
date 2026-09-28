--[[
page_userparam.lua -- 用户参数页(画面3, 2026-09-28自原参数页拆分)
================================================================================
用户参数(UserParaType 16B): 0x28 进页读快照, 0x27 写入+前端校验。
[厂家参数]按钮 = 画面侧功能按钮(打开对话框画面23, 密码数值输入绑 pf_pass,
确认=关闭对话框+执行通知写 LW.PWD.confirm=1) -> 本页校验密码(515516, 与
QT formconfig.cpp:172 同源), 正确则置 PWD.ok 并切换到画面4厂家参数页。
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
        addrs = { LW.PU.read, LW.PU.write, LW.PWD.confirm, LW.PWD.cancel },
    }

    function page:on_enter()                     -- 进页读用户参数快照
        PROTOCOL.send(FNC.GET_USER_PARA)
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == FNC.GET_USER_PARA then
            local ok2, u = pcall(CODEC.userpara.unpack, f.data)
            if ok2 then show_user(u)
            else wstr(LW.A.log, "userpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        if addr == LW.PU.read then
            PROTOCOL.send(FNC.GET_USER_PARA)
        elseif addr == LW.PU.write then
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_USER_PARA, CODEC.userpara.pack(t))
        elseif addr == LW.PWD.confirm then
            -- 密码对话框确认(关闭对话框按钮执行通知)
            local pw = r32(LW.PF.pass) or 0
            if pw == PASSWORD then
                w16(LW.PWD.ok, 1)
                wstr(LW.A.log, "√ 密码正确")
                APP.set_screen(LW.SCREEN.MANUPARAM)
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
