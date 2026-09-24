--[[
page_testdiag.lua —— 测试诊断页: 测试模式切换 / 0x08 位图轮询 / 0x09 点动 / 0x22 调试串
================================================================================
  轮询  0x08 TestModeStateType -> 编码器/北斗计数, 漏种漏株x行, IO/报警/输出位图
        (poll_cmds 机制: 仅本页可见时轮询, 离开自动停 —— app.lua 框架保证)
  按钮  TD.enter 0x1740 -> 0x0E 进入测试模式(空域)
        TD.exit  0x1741 -> 0x0F 退出(空域)
        TD.jogtrig 0x1744 -> 0x09 TestCMDType{CtrlNo, State}(4B)
        TD.debug 0x1745 -> 0x22 读调试信息(空域)
  应答  0x08 -> LW.TD 区刷新; 0x22 -> ASCII 过滤写 LW.A.log(D5 决策)
        注: 主页也有 0x22 按钮; 帧按当前页路由, 两页各自处理自己发出的 0x22
  State 语义: 下位机仅存 TestCMD 由主循环消费(protocool.c:385), 屏端透传不解释
返回 creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16

    local page = {
        id        = LW.SCREEN.TESTDIAG,
        poll_cmds = { FNC.GET_TEST_STATUS },         -- 0x08 仅本页可见时轮询
        addrs     = { LW.TD.enter, LW.TD.exit, LW.TD.jogtrig, LW.TD.debug },
    }

    function page:on_frame(f)
        local d = f.data
        if f.fnc == FNC.GET_TEST_STATUS then        -- 0x08 测试状态
            local ok, st = pcall(CODEC.teststate.unpack, d)
            if ok then
                w32(LW.TD.encodercnt, st.EncoderCnt)
                w32(LW.TD.bdcnt,      st.BdCnt)
                for i = 1, CODEC.ROWS do
                    w32(LW.TD.loufei1 + (i - 1) * 2, st.LoufeiCnt[i])
                    w32(LW.TD.louzh1 + (i - 1) * 2, st.LouZHCnt[i])
                end
                w32(LW.TD.input,   st.InputState)   -- 位指示灯 x32 绑定
                w32(LW.TD.warning, st.WarningState)
                w32(LW.TD.ctrl,    st.CtrlState)
            else
                wstr(LW.A.log, "teststate unpack err: len=" .. #d)
            end
        elseif f.fnc == FNC.RD_DEBUG_INFO then      -- 0x22 (D5: ASCII 过滤)
            local t = {}
            for i = 1, #d do
                local b = string.byte(d, i)
                if b < 0x80 then t[#t + 1] = string.char(b) end
            end
            wstr(LW.A.log, table.concat(t))
        end
    end

    function page:on_update(addr)
        if addr == LW.TD.enter then
            PROTOCOL.send(FNC.CMD_START_TEST)       -- 空域
        elseif addr == LW.TD.exit then
            PROTOCOL.send(FNC.CMD_STOP_TEST)        -- 空域
        elseif addr == LW.TD.jogtrig then
            local cmd = CODEC.testcmd.pack{
                CtrlNo = r16(LW.TD.jogno),
                State  = r16(LW.TD.jogon),
            }
            PROTOCOL.send(FNC.CMD_SVCTRL, cmd)
        elseif addr == LW.TD.debug then
            PROTOCOL.send(FNC.RD_DEBUG_INFO)        -- 空域
        end
    end

    return page
end
