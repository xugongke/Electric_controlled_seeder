--[[
page_sowrt.lua —— 实时播种页(0x1F00~, 画面24; 2026-10-13 M3任务向导拆页重构)
================================================================================
还原 QT DialogRealtimeTask 左右两栏(800×480全屏, 拆页重构用户决策):
  左栏: 调试信息(a_log) / 排列·列行程(a_offlen/a_voff, cm缩放0.01显示m) /
        速度(rt_speed mm/s缩放0.001显示m/s) / 行进方向开关(rt_positive) /
        路线6态图(rt_path_type) / 清种打点三态(rt_gapdot) / 图外播种
        (rt_sow_exceed, 无AB线强制0) / AB线查看·保存(功能按钮开画面22, 复用
        jobrun ABP影子页)·清除(rt_abclr) / 当前+最近完成 漏种漏肥各6路
        (rt_cur_zh/fe, rt_last_zh/fe, jobrun 0x21常驻写入)
  右栏: 地图画布(WidgetBasicGraph ID=1, 544×360: 块状态色+轨迹+农机标记) /
        视图下拉(rt_view) / 更改起点(开关+排/列输入+应用, 仅记录/标记,
        与原画面6口径一致——路径几何不变) / 开始·停止 / 运行状态灯
        (a_runstate) / 完成率·进度(rt_pct/done/tot) / 任务结果(跳画面7并
        预选APP.preset_hist_task) / 导出U盘
开始: 收集左栏参数写入任务(path_type/positive/sow_exceed/outset)后
  JOBRUN.start(task, {gap=rt_gapdot直读}); 停止: JOBRUN.stop()(含无AB线
  停止保存建议弹窗, 复用既有机制)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP, STORE, JOBRUN = ctx.APP, ctx.STORE, ctx.JOBRUN
    local MAPDRAW, LOGGER, FILEIO = ctx.MAPDRAW, ctx.LOGGER, ctx.FILEIO
    local PROTOCOL = ctx.PROTOCOL
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local W = { task = nil, ver = -1, qzdd = -1,
                last_pt = -1, last_pos = -1,
                mv = nil, follow = true }   -- M40视口状态/作业跟随

    local function fname_stamp(s)
        -- "2026-10-15 12:00:00" -> "2026_10_15_12_00_00"(屏端无gsub手写)
        local out = {}
        for i = 1, #s do
            local c = string.sub(s, i, i)
            local b = string.byte(c)
            if (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
               or (b >= 97 and b <= 122) then
                out[#out + 1] = c
            else
                out[#out + 1] = "_"
            end
        end
        return table.concat(out)
    end


    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function task_map(t)
        return t and STORE.maps[t.map] or nil
    end

    ---------------------------------------------------------------- 参数收发
    local function load_params()
        -- 任务/配置参数 -> 左栏控件(进入画面/新建后)
        local t = W.task and STORE.tasks[W.task] or nil
        if not t then return end
        w16(LW.RT.path_type, t.path_type or 0)
        w16(LW.RT.positive, t.positive or 0)
        -- 图外播种恒默认关(2026-10-15用户要求: 此前还原任务存值,
        -- 上次开过则本次进来是1; QT每次开窗checkbox默认不勾)
        w16(LW.RT.sow_exceed, 0)
        -- 清种时打点(bool, 会话内保持; 不再装载过道打点config 2026-10-14)
        w16(LW.RT.gapdot, W.qzdd == 1 and 1 or 0)
        w16(LW.RT.sp_enable, 0)
        local m2 = task_map(t)
        if m2 and t.outset then
            -- 0基->显示号(排显示=总排-内部行, 与原画面6一致)
            w16(LW.RT.sp_row, math.max(1, (m2.rows or 1) - (t.outset.r or 0)))
            w16(LW.RT.sp_col, (t.outset.c or 0) + 1)
        else
            w16(LW.RT.sp_row, 1)
            w16(LW.RT.sp_col, 1)
        end
    end

    local function harvest(outset_only)
        -- 左栏控件 -> 任务字段(开始前/应用起点时)
        local t = W.task and STORE.tasks[W.task]
        if not t then return false end
        local m = task_map(t)
        if not outset_only then
            t.path_type = r16(LW.RT.path_type) or 0
            if t.path_type < 0 or t.path_type > 5 then t.path_type = 0 end
            t.positive = (r16(LW.RT.positive) or 0) ~= 0 and 1 or 0
            local has_ab = m and m.ab and m.ab.has
            t.sow_exceed = (r16(LW.RT.sow_exceed) == 1 and has_ab) and 1 or 0
            if r16(LW.RT.sow_exceed) == 1 and not has_ab then
                w16(LW.RT.sow_exceed, 0)      -- 无AB线: 图外播种强制关
                log("WRN", "无AB线, 图外播种不可用已自动关闭")
            end
        end
        if r16(LW.RT.sp_enable) == 1 then
            local r = (r16(LW.RT.sp_row) or 1) - 1
            local c = (r16(LW.RT.sp_col) or 1) - 1
            local rows = m and m.rows or 1
            -- 显示号->0基: 排内部行 = 总排-显示排
            t.outset = { r = math.min(math.max(rows - 1 - r, 0), rows - 1),
                         c = math.min(math.max(c, 0),
                                      (m and m.cols or 1) - 1) }
            w16(LW.RT.sp_enable, 0)          -- 应用后复位开关
        end
        STORE.task_save(W.task)
        return true
    end

    ---------------------------------------------------------------- 画布/刷新
    local CANVAS_W, CANVAS_H = 550, 397   -- 2026-10-26用户重排(M46)

    local function paint()
        if not MAPDRAW then return end
        local t = W.task and STORE.tasks[W.task] or nil
        if not t then return end
        local m = task_map(t)
        if not m then return end
        local v = r16(LW.RT.view) or 0
        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
            viewp = W.mv,                   -- M40视口(大排列数; 缩略图M41撤)
        }
        -- 农机标记已删除(2026-10-15用户要求, 不再传machine)
        -- 起点V方向: 起点列的行进方向(路径首到达该列的节点positive)
        if ctx.PATHALGO and t.outset then
            local pp = ctx.PATHALGO.create_path(m, t.path_type,
                                              t.positive == 1)
            if pp then
                opts.outset_dir = ctx.PATHALGO.column_direction(
                    pp, t.outset.c)
            end
        end
        MAPDRAW.render(MAPDRAW.cmds(m, t, opts), 250, 30)
    end

    local function pick_task()
        -- 预选(任务管理页[开始任务]) > 作业中任务 > 最近未完成 > 最新任务
        if APP.preset_sowrt_task then
            local n = APP.preset_sowrt_task
            APP.preset_sowrt_task = nil
            if STORE.tasks[n] then return n end
        end
        if JOBRUN and JOBRUN.active() then
            local s = JOBRUN.snapshot()
            if s and STORE.tasks[s.task] then return s.task end
        end
        local lst = STORE.task_list()
        for i = #lst, 1, -1 do
            local _, tot, pct = STORE.task_progress(lst[i])
            if tot == 0 or pct < 100 then return lst[i] end
        end
        return lst[#lst]
    end

    -- 方向/路线切换联动(2026-10-16十六修, 对齐QT :150-183方向单选触发
    -- 当前路线handler + :806-821 clearOutset+createPath+outset=path[0]):
    -- 重建路径, 播种起点重置为新路径首节点(手动改的起点随之失效)
    local function relink_outset(pt, pos)
        local t = W.task and STORE.tasks[W.task]
        if not t then return end
        local m = task_map(t)
        if not m then return end
        t.path_type = pt
        t.positive = pos
        if JOBRUN and JOBRUN.reset_path then JOBRUN.reset_path() end
        local path = ctx.PATHALGO and ctx.PATHALGO.create_path
                    and ctx.PATHALGO.create_path(m, pt, pos == 1)
        if path and path[1] then
            t.outset = { r = path[1].row, c = path[1].column }
        end
        STORE.task_save(W.task)
        if m and t.outset then
            w16(LW.RT.sp_row, math.max(1, m.rows - t.outset.r))
            w16(LW.RT.sp_col, t.outset.c + 1)
        end
        w16(LW.RT.path_type, pt)
        w16(LW.RT.positive, pos)
        W.ver = -1
        log("INF", ("路线/方向联动: 起点=%d,%d"):format(
            t.outset and (m.rows - t.outset.r) or 0,
            t.outset and (t.outset.c + 1) or 0))
    end

    ---------------------------------------------------------------- 视口按钮(M40)
    -- 跟随: 视口居中当前作业块(jobrun.snapshot.cur_row/cur_col)
    local function follow_now(m)
        local s = JOBRUN and JOBRUN.snapshot and JOBRUN.snapshot()
        if s and s.cur_row and s.cur_col then
            W.mv = MAPDRAW.center_on(W.mv, m, CANVAS_W, CANVAS_H, false,
                                     s.cur_row, s.cur_col)
        end
    end

    -- 平移/适配/缩小退出跟随(地图App惯例), 放大保持跟随(就地缩放)
    local function view_hit(addr)
        local t = W.task and STORE.tasks[W.task] or nil
        local m = t and task_map(t)
        if not m then return false end
        if addr == LW.MV.up then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, -0.5)
        elseif addr == LW.MV.down then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, 0.5)
        elseif addr == LW.MV.left then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, -0.5, 0)
        elseif addr == LW.MV.right then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0.5, 0)
        elseif addr == LW.MV.zin then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, 1)
        elseif addr == LW.MV.zout then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, -1)
        elseif addr == LW.MV.fit then
            W.follow = false
            W.mv = MAPDRAW.fit_view(m, CANVAS_W, CANVAS_H, false)
        else
            return false
        end
        -- M41: 写画布脏标触发重绘(redraw内建不可依赖)
        w16(LW.RT.canvas, (r16(LW.RT.canvas) or 0) == 1 and 0 or 1)
        if redraw then redraw() end
        log('INF', '视口 scale=' .. tostring(W.mv and W.mv.scale or '适'))
        return true
    end

    local page = {
        id = LW.SCREEN.SOWRT,
        poll_cmds = { PROTOCOL and PROTOCOL.FNC.GET_BZ_STATUS or nil },
        addrs = {
            LW.RT.btn_start, LW.RT.btn_stop, LW.RT.btn_result,
            LW.RT.btn_exp, LW.RT.btn_abclr, LW.RT.btn_spply,
            LW.MV.up, LW.MV.down, LW.MV.left, LW.MV.right,
            LW.MV.zin, LW.MV.zout, LW.MV.fit,
        },
    }

    function page:on_enter()
        W.task = pick_task()
        if W.task then
            wstr(LW.RT.tname, string.sub(W.task, 1, 15))
            load_params()
            local m = task_map(STORE.tasks[W.task])
            if JOBRUN then JOBRUN.ab_hint_map = m and m.name or nil end
        else
            wstr(LW.RT.tname, "(无任务)")
        end
        W.last_pt = r16(LW.RT.path_type) or 0
        W.last_pos = (r16(LW.RT.positive) == 1) and 1 or 0
        do                                  -- 进页复位适配视图(M47统一梯)
            local t0 = W.task and STORE.tasks[W.task] or nil
            local m0 = t0 and task_map(t0)
            W.mv = m0 and MAPDRAW.fit_view(m0, CANVAS_W, CANVAS_H, false)
                   or nil
        end
        W.follow = true                     -- 进页默认跟随作业
        W.ver = -1
    end

    function page:on_tick()
        -- 方向/路线切换联动起点(仅空闲; 作业中控件已被权限禁触,
        -- 双保险仍判active)
        local pt = r16(LW.RT.path_type) or 0
        local pos = (r16(LW.RT.positive) == 1) and 1 or 0
        if W.last_pt >= 0 and (pt ~= W.last_pt or pos ~= W.last_pos)
           and not (JOBRUN and JOBRUN.active()) then
            relink_outset(pt, pos)
        end
        W.last_pt, W.last_pos = pt, pos
        -- 清种时打点开关变更即下发(0x29, bool)
        local qz = (r16(LW.RT.gapdot) == 1) and 1 or 0
        if qz ~= W.qzdd then
            W.qzdd = qz
            PROTOCOL.send(PROTOCOL.FNC.QZDD_ENABLE, string.char(qz))
        end
        if not W.task then return end
        local d, tot, pct = STORE.task_progress(W.task)
        w16(LW.RT.pct, pct or 0)
        w16(LW.RT.done, d or 0)
        w16(LW.RT.tot, tot or 0)
        local ver = JOBRUN and JOBRUN.draw_ver or 0
        if ver ~= W.ver then
            W.ver = ver
            if W.follow then
                local t = W.task and STORE.tasks[W.task] or nil
                local m = t and task_map(t)
                if m then follow_now(m) end
            end
            w16(LW.RT.canvas, (r16(LW.RT.canvas) or 0) == 1 and 0 or 1)
            if redraw then redraw() end
        end
    end

    function page:on_drawctrl(cid)
        if cid == 1 then paint() end
    end

    local function on_start()
        -- 开始按钮(2026-10-15回撤合并: 恢复独立开始/停止, 双按钮均带
        -- 控件权限变灰——开始仅空闲可用/停止仅作业中可用)
        if JOBRUN and JOBRUN.active() then
            log("WRN", "作业进行中, 请先停止")
            return
        end
        if not W.task then log("ERR", "无任务"); return end
        if not harvest(false) then return end
        -- 清种时打点(0x29): 独立命令随开始一并重发(对齐QT :499-501
        -- setDotWhenClearSeed为bool独立下发; 过道打点0x31回归config)
        local qz = (r16(LW.RT.gapdot) == 1) and 1 or 0
        PROTOCOL.send(PROTOCOL.FNC.QZDD_ENABLE, string.char(qz))
        W.qzdd = qz
        local ok, err = JOBRUN.start(W.task)
        log(ok and "INF" or "ERR",
            ok and ("作业启动 " .. W.task)
               or ("启动失败: " .. tostring(err)))
        if ok then
            W.follow = true                     -- M51: 开始任务自动跟随
        end
    end

    page.mv_get = function() return W.mv, W.follow end   -- 视口状态钩子(M41)

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end
        if addr == LW.RT.btn_start then
            on_start()
        elseif addr == LW.RT.btn_stop then
            if JOBRUN then JOBRUN.stop() end
        elseif addr == LW.RT.btn_abclr then
            local t = W.task and STORE.tasks[W.task] or nil
            local m = task_map(t)
            if m then
                local ok, err = JOBRUN.ab_clear_map(m.name)
                log(ok and "INF" or "ERR",
                    ok and ("清除AB线 " .. m.name)
                       or ("清除失败: " .. tostring(err)))
            end
        elseif addr == LW.RT.btn_spply then
            if harvest(true) then
                log("INF", "起点已更新(记录/标记; 路径几何不变)")
                W.ver = -1
                if redraw then redraw() end
            end
        elseif addr == LW.RT.btn_result then
            APP.preset_hist_task = W.task
            APP.goto_screen(LW.SCREEN.HISTORY)
        elseif addr == LW.RT.btn_exp then
            if W.task and FILEIO then
                -- 2026-10-15: 导出即任务文件task_*.csv(信息+状态+是否播种+
                -- 结果一体, 只含实际存在的排列表行, 不复刻QT的脏输出)
                -- 2026-10-15: 文件名带时间戳(同任务可多次导出不覆盖)
                local nm2 = STORE.slug_head and STORE.slug_head(W.task)
                          or (STORE.slug and STORE.slug(W.task) or W.task)
                local fname = "task_" .. nm2 .. "_"
                    .. fname_stamp(NOW()) .. ".csv"
                local ok = FILEIO.write_all("2:" .. fname,
                                             STORE.export_task_text(W.task))
                if ok and STORE.task_flush then STORE.task_flush(W.task) end
                if ok and STORE.task_export_clear then
                    STORE.task_export_clear(W.task)  -- 3:结果清档(已并入U盘task)
                end
                log(ok and "INF" or "ERR",
                    ok and ("导出任务 " .. W.task .. " -> " .. fname .. "(3:结果已清)")
                       or "导出失败")
            end
        end
    end

    return page
end
