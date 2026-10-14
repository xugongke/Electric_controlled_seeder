--[[
page_history.lua —— 历史记录页(0x1900~, 画面7, B档)
================================================================================
任务列表(多行字符串+上下移) → 查看明细(各排结果) / 导出U盘 / 删除。
明细: 任务规格 + 已完成排的结果摘要(起止时间/穴肥合计)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP = ctx.APP
    local STORE, LOGGER, FILEIO = ctx.STORE, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6
    local S = { sel = 0, top = 0, items = {} }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function task_names()
        return STORE and STORE.task_list() or {}   -- B档数据层降级容错
    end

    local function refresh_list()
        S.items = {}
        for _, n in ipairs(task_names()) do
            local d, tot, pct = STORE.task_progress(n)
            S.items[#S.items + 1] = ("%s %d/%d"):format(n, d, tot)
        end
        local lines = {}
        for i = S.top + 1, math.min(S.top + LIST_ROWS, #S.items) do
            local mark = (i == S.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. S.items[i]
        end
        if #lines == 0 then lines[1] = " 无记录" end
        wstr(LW.HIST.list, table.concat(lines, "\r\n"))
        w16(LW.HIST.count, #S.items)
        -- 2026-09-10 修: 回写选中项/列表首项(此前只写列表文本, 画面数值控件恒0)
        w16(LW.HIST.selidx, S.sel)
        w16(LW.HIST.listtop, S.top)
    end

    local function selected_name()
        local names = task_names()
        return names[S.sel + 1]
    end

    local function render_detail()
        local n = selected_name()
        if not n then wstr(LW.HIST.detail, " "); return end
        local t = STORE.task_get(n)
        local lines = { ("%s 地图=%s"):format(n, t and t.map or "?") }
        if t then
            lines[#lines + 1] = ("路径%d 方向%d 起点%d,%d"):format(
                t.path_type or 0, t.positive or 0,
                (t.outset and t.outset.r or 0) + 1,
                (t.outset and t.outset.c or 0) + 1)
            -- 结果摘要: 最近几条(旧->新取尾部)
            local res = STORE.results[n] or {}
            local from = math.max(1, #res - 5)
            for i = from, #res do
                local e = res[i]
                local ss, fs = 0, 0
                for _, v in ipairs(e.seed or {}) do ss = ss + v end
                for _, v in ipairs(e.fert or {}) do fs = fs + v end
                lines[#lines + 1] = ("排%s 穴%d 肥%d %s"):format(
                    tostring(e.row), ss, fs,
                    (e.end_t or ""):sub(1, 10))
            end
            local d, tot, pct = STORE.task_progress(n)
            lines[#lines + 1] = ("完成 %d/%d %d%%"):format(d, tot, pct)
        end
        wstr(LW.HIST.detail, table.concat(lines, "\r\n"))
    end

    local function export_usb()
        local n = selected_name()
        if not n then return end
        if not FILEIO then log("ERR", "fileio未注入"); return end
        local txt = STORE.export_task_text(n)
        -- U盘文件名必须纯ASCII(屏端文件系统限制, 真机实测), 用 store.slug;
        -- 导出的CSV内容里 #TASK 行仍是中文显示名
        local fname = "result_" .. (STORE.slug and STORE.slug(n) or n) .. ".csv"
        local ok, err = FILEIO.write_all("2:" .. fname, txt)
        log(ok and "INF" or "ERR",
            ok and ("导出任务 " .. n .. " -> " .. fname)
               or ("导出失败 " .. tostring(err)))
    end

    local page = {
        id = LW.SCREEN.HISTORY,                   -- 画面号(数字, APP.set_screen 路由)
        on_enter = function()
            -- 外部预选(2026-10-13 M3): 实时播种页[任务结果]跳转携带任务名
            if APP and APP.preset_hist_task then
                local want = APP.preset_hist_task
                APP.preset_hist_task = nil
                local lst = task_names()
                for i, n in ipairs(lst) do
                    if n == want and i - 1 ~= S.sel then
                        S.sel = i - 1
                        S.top = math.max(0, i - 1 - 2)
                    end
                end
            end
            refresh_list()
            render_detail()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {                                 -- 按钮地址声明(APP.by_addr 路由必需)
            LW.HIST.btn_up, LW.HIST.btn_down, LW.HIST.btn_view,
            LW.HIST.btn_exp, LW.HIST.btn_del,
        },
        on_update = function(self, addr, val)
            if val ~= 1 then return end
            if addr == LW.HIST.btn_up and S.sel > 0 then
                S.sel = S.sel - 1
                if S.sel < S.top then S.top = S.sel end
                refresh_list(); render_detail()
            elseif addr == LW.HIST.btn_down and S.sel < #S.items - 1 then
                S.sel = S.sel + 1
                if S.sel >= S.top + LIST_ROWS then S.top = S.sel - LIST_ROWS + 1 end
                refresh_list(); render_detail()
            elseif addr == LW.HIST.btn_view then
                render_detail()
            elseif addr == LW.HIST.btn_exp then
                export_usb()
            elseif addr == LW.HIST.btn_del then
                local n = selected_name()
                if n then
                    local okd, errd = STORE.task_delete(n)
                    log(okd and "CMD" or "ERR",
                        "删除任务 " .. n
                        .. (okd and "(已验证)"
                            or (": " .. tostring(errd))))
                    if S.sel > 0 then S.sel = S.sel - 1 end
                    refresh_list(); render_detail()
                end
            end
        end,
    }
    return page
end
