--[[
page_home.lua —— 主页: 作业状态监视 + 启停控制
================================================================================
自 POC 阶段 main.lua 迁移(行为/LW地址不变, 供 e2e 回归对照):
  轮询  0x21 BZStatusType -> 状态区刷新
  按钮  B_START 0x1100 -> 0x0A 启动小区播种
        B_STOP  0x1101 -> 0x0B 停止播种
        B_VER   0x1102 -> 0xA3 查询版本
        B_DEBUG 0x1103 -> 0x22 读调试信息
  应答  0xA3 -> 版本串; 0x22 -> 调试串(D5决策: 暂显ASCII, 过滤>=0x80字节)
返回 creator(ctx) -> page 表(ctx 见 app.lua 头注释)
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local JOBRUN, STORE = ctx.JOBRUN, ctx.STORE
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr = ctx.w16, ctx.w32, ctx.wstr

    local page = {
        id        = LW.SCREEN.HOME,
        poll_cmds = { FNC.GET_BZ_STATUS },           -- 0x21
        addrs     = { LW.B.start, LW.B.stop, LW.B.ver, LW.B.debug },
    }

    -- 进入主页: 查一次版本(链路自检)
    function page:on_enter()
        PROTOCOL.send(FNC.GET_SOFT_VER)
    end

    function page:on_frame(f)
        local d = f.data
        if f.fnc == FNC.GET_BZ_STATUS then           -- 0x21 作业状态
            local ok, st = pcall(CODEC.bzstatus.unpack, d)
            if ok then
                w16(LW.A.runstate, st.RunState)
                w16(LW.A.bdstate,  st.BdState)
                w32(LW.A.speed,    st.Speed)
                w16(LW.A.rownum,   st.RowNum)
                w32(LW.A.offlen,   st.OffLen)
                w32(LW.A.voff,     st.VerticalOff)
                for i = 1, CODEC.ROWS do w16(LW.A.loufei + i - 1, st.LoufeiCnt[i]) end
                w16(LW.A.louzh, st.LouZHCnt[1])
            else
                wstr(LW.A.log, "bzstatus unpack err: len=" .. #d)
            end
        elseif f.fnc == FNC.GET_SOFT_VER then        -- 0xA3 版本串
            wstr(LW.A.ver, d)
        elseif f.fnc == FNC.RD_DEBUG_INFO then       -- 0x22 调试串(D5: ASCII过滤)
            local t = {}
            for i = 1, #d do
                local b = string.byte(d, i)
                if b < 0x80 then t[#t + 1] = string.char(b) end
            end
            wstr(LW.A.log, table.concat(t))
        elseif f.fnc == FNC.STORE_AB then            -- 0x23 停止时AB线采集应答
            if JOBRUN and JOBRUN.save_ab then
                if JOBRUN.save_ab(d) then
                    wstr(LW.A.tip, "√ AB线已保存")
                end
            end
        end
    end

    function page:on_update(addr)
        -- 开始键(QT pushButtonStart 语义三分支):
        --   作业中           -> 裸发 0x0A(下位机级续播, 任务参数已在线)
        --   趟间等待(跨趟挂起) -> 提示先停止(实操流程: 停止->掉头->开始)
        --   无作业有断点     -> 断点续作 resume(下发新趟 0x20 参数+0x0A,
        --                        等价 QT signalStartSow :276/:299)
        --   无任务           -> 裸发 0x0A(非任务手动播种场景)
        if     addr == LW.B.start then
            if JOBRUN and JOBRUN.active() then
                local s = JOBRUN.snapshot()
                if s and s.trip_wait then
                    wstr(LW.A.log, "本趟已完成 请先按停止")
                else
                    PROTOCOL.send(FNC.CMD_START_BZ)
                end
            else
                local name
                if JOBRUN and STORE and STORE.task_list then
                    for _, n in ipairs(STORE.task_list()) do
                        local d, tot = STORE.task_progress(n)
                        if d < tot then name = n break end
                    end
                end
                if name then
                    local ok, err = JOBRUN.start(name, { resume = true })
                    if not ok then wstr(LW.A.log, "续作失败: " .. tostring(err)) end
                else
                    PROTOCOL.send(FNC.CMD_START_BZ)
                end
            end
        -- 停止经作业调度层: 有任务时归档断点/清现场(100%完成待停也在此收尾),
        -- 无任务(B档降级)时裸发急停; 两条路径内部均发 0x0B
        elseif addr == LW.B.stop  then
            if JOBRUN then JOBRUN.stop() else PROTOCOL.send(FNC.CMD_STOP_BZ) end
        elseif addr == LW.B.ver   then PROTOCOL.send(FNC.GET_SOFT_VER)
        elseif addr == LW.B.debug then PROTOCOL.send(FNC.RD_DEBUG_INFO)
        end
    end

    return page
end
