--[[
mapdraw.lua —— 地图绘制纯函数模块(2026-10-13 M2, 任务向导拆页重构)
================================================================================
职责: (地图, 任务块状态, 视图选项) -> 平台无关绘制指令数组; 屏端由
page_taskmgr/page_sowrt 的 on_drawctrl 薄壳逐指令翻译为 draw_* 调用
(隔离平台API签名风险, PC/lupa可完整单测)。

指令集(op):
  rect  x0 y0 x1 y1 fill(0边框/1填充) color(rgb565)
  arect x0 y0 x1 y1 alpha(0~255)              半透明叠加(轨迹)
  line  x0 y0 x1 y1 w color
  text  s x y w h size color align(0左/1中/2右)  (字符串为GB2312字节)

QT对照(dialogrealtimetask.cpp:55-135 QTableView网格):
  状态色: 0待播灰 / 1已下发蓝 / 2完成绿 / 3中断橙红; 不播小区深灰
  排标签 = "排"+(rows-r) 倒序; 列标签 = "列"+(c+1)
  视图: 排列"排-列" / 编号 / 密度(QT comboBoxView 三态)
布局: 均匀网格 + 排间过道灰带(比例带), 排/列标签沿边, fit-scale居中。
纯函数零平台依赖: 不用 string.rep/gsub/gmatch(屏端裁剪), 不触碰LW。
--]]

local mapdraw = {}

-- 状态色(RGB888 -> 由适配层rgb565转换; 此处直接给rgb565换算用888分量)
mapdraw.COLORS = {
    pending = { 192, 192, 192 },   -- 0 待播 灰
    running = { 0, 112, 192 },     -- 1 已下发 蓝
    done    = { 34, 139, 34 },     -- 2 完成 绿
    broken  = { 237, 108, 36 },    -- 3 中断 橙红
    nosow   = { 64, 64, 64 },      -- 不播 深灰
    aisle   = { 228, 228, 228 },   -- 过道带 更浅灰(与待播灰拉开)
    grid    = { 0, 0, 0 },         -- 网格线/文字 黑
    label   = { 0, 0, 0 },
    outset  = { 255, 200, 0 },     -- 起点标记 黄
    machine = { 255, 0, 0 },       -- 农机标记 红
    trail   = { 34, 139, 34 },     -- 轨迹叠加 绿
}

