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
    -- 前置声明: 画面25小节函数被画面9按钮处理器先行引用(定义在后)
    local dlg_init, dlg_refresh, refit

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

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
            -- M48: 只显任务名(原带完成率%, 完成率看详情)
            lines[#lines + 1] = (i == W.sel + 1 and ">" or " ") .. W.items[i]
        end
        wstr(LW.TM.list, table.concat(lines, "\r\n"))
        w16(LW.TM.count, #W.items)
        w16(LW.TM.selidx, W.sel + 1)   -- M50: 1基
        if refit then refit() end               -- M48: 切换即回"适"
    end

    local function cur_task()
        local n = W.items[W.sel + 1]
        return n, n and STORE.tasks[n] or nil
    end

    local function render_detail()
        -- QT风格任务详情单文本(M42): 任务名/地图/创建/最近作业/完成率/几何
        local n, t = cur_task()
        if not t then
            wstr(LW.TM.tdetail, "(无任务)")
            return
        end
        local m = STORE.maps[t.map]
        local _, _, pct = STORE.task_progress(n)
        local ab = m and m.ab and m.ab.has and "有" or "无"
        local geo = m and (string.format("%d排x%d列 AB:%s", m.rows or 0,
                              m.cols or 0, ab)) or "地图缺失"
        wstr(LW.TM.tdetail, table.concat({
            tostring(n),
            "地图:" .. tostring(t.map or ""),
            "创建:" .. tostring(t.create_time or ""),
            "最近作业:" .. tostring(t.last_work_time or ""),
            string.format("完成率:%d%%", pct or 0),
            geo,
        }, "\r\n"))
    end

    ---------------------------------------------------------------- 画布
    local CANVAS_W, CANVAS_H = 465, 400   -- 2026-10-26用户重排(M46, 与画面1同)

    ---------------------------------------------------------------- 视图回适(M48)
    -- 切换任务即回"适"(fit底档整图居中), 与"适"按钮同一目标视图
    refit = function()
        local n = W.items and W.items[W.sel + 1]
        local t = n and STORE.tasks[n]
        local m = t and STORE.maps[t.map]
        W.mv = m and MAPDRAW.auto_view(m, CANVAS_W, CANVAS_H, false) or nil
        w16(LW.TM.canvas, (r16(LW.TM.canvas) or 0) == 1 and 0 or 1)
    end

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
            viewp = W.mv,                   -- M40视口(大排列数; 缩略图M41撤)
        }
        -- 农机标记已删除(2026-10-15用户要求, 不再传machine)
        if ctx.PATHALGO and t.outset then
            local pp = ctx.PATHALGO.create_path(m, t.path_type,
                                              t.positive == 1)
            if pp then
                opts.outset_dir = ctx.PATHALGO.column_direction(
                    pp, t.outset.c)
            end
        end
        MAPDRAW.render(MAPDRAW.cmds(m, t, opts), 335, 30)
    end

    local function mark_dirty()
        W.ver = -1                             -- 强制on_tick比对失效->redraw
    end
    local canvas_dirty_from_dlg = false       -- 弹窗创建后画布置脏(声明
                                            --   在前供dlg闭包引用)

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
                -- 文件名过滤手写(二十一修: 复杂match屏端不可靠)
                if type(fn) == "string"
                   and string.sub(fn, 1, 5) == "task_"
                   and string.sub(fn, #fn - 3) == ".csv" then
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
    ---------------------------------------------------------------- 视口按钮(M40)
    local function view_hit(addr)
        local n, t = cur_task()
        local m = n and STORE.maps[t and t.map]
        if not m then return false end
        if addr == LW.MV.up then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, -0.5)
        elseif addr == LW.MV.down then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, 0.5)
        elseif addr == LW.MV.left then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, -0.5, 0)
        elseif addr == LW.MV.right then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0.5, 0)
        elseif addr == LW.MV.zin then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, 1)
        elseif addr == LW.MV.zout then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, -1)
        elseif addr == LW.MV.fit then
            W.mv = MAPDRAW.fit_view(m, CANVAS_W, CANVAS_H, false)
        else
            return false
        end
        mark_dirty()
        w16(LW.TM.canvas, (r16(LW.TM.canvas) or 0) == 1 and 0 or 1)
        log('INF', '视口 scale=' .. tostring(W.mv and W.mv.scale or '适'))
        return true
    end

    local page = {
        id = LW.SCREEN.TASKMGR,
        poll_cmds = {},
        addrs = {
            LW.TM.btn_new,
            LW.TM.btn_del, LW.TM.btn_imp, LW.TM.btn_exp, LW.TM.btn_reset,
            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_start,
            LW.MV.up, LW.MV.down, LW.MV.left, LW.MV.right,
            LW.MV.zin, LW.MV.zout, LW.MV.fit,
        },
    }

    function page:on_enter()
        W.sel, W.top = 0, 0
        refresh()
        render_detail()
        mark_dirty()
    end

    function page:on_tick()
        if canvas_dirty_from_dlg then
            canvas_dirty_from_dlg = false
            W.ver = -1
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

    page.mv_get = function() return W.mv, W.follow end   -- 视口状态钩子(M41)

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end
        if addr == LW.TM.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_new then
            dlg_init()                    -- 弹窗即将打开: 预填地图/默认名
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
            local okd, errd = STORE.task_delete(n)
            log(okd and "INF" or "ERR",
                okd and ("删除任务 " .. n .. (errd and ("(" .. errd .. ")")
                                                  or "(已验证)"))
                   or ("删除任务失败 " .. n .. ": " .. tostring(errd)))
            log("INF", "删除任务 " .. n)
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_imp then
            start_scan()
        elseif addr == LW.TM.btn_exp then
            local n = W.items[W.sel + 1]
            if not n or not FILEIO then return end
            -- 2026-10-15: 文件名带时间戳(同任务可多次导出不覆盖)
            local nm = STORE.slug_head and STORE.slug_head(n)
                      or STORE.slug(n)
            local fname = "task_" .. nm .. "_"
                .. fname_stamp(NOW()) .. ".csv"
            local ok = FILEIO.write_all("2:" .. fname,
                                         STORE.export_task_text(n))
            if ok and STORE.task_flush then STORE.task_flush(n) end
            if ok and STORE.task_export_clear then
                STORE.task_export_clear(n)      -- 3:结果清档(已并入U盘task)
            end
            log(ok and "INF" or "ERR",
                ok and ("导出任务 " .. n .. " -> " .. fname .. "(3:结果已清)")
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

    dlg_init = function()
        -- 弹窗打开路径: ButtonUsage=1弹窗不触发on_screen_change,
        -- dlg.on_enter不可靠(2026-10-13用户实测地图数0), 由画面9侧
        -- [新建任务]按钮执行通知(tm_btn_new)在此初始化弹窗数据
        D.sel = 0
        dlg_refresh()
        local n = "任务"
            .. tostring(#(STORE and STORE.task_list() or {}) + 1)
        wstr(LW.NT.name, n)
    end

    dlg_refresh = function()
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
        dlg_init()                       -- 弹窗若触发on_enter同样初始化
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
                local ok, s = pcall(rstr, LW.NT.name, 16)
                if ok and type(s) == "string" then name = s end
            end
            if name == "" then
                -- 附地址区hex转储(如再空, 一次定位输入落址/布局)
                local hex = ""
                for i = 0, 7 do
                    local v = r16 and r16(LW.NT.name + i) or -1
                    hex = hex .. string.format("%04X ", v)
                end
                log("ERR", "任务名不能为空 NT.name区: " .. hex)
                wstr(LW.NT.mapsel, "失败:任务名不能为空")
                return
            end
            local mapn = D.items[D.sel + 1]
            if not mapn then
                log("ERR", "无地图可选")
                return
            end
            local mm0 = STORE.maps[mapn]
            local orow = mm0 and (mm0.rows - 1) or 0
            -- M50: 起始黄框默认1排1列(排显示号倒序: 内部末排); 正(QT新任务positive=false)
            local t, err = STORE.task_create(name, mapn, 0, 0, 0,
                                             orow, 0, NOW())
            if not t then
                log("ERR", "创建失败: " .. tostring(err))
                wstr(LW.NT.mapsel, "失败:" .. tostring(err))
                wstr(LW.TM.tdetail, "创建失败: " .. tostring(err))
                return
            end
            log("INF", "任务已创建 " .. name .. " 地图=" .. mapn)
            wstr(LW.NT.mapsel, "已创建 " .. name)
            wstr(LW.TM.tdetail, "已创建 " .. name)
            -- 弹窗关闭不触发画面9 on_enter(同打开), 就地刷新列表/详情
            W.sel = math.max(0, #STORE.task_list() - 1)
            refresh()
            render_detail()
            canvas_dirty_from_dlg = true
        end
        -- btn_cancel: 仅关闭(按钮行为), 无动作
    end

    if APP and APP.register then
        APP.register(dlg)                     -- 弹窗页单独注册(id=25)
    end

    return page
end
