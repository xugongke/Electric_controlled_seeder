--[[
page_continuous.lua -- 连续播种页(画面2, 2026-09-28重设对齐QT formcontinuoussow)
================================================================================
QT口径: 用户只须输入密度即可开始; 行距/行长默认60/500可调(屏端无config.ini,
以输入控件默认值承载); 株距=行长*10/(密度-1)四舍五入只读显示(QT :116);
ZhuShu=0自动。运行显示: 排列行程/速度/漏肥漏株各6路(0x21轮询经jobrun常驻
截获存 last_status, 本页 on_tick 取快照刷新显示)。
LW: LW.CONT (0x1400区)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local JOBRUN = ctx.JOBRUN
    local FNC = PROTOCOL.FNC
    local r32, w16, w32 = ctx.r32, ctx.w16, ctx.w32

    local function s32(v)
        v = v & 0xFFFFFFFF
        if v >= 0x80000000 then v = v - 0x100000000 end
        return v
    end
    local function s16(v)
        v = v & 0xFFFF
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end

    local page = {
        id = LW.SCREEN.CONTINUOUS,
        -- 0x21: 应答被 jobrun 常驻订阅截获(更新 jobrun.last_status),
        -- 连续模式无作业不设 always_poll, 由本页 poll 触发请求
        poll_cmds = { FNC.GET_BZ_STATUS },
        addrs = { LW.CONT.start, LW.CONT.stop },
    }

    function page:on_enter()
        w16(LW.CONT.start, 0)
        w16(LW.CONT.stop, 0)
    end

    function page:on_leave() end

    function page:on_frame() end

    function page:on_update(addr)
        if addr == LW.CONT.start then
            local density = s32(r32(LW.CONT.density))
            local celllen = s32(r32(LW.CONT.celllen))
            local hju     = s16(r32(LW.CONT.hju))
            if density < 2 or celllen < 10 then
                w16(LW.CONT.start, 0)
                return                          -- 密度>=2才有株距意义
            end
            PROTOCOL.send(FNC.CMD_START_LXBZ, CODEC.lxbz.pack {
                Density = density, CellLen = celllen, Hju = hju, ZhuShu = 0,
            })
        elseif addr == LW.CONT.stop then
            PROTOCOL.send(FNC.CMD_STOP_LXBZ)    -- 空域
        end
    end

    -- 运行显示: 株距计算 + jobrun.last_status 刷新行程/速度/计数
    page.on_tick = function()
        local density = s32(r32(LW.CONT.density))
        local celllen = s32(r32(LW.CONT.celllen))
        if density > 1 and celllen > 0 then
            -- QT formcontinuoussow.cpp:116 株距四舍五入
            w32(LW.CONT.zhuju, (celllen * 10 // (density - 1) + 5) // 10)
        end
        local st = JOBRUN and JOBRUN.last_status
        if st then
            w32(LW.CONT.offlen, st.OffLen or 0)
            w32(LW.CONT.speed,  st.Speed or 0)
            for i = 1, CODEC.ROWS do
                w32(LW.CONT.loufei1 + (i - 1) * 2, st.LoufeiCnt[i] or 0)
                w32(LW.CONT.louzh1 + (i - 1) * 2, st.LouZHCnt[i] or 0)
            end
        end
    end

    return page
end
