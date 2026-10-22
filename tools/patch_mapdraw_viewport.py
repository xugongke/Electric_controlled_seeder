# -*- coding: utf-8 -*-
"""patch_mapdraw_viewport.py — mapdraw.lua 视口渲染 + 缩略图 + 视图控制器 (M40)。

插入到"平台适配"段之前; cmds 增加 opts.viewp(nil=适配, 兼容旧路径)与
opts.minimap(画布右侧缩略条+视口红框), 并提供 pan/zoom/center_on 视图
控制器(纯函数, 三页共用)。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PATH = r'F:\Cubemx_Project\Electric_controlled_seeder\HIMproject\Project\mapdraw.lua'

ANCHOR = '-------------------------------------------------------------------- 平台适配'

BLOCK = '''-------------------------------------------------------------------- 视口(M40)
-- 大排列数根治: 世界坐标系(1格=1单位见方, 过道带=AISLE_FRAC格高)上取
-- 视口{cx,cy中心, scale每格像素}, cmds只画相交区间, 指令量与画布面积
-- 成正比、与世界尺寸无关。opts.viewp=nil回落整图适配(旧路径不变)。
-- 视图控制器 pan/zoom/center_on 供三页 on_update(LW.MV按钮)调用。

local ZOOMS = { 8, 12, 18, 26, 36, 48 }   -- 缩放档位(每格像素)
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
function mapdraw.zoom_step(fit, cur, dir)
    if dir > 0 then
        if not cur then return ZOOMS[1] end
        for i = 1, #ZOOMS do
            if ZOOMS[i] > cur then return ZOOMS[i] end
        end
        return cur
    end
    for i = #ZOOMS, 1, -1 do
        if ZOOMS[i] < cur then
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

'''

src = open(PATH, 'rb').read().decode('gb18030')
assert 'mapdraw.cmds_vp' not in src, '视口段已存在'
assert src.count(ANCHOR) == 1, '平台适配锚点异常'
# cmds 分派: 视口模式走 cmds_vp
OLD_DISPATCH = ("function mapdraw.cmds(m, t, opts)\r\n"
                "    opts = opts or {}\r\n"
                "    local out = {}")
NEW_DISPATCH = ("function mapdraw.cmds(m, t, opts)\r\n"
                "    opts = opts or {}\r\n"
                "    if opts.viewp then return mapdraw.cmds_vp(m, t, opts) end\r\n"
                "    local out = {}")
assert src.count(OLD_DISPATCH) == 1, 'cmds分派锚点异常'
src = src.replace(OLD_DISPATCH, NEW_DISPATCH)
src = src.replace(ANCHOR, BLOCK + ANCHOR)
open(PATH, 'wb').write(src.encode('gb18030'))
print('mapdraw.lua 视口段已插入, cmds已分派')
