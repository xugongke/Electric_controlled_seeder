--[[
pathalgo.lua —— 路径算法层: createPath 六种 + startNode 逐排预置参数（B档）
================================================================================
逐函数对齐 QT 源码:
  create_path      <- dialogrealtimetask.cpp:913 createPath(pathType 0~5)
  column_direction <- dialogrealtimetask.cpp:1180 (作业中从 path 序列查列方向)
  is_sow           <- task.cpp:344 Task::isSow (组内任一块 sow 且 state∈{0,1})
  density          <- task.cpp:373 Task::density (图外/不播/微调三态)
  start_node       <- dialogrealtimetask.cpp:701 startNode (当前排+下一排参数组)
  fwd_start/bwd_start/start_pos <- map.cpp:733/747/755
坐标全 0 基。纯函数无副作用, 依赖全部经参数注入。
--]]

local pathalgo = {}

local function bet(m)   -- 一趟组宽 = MachineColumn/BlockColumn
    return math.max(1, math.floor((m.machine_cols or 1) / (m.block_col or 1)))
end
pathalgo.block_each_trip = bet

-------------------------------------------------------------------- createPath
-- 生成有序作业序列 { {row=, column=组起点列, positive=行进方向bool} ... }
-- positive=true: row 0→rows-1 递增; false: rows-1→0 递减
local function emit(path, rows, col, positive)
    -- (2026-10-10对齐QT实测: 播种方向=正 -> 从末排(5,1)起向排号减小;
    --  反向 -> 从首排(1,1)起向排号增大; 与用户QT联调观察一致)
    if positive then
        for r = rows - 1, 0, -1 do path[#path + 1] = { row = r, column = col, positive = true } end
    else
        for r = 0, rows - 1 do path[#path + 1] = { row = r, column = col, positive = false } end
    end
end

function pathalgo.create_path(m, path_type, positive)
    local path = {}
    local b = bet(m)
    local rows = m.rows
    local trip = math.floor(m.cols / b)      -- QT: trip=cols/blockEachTrip 整除
    local cols = {}
    local dirs = {}

    if path_type == 0 then
        -- 梭形交替(左起): 0正,1反,2正...
        local i = 0
        while i < trip do
            cols[#cols + 1] = b * i;  i = i + 1;  dirs[#dirs + 1] = positive
            if i == trip then break end
            cols[#cols + 1] = b * i;  i = i + 1;  dirs[#dirs + 1] = not positive
        end
    elseif path_type == 1 then
        -- 全同向(左起)
        for i = 0, trip - 1 do
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 2 then
        -- 中间分两侧, 左半先(左端进出): 0正,trip-1反,1正,trip-2反...
        local i = 0
        while i < trip / 2 do
            cols[#cols + 1] = b * i;            dirs[#dirs + 1] = positive
            cols[#cols + 1] = b * (trip - 1 - i); dirs[#dirs + 1] = not positive
            i = i + 1
        end
        if trip % b == 1 then                   -- QT 奇数剩余趟判断(照抄)
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 3 then
        -- 梭形交替(右起): trip-1正,trip-2反...
        local i = trip - 1
        while i >= 0 do
            cols[#cols + 1] = b * i;  i = i - 1;  dirs[#dirs + 1] = positive
            if i < 0 then break end
            cols[#cols + 1] = b * i;  i = i - 1;  dirs[#dirs + 1] = not positive
        end
    elseif path_type == 4 then
        -- 全同向(右起)
        for i = trip - 1, 0, -1 do
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 5 then
        -- 中间分两侧, 右半先(右端进出): trip-1正,0反,trip-2正,1反...
        local i = 0
        while i < trip / 2 do
            cols[#cols + 1] = b * (trip - 1 - i); dirs[#dirs + 1] = positive
            cols[#cols + 1] = b * i;              dirs[#dirs + 1] = not positive
            i = i + 1
        end
        if trip % b == 1 then
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    else
        return nil, "路径类型非法"
    end

    for k = 1, #cols do emit(path, rows, cols[k], dirs[k]) end
    return path
end

-- 作业中查列方向 (dialogrealtimetask.cpp:1180)
function pathalgo.column_direction(path, column)
    for _, pn in ipairs(path) do
        if pn.column == column then return pn.positive end
    end
    return true
end

-------------------------------------------------------------------- isSow/density
-- task.blocks[r][c] = { state=0/1/2/3, sow=0/1 }
function pathalgo.is_sow(task, m, row, column, b)
    if row >= 0 and row < m.rows then
        for i = 0, bet(m) - 1 do
            local blk = task.blocks[row] and task.blocks[row][column + i]
            -- 组内任一未完成且需播种 → 该组需播 (QT task.cpp:354)
            if blk and blk.sow == 1 and (blk.state == 0 or blk.state == 1) then
                return true
            end
        end
        return false
    end
    return b          -- 图外: 由"出图播种"开关决定
end

-- fine_tune: {{origin,specified,enabled}...} 密度微调映射(可为nil)
function pathalgo.density(task, m, row, column, b, fine_tune)
    local d
    if b then
        if row < 0 then
            d = m.blocks[0][column].density          -- 图外上侧: 首排密度
        elseif row < m.rows then
            d = pathalgo.is_sow(task, m, row, column, b)
                and m.blocks[row][column].density or 0
        else
            d = m.blocks[m.rows - 1][column].density  -- 图外下侧: 末排密度
        end
    else
        if row >= 0 and row < m.rows then
            d = pathalgo.is_sow(task, m, row, column, b)
                and m.blocks[row][column].density or 0
        else
            d = -1                                    -- 图外不播
        end
    end
    if fine_tune then
        for _, ft in ipairs(fine_tune) do
            if ft.enabled and ft.origin == d then return ft.specified end
        end
    end
    return d
end

-------------------------------------------------------------------- 起始位置
-- 正向累计: row<0 图外按首排+首过道倒推; row>=0 图内 sum(rowlen[i]+aisle[i+1])
function pathalgo.fwd_start(m, row)
    local d = 0
    if row < 0 then
        for _ = row + 1, -1 do                -- QT: i++<0 → row=-1 计0次, row=-2 计1次
            d = d - (m.rowlen[1] + m.aisle[1])
        end
    else
        for i = 0, row - 1 do
            if i < m.rows then
                d = d + m.rowlen[i + 1] + m.aisle[i + 2]
            else
                d = d + m.rowlen[m.rows] + m.aisle[m.rows + 1]
            end
        end
    end
    return d
end

-- 反向起点 = 正向累计 + 本排排长 (图外负排用首排长)
function pathalgo.bwd_start(m, row)
    if row < 0 then
        return pathalgo.fwd_start(m, row) + m.rowlen[1]
    end
    local ri = (row < m.rows) and row or (m.rows - 1)
    return pathalgo.fwd_start(m, row) + m.rowlen[ri + 1]
end

-- AB 参考: ab = { has=bool, dir=bool, a_row=int } (无AB时 a_row=outset排)
function pathalgo.start_pos(m, row, d, ab)
    -- (2026-10-10最终: 绝对行程体系 —— StartPOS=目标排播种位全图绝对位置
    -- (1,1端地头=0): 正向排上沿fwd(row); 反向排下沿fwd(row)+排长.
    --  模拟器按绝对值引导(StartPOS±800预备段), 触发=绝对位置比较;
    --  显示: 正向0递增/反向从全图长+预备递减(正数)
    if d then
        return pathalgo.fwd_start(m, row)
    end
    local ri = (row >= 0 and row < m.rows) and row or (m.rows - 1)
    return pathalgo.fwd_start(m, row) + (m.rowlen[ri + 1] or 0)
end

-------------------------------------------------------------------- startNode
-- 逐排预置参数组 (dialogrealtimetask.cpp:701 BZCellParaType_st 语义字段)
-- 返回 table 供 codec.pack_bzcell 打包 0x20 下发
-- task: store 任务(含 blocks/sow_exceed); m: 地图; path: create_path 产物
-- row/column: 当前节点 0 基; ab: AB 参考; fine_tune: 密度微调
function pathalgo.start_node(task, m, path, row, column, ab, fine_tune)
    local b = (task.sow_exceed == 1)          -- 出图播种开关
    local d = pathalgo.column_direction(path, column)
    local rows = m.rows
    local bc = m.block_col or 1
    local ncol = m.machine_cols               -- maxSowColumn 播种行数

    local function dens_vec(r)
        local t = {}
        for i = 0, ncol - 1 do
            t[i + 1] = pathalgo.density(task, m, r, column + math.floor(i / bc), b, fine_tune)
        end
        return t
    end

    local p = {}
    p.TXFlag = (not ab.has) and 1 or ((d == ab.dir) and 1 or 0)
    p.isAfterNextZoneSow = pathalgo.is_sow(task, m, d and (row + 2) or (row - 2), column, b) and 1 or 0
    p.RowNum = row
    p.DisplayRowNum = rows - row

    if row >= 0 and row < rows then
        -- 当前排在图内
        if d then
            p.FinalFlag = (b or row >= rows - 1) and 1 or 0
            p.InS = m.aisle[row + 1]
        else
            p.FinalFlag = (b or row <= 0) and 1 or 0
            p.InS = m.aisle[row + 2]
        end
        p.Density = dens_vec(row)
        p.CellLen = m.rowlen[row + 1]
    else
        -- 当前排在图外
        p.FinalFlag = b and 0 or 1
        if d then
            p.InS = m.aisle[rows + 1]
            p.Density = dens_vec(rows)        -- 图外: 末排密度(t.density row>=rows 分支)
            p.CellLen = m.rowlen[rows]
        else
            p.InS = m.aisle[1]
            p.Density = dens_vec(0)           -- 图外: 首排密度(反向 row<=-1? 主段用0行)
            p.CellLen = m.rowlen[1]
        end
    end
    p.StartPOS = pathalgo.start_pos(m, p.RowNum, d, ab)

    p.NextRowNum = d and (row + 1) or (row - 1)
    p.NextDisplayRowNum = rows - p.NextRowNum
    local nr = p.NextRowNum
    if nr >= 0 and nr < rows then
        -- 下一排在图内
        if d then
            p.NextFinalFlag = ((not b) and nr < rows - 1) and 0 or 1
            p.NextInS = m.aisle[nr + 2]
        else
            p.NextFinalFlag = ((not b) and nr > 0) and 0 or 1
            p.NextInS = m.aisle[nr + 1]
        end
        p.NextDensity = dens_vec(nr)
        p.NextCellLen = m.rowlen[nr + 1]
    else
        -- 下一排在图外
        p.NextFinalFlag = b and 0 or 1
        if d then
            p.NextInS = m.aisle[rows + 1]
            p.NextDensity = dens_vec(rows)
            p.NextCellLen = m.rowlen[rows]
        else
            p.NextInS = m.aisle[1]
            p.NextDensity = dens_vec(-1)      -- QT: 反向图外 Next 用 density(-1) → b?0:-1
            p.NextCellLen = m.rowlen[1]
        end
    end
    p.NextCellStartPOS = pathalgo.start_pos(m, nr, d, ab)
    return p
end

return pathalgo
