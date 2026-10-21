--[[
page_testdiag.lua -- 测试诊断页(画面5, 2026-10-21重设计对齐QT formtest)
================================================================================
布局对齐QT formtest.ui双栏(hmiprj_build_test5.py重建):
  左栏 输入状态: 15项具名输入(零位开关1~6/自动供种接近开关/预留输入/钢索1~2/
        压力/风机/脚踏板/一键初始化按钮/北斗, bit0~14)状态灯(LW171C.x)+
        报警灯(LW171E.x) + 编码器/北斗计数 + 漏种/漏肥各6路表;
  右栏 输出控制: 17个一键翻转按钮(阀CtrlNo0~9: 预落种/倒种/清种/刮种/
        预留1~2/喇叭/打点器/报警灯/运行指示灯 + 电机CtrlNo16~22:
        步进电机1~4/自动供种步进电机/步进电机5~6), 点按=读当前CtrlState位
        取反后0x09下发(QT setValveState(ch,!bit)同款), 各配报警灯
        (阀LW171E.0~9/电机LW171F.0~6)。
进出测试模式自动化(2026-10-21对齐QT mainwindow :71/:88切页自动
enter/exitTestMode; 原进/出测试按钮已删):
  进页面: 参数链0x27成功->0x25->成功->0x0E(作业进行中禁止进入);
          链完成前离页/再入由会话令牌作废旧回调。
  离页面: 直接0x0F。
报警使能勾选(QT TestWarning组)屏端无UI不写(与parastore口径一致)。
0x26行数动态切换由jobrun全局路由处理(本页不重复订阅)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr = ctx.w16, ctx.w32, ctx.wstr
    local JOBRUN = ctx.JOBRUN

    local last_ctrl = 0                        -- 最近一帧0x08的CtrlState

    -- 输出一键翻转按钮地址 -> CtrlNo(2026-10-21补sw9运行指示灯阀,
    -- 对齐QT formtest 17路输出)。防御式构建(2026-10-22): 某标签缺失
    -- (如屏上lwmap.lua未同步到含sw9的版本)时跳过该路, 不再因nil键
    -- 崩掉创建器致整页注册失败(自动进入随之失效, 用户实测)
    local SW = {}
    for _, e in ipairs({
        { LW.TD.sw0, 0 },  { LW.TD.sw1, 1 },  { LW.TD.sw2, 2 },
        { LW.TD.sw3, 3 },  { LW.TD.sw4, 4 },  { LW.TD.sw5, 5 },
        { LW.TD.sw6, 6 },  { LW.TD.sw7, 7 },  { LW.TD.sw8, 8 },
        { LW.TD.sw9, 9 },
        { LW.TD.m1, 16 }, { LW.TD.m2, 17 }, { LW.TD.m3, 18 },
        { LW.TD.m4, 19 }, { LW.TD.m5, 20 }, { LW.TD.m6, 21 },
        { LW.TD.m7, 22 },
    }) do
        if e[1] then SW[e[1]] = e[2] end
    end

    local page = {
        id = LW.SCREEN.TESTDIAG,
        poll_cmds = { FNC.GET_TEST_STATUS },   -- 0x08 仅本页可见时轮询
                                               -- (QT signalEnterTestMode启testTimer同)
        addrs = { LW.TD.enter, LW.TD.exit },   -- 进/出按钮(2026-10-22恢复手动兜底)
    }
    for a in pairs(SW) do page.addrs[#page.addrs + 1] = a end

    -- 进测试流程(自动+手动共用): 参数链0x27->0x25->0x0E
    local function enter_flow()
        if JOBRUN and JOBRUN.active() then
            wstr(LW.A.log, "作业进行中, 禁止进入测试模式")
            return
        end
        local token = {}                        -- 会话令牌: 离页/再入作废旧链
        page.token = token
        local enter_test = function()
            if page.token ~= token then return end
            PROTOCOL.send(FNC.CMD_START_TEST)   -- 0x0E 空域
            wstr(LW.A.log, "已进入测试模式")
        end
        if ctx.PARASTORE then
            ctx.PARASTORE.begin("TEST", nil, enter_test)
        else
            enter_test()                        -- A档降级: 直发
        end
    end

    -- 退测试流程(自动+手动共用): 直接0x0F
    local function exit_flow()
        page.token = nil                        -- 链完成前离页: 回调作废
        PROTOCOL.send(FNC.CMD_STOP_TEST)        -- 0x0F 空域
        wstr(LW.A.log, "已退出测试模式")
    end

    function page:on_enter()
        -- 对齐QT mainwindow:88: 切入测试页自动进测试模式
        enter_flow()
    end

    function page:on_leave()
        -- 对齐QT mainwindow:71: 切离测试页自动退测试模式
        exit_flow()
    end

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
            enter_flow()                        -- 手动进入(兜底)
        elseif addr == LW.TD.exit then
            exit_flow()                         -- 手动退出(兜底)
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
