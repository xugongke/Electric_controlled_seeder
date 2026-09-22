--[[
csv.lua —— CSV/行文本 解析与序列化（B档数据层, 纯函数无副作用）
================================================================================
依据: POC/docs/移植规格-B档冻结.md §3.2 格式冻结
约定: 编码GB2312(本模块只处理字节流, 不做转码); 换行\r\n或\n; 分隔逗号;
      字段禁逗号/换行(名字类校验 check_name); 无引号转义。
地图格式: #MAP/#DIM/#ROWLEN/#AISLE/#AB/#BLOCKS   (BLOCKS 内 1 基, 存储 0 基)
任务格式: #TASK/#MAP/#PATH/#EXCEED/#OUTSET/#LAST/#STATE/#TIME/#BLOCKS/#RESULTS (0 基)
返回: parse_xxx(text) -> obj|nil, msgs(数组, 前缀"E:"致命/"W:"警告)
--]]

local csv = {}

-------------------------------------------------------------------- 基础
-- 平台兼容: string.gsub / string.gmatch / string.rep 屏端不可用(文档LUA/000_Lua_Api),
-- 以下均手写等价实现, 行为与PC Lua原版逐一验证一致(hmi_port/tests/test_him_equivalence.py)

local NL = string.char(10)
local CR = string.char(13)
local function is_space(c)
    return c == 32 or c == 9 or c == 13 or c == 10 or c == 11 or c == 12
end

local function trim(s)
    local i, j = 1, #s
    while i <= j and is_space(string.byte(s, i)) do i = i + 1 end
    while j >= i and is_space(string.byte(s, j)) do j = j - 1 end
    if i > j then return "" end
    return string.sub(s, i, j)
end

