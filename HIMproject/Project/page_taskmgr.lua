--[[
page_taskmgr.lua —— 任务管理页(0x1E00~, 画面9) + 新建任务对话框(画面25)
================================================================================
还原 QT FormTask 三栏设计(2026-10-13 M3 任务向导拆页重构):
  左栏: 任务列表(多行字符串+上/下/选中) + 新建(开画面25)/删除/导入/导出/重置
  中栏: 任务详情(名/地图/创建/上次工作/完成率/摘要) + [开始任务]进画面24
  右栏: 地图画布(WidgetBasicGraph ID=1) 小区完成状态 + 视图下拉(排列/编号/密度)
画面25(新建任务对话框, 对齐 QT DialogNewTask): 任务名(全键盘) + 地图选择
  (上/下移) + 确定(关闭+通知nt_btn_ok)/取消(关闭+通知nt_btn_cancel)。
  创建只收名称+地图(路径/方向/起点/图外/打点在实时播种页配置, 与QT一致)。
任务导入导出: U盘 task_<slug>.csv(csv.render_task/parse_task往返); 导出复用
  store.export_task_text(任务定义+全部结果); U盘列目录走fileio回调(同page_map,
  虚拟屏空目录回退读 2:tasks.txt 清单)。
地图绘制: MAPDRAW.cmds(map, task, opts) -> MAPDRAW.render(平台适配); 重绘时机
  = 进入画面/选中变化/块状态变化(jobrun.draw_ver)/作业启停(同draw_ver)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP, STORE, JOBRUN = ctx.APP, ctx.STORE, ctx.JOBRUN
    local MAPDRAW, LOGGER, FILEIO = ctx.MAPDRAW, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16, rstr = ctx.w16, ctx.wstr, ctx.r16, ctx.rstr
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6
    local W = { sel = 0, top = 0, items = {}, ver = -1 }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function trim16(s)
        return string.sub(tostring(s or ""), 1, 16)
    end

    ---------------------------------------------------------------- 列表/详情
    local function refresh()
        W.items = STORE and STORE.task_list() or {}
        if W.sel >= #W.items then W.sel = math.max(0, #W.items - 1) end
        if W.sel < W.top then W.top = W.sel end
        if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
        local lines = {}
        for i = W.top + 1, math.min(#W.items, W.top + LIST_ROWS) do
            local _, _, pct = STORE.task_progress(W.items[i])
            local ln = (i == W.sel + 1 and ">" or " ")
                .. W.items[i] .. " " .. tostring(pct or 0) .. "%"
            lines[#lines + 1] = string.sub(ln, 1, 15)
        end
        wstr(LW.TM.list, table.concat(lines, "\r\n"))
        w16(LW.TM.count, #W.items)
        w16(LW.TM.selidx, W.sel)
    end

    local function cur_task()
        local n = W.items[W.sel + 1]
        return n, n and STORE.tasks[n] or nil
    end

    local function render_detail()
        local n, t = cur_task()
        if not t then
            wstr(LW.TM.tname, "(无任务)")
            wstr(LW.TM.tmap, "")
            wstr(LW.TM.tcreate, "")
            wstr(LW.TM.tlast, "")
            w16(LW.TM.tpct, 0)
            wstr(LW.TM.tremark, "")
            return
        end
        local m = STORE.maps[t.map]
        wstr(LW.TM.tname, trim16(n))
        wstr(LW.TM.tmap, trim16(t.map))
        wstr(LW.TM.tcreate, trim16(t.create_time))
        wstr(LW.TM.tlast, trim16(t.last_work_time))
        local _, _, pct = STORE.task_progress(n)
        w16(LW.TM.tpct, pct or 0)
        local ab = m and m.ab and m.ab.has
        wstr(LW.TM.tremark, m and (string.format("%d排x%d列 AB:%s",
            m.rows or 0, m.cols or 0, ab and "有" or "无")) or "地图缺失")
    end

    ---------------------------------------------------------------- 画布
    local CANVAS_W, CANVAS_H = 322, 360

    local function paint()
        if not MAPDRAW then return end
        local n, t = cur_task()
        if not t then return end
        local m = STORE.maps[t.map]
        if not m then return end
        local v = r16 and r16(LW.TM.view) or 0
        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
        }
        if JOBRUN and JOBRUN.active() then
            local s = JOBRUN.snapshot()
            if s and s.task == n then
                opts.machine = s.machine
                opts.trail = s.trail
            end
        end
        MAPDRAW.render(MAPDRAW.cmds(m, t, opts))
    end

    local function mark_dirty()
        W.ver = -1                             -- 强制on_tick比对失效->redraw
    end

    ---------------------------------------------------------------- U盘导入(fileio回调式, 同page_map)
    local function start_scan()
        if not FILEIO then log("ERR", "fileio未注入"); return end
        if not STORE then log("ERR", "数据层不可用"); return end
        FILEIO.list("2:", function(list, dir)
            if not list then
                log("ERR", "列目录失败 " .. tostring(dir))
                return
            end
            if #list == 0 then                 -- 虚拟屏回退: 清单 2:tasks.txt
                local lines = FILEIO.read_lines
                    and FILEIO.read_lines("2:tasks.txt") or nil
                if lines then
                    for i = 1, #lines do
                        if #lines[i] > 0 then list[#list + 1] = lines[i] end
                    end
                end
            end
            local cnt = 0
            for _, fn in ipairs(list) do
                if type(fn) == "string" and fn:match("^task_.+%.csv$") then
                    local txt = FILEIO.read_all("2:" .. fn)
                    if txt then
                        local t, err = STORE.task_import_text(txt)
                        if t then
                            cnt = cnt + 1
                        else
                            log("ERR", "任务导入失败 " .. fn .. ": "
                                .. tostring(err))
                        end
                    end
                end
            end
            log(cnt > 0 and "INF" or "WRN",
                ("U盘任务导入 %d 个"):format(cnt))
            W.sel, W.top = 0, 0
            refresh()
            render_detail()
            mark_dirty()
        end)
    end

    ---------------------------------------------------------------- 画面9页表
    local page = {
        id = LW.SCREEN.TASKMGR,
        poll_cmds = {},
        addrs = {
            LW.TM.btn_del, LW.TM.btn_imp, LW.TM.btn_exp, LW.TM.btn_reset,
            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_sel, LW.TM.btn_start,
        },
    }

    function page:on_enter()
        W.sel, W.top = 0, 0
        refresh()
        render_detail()
        mark_dirty()
    end

    function page:on_tick()
        local n = W.items[W.sel + 1]
        if n then
            local _, _, pct = STORE.task_progress(n)
            w16(LW.TM.tpct, pct or 0)
        end
        local ver = JOBRUN and JOBRUN.draw_ver or 0
        if ver ~= W.ver then
            W.ver = ver
            if redraw then redraw() end
        end
    end

    function page:on_drawctrl(cid)
        if cid == 1 then paint() end
    end

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if addr == LW.TM.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_sel then
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_del then
            local n = W.items[W.sel + 1]
            if not n then return end
            if JOBRUN and JOBRUN.active() then
                local s = JOBRUN.snapshot()
                if s and s.task == n then
                    log("ERR", "作业中任务不可删除: " .. n)
                    return
                end
            end
            STORE.task_delete(n)
            log("INF", "删除任务 " .. n)
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_imp then
            start_scan()
        elseif addr == LW.TM.btn_exp then
            local n = W.items[W.sel + 1]
            if not n or not FILEIO then return end
            local fname = "task_" .. STORE.slug(n) .. ".csv"
            local ok = FILEIO.write_all("2:" .. fname,
                                         STORE.export_task_text(n))
            log(ok and "INF" or "ERR",
                ok and ("导出任务 " .. n .. " -> " .. fname)
                   or "任务导出失败")
        elseif addr == LW.TM.btn_reset then
            local n = W.items[W.sel + 1]
            if not n then return end
            if JOBRUN and JOBRUN.active() then
                local s = JOBRUN.snapshot()
                if s and s.task == n then
                    log("ERR", "作业中任务不可重置: " .. n)
                    return
                end
            end
            local ok, err = STORE.task_reset(n)
            log(ok and "INF" or "ERR",
                ok and ("重置任务 " .. n) or ("重置失败 " .. tostring(err)))
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_start then
            local n, t = cur_task()
            if not n then log("ERR", "无任务可开始"); return end
            if not STORE.maps[t.map] then
                log("ERR", "任务地图缺失: " .. tostring(t.map))
                return
            end
            APP.preset_sowrt_task = n
            APP.goto_screen(LW.SCREEN.SOWRT)
        end
    end

    ---------------------------------------------------------------- 画面25 新建任务
    local D = { sel = 0, items = {} }

    local function dlg_refresh()
        D.items = STORE and STORE.map_list() or {}
        if D.sel >= #D.items then D.sel = math.max(0, #D.items - 1) end
        wstr(LW.NT.mapsel,
             string.sub(D.items[D.sel + 1] or "(无地图)", 1, 15))
        w16(LW.NT.count, #D.items)
        w16(LW.NT.selidx, D.sel)
    end

    local dlg = {
        id = LW.SCREEN.NEWTASK,
        poll_cmds = {},
        addrs = {
            LW.NT.btn_ok, LW.NT.btn_cancel, LW.NT.btn_up, LW.NT.btn_down,
        },
    }

    function dlg:on_enter()
        D.sel = 0
        dlg_refresh()
        -- 默认名: 任务N(与原画面6口径一致, 用户可改)
        local n = "任务" .. tostring(#(STORE and STORE.task_list() or {}) + 1)
        wstr(LW.NT.name, n)
    end

    function dlg:on_update(addr, val)
        if val ~= 1 then return end
        if addr == LW.NT.btn_up and D.sel > 0 then
            D.sel = D.sel - 1
            dlg_refresh()
        elseif addr == LW.NT.btn_down and D.sel < #D.items - 1 then
            D.sel = D.sel + 1
            dlg_refresh()
        elseif addr == LW.NT.btn_ok then
            local name = ""
            if rstr then
                local ok, s = pcall(rstr, LW.NT.name)
                if ok and type(s) == "string" then name = s end
            end
            if name == "" then
                log("ERR", "任务名不能为空")
                return
            end
            local mapn = D.items[D.sel + 1]
            if not mapn then
                log("ERR", "无地图可选")
                return
            end
            local t, err = STORE.task_create(name, mapn, 0, 1, 0, 0, 0, NOW())
            if not t then
                log("ERR", "创建失败: " .. tostring(err))
                return
            end
            log("INF", "任务已创建 " .. name .. " 地图=" .. mapn)
            -- 关闭弹窗由按钮自身(ButtonUsage=2)完成; 画面9 on_enter 自动刷新
        end
        -- btn_cancel: 仅关闭(按钮行为), 无动作
    end

    if APP and APP.register then
        APP.register(dlg)                     -- 弹窗页单独注册(id=25)
    end

    return page
end
