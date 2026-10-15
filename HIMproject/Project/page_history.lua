--[[
page_history.lua —— 历史记录页(0x1900~, 画面7; 2026-10-16十八修重设计)
================================================================================
对齐QT FormHistory样式(裁剪到800x480):
  顶行: 任务总数/选中项 + [导出U盘][删除]
  左栏: 任务列表(名+完成度) + 上移/下移 + 刷新
  右区: 结果表(等宽字体对齐, wqyMicroHeiMono):
        排|列|状|播1-6|肥1-6 逐行 + 表头 + 任务摘要(地图/路径/方向/完成率)
        + 起止时间行(选中行), 上下翻页浏览全部结果。
数据记录组件评估(2026-10-16): 其数据源=资料取样(Flash采样)/配方数据,
官方对动态数据的推荐方案即"字符串表格+Lua拼接"——本页采用后者,
虚拟屏也可联调(资料取样走Flash存储虚拟屏不支持)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP = ctx.APP
    local STORE, LOGGER, FILEIO = ctx.STORE, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 10
    local TBL_ROWS = 13                -- 结果表可见行数(含表头)
    local S = { sel = 0, top = 0, items = {}, ttop = 1 }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function task_names()
        return STORE and STORE.task_list() or {}
    end

    -- 等宽填充: 数字右对齐定宽(n字符), 中文按2宽
    local function pad_n(v, w)
        local s = tostring(v or 0)
        while #s < w do s = " " .. s end
        return s
    end

    local function refresh_list()
        S.items = {}
        for _, n in ipairs(task_names()) do
            local d, tot, pct = STORE.task_progress(n)
            S.items[#S.items + 1] = ("%s %d%%"):format(n, pct or 0)
        end
        local lines = {}
        for i = S.top + 1, math.min(S.top + LIST_ROWS, #S.items) do
            local mark = (i == S.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. S.items[i]
        end
        if #lines == 0 then lines[1] = " 无记录" end
        wstr(LW.HIST.list, table.concat(lines, "\r\n"))
        w16(LW.HIST.count, #S.items)
        w16(LW.HIST.selidx, S.sel)
    end

    local function selected_name()
        local names = task_names()
        return names[S.sel + 1]
    end

    local function render_detail()
        local n = selected_name()
        if not n then
            wstr(LW.HIST.detail, " 无任务")
            return
        end
        local t = STORE.task_get(n)
        local m = t and STORE.maps[t.map]
        local lines = {}
        -- 摘要行
        local dir = (t and t.positive == 1) and "反" or "正"
        lines[#lines + 1] = ("%s %d排x%d列 路%d %s"):format(
            (t and t.map or "?"), m and m.rows or 0, m and m.cols or 0,
            t and t.path_type or 0, dir)
        local d, tot, pct = STORE.task_progress(n)
        lines[#lines + 1] = ("完成 %d/%d %d%% 共%d条"):format(
            d or 0, tot or 0, pct or 0,
            #(STORE.results[n] or {}))
        -- 表头: 排 列 状 播1..6 肥1..6
        local hd = { "排", "列", "状" }
        for i = 1, 6 do hd[#hd + 1] = "播" .. i end
        for i = 1, 6 do hd[#hd + 1] = "肥" .. i end
        lines[#lines + 1] = table.concat(hd, " ")
        -- 结果行(等宽对齐; 排/列显示号口径)
        local res = STORE.results[n] or {}
        local rows = m and m.rows or 5
        local from = S.ttop
        local to = math.min(S.ttop + TBL_ROWS - 1, #res)
        for i = from, to do
            local e = res[i]
            local ss, fs = 0, 0
            for _, v in ipairs(e.seed or {}) do ss = ss + v end
            for _, v in ipairs(e.fert or {}) do fs = fs + v end
            local f = {
                pad_n(rows - (e.r or 0), 2),
                pad_n((e.c or 0) + 1, 2),
                pad_n(e.state or 0, 1),
            }
            for k = 1, 6 do f[#f + 1] = pad_n((e.seed or {})[k], 3) end
            for k = 1, 6 do f[#f + 1] = pad_n((e.fert or {})[k], 3) end
            lines[#lines + 1] = table.concat(f, " ")
        end
        if #res == 0 then
            lines[#lines + 1] = " (暂无结果记录)"
        elseif to < #res then
            lines[#lines + 1] = (" ...还有%d条 [刷新]翻页"):format(#res - to)
        end
        wstr(LW.HIST.detail, table.concat(lines, "\r\n"))
    end

    local function export_usb()
        local n = selected_name()
        if not n then return end
        if not FILEIO then log("ERR", "fileio未注入"); return end
        local txt = STORE.export_task_text(n)
        local nm = STORE.slug_head and STORE.slug_head(n)
                  or (STORE.slug and STORE.slug(n) or n)
        local ts = NOW()
        local stamp = {}
        for i = 1, #ts do
            local c = string.sub(ts, i, i)
            local b = string.byte(c)
            if (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
               or (b >= 97 and b <= 122) then
                stamp[#stamp + 1] = c
            else
                stamp[#stamp + 1] = "_"
            end
        end
        local fname = "task_" .. nm .. "_" .. table.concat(stamp) .. ".csv"
        local ok, err = FILEIO.write_all("2:" .. fname, txt)
        if ok and STORE.task_flush then STORE.task_flush(n) end
        if ok and STORE.task_export_clear then
            STORE.task_export_clear(n)
        end
        log(ok and "INF" or "ERR",
            ok and ("导出任务 " .. n .. " -> " .. fname .. "(3:结果已清)")
               or ("导出失败 " .. tostring(err)))
    end

    local page = {
        id = LW.SCREEN.HISTORY,
        on_enter = function()
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
            S.ttop = 1
            refresh_list()
            render_detail()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {
            LW.HIST.btn_up, LW.HIST.btn_down, LW.HIST.btn_view,
            LW.HIST.btn_exp, LW.HIST.btn_del,
        },
        on_update = function(self, addr, val)
            if val ~= 1 then return end
            if addr == LW.HIST.btn_up then
                if S.sel > 0 then
                    S.sel = S.sel - 1
                    if S.sel < S.top then S.top = S.sel end
                    S.ttop = 1
                    refresh_list(); render_detail()
                end
            elseif addr == LW.HIST.btn_down then
                if S.sel < #S.items - 1 then
                    S.sel = S.sel + 1
                    if S.sel >= S.top + LIST_ROWS then
                        S.top = S.sel - LIST_ROWS + 1
                    end
                    S.ttop = 1
                    refresh_list(); render_detail()
                end
            elseif addr == LW.HIST.btn_view then
                -- 刷新=结果表翻页(到底回卷)
                local n = selected_name()
                local res = n and (STORE.results[n] or {}) or {}
                S.ttop = S.ttop + TBL_ROWS - 1
                if S.ttop > #res then S.ttop = 1 end
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