-- 行迭代: 剥BOM/统一\r\n; 返回迭代器 (等价原 gmatch("([^\n]*)\n?") 语义)
function csv.iter_lines(text)
    if text:sub(1, 3) == "\xEF\xBB\xBF" then text = text:sub(4) end
    if string.find(text, CR, 1, true) then        -- 含\r才做归一化(快路径跳过)
        local out, i, n = {}, 1, #text
        while i <= n do
            if string.byte(text, i) == 13 then
                out[#out + 1] = NL
                if i < n and string.byte(text, i + 1) == 10 then i = i + 1 end
            else
                out[#out + 1] = string.sub(text, i, i)
            end
            i = i + 1
        end
        text = table.concat(out)
    end
    local pos, empty_yielded = 1, false
    return function()
        if not empty_yielded and #text == 0 then
            empty_yielded = true
            return ""                             -- 原语义: 空文本产一次空行
        end
        if pos > #text then return nil end
        local nl = string.find(text, NL, pos, true)
        if nl then
            local seg = string.sub(text, pos, nl - 1)
            pos = nl + 1
            return seg
        end
        local seg = string.sub(text, pos)
        pos = #text + 1
        return seg
    end
end

function csv.split(line)
    local t = {}
    local pos = 1
    while true do
        local c = string.find(line, ",", pos, true)
        if not c then
            t[#t + 1] = trim(string.sub(line, pos))
            break
        end
        t[#t + 1] = trim(string.sub(line, pos, c - 1))
        pos = c + 1
        if #t > 32 then break end                 -- 字段数护栏
    end
    return t
end

local function num(s)
    if s == nil then return nil end
    return tonumber(s)
end

-- 名字校验: 非空/无逗号换行/<=31字节(GB2312汉字≈15个)
function csv.check_name(s)
    if type(s) ~= "string" or #s == 0 then return false, "空名字" end
    if #s > 31 then return false, "名字超31字节" end
    if s:find("[,\r\n]") then return false, "名字含逗号或换行" end
    return true
end

-- 等价于原 s:gsub("%.?0+$", ""): 去尾部连续'0', 再去残留的'.'
local function trim_zeros(s)
    if string.find(s, ".", 1, true) then
        local e = #s
        while e >= 1 and string.byte(s, e) == 48 do e = e - 1 end   -- '0'
        if e >= 1 and string.byte(s, e) == 46 then e = e - 1 end    -- '.'
        return string.sub(s, 1, e)
    end
    return s
end

local function fmt_num(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
    end
    return trim_zeros(string.format("%.8f", v))  -- 8位小数=GPS毫米级, 去尾零
end

-------------------------------------------------------------------- 地图解析
-- #DIM 校验界限
local ROWS_MAX, COLS_MAX, MC_MAX = 200, 200, 16

function csv.parse_map(text)
    local msgs = {}
    local m = { name = nil, rows = nil, cols = nil, machine_cols = nil,
                col_gap = nil, rowlen = {}, aisle = {},
                blocks = {}, ab = nil, block_cnt = 0 }
    local in_blocks = false
    local seen = {}

    for line in csv.iter_lines(text) do
        if line ~= "" then
            local f = csv.split(line)
            local tag = f[1]
            if tag == "#BLOCKS" then
                in_blocks = true
            elseif in_blocks then
                local r, c, bnum, den, sow = num(f[1]), num(f[2]), num(f[3]), num(f[4]), num(f[5])
                if not (r and c and bnum ~= nil) then
                    msgs[#msgs + 1] = ("E:BLOCKS行非法: %s"):format(line)
                elseif not m.rows then
                    msgs[#msgs + 1] = "E:#DIM缺失(在BLOCKS前)"
                elseif r < 1 or r > m.rows or c < 1 or c > m.cols then
                    msgs[#msgs + 1] = ("E:BLOCKS越界 r=%s c=%s"):format(tostring(f[1]), tostring(f[2]))
                else
                    local rr, cc = r - 1, c - 1                -- 转0基
                    if m.blocks[rr] and m.blocks[rr][cc] then
                        msgs[#msgs + 1] = ("W:重复块(%d,%d)覆盖"):format(r, c)
                    end
                    if not m.blocks[rr] then m.blocks[rr] = {} end
                    m.blocks[rr][cc] = { num = bnum,
                                         density = den or 0,
                                         sow = (sow == nil) and 1 or (sow ~= 0 and 1 or 0) }
                    m.block_cnt = m.block_cnt + 1
                end
            elseif tag == "#MAP" then
                m.name = f[2]
                if not (csv.check_name(f[2] or "")) then
                    msgs[#msgs + 1] = "E:#MAP名字非法"
                end
            elseif tag == "#DIM" then
                m.rows, m.cols, m.machine_cols, m.col_gap =
                    num(f[2]), num(f[3]), num(f[4]), num(f[5])
                m.block_col = num(f[6]) or 1       -- 可选: BlockColumn(小区行数), 默认1
                if not (m.rows and m.cols and m.machine_cols and m.col_gap) then
                    msgs[#msgs + 1] = "E:#DIM需4个数值(rows,cols,machine_cols,col_gap)"
                elseif m.rows < 1 or m.rows > ROWS_MAX
                    or m.cols < 1 or m.cols > COLS_MAX
                    or m.machine_cols < 1 or m.machine_cols > MC_MAX
                    or m.block_col < 1 or m.block_col > 8
                    or m.machine_cols % m.block_col ~= 0 then
                    msgs[#msgs + 1] = ("E:#DIM越界 %s"):format(line)
                end
                seen.DIM = true
            elseif tag == "#ROWLEN" or tag == "#AISLE" then
                local arr = (tag == "#ROWLEN") and m.rowlen or m.aisle
                for i = 2, #f do
                    local v = num(f[i])
                    if v == nil or v < 0 then
                        msgs[#msgs + 1] = ("E:%s数值非法: %s"):format(tag, tostring(f[i]))
                    else
                        arr[#arr + 1] = v
                    end
                end
            elseif tag == "#AB" then
                if #f >= 8 then
                    -- 第9字段: AB参考排(QT Map.ARow 0基), 缺省0
                    -- 第10字段: AB方向bool(QT Map.ABLineDirection, 1=同向/A在排上沿)
                    --   旧文件缺省由 a_row 反推(formmap.cpp:353 aRow=dir?0:rows-1)
                    m.ab = { name = f[2],
                             sn = num(f[3]), se = num(f[4]),
                             en = num(f[5]), ee = num(f[6]),
                             sdir = num(f[7]), cdir = num(f[8]),
                             a_row = num(f[9]) or 0,
                             abdir = num(f[10])
                                 or ((num(f[9]) or 0) == 0 and 1 or 0),
                             has = true }
                    local bad = (m.ab.sn == nil or m.ab.se == nil or m.ab.en == nil
                                 or m.ab.ee == nil or m.ab.sdir == nil or m.ab.cdir == nil)
                    if bad then
                        m.ab = nil
                        msgs[#msgs + 1] = "E:#AB字段数值非法"
                    end
                else
                    msgs[#msgs + 1] = "W:#AB字段不足已忽略"
                end
            elseif tag:sub(1, 1) == "#" then
                -- 未知标签: 容错跳过(前向兼容)
            else
                msgs[#msgs + 1] = ("W:无法识别行已忽略: %s"):format(line:sub(1, 24))
            end
        end
    end

    -- 结构校验
    if not seen.DIM then msgs[#msgs + 1] = "E:缺#DIM" end
    if m.name == nil then msgs[#msgs + 1] = "E:缺#MAP" end
    if m.rows then
        if #m.rowlen ~= m.rows then
            msgs[#msgs + 1] = ("E:#ROWLEN需%d条实有%d"):format(m.rows, #m.rowlen)
        end
        if #m.aisle ~= m.rows + 1 then
            msgs[#msgs + 1] = ("E:#AISLE需%d条实有%d"):format(m.rows + 1, #m.aisle)
        end
        local want = m.rows * m.cols
        if m.block_cnt < want then
            msgs[#msgs + 1] = ("W:BLOCKS缺%d/%d块,按默认补(密度0不播)"):format(want - m.block_cnt, want)
            for r = 0, m.rows - 1 do
                m.blocks[r] = m.blocks[r] or {}
                for c = 0, m.cols - 1 do
                    if not m.blocks[r][c] then
                        m.blocks[r][c] = { num = 0, density = 0, sow = 0 }
                    end
                end
            end
        end
    end

    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return m, msgs
end

-------------------------------------------------------------------- 地图序列化
function csv.render_map(m)
    local L = {}
    L[#L + 1] = ("#MAP,%s"):format(m.name)
    if (m.block_col or 1) > 1 then
        L[#L + 1] = ("#DIM,%d,%d,%d,%s,%d"):format(
            m.rows, m.cols, m.machine_cols, fmt_num(m.col_gap), m.block_col)
    else
        L[#L + 1] = ("#DIM,%d,%d,%d,%s"):format(
            m.rows, m.cols, m.machine_cols, fmt_num(m.col_gap))
    end
    for r = 1, m.rows do L[#L + 1] = ("#ROWLEN,%s"):format(fmt_num(m.rowlen[r] or 0)) end
    for i = 1, m.rows + 1 do L[#L + 1] = ("#AISLE,%s"):format(fmt_num(m.aisle[i] or 0)) end
    if m.ab then
        L[#L + 1] = ("#AB,%s,%s,%s,%s,%s,%s,%s,%d,%d"):format(
            m.ab.name, fmt_num(m.ab.sn), fmt_num(m.ab.se), fmt_num(m.ab.en),
            fmt_num(m.ab.ee), fmt_num(m.ab.sdir), fmt_num(m.ab.cdir),
            m.ab.a_row or 0, m.ab.abdir or 1)
    end
    L[#L + 1] = "#BLOCKS"
    for r = 0, m.rows - 1 do
        for c = 0, m.cols - 1 do
            local b = (m.blocks[r] or {})[c] or { num = 0, density = 0, sow = 0 }
            L[#L + 1] = ("%d,%d,%d,%d,%d"):format(r + 1, c + 1, b.num, b.density, b.sow)
        end
    end
    return table.concat(L, "\r\n") .. "\r\n"
end

-------------------------------------------------------------------- 任务解析
-- 结果行: r,c,state,start,end,seed[1..n],fert[1..n] (n=seed列数, 自适应4/6)
local function parse_result_line(f)
    local r, c, st = num(f[1]), num(f[2]), num(f[3])
    if r == nil or c == nil or st == nil then return nil end
    local e = { r = r, c = c, state = st, start_t = f[4] or "", end_t = f[5] or "",
                seed = {}, fert = {} }
    local cols = #f - 5
    if cols < 2 or cols % 2 ~= 0 then return nil end
    local n = cols / 2
    for i = 1, n do e.seed[i] = num(f[5 + i]) or 0 end
    for i = 1, n do e.fert[i] = num(f[5 + n + i]) or 0 end
    return e
end

local function render_result_line(e)
    local t = { ("%d,%d,%d,%s,%s"):format(e.r, e.c, e.state, e.start_t, e.end_t) }
    for _, v in ipairs(e.seed) do t[#t + 1] = tostring(v) end
    for _, v in ipairs(e.fert) do t[#t + 1] = tostring(v) end
    return table.concat(t, ",")
end

function csv.parse_task(text)
    local msgs = {}
    local t = { name = nil, map = nil, path_type = 0, positive = 0, sow_exceed = 0,
                outset = { r = 0, c = 0 }, last = { r = -1, c = -1 },
                state = 0, create_time = "", last_work_time = "",
                blocks = {}, results = {} }
    local section = nil

    for line in csv.iter_lines(text) do
        if line ~= "" then
            local f = csv.split(line)
            local tag = f[1]
            if tag == "#BLOCKS" or tag == "#RESULTS" then
                section = tag
            elseif section == "#BLOCKS" then
                local r, c, st, sow = num(f[1]), num(f[2]), num(f[3]), num(f[4])
                if r == nil or c == nil or st == nil then
                    msgs[#msgs + 1] = ("E:BLOCKS行非法: %s"):format(line)
                else
                    if not t.blocks[r] then t.blocks[r] = {} end
                    t.blocks[r][c] = { state = st, sow = (sow or 1) ~= 0 and 1 or 0 }
                end
            elseif section == "#RESULTS" then
                local e = parse_result_line(f)
                if e then
                    t.results[#t.results + 1] = e
                else
                    msgs[#msgs + 1] = ("W:RESULTS行非法已忽略: %s"):format(line:sub(1, 24))
                end
            elseif tag == "#TASK" then
                t.name = f[2]
                if not csv.check_name(f[2] or "") then msgs[#msgs + 1] = "E:#TASK名字非法" end
            elseif tag == "#MAP" then
                t.map = f[2]
                if not csv.check_name(f[2] or "") then msgs[#msgs + 1] = "E:#MAP名字非法" end
            elseif tag == "#PATH" then
                local pt, po = num(f[2]), num(f[3])
                if pt == nil or pt < 0 or pt > 5 then
                    msgs[#msgs + 1] = ("E:#PATH非法: %s"):format(line)
                else
                    t.path_type = pt
                    t.positive = (po and po ~= 0) and 1 or 0
                end
            elseif tag == "#EXCEED" then
                t.sow_exceed = (num(f[2]) or 0) ~= 0 and 1 or 0
            elseif tag == "#OUTSET" then
                local r, c = num(f[2]), num(f[3])
                if r == nil or c == nil then
                    msgs[#msgs + 1] = ("E:#OUTSET非法: %s"):format(line)
                else
                    t.outset = { r = r, c = c }
                end
            elseif tag == "#LAST" then
                local r, c = num(f[2]), num(f[3])
                t.last = { r = r or -1, c = c or -1 }
            elseif tag == "#STATE" then
                t.state = num(f[2]) or 0
            elseif tag == "#TIME" then
                t.create_time, t.last_work_time = f[2] or "", f[3] or ""
            elseif tag:sub(1, 1) == "#" then
                -- 未知标签容错
            else
                msgs[#msgs + 1] = ("W:节外行已忽略: %s"):format(line:sub(1, 24))
            end
        end
    end

    if t.name == nil then msgs[#msgs + 1] = "E:缺#TASK" end
    if t.map == nil then msgs[#msgs + 1] = "E:缺#MAP" end
    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return t, msgs
end

-------------------------------------------------------------------- 任务序列化
function csv.render_task(t)
    local L = {}
    L[#L + 1] = ("#TASK,%s"):format(t.name)
    L[#L + 1] = ("#MAP,%s"):format(t.map)
    L[#L + 1] = ("#PATH,%d,%d"):format(t.path_type, t.positive)
    L[#L + 1] = ("#EXCEED,%d"):format(t.sow_exceed and 1 or 0)
    L[#L + 1] = ("#OUTSET,%d,%d"):format(t.outset.r, t.outset.c)
    L[#L + 1] = ("#LAST,%d,%d"):format(t.last.r, t.last.c)
    L[#L + 1] = ("#STATE,%d"):format(t.state)
    L[#L + 1] = ("#TIME,%s,%s"):format(t.create_time, t.last_work_time)
    L[#L + 1] = "#BLOCKS"
    local rows = 0
    for r in pairs(t.blocks) do if r > rows then rows = r end end
    for r = 0, rows do
        if t.blocks[r] then
            local cols = 0
            for c in pairs(t.blocks[r]) do if c > cols then cols = c end end
            for c = 0, cols do
                local b = t.blocks[r][c]
                if b then
                    L[#L + 1] = ("%d,%d,%d,%d"):format(r, c, b.state, b.sow)
                end
            end
        end
    end
    if #t.results > 0 then
        L[#L + 1] = "#RESULTS"
        for _, e in ipairs(t.results) do
            L[#L + 1] = render_result_line(e)
        end
    end
    return table.concat(L, "\r\n") .. "\r\n"
end

csv.render_result_line = render_result_line
csv.parse_result_line  = parse_result_line

return csv