function mapdraw.rgb565(r, g, b)
    return ((r // 8) << 11) | ((g // 4) << 5) | (b // 8)
end

-------------------------------------------------------------------- 偏移->行
-- 累计偏移(排起点坐标系)处的排号; 落在过道/越界返回 nil
-- (QT map.cpp offsetToRow: -999999哨兵语义此处用nil表达)
function mapdraw.row_at(m, off)
    if not m or not m.rows or off == nil or off < 0 then return nil end
    local pos = 0
    for r = 0, m.rows - 1 do
        local rl = m.rowlen[r + 1] or 0
        -- 下界off>=pos不可省: 否则排后过道区间会误命中下一排
        if off >= pos and off < pos + rl then return r end
        pos = pos + rl + (m.aisle[r + 2] or 0)
    end
    return nil
end

-- 图外感知版(QT :374-382: 过道=-999999隐藏, 图外夹取-1/rows仍显示):
-- off<0 -> -1(图前); 越过末排终点 -> rows(图后); 排间过道 -> nil
function mapdraw.row_at_edge(m, off)
    if not m or not m.rows or off == nil then return nil end
    if off < 0 then return -1 end
    local pos = 0
    for r = 0, m.rows - 1 do
        local rl = m.rowlen[r + 1] or 0
        if off < pos + rl then return r end
        pos = pos + rl
        local gap = m.aisle[r + 2] or 0
        if r < m.rows - 1 and off < pos + gap then
            return nil                        -- 排间过道(隐藏)
        end
        pos = pos + gap
    end
    return m.rows                             -- 末排之后(图后夹取)
end

-------------------------------------------------------------------- 布局
-- fit-scale: 均匀网格 + 排间过道带(AISLE_FRAC*ch, 至少4px), 排/列标签边距
local AISLE_FRAC = 0.22                          -- 过道带比例(收窄,
                                                 --   2026-10-14样式重设计)
local LABEL_W, LABEL_H = 22, 18
local PAD = 4                                    -- 画布内边距(防控件
                                                 --   边框裁剪最外圈)

function mapdraw.layout(m, w, h)
    local rows, cols = m.rows or 1, m.cols or 1
    local iw, ih = w - LABEL_W - 2 * PAD, h - LABEL_H - 2 * PAD
    if iw < 20 or ih < 20 then return nil end
    local ch = ih // (rows + math.floor(AISLE_FRAC * (rows + 1)) + 1)
    if ch < 6 then ch = 6 end
    local aisle = math.max(4, math.floor(ch * AISLE_FRAC))
    local total_h = rows * ch + (rows + 1) * aisle
    if total_h > ih then                     -- 极端多排: 压缩过道
        aisle = math.max(2, (ih - rows * ch) // (rows + 1))
        total_h = rows * ch + (rows + 1) * aisle
    end
    local cw = iw // cols
    if cw < 6 then cw = 6 end
    return {
        x0 = LABEL_W + PAD + (iw - cw * cols) // 2,
        y0 = LABEL_H + PAD + (ih - total_h) // 2,
        cw = cw, ch = ch, aisle = aisle,
        rows = rows, cols = cols,
    }
end

local function cell_rect(g, r, c)
    local x = g.x0 + c * g.cw
    local y = g.y0 + (r + 1) * g.aisle + r * (g.ch + g.aisle)
    return x, y, x + g.cw - 1, y + g.ch - 1
end
mapdraw.cell_rect = cell_rect

-------------------------------------------------------------------- 指令生成
-- m: store地图; t: store任务(可nil=无任务纯地图); opts:
--   view     'arrange'|'num'|'density'
--   machine  {row=,col=}(可nil)
--   trail    {{row=,col=},...}(可nil)
--   outset   {r=,c=}(可nil, 缺省取t.outset)
local function state_color(m, t, r, c)
    local b = m.blocks and m.blocks[r] and m.blocks[r][c]
    if not b or b.sow == 0 then return mapdraw.COLORS.nosow end
    if not t or not t.blocks or not t.blocks[r] then
        return mapdraw.COLORS.pending
    end
    local tb = t.blocks[r][c]
    local st = tb and tb.state or 0
    if st == 2 then return mapdraw.COLORS.done end
    if st == 3 then return mapdraw.COLORS.broken end
    if st == 1 then return mapdraw.COLORS.running end
    return mapdraw.COLORS.pending
end

function mapdraw.cmds(m, t, opts)
    opts = opts or {}
    -- minimap开启即走视口路径(viewp=nil=居中适配, 缩略图/红框常显)
    if opts.viewp or opts.minimap then return mapdraw.cmds_vp(m, t, opts) end
    local out = {}
    local g = mapdraw.layout(m, opts.w or 500, opts.h or 380)
    if not g then return out, nil end

    -- 底白 + 过道带(整幅横条, 含首尾)
    out[#out + 1] = { op = 'rect', x0 = 0, y0 = 0,
                      x1 = (opts.w or 500) - 1, y1 = (opts.h or 380) - 1,
                      fill = 1, color = mapdraw.rgb565(255, 255, 255) }
    local ac = mapdraw.rgb565(mapdraw.COLORS.aisle[1],
                              mapdraw.COLORS.aisle[2], mapdraw.COLORS.aisle[3])
    local gx1 = g.x0 + g.cols * g.cw - 1
    for i = 0, g.rows do
        local y = g.y0 + i * (g.ch + g.aisle)
        out[#out + 1] = { op = 'rect', x0 = g.x0, y0 = y,
                          x1 = gx1, y1 = y + g.aisle - 1, fill = 1, color = ac }
    end

    -- 小区色块
    for r = 0, g.rows - 1 do
        for c = 0, g.cols - 1 do
            local col = state_color(m, t, r, c)
            local x0, y0, x1, y1 = cell_rect(g, r, c)
            -- 满格填充(2026-10-14: 原内缩1px+贯穿线在视觉上产生错位感;
            --   改QT式满格无缝, 格界靠颜色差与过道带表达)
            out[#out + 1] = { op = 'rect', x0 = x0, y0 = y0,
                              x1 = x1, y1 = y1, fill = 1,
                              color = mapdraw.rgb565(col[1], col[2], col[3]) }
        end
    end

    -- 每格细边框(2026-10-14: 满格填充后的格子感; 中大图省略保指令量:
    --   <=200格画边框, 更大只靠色块)
    local kc = mapdraw.rgb565(mapdraw.COLORS.grid[1],
                              mapdraw.COLORS.grid[2], mapdraw.COLORS.grid[3])
    if g.rows * g.cols <= 200 and g.cw >= 8 and g.ch >= 8 then
        for r = 0, g.rows - 1 do
            for c = 0, g.cols - 1 do
                local x0, y0, x1, y1 = cell_rect(g, r, c)
                out[#out + 1] = { op = 'rect', x0 = x0, y0 = y0,
                                  x1 = x1, y1 = y1, fill = 0, color = kc }
            end
        end
    end

    -- 排/列标签(排显示号=rows-r, 与QT表头一致)
    local lc = mapdraw.rgb565(mapdraw.COLORS.label[1],
                              mapdraw.COLORS.label[2], mapdraw.COLORS.label[3])
    if g.ch >= 14 then
        for r = 0, g.rows - 1 do
            local _, y0, _, y1 = cell_rect(g, r, 0)
            out[#out + 1] = { op = 'text', s = tostring(g.rows - r),
                              x = 0, y = y0, w = LABEL_W - 2,
                              h = g.ch, size = math.min(16, g.ch),
                              color = lc, align = 1 }
        end
    end
    if g.cw >= 18 then
        for c = 0, g.cols - 1 do
            local x0 = g.x0 + c * g.cw
            out[#out + 1] = { op = 'text', s = tostring(c + 1),
                              x = x0, y = 0, w = g.cw, h = LABEL_H - 2,
                              size = 14, color = lc, align = 1 }
        end
    end

    -- 格内视图文字(格子足够大才画)
    local view = opts.view or 'arrange'
    if g.cw >= 44 and g.ch >= 22 then
        for r = 0, g.rows - 1 do
            for c = 0, g.cols - 1 do
                local b = m.blocks and m.blocks[r] and m.blocks[r][c]
                if b and b.sow ~= 0 then
                    local s
                    if view == 'num' then
                        s = tostring(b.num or 0)
                    elseif view == 'density' then
                        s = tostring(b.density or 0)
                    else
                        s = tostring(g.rows - r) .. "-" .. tostring(c + 1)
                    end
                    local x0, y0, x1, y1 = cell_rect(g, r, c)
                    out[#out + 1] = { op = 'text', s = s, x = x0, y = y0,
                                      w = g.cw, h = g.ch,
                                      size = math.min(16, g.ch - 4),
                                      color = mapdraw.rgb565(255, 255, 255),
                                      align = 1 }
                end
            end
        end
    end

    -- 起点标记(2026-10-16十六修: 粗框4线w=3 + V形指示行进方向,
    -- outset_dir=true行号增=V尖朝下; 小格退化为粗框无V)
    local os_ = opts.outset or (t and t.outset or nil)
    if os_ and os_.r >= 0 and os_.r < g.rows and os_.c >= 0
       and os_.c < g.cols then
        local x0, y0, x1, y1 = cell_rect(g, os_.r, os_.c)
        local oc = mapdraw.rgb565(mapdraw.COLORS.outset[1],
                                  mapdraw.COLORS.outset[2],
                                  mapdraw.COLORS.outset[3])
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y0,
                          x1 = x1, y1 = y0, w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y1,
                          x1 = x1, y1 = y1, w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y0,
                          x1 = x0, y1 = y1, w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x1, y0 = y0,
                          x1 = x1, y1 = y1, w = 3, color = oc }
        if g.cw >= 16 and g.ch >= 12 then
            local cx = (x0 + x1) // 2
            local sg = opts.outset_dir and 1 or -1
            local cy = (y0 + y1) // 2
            local h = g.ch // 4
            out[#out + 1] = { op = 'line', x0 = cx - h,
                              y0 = cy - sg * h, x1 = cx, y1 = cy + sg * h,
                              w = 3, color = oc }
            out[#out + 1] = { op = 'line', x0 = cx + h,
                              y0 = cy - sg * h, x1 = cx, y1 = cy + sg * h,
                              w = 3, color = oc }
        end
    end

    -- 轨迹显示已移除(2026-10-14用户要求: 只显示小车位置, 经过小区不变色)

    -- 农机标记与四周图外显示已删除(2026-10-15用户要求)

    return out, g
end


-------------------------------------------------------------------- 视口(M40)
-- 大排列数根治: 世界坐标系(1格=1单位见方, 过道带=AISLE_FRAC格高)上取
-- 视口{cx,cy中心, scale每格像素}, cmds只画相交区间, 指令量与画布面积
-- 成正比、与世界尺寸无关。opts.viewp=nil回落整图适配(旧路径不变)。
-- 视图控制器 pan/zoom/center_on 供三页 on_update(LW.MV按钮)调用。

local MINI_W = 96                          -- 缩略条宽(画布右侧)
local VP_MARGIN = 0.75                     -- 视口越界余量(格)

function mapdraw.world_size(m)
    local rows, cols = m.rows or 1, m.cols or 1
    return cols, rows * (1 + AISLE_FRAC) + AISLE_FRAC
end

-- 适配缩放(每格像素, 方格), 上限32下限2
function mapdraw.fit_scale(m, vw, vh)
    local ww, wh = mapdraw.world_size(m)
    local s = math.min(vw / ww, vh / wh)
    if s > 32 then s = 32 end
    if s < 2 then s = 2 end
    return s
end

-- 缩放步进: dir=1放大/-1缩小; 返回nil=适配(缩过适配档即回落适配)
local ZOOMS = { 8, 12, 18, 26, 36, 48, 64 }   -- 固定档位表(用户偏好M45)

function mapdraw.zoom_step(fit, cur, dir)
    -- 档位表+最小观感步进1.2x: 跳过与当前档过近的档(M41教训: fit被32
    -- 上限截住时36-32仅+12%肉眼不可辨, 真机"按大不放大"观感根因);
    -- fit态缩小直接回落适配(nil)
    if dir > 0 then
        local base = cur or fit
        for i = 1, #ZOOMS do
            if ZOOMS[i] >= base * 1.2 then return ZOOMS[i] end
        end
        return cur or fit                       -- 已到最大档
    end
    if not cur then return nil end              -- 适配已最小(M41: 原nil比较
                                                --   崩溃, 真机报on_update异常)
    for i = #ZOOMS, 1, -1 do
        if ZOOMS[i] < cur / 1.2 then
            if ZOOMS[i] <= fit then return nil end
            return ZOOMS[i]
        end
    end
    return nil
end

-- 主视区矩形(让出排/列标签边距; 缩略图开启再让出右侧竖条)
function mapdraw.view_rect(w, h, minimap)
    local vw = w - LABEL_W - 2 * PAD - (minimap and (MINI_W + PAD) or 0)
    return LABEL_W + PAD, LABEL_H + PAD, vw, h - LABEL_H - 2 * PAD
end

local function clamp_center(cx, cy, ww, wh, uw, uh)
    if uw >= ww then cx = ww / 2
    else
        local lo, hi = uw / 2 - VP_MARGIN, ww - uw / 2 + VP_MARGIN
        if cx < lo then cx = lo elseif cx > hi then cx = hi end
    end
    if uh >= wh then cy = wh / 2
    else
        local lo, hi = uh / 2 - VP_MARGIN, wh - uh / 2 + VP_MARGIN
        if cy < lo then cy = lo elseif cy > hi then cy = hi end
    end
    return cx, cy
end

-- 视口投影: 世界左上(x0,y0)+scale+主视区屏幕矩形; nil视图=居中适配
function mapdraw.projection(m, w, h, view, minimap)
    local vx0, vy0, vw, vh = mapdraw.view_rect(w, h, minimap)
    local ww, wh = mapdraw.world_size(m)
    local scale = (view and view.scale) or mapdraw.fit_scale(m, vw, vh)
    local uw, uh = vw / scale, vh / scale
    local x0, y0
    if view then
        x0, y0 = view.cx - uw / 2, view.cy - uh / 2
    else
        x0, y0 = (ww - uw) / 2, (wh - uh) / 2
    end
    x0, y0 = clamp_center(x0 + uw / 2, y0 + uh / 2, ww, wh, uw, uh)
    return { x0 = x0 - uw / 2, y0 = y0 - uh / 2, scale = scale,
             vx0 = vx0, vy0 = vy0, vw = vw, vh = vh, uw = uw, uh = uh }
end

function mapdraw.pan(view, m, w, h, minimap, dxf, dyf)
    local p = mapdraw.projection(m, w, h, view, minimap)
    local cx = (view and view.cx) or (p.x0 + p.uw / 2)
    local cy = (view and view.cy) or (p.y0 + p.uh / 2)
    return mapdraw.center_scale(m, cx + dxf * p.uw, cy + dyf * p.uh,
                                p.scale, w, h, minimap)
end

function mapdraw.zoom(view, m, w, h, minimap, dir)
    local vx0, vy0, vw, vh = mapdraw.view_rect(w, h, minimap)
    local fit = mapdraw.fit_scale(m, vw, vh)
    local scale = mapdraw.zoom_step(fit, view and view.scale, dir)
    if not scale then return nil end
    local p = mapdraw.projection(m, w, h, view, minimap)
    local cx = (view and view.cx) or (p.x0 + p.uw / 2)
    local cy = (view and view.cy) or (p.y0 + p.uh / 2)
    return mapdraw.center_scale(m, cx, cy, scale, w, h, minimap)
end

-- 居中于格(r,c)(跟随用)并保持现缩放(nil取适配)
function mapdraw.center_on(view, m, w, h, minimap, r, c)
    local p = mapdraw.projection(m, w, h, view, minimap)
    return mapdraw.center_scale(m, c + 0.5,
        r * (1 + AISLE_FRAC) + AISLE_FRAC + 0.5, p.scale, w, h, minimap)
end

-- 以给定世界点为中心/缩放构造视图(夹取越界)
function mapdraw.center_scale(m, cx, cy, scale, w, h, minimap)
    local vx0, vy0, vw, vh = mapdraw.view_rect(w, h, minimap)
    local ww, wh = mapdraw.world_size(m)
    cx, cy = clamp_center(cx, cy, ww, wh, vw / scale, vh / scale)
    return { cx = cx, cy = cy, scale = scale }
end

-- 行概览色(缩略图行带): done>broken>running>pending, 全不播深灰
local function row_overview(m, t, r)
    local row = m.blocks and m.blocks[r]
    if not row then return mapdraw.COLORS.pending end
    local pri, best = 0, nil
    local any = false
    for c = 0, (m.cols or 1) - 1 do
        local b = row[c]
        if b and b.sow ~= 0 then
            any = true
            local st = 0
            if t and t.blocks and t.blocks[r] then
                local tb = t.blocks[r][c]
                st = tb and tb.state or 0
            end
            local p = (st == 2 and 4) or (st == 3 and 3) or (st == 1 and 2) or 1
            if p > pri then pri, best = p, st end
        end
    end
    if not any then return mapdraw.COLORS.nosow end
    if best == 2 then return mapdraw.COLORS.done end
    if best == 3 then return mapdraw.COLORS.broken end
    if best == 1 then return mapdraw.COLORS.running end
    return mapdraw.COLORS.pending
end

-- 视口模式指令生成
function mapdraw.cmds_vp(m, t, opts)
    local out = {}
    local w, h = opts.w or 500, opts.h or 380
    local minimap = opts.minimap and true or false
    local p = mapdraw.projection(m, w, h, opts.viewp, minimap)
    local g = AISLE_FRAC
    local rows, cols = m.rows or 1, m.cols or 1
    out[#out + 1] = { op = 'rect', x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1,
                      fill = 1, color = mapdraw.rgb565(255, 255, 255) }
    local function sx(wx) return p.vx0 + (wx - p.x0) * p.scale end
    local function sy(wy) return p.vy0 + (wy - p.y0) * p.scale end
    -- 可见区间(世界坐标反解)
    local wy1 = p.y0 + p.uh
    local wx1 = p.x0 + p.uw
    local r0 = math.floor((p.y0 - 1 - g) / (1 + g)) + 1
    local r1 = math.ceil((wy1 - g) / (1 + g)) - 1
    local c0 = math.floor(p.x0)
    local c1 = math.ceil(wx1) - 1
    if r0 < 0 then r0 = 0 end
    if r1 > rows - 1 then r1 = rows - 1 end
    if c0 < 0 then c0 = 0 end
    if c1 > cols - 1 then c1 = cols - 1 end
    -- 过道带(可见的; 带高不足1px跳过)
    if g * p.scale >= 1 then
        local ac = mapdraw.rgb565(mapdraw.COLORS.aisle[1],
                                  mapdraw.COLORS.aisle[2],
                                  mapdraw.COLORS.aisle[3])
        local bx0 = sx(math.max(p.x0, 0))
        local bx1 = sx(math.min(wx1, cols)) - 1
        local i0 = math.floor(p.y0 / (1 + g))
        local i1 = math.ceil(wy1 / (1 + g)) - 1
        if i0 < 0 then i0 = 0 end
        if i1 > rows then i1 = rows end
        for i = i0, i1 do
            local yy = sy(i * (1 + g))
            out[#out + 1] = { op = 'rect', x0 = bx0, y0 = yy,
                              x1 = bx1, y1 = yy + g * p.scale - 1,
                              fill = 1, color = ac }
        end
    end
    -- 小区色块(可见区间; 指令量=可见格数, 与世界尺寸无关)
    for r = r0, r1 do
        local yy0 = sy(r * (1 + g) + g)
        local yy1 = yy0 + p.scale - 1
        for c = c0, c1 do
            local col = state_color(m, t, r, c)
            local xx0 = sx(c)
            out[#out + 1] = { op = 'rect', x0 = xx0, y0 = yy0,
                              x1 = xx0 + p.scale - 1, y1 = yy1, fill = 1,
                              color = mapdraw.rgb565(col[1], col[2], col[3]) }
        end
    end
    -- 格边框(可见格<=200才画, 沿用整图模式规则)
    local kc = mapdraw.rgb565(mapdraw.COLORS.grid[1],
                              mapdraw.COLORS.grid[2], mapdraw.COLORS.grid[3])
    if (r1 - r0 + 1) * (c1 - c0 + 1) <= 200 and p.scale >= 8 then
        for r = r0, r1 do
            for c = c0, c1 do
                local xx0, yy0 = sx(c), sy(r * (1 + g) + g)
                out[#out + 1] = { op = 'rect', x0 = xx0, y0 = yy0,
                                  x1 = xx0 + p.scale - 1,
                                  y1 = yy0 + p.scale - 1, fill = 0, color = kc }
            end
        end
    end
    -- 排标签(排显示号=rows-r, 与QT表头一致)
    local lc = mapdraw.rgb565(mapdraw.COLORS.label[1],
                              mapdraw.COLORS.label[2], mapdraw.COLORS.label[3])
    if p.scale >= 14 then
        for r = r0, r1 do
            out[#out + 1] = { op = 'text', s = tostring(rows - r),
                              x = 0, y = sy(r * (1 + g) + g), w = LABEL_W - 2,
                              h = p.scale, size = math.min(16, p.scale),
                              color = lc, align = 1 }
        end
    end
    if p.scale >= 18 then
        for c = c0, c1 do
            out[#out + 1] = { op = 'text', s = tostring(c + 1),
                              x = sx(c), y = 0, w = p.scale, h = LABEL_H - 2,
                              size = 14, color = lc, align = 1 }
        end
    end
    -- 格内视图文字(格子足够大)
    local view = opts.view or 'arrange'
    if p.scale >= 44 then
        for r = r0, r1 do
            for c = c0, c1 do
                local b = m.blocks and m.blocks[r] and m.blocks[r][c]
                if b and b.sow ~= 0 then
                    local s
                    if view == 'num' then
                        s = tostring(b.num or 0)
                    elseif view == 'density' then
                        s = tostring(b.density or 0)
                    else
                        s = tostring(rows - r) .. "-" .. tostring(c + 1)
                    end
                    out[#out + 1] = { op = 'text', s = s, x = sx(c),
                                      y = sy(r * (1 + g) + g), w = p.scale,
                                      h = p.scale, size = 16,
                                      color = mapdraw.rgb565(255, 255, 255),
                                      align = 1 }
                end
            end
        end
    end
    -- 起点标记(粗框4线+V形, 小格退化为粗框; 与整图模式同款)
    local os_ = opts.outset or (t and t.outset or nil)
    if os_ and os_.r >= 0 and os_.r < rows and os_.c >= 0
       and os_.c < cols and os_.r >= r0 and os_.r <= r1
       and os_.c >= c0 and os_.c <= c1 then
        local x0 = sx(os_.c)
        local y0 = sy(os_.r * (1 + g) + g)
        local x1 = x0 + p.scale - 1
        local y1 = y0 + p.scale - 1
        local oc = mapdraw.rgb565(mapdraw.COLORS.outset[1],
                                  mapdraw.COLORS.outset[2],
                                  mapdraw.COLORS.outset[3])
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y0, x1 = x1, y1 = y0,
                          w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y1, x1 = x1, y1 = y1,
                          w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y0, x1 = x0, y1 = y1,
                          w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x1, y0 = y0, x1 = x1, y1 = y1,
                          w = 3, color = oc }
        if p.scale >= 16 then
            local cx = (x0 + x1) // 2
            local sg = opts.outset_dir and 1 or -1
            local cy = (y0 + y1) // 2
            local hh = p.scale // 4
            out[#out + 1] = { op = 'line', x0 = cx - hh, y0 = cy - sg * hh,
                              x1 = cx, y1 = cy + sg * hh, w = 3, color = oc }
            out[#out + 1] = { op = 'line', x0 = cx + hh, y0 = cy - sg * hh,
                              x1 = cx, y1 = cy + sg * hh, w = 3, color = oc }
        end
    end
    -- 缩略图(右侧竖条): 行带概览色 + 视口红框, "完整看全图"
    if minimap then
        local mx0 = w - PAD - MINI_W
        local my0 = LABEL_H + PAD
        local my1 = h - PAD
        local wrc = mapdraw.rgb565(255, 0, 0)
        out[#out + 1] = { op = 'rect', x0 = mx0, y0 = my0, x1 = w - PAD,
                          y1 = my1, fill = 1,
                          color = mapdraw.rgb565(255, 255, 255) }
        out[#out + 1] = { op = 'rect', x0 = mx0, y0 = my0, x1 = w - PAD,
                          y1 = my1, fill = 0, color = kc }
        local ww, wh = mapdraw.world_size(m)
        local bh = (my1 - my0) / (rows + 1)
        for r = 0, rows - 1 do
            local col = row_overview(m, t, r)
            local yy = my0 + (r + 1) * bh
            out[#out + 1] = { op = 'rect', x0 = mx0 + 2, y0 = yy,
                              x1 = w - PAD - 2, y1 = yy + bh,
                              fill = 1,
                              color = mapdraw.rgb565(col[1], col[2], col[3]) }
        end
        -- 视口红框(世界->缩略条仿射)
        local fx0 = mx0 + 2 + math.max(p.x0, 0) / cols * (MINI_W - 4)
        local fx1 = mx0 + 2 + math.min(wx1, cols) / cols * (MINI_W - 4)
        local fy0 = my0 + math.max(p.y0, 0) / wh * (my1 - my0)
        local fy1 = my0 + math.min(wy1, wh) / wh * (my1 - my0)
        out[#out + 1] = { op = 'rect', x0 = fx0, y0 = fy0, x1 = fx1,
                          y1 = fy1, fill = 0, color = wrc }
    end
    return out, p
end

-------------------------------------------------------------------- 平台适配
-- cmds -> draw_* 翻译(on_draw回调内调用; PC/lupa无绘图API时整段跳过)。
-- draw_text charcode=1: 指令字符串为GB2312字节(lua源文件即GB18030)
function mapdraw.render(cmds, ox, oy)
    -- ox/oy: 画布控件在画面中的原点(2026-10-13用户实测: draw_*为整画面
    -- 坐标系, 画布控件不提供平移, 不加偏移会画到画面左上角)
    ox, oy = ox or 0, oy or 0
    if set_pen_color == nil then return end
    for i = 1, #cmds do
        local c = cmds[i]
        if c.op == "rect" then
            set_pen_color(c.color or 0)
            draw_rect(c.x0 + ox, c.y0 + oy, c.x1 + ox, c.y1 + oy,
                      c.fill == 1 and 1 or 0)
        elseif c.op == "arect" then
            draw_rect_alpha(c.x0 + ox, c.y0 + oy, c.x1 + ox, c.y1 + oy,
                           c.alpha or 128)
        elseif c.op == "line" then
            set_pen_color(c.color or 0)
            draw_line(c.x0 + ox, c.y0 + oy, c.x1 + ox, c.y1 + oy,
                      c.w or 1)
        elseif c.op == "text" then
            draw_text(c.s, c.x + ox, c.y + oy, c.w, c.h, 0,
                      c.size or 16, c.color or 0, c.align or 1, 1)
        end
    end
end

return mapdraw
