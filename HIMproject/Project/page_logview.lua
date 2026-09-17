--[[
page_logview.lua —— 日志查看页(0x1A00~, 画面8, B档)
================================================================================
日志窗口多行显示(尾部对齐=最新在下), 上/下翻页, 跳最新, 清空, 导出U盘。
--]]

return function(ctx)
    local LW = ctx.LW
    local LOGGER, FILEIO = ctx.LOGGER, ctx.FILEIO
    local w16, wstr = ctx.w16, ctx.wstr

    local VIEW_ROWS = 8
    local top = 1                     -- 窗口首条(1基, 旧->新)

    local function refresh()
        local cnt = LOGGER and LOGGER.count() or 0
        if cnt == 0 then
            top = 1
            wstr(LW.LOGV.view, " 无日志")
        else
            if top > cnt then top = math.max(1, cnt - VIEW_ROWS + 1) end
            if top < 1 then top = 1 end
            local lines = LOGGER.view(top, VIEW_ROWS)
            wstr(LW.LOGV.view, table.concat(lines, "\r\n"))
        end
        w16(LW.LOGV.count, cnt)
    end

    local page = {
        id = LW.SCREEN.LOGVIEW,                   -- 画面号(数字, APP.set_screen 路由)
        on_enter = function()
            -- 进入时跳到最新(尾部)
            local cnt = LOGGER and LOGGER.count() or 0
            top = math.max(1, cnt - VIEW_ROWS + 1)
            refresh()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {                                 -- 按钮地址声明(APP.by_addr 路由必需)
            LW.LOGV.btn_up, LW.LOGV.btn_down, LW.LOGV.btn_top,
            LW.LOGV.btn_clear, LW.LOGV.btn_exp,
        },
        on_update = function(self, addr, val)
            if val ~= 1 then return end
            local cnt = LOGGER and LOGGER.count() or 0
            if addr == LW.LOGV.btn_up then
                top = math.max(1, top - VIEW_ROWS)
                refresh()
            elseif addr == LW.LOGV.btn_down then
                top = math.min(math.max(1, cnt - VIEW_ROWS + 1), top + VIEW_ROWS)
                refresh()
            elseif addr == LW.LOGV.btn_top then
                top = math.max(1, cnt - VIEW_ROWS + 1)
                refresh()
            elseif addr == LW.LOGV.btn_clear then
                if LOGGER then
                    LOGGER.clear()
                    LOGGER.log("CMD", "日志清空")
                end
                top = 1
                refresh()
            elseif addr == LW.LOGV.btn_exp then
                if FILEIO and LOGGER then
                    local ok, err = FILEIO.copy("3:log.txt", "2:log_export.txt")
                    LOGGER.log(ok and "INF" or "ERR",
                        ok and "日志导出" or ("导出失败 " .. tostring(err)))
                    refresh()
                end
            end
        end,
    }

    return page
end
