--[[
store.lua —— 数据层: 9表驻留模型 + 行文本持久化 + 启动恢复（B档）
================================================================================
依据: POC/docs/移植规格-B档冻结.md §3
内存模型: store.maps / store.tasks / store.results / store.cfg (坐标全 0 基)
持久化(内部Flash "3:", prefix 可注入):
  map_<名>.csv    地图(原样转存U盘导入内容)
  task_<名>.csv   任务定义+块状态(不含结果, 排级重写)
  result_<名>.csv 结果记录(追加式)
  index.txt       "M,<名>"/"T,<名>" 清单(启动免扫目录)
块状态: 0待播 1已下发 2完成 3中断(boot时1→3, 对齐QT task.cpp:44 且修正isSow含3)
依赖注入: store.init(fileio模块, csv模块, prefix) —— 屏端 main.lua / PC 测试均如此装配
--]]

local store = {}

store.maps    = {}      -- [name] = map(csv.parse_map 产物, 另含 block_col)
store.tasks   = {}      -- [name] = task(csv.parse_task 产物)
store.results = {}      -- [name] = { {r,c,state,start_t,end_t,seed={},fert={}} }
store.cfg     = { fine_tune = {} }   -- {{origin,specified,enabled}}

local F, C, PREFIX = nil, nil, "3:"

local function p_map(n)    return PREFIX .. "map_" .. n .. ".csv" end
local function p_task(n)   return PREFIX .. "task_" .. n .. ".csv" end
local function p_result(n) return PREFIX .. "result_" .. n .. ".csv" end
local function p_index()   return PREFIX .. "index.txt" end

-------------------------------------------------------------------- 装配
function store.init(fileio_mod, csv_mod, prefix)
    F, C, PREFIX = fileio_mod, csv_mod, prefix or "3:"
    return store
end

local function bet(map)   -- 一趟覆盖的列数 = MachineColumn/BlockColumn (QT blockEachTrip)
    return math.max(1, math.floor((map.machine_cols or 1) / (map.block_col or 1)))
end
store.block_each_trip = function(map) return bet(map) end

-- 实际组宽: 末趟剩余列可能小于 bet (QT 奇数剩余趟语义)
local function grp(map, c0)
    local n = bet(map)
    if map.cols and c0 + n > map.cols then n = map.cols - c0 end
    return math.max(1, n)
end

