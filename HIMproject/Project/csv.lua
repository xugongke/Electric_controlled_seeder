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

-------------------------------------------------------------------- 区块式解析(2026-10-08)
-- 布局=QT上位机xlsx导出同款(用户样例), 单文件五区块:
--   信息(键值+排长/过道序列藏C/D列) / AB线(BDPara全字段+A点排/A点列/
--   方向/名称) / 编号 / 密度 / 是否播种(矩阵, 行倒序N排在上, 列从B列1基)
-- "; "注释行忽略; 编号区允许空(顺位补), 密度/播种区必须完整
function csv.parse_map_grid(text)
    local msgs = {}
    local m = { name = nil, rows = nil, cols = nil, machine_cols = nil,
                col_gap = nil, rowlen = {}, aisle = {}, block_col = 1,
                blocks = {}, ab = nil, block_cnt = 0 }
    local section = nil
    local rowlen_seq, aisle_seq = {}, {}
    local abf = {}
    local head_pending = {}

    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= ";" then
            local f = csv.split(line)
            local a1 = f[1] or ""
            if a1 == "信息" or a1 == "AB线" or a1 == "编号"
               or a1 == "密度" or a1 == "是否播种" then
                section = a1
                head_pending[section] = true
            elseif section == "信息" then
                if a1 ~= "类型" then              -- 表头行(排长cm/过道长cm)
                    if a1 == "名称" then m.name = (f[2] ~= "" and f[2]) or nil
                        -- 地图显示名(hmi_export; 空串归nil)
                    elseif a1 == "排" then m.rows = num(f[2])
                    elseif a1 == "列" then m.cols = num(f[2])
                    elseif a1 == "小区行数" then m.block_col = num(f[2]) or 1
                    elseif a1 == "机器行数" then m.machine_cols = num(f[2])
                    elseif a1 == "行间距(cm)" then m.col_gap = num(f[2])
                    end
                    local cl, ai = num(f[3]), num(f[4])
                    if cl then rowlen_seq[#rowlen_seq + 1] = cl end
                    if ai then aisle_seq[#aisle_seq + 1] = ai end
                end
            elseif section == "AB线" then
                if a1 ~= "" then abf[a1] = f[2] end
            elseif section == "编号" or section == "密度"
                or section == "是否播种" then
                if head_pending[section] and a1 == "" then
                    head_pending[section] = false  -- ",1列,2列"表头行
                else
                    local rr = a1:match("^(%d+)排$")
                    local r = rr and tonumber(rr)
                    if r and m.rows and r >= 1 and r <= m.rows then
                        local r0 = r - 1
                        if not m.blocks[r0] then m.blocks[r0] = {} end
                        for c = 2, #f do
                            local c0 = c - 2
                            if m.cols and c0 >= 0 and c0 < m.cols then
                                local cur = m.blocks[r0][c0]
                                           or { num = r0 * m.cols + c0 + 1,
                                                density = 0, sow = 1 }
                                local v = num(f[c])
                                if section == "编号" then
                                    if v ~= nil then cur.num = v end
                                elseif section == "密度" then
                                    cur.density = v or 0
                                else
                                    if v ~= nil then
                                        cur.sow = (v ~= 0) and 1 or 0
                                    end
                                end
                                m.blocks[r0][c0] = cur
                            end
                        end
                    end
                end
            end
        end
    end

    -- 校验与组装(对齐 legacy 口径)
    if not (m.rows and m.cols and m.machine_cols and m.col_gap) then
        msgs[#msgs + 1] = "E:信息区缺排/列/机器行数/行间距"
        return m, msgs
    end
    if #rowlen_seq ~= m.rows then
        msgs[#msgs + 1] = ("E:排长需%d条实有%d"):format(m.rows, #rowlen_seq)
    else
        m.rowlen = rowlen_seq
    end
    -- 旧版render补0自愈(2026-10-13): D列曾在rows+1之后补0, rows<7的
    -- 地图过道超期且尾部全0 -> 截断告警, 已损坏的落盘文件重启可恢复开播
    if m.rows and #aisle_seq > m.rows + 1 then
        local want = m.rows + 1
        local pad = true
        for i = want + 1, #aisle_seq do
            if aisle_seq[i] ~= 0 then
                pad = false
                break
            end
        end
        if pad then
            local extra = #aisle_seq - want
            for _ = 1, extra do aisle_seq[#aisle_seq] = nil end
            msgs[#msgs + 1] = ("W:过道尾部%d条补0已截断(旧版渲染兼容)")
                :format(extra)
        end
    end
    if #aisle_seq ~= m.rows + 1 then
        msgs[#msgs + 1] = ("E:过道需%d条实有%d"):format(m.rows + 1, #aisle_seq)
    else
        m.aisle = aisle_seq
    end
    local want = m.rows * m.cols
    local got = 0
    for r = 0, m.rows - 1 do
        for c = 0, m.cols - 1 do
            if m.blocks[r] and m.blocks[r][c] then got = got + 1 end
        end
    end
    if got ~= want then
        msgs[#msgs + 1] = ("E:密度矩阵需%d块实有%d"):format(want, got)
    end
    m.block_cnt = got
    -- 地图名: 信息区"名称"行(hmi_export生成); 缺省由store用导入文件名兜底

    if abf["StartN"] ~= nil then
        m.ab = { name = abf["名称"] or "ab",
                 sn = tonumber(abf["StartN"]), se = tonumber(abf["StartE"]),
                 en = tonumber(abf["EndBN"]), ee = tonumber(abf["EndBE"]),
                 sdir = tonumber(abf["StartDir"]),
                 cdir = tonumber(abf["CalcDir"]),
                 a_row = tonumber(abf["A点排"]) or 0,
                 a_col = tonumber(abf["A点列"]) or 0,
                 abdir = (abf["方向"] == "TRUE"
                          or abf["方向"] == "1") and 1 or 0,
                 startstate = tonumber(abf["StartState"]) or 1,
                 calcdirflag = tonumber(abf["CalcDirFlag"]) or 1,
                 offlen = tonumber(abf["OffLen"]) or 0,
                 bdofftime = tonumber(abf["BDOffTime"]) or 100,
                 has = true }
        if m.ab.sn == nil or m.ab.se == nil or m.ab.en == nil
            or m.ab.ee == nil or m.ab.sdir == nil or m.ab.cdir == nil then
            m.ab = nil
            msgs[#msgs + 1] = "E:AB线字段数值非法"
        end
    end
    return m, msgs
end

-- 双格式分派: 首个有效行首字段="信息" -> 区块式; 否则旧#段式
function csv.parse_map(text)
    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= ";" then
            local f = csv.split(line)
            if (f[1] or "") == "信息" then
                local m1, m2 = csv.parse_map_grid(text)
                return m1, m2
            end
            break
        end
    end
    -- (局部中转: 避免出现模块尾return字面, 兼容测试的patch注入点)
    local m1, m2 = csv.parse_map_legacy(text)
    return m1, m2
end

-------------------------------------------------------------------- 地图解析
-- #DIM 校验界限
local ROWS_MAX, COLS_MAX, MC_MAX = 200, 200, 16

function csv.parse_map_legacy(text)  -- 旧#段式(2026-10-08前)
    local msgs = {}
    local m = { name = nil, rows = nil, cols = nil, machine_cols = nil,
                col_gap = nil, rowlen = {}, aisle = {},
                blocks = {}, ab = nil, block_cnt = 0 }
    local in_blocks = false
    local seen = {}

    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= ";" then   -- ";"=中文注解行(hmi_export)
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
                    -- 第11~14字段(2026-10-08, QT ABLine表): 起始状态/方向标志/
                    --   偏移长度cm/偏移时间ms; 旧文件缺省=屏端下发语义(1/1/0/100)
                    m.ab = { name = f[2],
                             sn = num(f[3]), se = num(f[4]),
                             en = num(f[5]), ee = num(f[6]),
                             sdir = num(f[7]), cdir = num(f[8]),
                             a_row = num(f[9]) or 0,
                             abdir = num(f[10])
                                 or ((num(f[9]) or 0) == 0 and 1 or 0),
                             startstate = num(f[11]) or 1,
                             calcdirflag = num(f[12]) or 1,
                             offlen = num(f[13]) or 0,
                             bdofftime = num(f[14]) or 100,
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
    -- 区块式(2026-10-08, QT xlsx导出同款布局); 旧#段式文件保存后自动升级
    local L = {}
    local function row(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
        L[#L + 1] = table.concat(t, ",")
    end
    row("信息", "", "", "")
    -- 名称行(2026-10-13补, 对齐hmi_export.render_map_csv): 旧版不写,
    -- 地图经map_save重渲染后名称丢失, 重启boot重载m.name=nil
    if m.name and m.name ~= "" then row("名称", m.name) end
    row("类型", "播种", "排长(cm)", "过道长(cm)")
    -- 信息区: C列=排长(rows条), D列=过道(rows+1条), 标签行固定8个不够留空
    local labels = { "创建时间", "修改时间", "备注", "排", "列",
                     "小区行数", "机器行数", "行间距(cm)" }
    local meta_rows = math.max(8, (m.rows or 0) + 1)
    for i = 1, meta_rows do
        local lab = labels[i] or ""
        local b = ""
        if lab == "排" then b = m.rows or 0
        elseif lab == "列" then b = m.cols or 0
        elseif lab == "小区行数" then b = m.block_col or 1
        elseif lab == "机器行数" then b = m.machine_cols or 6
        elseif lab == "行间距(cm)" then b = fmt_num(m.col_gap or 60) end
        local c = ""
        if i <= (m.rows or 0) then c = fmt_num(m.rowlen[i] or 0) end
        -- D列仅rows+1行(2026-10-13, 对齐hmi_export): 此前行行写值,
        -- rows<7地图回写后过道多出补0条目 -> 重启重载E: -> m.aisle空
        -- -> start_node对nil算术炸断启动链(0x24后0x20/0x31/0x0A全不发)
        local d = ""
        if i <= (m.rows or 0) + 1 then d = fmt_num(m.aisle[i] or 0) end
        row(lab, b, c, d)
    end
    row("", "", "", "")
    if m.ab then
        row("AB线", "", "", "")
        row("StartN", fmt_num(m.ab.sn or 0))
        row("StartE", fmt_num(m.ab.se or 0))
        row("EndBN", fmt_num(m.ab.en or 0))
        row("EndBE", fmt_num(m.ab.ee or 0))
        row("StartDir", fmt_num(m.ab.sdir or 0))
        row("CalcDir", fmt_num(m.ab.cdir or 0))
        row("StartState", m.ab.startstate or 1)
        row("CalcDirFlag", m.ab.calcdirflag or 1)
        row("OffLen", m.ab.offlen or 0)
        row("BDOffTime", m.ab.bdofftime or 100)
        row("Resv", 0)
        row("CrcCheck", 0)
        row("A点排", m.ab.a_row or 0)
        row("A点列", m.ab.a_col or 0)
        row("方向", (m.ab.abdir or 0) == 1 and "TRUE" or "FALSE")
        row("名称", m.ab.name or "")
        row("", "", "", "")
    end
    local function matrix(title, get)
        row(title, "", "", "")
        local hd = { "" }
        for c = 1, m.cols do hd[c + 1] = c .. "列" end
        L[#L + 1] = table.concat(hd, ",")
        for r = m.rows, 1, -1 do
            local vals = { r .. "排" }
            for c = 1, m.cols do
                local b = (m.blocks[r - 1] or {})[c - 1]
                           or { num = 0, density = 0, sow = 1 }
                vals[c + 1] = get(b)
            end
            L[#L + 1] = table.concat(vals, ",")
        end
        row("", "", "", "")
    end
    matrix("编号", function(b) return b.num end)
    matrix("密度", function(b) return b.density end)
    matrix("是否播种", function(b) return b.sow end)
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

-- 双格式分派(2026-10-13): 首个有效行首字段="信息" -> Excel式(任务.csv
-- 导出布局); 否则旧#段式(内部3:盘存储格式)
function csv.parse_task(text)
    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local f0 = csv.split(line)
            if (f0[1] or "") == "信息" then
                return csv.parse_task_xlsx(text)
            end
            break
        end
    end
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


-------------------------------------------------------------------- 任务Excel格式(2026-10-13)
-- 仿QT"任务.csv"导出布局(用户样例): 信息键值区 + 状态矩阵 + 是否播种矩阵
-- + 结果表; U盘导出供Excel直接查看(GB2312)。parse_task双格式分派,
-- 导出的文件可再导入(内部3:盘存储仍用#段式, 互不影响)。
local function task_dims(t)
    local rows, cols = 0, 0
    for r, rowb in pairs(t.blocks) do
        if r + 1 > rows then rows = r + 1 end
        for c in pairs(rowb) do
            if c + 1 > cols then cols = c + 1 end
        end
    end
    return rows, cols
end

function csv.render_task_xlsx(t)
    local L = {}
    local function row(...)
        local s = {}
        for i = 1, select("#", ...) do s[i] = tostring(select(i, ...)) end
        L[#L + 1] = table.concat(s, ",")
    end
    local rows, cols = task_dims(t)
    row("信息")
    row("名称", t.name or "")
    row("地图", t.map or "")
    row("创建时间", t.create_time or "")
    row("最后工作时间", t.last_work_time or "")
    row("备注", t.remark or "")
    row("排", rows)
    row("列", cols)
    row("路线类型", t.path_type or 0)
    row("路线方向", (t.positive == 1) and "正" or "反")
    row("起点排列", (t.outset and t.outset.r) or 0,
        (t.outset and t.outset.c) or 0)
    row("最近完成排列", (t.last and t.last.r) or -1,
        (t.last and t.last.c) or -1)
    row("")
    local function matrix(title, get)
        row(title)
        local hd = { "" }
        for c = 1, cols do hd[c + 1] = c .. "列" end
        L[#L + 1] = table.concat(hd, ",")
        for r = rows, 1, -1 do
            local vals = { r .. "排" }
            for c = 1, cols do
                local b = (t.blocks[r - 1] or {})[c - 1]
                vals[c + 1] = get(b)
            end
            L[#L + 1] = table.concat(vals, ",")
        end
        row("")
    end
    matrix("状态", function(b) return b and b.state or 0 end)
    matrix("是否播种", function(b)
        return (b and b.sow == 1) and "√" or ""
    end)
    row("结果")
    local hd = { "排", "列", "开始时间", "完成时间", "状态" }
    for i = 1, 6 do hd[#hd + 1] = i .. "行播种" end
    for i = 1, 6 do hd[#hd + 1] = i .. "行漏肥" end
    L[#L + 1] = table.concat(hd, ",")
    -- 排=显示排号(rows-内部行, 对齐QT :324 blockVector.size()-row;
    --   2026-10-14修正: 原r+1与QT口径相反); 列=1基
    for _, e in ipairs(t.results or {}) do
        local vals = { rows - e.r, e.c + 1, e.start_t or "", e.end_t or "",
                       e.state or 0 }
        for i = 1, 6 do vals[#vals + 1] = (e.seed or {})[i] or 0 end
        for i = 1, 6 do vals[#vals + 1] = (e.fert or {})[i] or 0 end
        L[#L + 1] = table.concat(vals, ",")
    end
    return table.concat(L, "\r\n") .. "\r\n"
end

function csv.parse_task_xlsx(text)
    local msgs = {}
    local t = { name = nil, map = nil, path_type = 0, positive = 0,
                sow_exceed = 0, outset = { r = 0, c = 0 },
                last = { r = -1, c = -1 }, state = 0,
                create_time = "", last_work_time = "",
                blocks = {}, results = {} }
    local section = nil
    for line in csv.iter_lines(text) do
        if line ~= "" then
            local f = csv.split(line)
            local a1 = f[1] or ""
            if a1 == "信息" or a1 == "状态" or a1 == "是否播种"
               or a1 == "结果" then
                section = a1
            elseif section == "信息" then
                if a1 == "名称" then t.name = f[2]
                elseif a1 == "地图" then t.map = f[2]
                elseif a1 == "创建时间" then t.create_time = f[2] or ""
                elseif a1 == "最后工作时间" then t.last_work_time = f[2] or ""
                elseif a1 == "备注" then t.remark = f[2] or ""
                elseif a1 == "路线类型" then
                    local v = num(f[2])
                    if v and v >= 0 and v <= 5 then t.path_type = v end
                elseif a1 == "路线方向" then
                    t.positive = (f[2] == "正") and 1 or 0
                elseif a1 == "起点排列" then
                    t.outset = { r = num(f[2]) or 0, c = num(f[3]) or 0 }
                elseif a1 == "最近完成排列" then
                    t.last = { r = num(f[2]) or -1, c = num(f[3]) or -1 }
                end
            elseif (section == "状态" or section == "是否播种") then
                local rr = a1:match("^(%d+)排$")
                if rr then
                    local r0 = tonumber(rr) - 1
                    if r0 >= 0 then
                        if not t.blocks[r0] then t.blocks[r0] = {} end
                        for c = 2, #f do
                            local c0 = c - 2
                            local cur = t.blocks[r0][c0]
                                       or { state = 0, sow = 1 }
                            if section == "状态" then
                                cur.state = num(f[c]) or 0
                            else
                                cur.sow = (f[c] ~= "" and f[c] ~= nil) and 1 or 0
                            end
                            t.blocks[r0][c0] = cur
                        end
                    end
                end
            elseif section == "结果" then
                local e = parse_result_line(f)
                if e then
                    e.r, e.c = e.r - 1, e.c - 1     -- 1基->0基
                    if e.r >= 0 and e.c >= 0 then
                        t.results[#t.results + 1] = e
                    end
                end
            end
        end
    end
    if t.name == nil then msgs[#msgs + 1] = "E:信息区缺名称" end
    if t.map == nil then msgs[#msgs + 1] = "E:信息区缺地图" end
    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return t, msgs
end

csv.render_result_line = render_result_line
csv.parse_result_line  = parse_result_line

return csv
