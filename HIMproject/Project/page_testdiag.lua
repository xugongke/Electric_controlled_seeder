--[[
page_testdiag.lua -- 测试诊断页(画面5, 2026-09-28重设对齐QT formtest)
================================================================================
输入状态: 15盏具名位灯(画面绑 td_input 位0~14, 报警红字绑 td_warning 同位):
  bit0~3 零位1~4 | bit4 自动供种 | bit5 预留 | bit6/7 钢索1/2 | bit8 压力
  bit9 风机 | bit10 脚踏板 | bit11 初始化 | bit12 北斗 | bit13/14 零位5/6
输出控制: 16个一键翻转按钮(阀CtrlNo0~8 + 电机CtrlNo16~22), 点按=读当前
  CtrlState位取反后0x09下发(QT setValveState(ch,!bit)同款);
  电机位在0x08应答的CtrlState里位于bit16~22(固件 DJCtrlState<<16 上报)。
计数: 编码器/北斗 + 漏肥/漏株各6路(随 codec.ROWS 由 0x26 动态切换, 4行残留已修)。
原 jogno/jogon/jogtrig 点动三件套已删(一键翻转取代)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr = ctx.w16, ctx.w32, ctx.wstr

    local last_ctrl = 0                        -- 最近一帧0x08的CtrlState

    -- 输出按钮地址 -> CtrlNo(一键翻转)
    local SW = {
        [LW.TD.sw0] = 0,  [LW.TD.sw1] = 1,  [LW.TD.sw2] = 2,  [LW.TD.sw3] = 3,
        [LW.TD.sw4] = 4,  [LW.TD.sw5] = 5,  [LW.TD.sw6] = 6,  [LW.TD.sw7] = 7,
        [LW.TD.sw8] = 8,
        [LW.TD.m1] = 16, [LW.TD.m2] = 17, [LW.TD.m3] = 18, [LW.TD.m4] = 19,
        [LW.TD.m5] = 20, [LW.TD.m6] = 21, [LW.TD.m7] = 22,
    }

    local page = {
        id = LW.SCREEN.TESTDIAG,
        poll_cmds = { FNC.GET_TEST_STATUS },         -- 0x08 仅本页可见时轮询
        addrs = { LW.TD.enter, LW.TD.exit },
    }
    for a in pairs(SW) do page.addrs[#page.addrs + 1] = a end

    function page:on_frame(f)
        if f.fnc ~= FNC.GET_TEST_STATUS then return end
        local ok, st = pcall(CODEC.teststate.unpack, f.data)
        if not ok then
            wstr(LW.A.log, "teststate unpack err: len=" .. #f.data)
            return
        end
        last_ctrl = st.CtrlState or 0
        w32(LW.TD.encodercnt, st.EncoderCnt)
        w32(LW.TD.bdcnt,      st.BdCnt)
        for i = 1, CODEC.ROWS do
            w32(LW.TD.loufei1 + (i - 1) * 2, st.LoufeiCnt[i])
            w32(LW.TD.louzh1 + (i - 1) * 2, st.LouZHCnt[i])
        end
        w32(LW.TD.input,   st.InputState)
        w32(LW.TD.warning, st.WarningState)
        w32(LW.TD.ctrl,    st.CtrlState)
    end

    function page:on_update(addr)
        if addr == LW.TD.enter then
            PROTOCOL.send(FNC.CMD_START_TEST)       -- 空域
        elseif addr == LW.TD.exit then
            PROTOCOL.send(FNC.CMD_STOP_TEST)
        else
            local no = SW[addr]
            if no then
                -- QT语义: 取反当前位再下发
                local state = 0
                if (last_ctrl >> no) & 1 == 0 then state = 1 end
                PROTOCOL.send(FNC.CMD_SVCTRL,
                              CODEC.testcmd.pack { CtrlNo = no, State = state })
            end
        end
    end

    return page
end
