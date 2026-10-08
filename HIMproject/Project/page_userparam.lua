--[[
page_userparam.lua -- 用户参数页(画面3, 2026-09-28自原参数页拆分)
================================================================================
用户参数: QT模式(2026-09-30) —— 表单从3:config.txt读(不从下位机回显,
QT同款: formconfig.cpp只读ini, getUserParameter()声明未用), [保存]只写
config.txt+RW过道打点(启动任务/测试/连播时由参数链统一下发0x27/0x25)。
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
        addrs = { LW.PU.write, LW.PU.reset, LW.PU.cfgexp,
                 LW.PWD.confirm, LW.PWD.cancel },
    }

    local function gappoint_load()
        -- 过道打点三态: 0=关 1=开 2=间隔(存config.txt [Application]GapPoint)
        local v = ctx.PARASTORE and ctx.PARASTORE.load_gap() or 0
        if v ~= 0 and v ~= 1 and v ~= 2 then v = 0 end
        w16(LW.PU.gappoint, v)
    end

    -- 株距微调表5档(QT SeedGapFineTuning; 原密度固定, 只收specified/enabled)
    local FT_D = { LW.PU.ft_d1, LW.PU.ft_d2, LW.PU.ft_d3,
                   LW.PU.ft_d4, LW.PU.ft_d5 }
    local FT_E = { LW.PU.ft_e1, LW.PU.ft_e2, LW.PU.ft_e3,
                   LW.PU.ft_e4, LW.PU.ft_e5 }

    local function fine_show()
        local t = ctx.PARASTORE and ctx.PARASTORE.load_fine()
        if not t then return end
        for i = 1, 5 do
            w16(FT_D[i], t[i].specified)
            w16(FT_E[i], t[i].enabled)
        end
    end

    local function fine_read()
        local t = {}
        for i = 1, 5 do
            t[i] = { specified = r16(FT_D[i]), enabled = r16(FT_E[i]) }
        end
        return t
    end

    function page:on_enter()                     -- 进页读用户参数快照
        -- 副本预填(2026-09-30): 下位机离线/屏重启后表单不显示0;
        -- 在线时随后被0x28应答覆盖为固件当前值
        if ctx.PARASTORE then
            local sv = ctx.PARASTORE.load_user()
            if sv then
                local U0 = LW.PU
                w16(U0.dztime, sv.DZTime)
                w16(U0.hj, sv.HJ & 0xFFFF)
                w32(U0.rmp, sv.RMP)
                w16(U0.antennatype, sv.AntennaType)
                w16(U0.antennadist, sv.AntennaDistance & 0xFFFF)
            end
        end
        -- QT模式: 不向下位机读取(0x28能力保留在协议层但页面不使用)
        gappoint_load()
        fine_show()
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == FNC.GET_USER_PARA then
            local ok2, u = pcall(CODEC.userpara.unpack, f.data)
            if ok2 then show_user(u); gappoint_load()
            else wstr(LW.A.log, "userpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        if addr == LW.PU.write then
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            -- QT模式: [保存]只写config.txt(启动任务/测试/连播时参数链统一下发)
            local gp = r16(LW.PU.gappoint) or 0
            if gp ~= 0 and gp ~= 1 and gp ~= 2 then gp = 0 end
            local okc = ctx.PARASTORE
                and ctx.PARASTORE.save_user(t, gp)
                and ctx.PARASTORE.save_fine(fine_read())
            if okc then
                wstr(LW.A.log, "√ 已保存(作业/测试启动时下发)")
            elseif ctx.PARASTORE then
                wstr(LW.A.log, "× 配置写入失败")
            end
        elseif addr == LW.PU.reset then
            -- 重置: 仅恢复表单QT默认值, 不下发(需再点保存; gappoint随下次保存持久化RW)
            local U = LW.PU
            -- rmp是u32占两字(LW0x1622~23), w16只写低字会残留高字
            -- (2026-10-08实测重置后显示2359326=高36低30), 必须w32整写
            for k, v in pairs(DEFAULTS_U) do
                if k == 'rmp' then w32(U.rmp, v) else w16(U[k], v) end
            end
            for i = 1, 5 do               -- 微调全不启用, 指定密度=原密度
                w16(FT_D[i], ({ 4000, 4500, 5000, 5500, 6000 })[i])
                w16(FT_E[i], 0)
            end
            wstr(LW.A.log, "√ 已恢复默认值, 保存后生效")
        elseif addr == LW.PU.cfgexp then
            -- 导出配置到U盘(3:config.txt -> 2:config.txt)
            if ctx.PARASTORE then
                local ok = ctx.PARASTORE.export_usb()
                if not ok then wstr(LW.A.log, "× 导出失败(插U盘?已保存?)") end
            else
                wstr(LW.A.log, "× 导出不可用")
            end
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
