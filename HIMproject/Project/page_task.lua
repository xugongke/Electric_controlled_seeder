--[[
page_task.lua —— 任务向导页(0x1800~, 画面6, B档)
================================================================================
4步状态机(LW.TW.step):
  1 选地图(列表+U盘导入) → 2 选AB线 → 3 路径方式/方向/图外播种 → 4 起始小区+创建
作业视图(tstate=2): jobrun.snapshot 写 LW 进度区。
列表交互: 多行字符串(选中行">"前缀) + 上/下移按钮; btn_sel 选中进入下一步。
依赖注入: creator(ctx) 同现有页面模式; ctx 增 STORE/JOBRUN/LOGGER/FILEIO。
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, FILEIO, PATHALGO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.FILEIO, ctx.PATHALGO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6                  -- 列表窗口行数(与 LW.TW.list 控件规划一致)

    -- 向导现场(非持久, 离开页面丢弃; 已创建任务落 store)
    local W = { map = nil, use_ab = false, sel = 0, top = 0, items = {} }

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
        -- 2026-09-10 修: 回写选中项/列表首项(此前只写列表文本, 画面数值控件恒0)
        w16(LW.TW.selidx, W.sel)
        w16(LW.TW.listtop, W.top)
    end

    local function step1_items()
        W.items = { "扫描U盘导入地图" }
        if not STORE then                       -- B档数据层降级(如虚拟屏无文件API)
            W.items[#W.items + 1] = "(数据层不可用)"
            return
        end
        for _, n in ipairs(STORE.map_list()) do
            W.items[#W.items + 1] = n .. " " .. STORE.map_spec(n)
        end
    end

    local function step2_items()
        local m = STORE.map_get(W.map)
        W.items = { "无AB线(地头行程开关设A点后开播)" }
        if m and m.ab then
            W.items[#W.items + 1] = ("使用地图AB线 %s"):format(m.ab.name or "")
        end
    end

    -- AB线操作目标地图: 作业中=当前任务地图, 向导中=已选地图
    local function ab_target_map()
        if JOBRUN and JOBRUN.active() then
            local s = JOBRUN.snapshot()
            if s then return s.map end
        end
        return W.map
    end

    local function on_ab_btn(addr)
        local map_name = ab_target_map()
        if not map_name then
            wstr(LW.TW.detail, "请先选择地图")
            return
        end
        if addr == LW.TW.ab_view then
            JOBRUN.ab_collect()                      -- 0x23 采集回显(LW.AB区)
            wstr(LW.TW.detail, "AB线采集中...")
        elseif addr == LW.TW.ab_import then
            if not JOBRUN.ab_cache then
                JOBRUN.ab_cache = JOBRUN.ab_rw_load()   -- RW缓存 -> 绑定地图
            end
            local ok, err = JOBRUN.ab_bind_map(map_name)
            wstr(LW.TW.detail, ok and ("AB线已绑定 " .. map_name)
                                   or ("绑定失败 " .. tostring(err):sub(1, 12)))
            if ok and r16(LW.TW.step) == 2 then
                W.sel, W.top = 0, 0
                step2_items()
                render_list()
            end
        elseif addr == LW.TW.ab_clear then
            local ok, err = JOBRUN.ab_clear_map(map_name)
            wstr(LW.TW.detail, ok and ("AB线已清除 " .. map_name)
                                   or ("清除失败 " .. tostring(err):sub(1, 12)))
            if ok and r16(LW.TW.step) == 2 then
                W.sel, W.top = 0, 0
                step2_items()
                render_list()
            end
        elseif addr == LW.TW.ab_save then
            local ok, err = JOBRUN.ab_rw_save()
            wstr(LW.TW.detail, ok and "AB线已保存RW(掉电保持)"
                                   or ("保存失败 " .. tostring(err):sub(1, 12)))
        end
    end

    local function step4_default_start()
        -- 默认起始小区 = 路径算法首节点(显示排=rows-row, 显示列=column+1)
        local m = STORE.map_get(W.map)
        if not (m and PATHALGO) then return end
        local path = PATHALGO.create_path(m, r16(LW.TW.path_type) or 0,
                                          r16(LW.TW.positive) == 1)
        if path and path[1] then
            w16(LW.TW.start_row, m.rows - path[1].row)
            w16(LW.TW.start_col, path[1].column + 1)
        end
    end

    local function goto_step(n)
        w16(LW.TW.step, n)
        W.sel, W.top = 0, 0
        if n == 1 then
            w16(LW.TW.tstate, 1)
            wstr(LW.TW.mapinfo, "选择地图")
            step1_items()
        elseif n == 2 then
            step2_items()
            local m = STORE.map_get(W.map)
            wstr(LW.TW.mapinfo, m and STORE.map_spec(W.map) or "")
        elseif n == 3 then
            wstr(LW.TW.detail, "0梭形 1同向 2中左 3右梭 4右同 5中右")
        elseif n == 4 then
            step4_default_start()
        end
        render_list()
    end

    ------------------------------------------------------------------ U盘导入
    -- list_dir 固件双时序: 异步经 on_list_dir 路由 / 同步返回 table(见 fileio.lua);
    -- 画面即时反馈: 扫描中... -> 回调刷新 / 回调超时(约3s, on_tick 判定)提示
    local tick_n = 0
    local scan_deadline = nil                 -- 非 nil = 扫描挂起中
    local SCAN_TICKS = math.max(5, math.ceil(3000 / (ctx.poll_ms or 200)))

    local function usb_import()
        if not FILEIO then return end
        if not STORE then wstr(LW.TW.detail, "数据层不可用"); return end
        if scan_deadline then wstr(LW.TW.detail, "扫描中,请稍候"); return end
        wstr(LW.TW.detail, "扫描U盘中...")
        local names = {}
        scan_deadline = tick_n + SCAN_TICKS
        -- list_dir 异步: 发起列举, 回调在 on_list_dir 路由(见 fileio.lua)
        local ok, err = FILEIO.list("2:", function(list, dir)
            scan_deadline = nil
            if not list then
                log("ERR", "列目录失败 " .. tostring(dir))
                wstr(LW.TW.detail, "扫描失败(未插U盘?)")
                return
            end
            -- 虚拟屏平台 list_dir 不回调, pump 收割空表:
            -- 回退约定清单 2:maps.txt(每行一个 map 文件名, 与 csv 同 GB2312)
            -- 实物屏 list_dir 正常枚举, 清单非必需, 二者无害共存
            if #list == 0 then
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
            wstr(LW.TW.detail,
                imported > 0 and ("导入%d张地图"):format(imported)
                or "无地图文件(或未插U盘)")
            -- 刷新步骤1列表
            if r16(LW.TW.step) == 1 then
                W.sel, W.top = 0, 0
                step1_items()
                render_list()
            end
        end)
        if not ok then
            scan_deadline = nil
            wstr(LW.TW.detail, "U盘不可用")
            log("ERR", "U盘未插入或不可读")
        end
    end

    ------------------------------------------------------------------ 按钮处理
    local function on_btn(addr, val)
        if val ~= 1 then return end
        if addr == LW.TW.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
        elseif addr == LW.TW.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()
        elseif addr == LW.TW.btn_cancel then
            W.map = nil
            goto_step(1)
        elseif addr == LW.TW.btn_sel then
            local step = r16(LW.TW.step) or 1
            if step == 1 then
                if W.sel == 0 then
                    usb_import()
                else
                    local names = STORE and STORE.map_list() or {}
                    W.map = names[W.sel]
                    if W.map then goto_step(2) end
                end
            elseif step == 2 then
                W.use_ab = (W.sel == 1)
                goto_step(3)
            else
                goto_step(math.min(step + 1, 4))
            end
        elseif addr == LW.TW.btn_prev then
            local step = r16(LW.TW.step) or 1
            if step > 1 then goto_step(step - 1) end
        elseif addr == LW.TW.btn_import then
            usb_import()
        elseif addr == LW.TW.btn_ok then
            -- 步骤4: 创建任务并启动
            local m = STORE.map_get(W.map)
            if not m then goto_step(1); return end
            local drow = math.max(0, math.min(m.rows - 1,
                m.rows - (r16(LW.TW.start_row) or m.rows)))
            local dcol = math.max(0, math.min(m.cols - 1,
                (r16(LW.TW.start_col) or 1) - 1))
            local seq = #STORE.task_list() + 1
            local name = "任务" .. seq
            local ok, err = STORE.task_create(name, W.map,
                r16(LW.TW.path_type) or 0, r16(LW.TW.positive) or 0,
                r16(LW.TW.sow_exceed) or 0, drow, dcol, NOW())
            if not ok then
                log("ERR", "任务创建失败: " .. tostring(err))
                wstr(LW.TW.detail, "创建失败 " .. tostring(err):sub(1, 24))
                return
            end
            log("CMD", ("创建任务 %s 地图=%s"):format(name, W.map))
            local ok2, err2 = JOBRUN.start(name)
            if not ok2 then
                log("ERR", "作业启动失败: " .. tostring(err2))
                wstr(LW.TW.detail, "启动失败 " .. tostring(err2):sub(1, 24))
                return
            end
            w16(LW.TW.tstate, 2)
            wstr(LW.TW.detail, "作业中 " .. name)
        elseif addr == LW.TW.btn_resume then
            -- 续接: 找最近的未完成任务
            for _, n in ipairs(STORE.task_list()) do
                local t = STORE.task_get(n)
                if t then
                    local d, tot = STORE.task_progress(n)
                    if d < tot then
                        local ok, err = JOBRUN.start(n, { resume = true })
                        if ok then
                            w16(LW.TW.tstate, 2)
                            wstr(LW.TW.detail, "续作 " .. n)
                        else
                            wstr(LW.TW.detail, tostring(err):sub(1, 24))
                        end
                        return
                    end
                end
            end
            wstr(LW.TW.detail, "无可续接任务")
        end
    end

    ------------------------------------------------------------------ 页面表
    local page = {
        id = LW.SCREEN.TASK,                     -- 画面号(数字, APP.set_screen 按 pages[6] 路由)
        on_enter = function()
            if JOBRUN.active() then
                local cs = JOBRUN.snapshot()
                w16(LW.TW.tstate, (cs and cs.completed) and 3 or 2)
            elseif W.map then
                goto_step(r16(LW.TW.step) or 1)
            else
                goto_step(1)
            end
        end,
        on_leave = function() end,
        poll_cmds = {},
        addrs = {                                -- 按钮地址声明(APP.by_addr 路由必需)
            LW.TW.btn_up, LW.TW.btn_down, LW.TW.btn_sel, LW.TW.btn_prev,
            LW.TW.btn_ok, LW.TW.btn_cancel, LW.TW.btn_resume, LW.TW.btn_import,
            LW.TW.ab_view, LW.TW.ab_import, LW.TW.ab_clear, LW.TW.ab_save,
        },
        on_frame = function(f)
            if f.fnc == ctx.PROTOCOL.FNC.GET_BZ_STATUS then
                job_view()
            end
        end,
    }

    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用, 点定义会错位收 self)
        on_btn(addr, val)
        on_ab_btn(addr)
    end

    -- 作业视图刷新(0x21 被 jobrun 常驻截获, 页面用 tick 级轻刷新)
    function job_view()
        if not JOBRUN.active() then
            if (r16(LW.TW.tstate) or 0) == 2 then
                w16(LW.TW.tstate, 3)
            end
            return
        end
        local s = JOBRUN.snapshot()
        if s then
            if s.completed then w16(LW.TW.tstate, 3) end   -- 完成待手动停止
            -- 显示排=rows-r(0基->1基显示口径, 对齐向导页与冻结规格); cur_col+1
            w16(LW.TW.cur_row, s.rows and (s.rows - (s.cur_row or 0)) or (s.cur_row or 0))
            w16(LW.TW.cur_col, (s.cur_col or 0) + 1)
            w16(LW.TW.done_cnt, s.done or 0)
            w16(LW.TW.total_cnt, s.total or 0)
            w16(LW.TW.pct, s.pct or 0)
        end
    end

    -- 页面 tick 钩子: 扫描回调超时判定 + 作业进度轻刷新(APP.tick 末尾调用, 若存在)
    page.on_tick = function()
        tick_n = tick_n + 1
        if scan_deadline and tick_n > scan_deadline then
            scan_deadline = nil
            wstr(LW.TW.detail, "扫描无响应(未插U盘?)")
            log("WRN", "list_dir 回调超时(异步无果)")
        end
        job_view()
    end

    return page
end
