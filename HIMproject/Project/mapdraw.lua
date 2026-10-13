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
    aisle   = { 210, 210, 210 },   -- 过道带 浅灰
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

-------------------------------------------------------------------- 布局
-- fit-scale: 均匀网格 + 排间过道带(AISLE_FRAC*ch, 至少4px), 排/列标签边距
local AISLE_FRAC = 0.35
local LABEL_W, LABEL_H = 30, 22

function mapdraw.layout(m, w, h)
    local rows, cols = m.rows or 1, m.cols or 1
    local iw, ih = w - LABEL_W, h - LABEL_H
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
        x0 = LABEL_W + (iw - cw * cols) // 2,
        y0 = LABEL_H + (ih - total_h) // 2,
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
            out[#out + 1] = { op = 'rect', x0 = x0 + 1, y0 = y0 + 1,
                              x1 = x1 - 1, y1 = y1 - 1, fill = 1,
                              color = mapdraw.rgb565(col[1], col[2], col[3]) }
        end
    end

    -- 网格线(O(rows+cols), 不逐格描边)
    local kc = mapdraw.rgb565(mapdraw.COLORS.grid[1],
                              mapdraw.COLORS.grid[2], mapdraw.COLORS.grid[3])
    if g.cw >= 14 and g.ch >= 10 then
        for c = 0, g.cols do
            out[#out + 1] = { op = 'line', x0 = g.x0 + c * g.cw,
                              y0 = g.y0, x1 = g.x0 + c * g.cw,
                              y1 = g.y0 + g.rows * (g.ch + g.aisle) + g.aisle - 1,
                              w = 1, color = kc }
        end
        for r = 0, g.rows do
            local y = g.y0 + (r + 1) * g.aisle + r * (g.ch + g.aisle)
            out[#out + 1] = { op = 'line', x0 = g.x0, y0 = y, x1 = gx1, y1 = y,
                              w = 1, color = kc }
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

    -- 起点标记(黄色空心框)
    local os_ = opts.outset or (t and t.outset or nil)
    if os_ and os_.r >= 0 and os_.r < g.rows and os_.c >= 0 and os_.c < g.cols then
        local x0, y0, x1, y1 = cell_rect(g, os_.r, os_.c)
        out[#out + 1] = { op = 'rect', x0 = x0 + 1, y0 = y0 + 1,
                          x1 = x1 - 1, y1 = y1 - 1, fill = 0,
                          color = mapdraw.rgb565(mapdraw.COLORS.outset[1],
                                                 mapdraw.COLORS.outset[2],
                                                 mapdraw.COLORS.outset[3]) }
    end

    -- 轨迹叠加(半透明绿 + 边框)
    if opts.trail then
        local tc = mapdraw.rgb565(mapdraw.COLORS.trail[1],
                                  mapdraw.COLORS.trail[2],
                                  mapdraw.COLORS.trail[3])
        for _, p in ipairs(opts.trail) do
            if p.row >= 0 and p.row < g.rows and p.col >= 0 and p.col < g.cols then
                local x0, y0, x1, y1 = cell_rect(g, p.row, p.col)
                out[#out + 1] = { op = 'arect', x0 = x0 + 1, y0 = y0 + 1,
                                  x1 = x1 - 1, y1 = y1 - 1, alpha = 70 }
                out[#out + 1] = { op = 'rect', x0 = x0 + 1, y0 = y0 + 1,
                                  x1 = x1 - 1, y1 = y1 - 1, fill = 0, color = tc }
            end
        end
    end

    -- 农机标记(当前格中心实心方块, 过道时不下画)
    if opts.machine and opts.machine.row and opts.machine.row >= 0
        and opts.machine.row < g.rows and opts.machine.col
        and opts.machine.col >= 0 and opts.machine.col < g.cols then
        local x0, y0, x1, y1 = cell_rect(g, opts.machine.row, opts.machine.col)
        local cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        local s = math.max(5, math.min(g.cw, g.ch) // 4)
        out[#out + 1] = { op = 'rect', x0 = cx - s, y0 = cy - s,
                          x1 = cx + s, y1 = cy + s, fill = 1,
                          color = mapdraw.rgb565(mapdraw.COLORS.machine[1],
                                                 mapdraw.COLORS.machine[2],
                                                 mapdraw.COLORS.machine[3]) }
    end

    return out, g
end


-------------------------------------------------------------------- 平台适配
-- cmds -> draw_* 翻译(on_draw回调内调用; PC/lupa无绘图API时整段跳过)。
-- draw_text charcode=1: 指令字符串为GB2312字节(lua源文件即GB18030)
function mapdraw.render(cmds)
    if set_pen_color == nil then return end
    for i = 1, #cmds do
        local c = cmds[i]
        if c.op == "rect" then
            set_pen_color(c.color or 0)
            draw_rect(c.x0, c.y0, c.x1, c.y1, c.fill == 1 and 1 or 0)
        elseif c.op == "arect" then
            draw_rect_alpha(c.x0, c.y0, c.x1, c.y1, c.alpha or 128)
        elseif c.op == "line" then
            set_pen_color(c.color or 0)
            draw_line(c.x0, c.y0, c.x1, c.y1, c.w or 1)
        elseif c.op == "text" then
            draw_text(c.s, c.x, c.y, c.w, c.h, 0, c.size or 16,
                      c.color or 0, c.align or 1, 1)
        end
    end
end

return mapdraw