-------------------------------------------------------------------- index 维护
local function index_write()
    local L = {}
    local names = {}
    for n in pairs(store.maps) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do L[#L + 1] = "M," .. n end
    names = {}
    for n in pairs(store.tasks) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do L[#L + 1] = "T," .. n end
    local s = table.concat(L, "\r\n")
    if #L > 0 then s = s .. "\r\n" end
    F.write_all(p_index(), s)
end

-------------------------------------------------------------------- 地图
-- 导入(文本): 解析校验 → 驻留 → 原样字节转存内部Flash → 更新index
function store.map_import_text(name, text)
    if not select(1, C.check_name(name)) then
        return nil, "地图名非法"
    end
    local m, msgs = C.parse_map(text)
    if not m then
        return nil, "地图解析失败: " .. (msgs[1] or "?")
    end
    if m.name ~= name then
        return nil, ("文件名与内容名不符(%s≠%s)"):format(name, tostring(m.name))
    end
    local ok, err = F.write_all(p_map(name), text)      -- 原样转存
    if not ok then return nil, "地图落盘失败: " .. tostring(err) end
    store.maps[name] = m
    index_write()
    return m, (#msgs > 0) and table.concat(msgs, "; ") or nil
end

-- 导入(U盘文件): 读全量→导入
function store.map_import_file(path, name)
    local text, err = F.read_all(path)
    if not text then return nil, "读取失败: " .. tostring(err) end
    return store.map_import_text(name, text)
end

-- 地图重渲染落盘(驻留对象已改, 如停止时保存AB线 -> #AB 段写回)
function store.map_save(name)
    local m = store.maps[name]
    if not m then return nil, "地图不存在" end
    return F.write_all(p_map(name), C.render_map(m))
end

function store.map_delete(name)
    store.maps[name] = nil
    F.remove(p_map(name))
    index_write()
end

function store.map_get(name) return store.maps[name] end

function store.map_list()
    local t = {}
    for n in pairs(store.maps) do t[#t + 1] = n end
    table.sort(t)
    return t
end

-- 向导列表摘要: "演示田 4排×6列"
function store.map_spec(name)
    local m = store.maps[name]
    if not m then return "?" end
    return ("%d排×%d列"):format(m.rows, m.cols)
end

-------------------------------------------------------------------- 任务
-- 创建: 克隆地图块状态(sow) → 全0待播; last=-1; 落盘
function store.task_create(name, map_name, path_type, positive, sow_exceed,
                           outset_r, outset_c, now)
    if not select(1, C.check_name(name)) then return nil, "任务名非法" end
    if store.tasks[name] then return nil, "任务已存在" end
    local m = store.maps[map_name]
    if not m then return nil, "地图不存在" end
    if not (outset_r >= 0 and outset_r < m.rows and outset_c >= 0 and outset_c < m.cols) then
        return nil, "起始小区越界"
    end
    local t = {
        name = name, map = map_name,
        path_type = path_type or 0,
        positive = (positive and positive ~= 0) and 1 or 0,
        sow_exceed = (sow_exceed and sow_exceed ~= 0) and 1 or 0,
        outset = { r = outset_r, c = outset_c },
        last = { r = -1, c = -1 },
        state = 0, create_time = now or "", last_work_time = now or "",
        blocks = {}, results = {},
    }
    for r = 0, m.rows - 1 do
        t.blocks[r] = {}
        for c = 0, m.cols - 1 do
            t.blocks[r][c] = { state = 0, sow = m.blocks[r][c].sow }
        end
    end
    store.tasks[name] = t
    store.results[name] = {}
    local ok, err = store.task_save(name)
    if not ok then
        store.tasks[name], store.results[name] = nil, nil
        return nil, "任务落盘失败: " .. tostring(err)
    end
    index_write()
    return t
end

-- 定义+块状态落盘(不含结果; 结果走追加文件)
function store.task_save(name)
    local t = store.tasks[name]
    if not t then return nil, "任务不存在" end
    local plain = {}
    for k, v in pairs(t) do plain[k] = v end
    plain.results = {}
    return F.write_all(p_task(name), C.render_task(plain))
end

function store.task_get(name) return store.tasks[name] end

function store.task_list()
    local t = {}
    for n in pairs(store.tasks) do t[#t + 1] = n end
    table.sort(t)
    return t
end

function store.task_delete(name)
    store.tasks[name], store.results[name] = nil, nil
    F.remove(p_task(name))
    F.remove(p_result(name))
    index_write()
end

-- startNode 下发后标记: 组内 c0..c0+bet-1 置1 (对齐 QT setBlockState(row,col,1))
-- 并落盘: 下发即掉电 → 重启识别为中断(3), 支持断点续作 (QT task.cpp:44)
function store.task_mark_dispatched(name, r, c0)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "块不存在" end
    local m = store.maps[t.map]
    local n = m and grp(m, c0) or 1
    for c = c0, c0 + n - 1 do
        if t.blocks[r][c] then t.blocks[r][c].state = 1 end
    end
    return store.task_save(name)
end

-- 排完成: 组内置2 + 追加结果行 + 更新断点 + 整任务落盘(排级频度)
function store.task_mark_row_done(name, r, c0, entries, now)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "块不存在" end
    local m = store.maps[t.map]
    local n = m and grp(m, c0) or 1
    local lines = {}
    for c = c0, c0 + n - 1 do
        if t.blocks[r][c] then t.blocks[r][c].state = 2 end
        local e = entries and entries[c - c0 + 1]
        if e then
            e.r, e.c = r, c
            store.results[name][#store.results[name] + 1] = e
            lines[#lines + 1] = C.render_result_line(e) .. "\r\n"
        end
    end
    if #lines > 0 then
        local ok, err = F.append(p_result(name), table.concat(lines))
        if not ok then return nil, "结果落盘失败: " .. tostring(err) end
    end
    t.last = { r = r, c = c0 + n - 1 }
    if now then t.last_work_time = now end
    return store.task_save(name)
end

function store.task_set_last(name, r, c, now)
    local t = store.tasks[name]
    if not t then return nil end
    t.last = { r = r, c = c }
    if now then t.last_work_time = now end
    return store.task_save(name)
end

-- 完成度: 分子=state2块数, 分母=总块数(对齐QT completionDegree口径)
-- 完成度: 分母=作业路径覆盖的小区数 (QT dialogrealtimetask.cpp:916
-- trip=cols/blockEachTrip 整除, 余数列不进路径不作业), 与 mark 口径一致;
-- 分母错大会导致任务完成后完成率封顶 <100% 且已完成任务仍被判定可续作。
function store.task_progress(name)
    local t = store.tasks[name]
    if not t then return 0, 0, 0 end
    local m = store.maps[t.map]
    local rows = (m and m.rows) or 0
    local cols = (m and m.cols) or 0
    local n = m and bet(m) or 1
    local cov = math.floor(cols / n) * n          -- 作业覆盖列数(整除, 丢余数列)
    if cov <= 0 then cov = cols end               -- 退化: 覆盖空时按全列兜底
    local done, total = 0, 0
    for r = 0, rows - 1 do
        local rowb = t.blocks[r]
        if rowb then
            for c = 0, cov - 1 do
                local b = rowb[c]
                if b then
                    total = total + 1
                    if b.state == 2 then done = done + 1 end
                end
            end
        end
    end
    return done, total, (total > 0) and math.floor(done * 100 / total) or 0
end

-- USB 导出文本: 任务定义 + 全部结果(合并渲染)
function store.export_task_text(name)
    local t = store.tasks[name]
    if not t then return nil, "任务不存在" end
    t.results = store.results[name] or {}
    local s = C.render_task(t)
    t.results = {}
    return s
end

-------------------------------------------------------------------- 结果/密度微调
function store.result_add(name, entry)
    local list = store.results[name]
    if not list then return nil, "任务不存在" end
    list[#list + 1] = entry
    return F.append(p_result(name), C.render_result_line(entry) .. "\r\n")
end

-- 密度微调映射(QT global.cpp densityIsSpecified/specifiedDensity; 首轮空表=恒等)
function store.apply_density(v)
    for _, ft in ipairs(store.cfg.fine_tune) do
        if ft.enabled and ft.origin == v then return ft.specified end
    end
    return v
end

-------------------------------------------------------------------- 启动恢复
-- 读 index → 装载全部地图/任务/结果; 空片无index返回零; 失败项跳过并计数
function store.boot()
    local warns = {}
    store.maps, store.tasks, store.results = {}, {}, {}

    local text = F.read_all(p_index())
    if not text or #text == 0 then
        return { maps = 0, tasks = 0, warns = { "空片或无index" } }
    end

    local mnames, tnames = {}, {}
    for line in C.iter_lines(text) do
        if line ~= "" then
            local f = C.split(line)
            if f[1] == "M" and f[2] then mnames[#mnames + 1] = f[2]
            elseif f[1] == "T" and f[2] then tnames[#tnames + 1] = f[2] end
        end
    end

    for _, n in ipairs(mnames) do
        local raw = F.read_all(p_map(n))
        local m
        if raw then m = C.parse_map(raw) end
        if m then
            store.maps[n] = m
        else
            warns[#warns + 1] = ("地图%s装载失败已跳过"):format(n)
        end
    end

    for _, n in ipairs(tnames) do
        local raw = F.read_all(p_task(n))
        local t
        if raw then t = C.parse_task(raw) end
        if t then
            -- 中断转换: 1→3 (QT task.cpp:44); 屏端isSow含3, 修正断电恢复密度误0
            for _, row in pairs(t.blocks) do
                for _, b in pairs(row) do
                    if b.state == 1 then b.state = 3 end
                end
            end
            store.tasks[n] = t
            store.results[n] = {}
            local rraw = F.read_all(p_result(n))
            if rraw then
                for line in C.iter_lines(rraw) do
                    if line ~= "" and line:sub(1, 1) ~= "#" then
                        local e = C.parse_result_line(C.split(line))
                        if e then store.results[n][#store.results[n] + 1] = e end
                    end
                end
            end
        else
            warns[#warns + 1] = ("任务%s装载失败已跳过"):format(n)
        end
    end

    -- index 与内存对齐(失败项剔除)
    index_write()
    return { maps = #store.map_list(), tasks = #store.task_list(), warns = warns }
end

return store
