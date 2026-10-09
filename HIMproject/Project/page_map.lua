--[[
page_map.lua -- 地图导入页(画面9, 2026-09-24新增)
================================================================================
仿QT地图管理页的屏端子集(地图创建/编辑由PC导出工具负责):
  地图列表(选中) + 详情摘要 + U盘扫描导入(map_*.csv, 文件名须ASCII, 显示名取#MAP)
  + 删除地图 (AB线功能已于2026-10-09移除: 纯行程开关模式)
U盘导入逻辑自原任务向导页迁移(2026-09-24向导删除)。
LW: LW.MAP (0x1C00区)。
依赖注入: creator(ctx) 同现有页面模式。
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, FILEIO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16

    local LIST_ROWS = 6
    local W = { sel = 0, top = 0, items = {} }

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
        wstr(LW.MAP.list, table.concat(lines, "\r\n"))
        w16(LW.MAP.count, #W.items)
        w16(LW.MAP.selidx, W.sel)
        w16(LW.MAP.listtop, W.top)
    end

    local function selected_name()
        local names = STORE and STORE.map_list() or {}
        return names[W.sel + 1]
    end

    local function refresh()
        W.items = {}
        if STORE then
            for _, n in ipairs(STORE.map_list()) do
                W.items[#W.items + 1] = n .. " " .. STORE.map_spec(n)
            end
        end
        if #W.items == 0 then W.items[1] = "(无地图, 请扫描U盘导入)" end
        W.sel, W.top = 0, 0
        render_list()
        wstr(LW.MAP.detail, "")
    end

    local function show_detail()
        local n = selected_name()
        if not (n and STORE) then return end
        local m = STORE.map_get(n)
        if not m then return end
        wstr(LW.MAP.detail, ("%s %d排x%d列"):format(n, m.rows, m.cols))
    end

    ------------------------------------------------------------------ U盘导入
    -- list_dir 固件双时序: 异步经 on_list_dir 路由 / 同步返回 table(见 fileio.lua)
    local tick_n = 0
    local scan_deadline = nil
    local SCAN_TICKS = math.max(5, math.ceil(3000 / (ctx.poll_ms or 200)))

    local function usb_import()
        if not FILEIO then return end
        if not STORE then wstr(LW.MAP.detail, "数据层不可用"); return end
        if scan_deadline then wstr(LW.MAP.detail, "扫描中,请稍候"); return end
        wstr(LW.MAP.detail, "扫描U盘中...")
        scan_deadline = tick_n + SCAN_TICKS
        local ok, err = FILEIO.list("2:", function(list, dir)
            scan_deadline = nil
            if not list then
                log("ERR", "列目录失败 " .. tostring(dir))
                wstr(LW.MAP.detail, "扫描失败(未插U盘?)")
                return
            end
            if #list == 0 then                   -- 虚拟屏回退: 约定清单 2:maps.txt
                local lines = FILEIO.read_lines("2:maps.txt")
                if lines then
                    for i = 1, #lines do
                        if #lines[i] > 0 then list[#list + 1] = lines[i] end
                    end
                end
            end
            local imported, msgs = 0, {}
            for _, fnm in ipairs(list) do
                if type(fnm) == "string" and fnm:match("^map_.+%.csv$") then
                    local name = fnm:sub(5, -5)
                    local ok2, w2 = STORE.map_import_file("2:" .. fnm, name)
                    if ok2 then imported = imported + 1 else msgs[#msgs + 1] = w2 end
                end
            end
            log(imported > 0 and "INF" or "WRN",
                ("U盘导入 %d 张地图"):format(imported))
            if #msgs > 0 then log("ERR", msgs[1]) end
            wstr(LW.MAP.detail,
                imported > 0 and ("导入%d张地图"):format(imported)
                or "无地图文件(或未插U盘)")
            refresh()
        end)
        if not ok then
            scan_deadline = nil
            wstr(LW.MAP.detail, "U盘不可用")
            log("ERR", "U盘未插入或不可读")
        end
    end

    ------------------------------------------------------------------ 按钮
    local function on_btn(addr, val)
        if val ~= 1 then return end
        if addr == LW.MAP.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
        elseif addr == LW.MAP.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()
        elseif addr == LW.MAP.btn_sel then
            show_detail()
        elseif addr == LW.MAP.btn_usb then
            usb_import()
        elseif addr == LW.MAP.btn_del then
            local n = selected_name()
            if n and STORE then
                STORE.map_delete(n)
                log("CMD", "删除地图 " .. n)
                wstr(LW.MAP.detail, "已删除 " .. n)
                refresh()
            end
        end
    end

    local page = {
        id = LW.SCREEN.MAP,
        poll_cmds = {},
        addrs = {
            LW.MAP.btn_up, LW.MAP.btn_down, LW.MAP.btn_sel, LW.MAP.btn_del,
            LW.MAP.btn_usb,
        },
    }

    function page:on_enter()
        refresh()
    end

    function page:on_leave() end

    function page:on_frame() end

    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        on_btn(addr, val)
    end

    page.on_tick = function()
        tick_n = tick_n + 1
        if scan_deadline and tick_n > scan_deadline then
            scan_deadline = nil
            wstr(LW.MAP.detail, "扫描无响应(未插U盘?)")
            log("WRN", "list_dir 回调超时(异步无果)")
        end
    end

    return page
end
