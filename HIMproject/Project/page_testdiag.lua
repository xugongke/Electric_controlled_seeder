--[[
page_testdiag.lua -- 测试诊断页(画面5, 2026-10-21重设计对齐QT formtest)
================================================================================
布局对齐QT formtest.ui双栏(hmiprj_build_test5.py重建):
  左栏 输入状态: 15项具名输入(零位开关1~6/自动供种接近开关/预留输入/钢索1~2/
        压力/风机/脚踏板/一键初始化按钮/北斗, bit0~14)状态灯(td_input0~14
        =LW1790+E显示字)+报警灯(td_walamp0~14=LW179F+)+编码器/北斗计数 +
        漏种/漏肥各6路表;
  右栏 输出控制: 17路位状态开关(阀CtrlNo0~9: 预落种/倒种/清种/刮种/
        预留1~2/喇叭/打点器/报警灯/运行指示灯 + 电机CtrlNo16~22:
        步进电机1~4/自动供种步进电机/步进电机5~6), WriteAddr=td_sw0~9/
        td_m1~7, 点按翻转写值on_update直发0x09(0=停止/1=动作, QT
        setValveState同款), 自保持显示(电机报警灯7路已按用户选择删除)。
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
    local sw_seen = {}                         -- 开关最后事件值: 只认"见过1后
                                               --   的0"(滤屏切初始化伪0事件)

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
        no_reset = true,    -- 位状态开关页: 按钮不复位(APP.on_button跳过清零,
                            --   开关单元自保持0/1状态显示)
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
        -- 位分解显示字(2026-10-22): 平台"字.位"地址灯实测不可靠(位灯不亮),
        -- 每位0/1写独立字, 位灯绑字地址(与rt_positive同款已验证机制);
        -- 输入位0~14 -> lamp_in0+N, 报警位0~14 -> lamp_wa0+N,
        -- 电机报警bit16~22 -> lamp_hi0+N
        for k = 0, 14 do
            w16(LW.TD.lamp_in0 + k, (st.InputState >> k) & 1)
            w16(LW.TD.lamp_wa0 + k, (st.WarningState >> k) & 1)
        end
        for k = 0, 6 do
            w16(LW.TD.lamp_hi0 + k, (st.WarningState >> (16 + k)) & 1)
        end
        -- 注意: 17路输出开关td_sw0~9/td_m1~7字不做CtrlState回显分解——
        -- 平台on_update对lua写地址是否触发无文档, 若触发则每帧0x08会
        -- 回环成0x09风暴; 开关为自保持显示(点击即生效, 模拟器/下位机
        -- 立即应用, 显示与实态一致)
    end

    function page:on_update(addr, v)
        if addr == LW.TD.enter then
            -- 位状态开关: 1=进入测试 0=退出测试(2026-10-22用户定义)
            if v == 1 then enter_flow() else exit_flow() end
        elseif addr == LW.TD.exit then
            exit_flow()                         -- 兼容保留(无控件)
        else
            local no = SW[addr]
            if no then
                -- 位状态开关: 开关单元值即目标态(0=停止 1=动作), 直发。
                -- v=0须main.lua对no_reset页放行才到得了这里(M37前被
                -- "0=复位态"守卫丢弃, 输出只能开不能关); 此处再滤一次
                -- 伪0(没开过就收到0=初始化/回声, 非用户关断)
                if v == 0 and sw_seen[addr] ~= 1 then return end
                sw_seen[addr] = v
                -- !! Lua 0为真值: 不可写 `v and 1 or 0`(v=0会得1, 关变开,
                -- 2026-10-22测试8抓现形); 必须显式判1
                PROTOCOL.send(FNC.CMD_SVCTRL,
                              CODEC.testcmd.pack { CtrlNo = no,
                                                   State = (v == 1) and 1 or 0 })
            end
        end
    end

    return page
end
