--[[
page_task.lua —— 任务作业页(画面6, 2026-09-24重构)
================================================================================
原4步向导已删除, 仿QT实时任务页结构:
  配置(tstate=1): 地图列表选择 + 任务参数区(路径方式/方向/起始排/起始列/图外播种)
        -> [创建任务] 只创建不启动(QT创建后由开始键执行)
  就绪(tstate=4): 任务已创建待开始 -> [开始作业] JOBRUN.start
  作业(tstate=2): jobrun.snapshot 轻刷新; [开始]=续趟裸发0x0A; [停止]=收尾
-- (AB线功能已于2026-10-09整体移除: 恒行程开关模式,
--  开播前地头按行程开关设A点; 见jobrun.ab_send_map全零0x24)
  完成(tstate=3): 待续接/返回配置
        导入/清除=字设置按钮(本页处理, 作用于所选/当前地图)。
U盘导入已移至地图导入页(page_map.lua, 画面9)。
依赖注入: creator(ctx) 同现有页面模式。
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, PATHALGO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.PATHALGO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6                  -- 列表窗口行数

    -- 页面现场(非持久): 配置态的选择与已创建任务名
    local W = { map = nil, task = nil, sel = 0, top = 0, items = {} }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function render_list()
        local lines = {}
        for i = W.top + 1, math.min(W.top + LIST_ROWS, #W.items) do
            local mark = (i == W.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. W.items[i]
        end
        while #lines < 1 do lines[1] = " " end
        wstr(LW.TW.list, table.concat(lines, "\r\n"))
        w16(LW.TW.count, #W.items)
        w16(LW.TW.selidx, W.sel)
    end

    -- 配置态列表: 地图清单
    local function cfg_items()
        W.items = {}
        if STORE then
            for _, n in ipairs(STORE.map_list()) do
                W.items[#W.items + 1] = n .. " " .. STORE.map_spec(n)
            end
        end
        if #W.items == 0 then W.items[1] = "(无地图, 请到地图导入页)" end
    end

    -- 选定地图: 摘要 + 默认起始小区(路径算法首节点)
    local function pick_map(name)
        local m = STORE and STORE.map_get(name)
        if not m then return end
        W.map = name
        wstr(LW.TW.mapinfo, name .. " " .. STORE.map_spec(name))
    end

    local function goto_state(n)
        w16(LW.TW.tstate, n)
        W.sel, W.top = 0, 0
        if n == 1 then
            cfg_items()
            wstr(LW.TW.detail, "选地图 设参数 后创建任务")
            if W.map and STORE and STORE.map_get(W.map) then
                pick_map(W.map)
            elseif STORE then
                local names = STORE.map_list()      -- 自动选中首张(单图零按键)
                W.sel = 0
                if names[1] then pick_map(names[1]) end
            end
        elseif n == 4 then
            wstr(LW.TW.detail, "任务已创建 按[开始作业]执行")
        elseif n == 2 then
            wstr(LW.TW.detail, "作业中 " .. tostring(W.task or ""))
        elseif n == 3 then
            wstr(LW.TW.detail, "已停止 可续接或返回配置")
        end
        render_list()
    end

    ------------------------------------------------------------------ AB操作
    ------------------------------------------------------------------ 按钮
    local function on_btn(addr, val)
        if val ~= 1 then return end
        local ts = r16(LW.TW.tstate) or 1

        if addr == LW.TW.btn_sel then
            -- 配置态: 循环选择地图(2026-09-24按画面清单移除上/下移按钮,
            -- 单键循环: 第1次选第2张...回到第1张; 进配置态时已自动选首张)
            if ts == 1 and STORE then
                local names = STORE.map_list()
                if #names > 1 then
                    W.sel = (W.sel + 1) % #names
                    if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1
                    elseif W.sel < W.top then W.top = W.sel end
                    render_list()
                end
                local name = names[W.sel + 1]
                if name then pick_map(name) end
            end

        elseif addr == LW.TW.btn_ok then
            -- 创建任务(不自动开始, 2026-09-24用户决策: 设置完参数点开始再执行)
            local m = STORE and STORE.map_get(W.map)
            if not m then
                goto_state(1)
                wstr(LW.TW.detail, "请先选择地图")
                return
            end
            -- 配置简化(2026-10-09): 固定 正向+起始(1,1)=0基(0,0)
            local drow, dcol = 0, 0
            local seq = #STORE.task_list() + 1
            local name = "任务" .. seq
            local ok, err = STORE.task_create(name, W.map,
                r16(LW.TW.path_type) or 0, 1,
                r16(LW.TW.sow_exceed) or 0, drow, dcol, NOW())
            if not ok then
                log("ERR", "任务创建失败: " .. tostring(err))
                wstr(LW.TW.detail, "创建失败 " .. tostring(err):sub(1, 20))
                return
            end
            W.task = name
            log("CMD", ("创建任务 %s 地图=%s"):format(name, W.map))
            goto_state(4)

        elseif addr == LW.TW.btn_start then
            if ts == 4 and W.task then
                local ok, err = JOBRUN.start(W.task)
                if ok then
                    goto_state(2)
                else
                    wstr(LW.TW.detail, "启动失败 " .. tostring(err):sub(1, 20))
                end
            elseif ts == 2 then
                -- 作业中开始键: 趟间挂起提示先停止, 否则裸发0x0A续播(QT语义)
                if JOBRUN.active() then
                    local s = JOBRUN.snapshot()
                    if s and s.trip_wait then
                        wstr(LW.TW.detail, "本趟已完成 请先按停止")
                    else
                        ctx.PROTOCOL.send(ctx.PROTOCOL.FNC.CMD_START_BZ)
                    end
                end
            end

        elseif addr == LW.TW.btn_stop then
            if JOBRUN then
                JOBRUN.stop()
                goto_state(3)
            end

        elseif addr == LW.TW.btn_cancel then
            -- 返回配置(不删除已建任务)
            goto_state(1)

        elseif addr == LW.TW.btn_resume then
            -- 续接"最近创建"的未完成任务(2026-10-09修0%bug: 原按列表序
            -- 取第一个未完成, 多任务积累时字典序选中旧的空任务)
            local best, best_ct = nil, ""
            for _, n in ipairs(STORE.task_list()) do
                local t = STORE.task_get(n)
                if t then
                    local d, tot = STORE.task_progress(n)
                    if d < tot and (t.create_time or "") >= best_ct then
                        best, best_ct = n, t.create_time or ""
                    end
                end
            end
            if best then
                local n = best
                local t = STORE.task_get(n)
                if t then
                    local d, tot = STORE.task_progress(n)
                    if d < tot then
                        W.task = n
                        local ok, err = JOBRUN.start(n, { resume = true })
                        if ok then goto_state(2)
                        else wstr(LW.TW.detail, tostring(err):sub(1, 20)) end
                        return
                    end
                end
            end
            wstr(LW.TW.detail, "无可续接任务")
        end
    end

    ------------------------------------------------------------------ 页面表
    local page = {
        id = LW.SCREEN.TASK,
        poll_cmds = {},
        addrs = {
            -- (2026-10-08修复: qzdd_set引用已删键=nil,
            --  ipairs首项截断导致本页按钮地址全未注册 -> 按钮无反应)
            LW.TW.btn_sel, LW.TW.btn_ok,
            LW.TW.btn_start, LW.TW.btn_stop, LW.TW.btn_cancel,
            LW.TW.btn_resume,
        },
    }

    function page:on_enter()
        if JOBRUN.active() then
            local cs = JOBRUN.snapshot()
            if cs then W.task = cs.task end
            w16(LW.TW.tstate, (cs and cs.completed) and 3 or 2)
        else
            goto_state(1)
        end
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == ctx.PROTOCOL.FNC.GET_BZ_STATUS then
            job_view()
        end
    end

    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        on_btn(addr, val)
    end

    -- 作业视图刷新(0x21被jobrun常驻截获, 页面用tick级轻刷新)
    function job_view()
        if not JOBRUN.active() then
            if (r16(LW.TW.tstate) or 0) == 2 then w16(LW.TW.tstate, 3) end
            return
        end
        local s = JOBRUN.snapshot()
        if s then
            if s.completed then w16(LW.TW.tstate, 3) end
            w16(LW.TW.cur_row, s.rows and (s.rows - (s.cur_row or 0)) or 0)
            w16(LW.TW.cur_col, (s.cur_col or 0) + 1)
            w16(LW.TW.done_cnt, s.done or 0)
            w16(LW.TW.total_cnt, s.total or 0)
            w16(LW.TW.pct, s.pct or 0)
        end
    end

    page.on_tick = function()
        job_view()
    end

    return page
end
