# -*- coding: utf-8 -*-
"""patch_m48.py — 三项改进 (M48, 2026-10-26用户反馈)。

1) 视区裁剪: 平台对draw_*不裁剪, 大倍率下视区边缘的整格/过道带/起点框
   会越出画布压到别的控件("跑出动态绘图区域外")——cmds_vp全部绘制
   截断到主视区矩形, 全越界剔除;
2) 任务列表只显任务名(去完成率%, 与M44地图列表同款);
3) 切换任务/地图(上下键、删除、导入、新建关闭)自动回"适"
   (fit底档整图居中)。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
DIR = 'HIMproject/Project/'

def patch(fname, subs):
    p = DIR + fname
    src = open(p, 'rb').read().decode('gb18030').replace('\r\n', '\n')
    for old, new, cnt in subs:
        n = src.count(old)
        assert n == cnt, '%s 锚点%d次(期望%d): %r' % (fname, n, cnt, old[:60])
        src = src.replace(old, new)
    open(p, 'wb').write(src.replace('\n', '\r\n').encode('gb18030'))
    print('%s 已打补丁(%d处)' % (fname, len(subs)))


# ---------------------------------------------------------------- mapdraw裁剪
patch('mapdraw.lua', [
    ('''    local function sx(wx) return p.vx0 + (wx - p.x0) * p.scale end
    local function sy(wy) return p.vy0 + (wy - p.y0) * p.scale end''',
     '''    local function sx(wx) return p.vx0 + (wx - p.x0) * p.scale end
    local function sy(wy) return p.vy0 + (wy - p.y0) * p.scale end
    local vx1, vy1 = p.vx0 + p.vw - 1, p.vy0 + p.vh - 1
    local function vclip(x0, y0, x1, y1)
        -- 视区裁剪(M48): 平台对draw_*不裁剪, 大倍率下视区边缘的整格/
        -- 过道带绘制会越出画布压到别的控件; 越界截断, 全越界剔除
        if x0 < p.vx0 then x0 = p.vx0 end
        if y0 < p.vy0 then y0 = p.vy0 end
        if x1 > vx1 then x1 = vx1 end
        if y1 > vy1 then y1 = vy1 end
        if x0 > x1 or y0 > y1 then return nil end
        return x0, y0, x1, y1
    end''', 1),
    # 过道带裁剪
    ('''        for i = i0, i1 do
            local yy = sy(i * (1 + g))
            out[#out + 1] = { op = 'rect', x0 = bx0, y0 = yy,
                              x1 = bx1, y1 = yy + g * p.scale - 1,
                              fill = 1, color = ac }
        end''',
     '''        for i = i0, i1 do
            local yy = sy(i * (1 + g))
            local ax0, ay0, ax1, ay1 = vclip(bx0, yy, bx1,
                                             yy + g * p.scale - 1)
            if ax0 then
                out[#out + 1] = { op = 'rect', x0 = ax0, y0 = ay0,
                                  x1 = ax1, y1 = ay1, fill = 1, color = ac }
            end
        end''', 1),
    # 小区色块裁剪
    ('''        for c = c0, c1 do
            local col = state_color(m, t, r, c)
            local xx0 = sx(c)
            out[#out + 1] = { op = 'rect', x0 = xx0, y0 = yy0,
                              x1 = xx0 + p.scale - 1, y1 = yy1, fill = 1,
                              color = mapdraw.rgb565(col[1], col[2], col[3]) }
        end''',
     '''        for c = c0, c1 do
            local col = state_color(m, t, r, c)
            local cx0, cy0, cx1, cy1 = vclip(sx(c), yy0,
                                             sx(c) + p.scale - 1, yy1)
            if cx0 then
                out[#out + 1] = { op = 'rect', x0 = cx0, y0 = cy0,
                                  x1 = cx1, y1 = cy1, fill = 1,
                                  color = mapdraw.rgb565(col[1], col[2],
                                                         col[3]) }
            end
        end''', 1),
    # 边框裁剪
    ('''        for r = r0, r1 do
            for c = c0, c1 do
                local xx0, yy0 = sx(c), sy(r * (1 + g) + g)
                out[#out + 1] = { op = 'rect', x0 = xx0, y0 = yy0,
                                  x1 = xx0 + p.scale - 1,
                                  y1 = yy0 + p.scale - 1, fill = 0, color = kc }
            end
        end''',
     '''        for r = r0, r1 do
            for c = c0, c1 do
                local bx0, by0, bx1, by1 = vclip(sx(c), sy(r * (1 + g) + g),
                    sx(c) + p.scale - 1, sy(r * (1 + g) + g) + p.scale - 1)
                if bx0 then
                    out[#out + 1] = { op = 'rect', x0 = bx0, y0 = by0,
                                      x1 = bx1, y1 = by1, fill = 0, color = kc }
                end
            end
        end''', 1),
    # 排标签: 行带整行可见才画(防越出上下缘)
    ('''    if p.scale >= 14 then
        for r = r0, r1 do
            out[#out + 1] = { op = 'text', s = tostring(rows - r),
                              x = 0, y = sy(r * (1 + g) + g), w = LABEL_W - 2,
                              h = p.scale, size = math.min(16, p.scale),
                              color = lc, align = 1 }
        end
    end''',
     '''    if p.scale >= 14 then
        for r = r0, r1 do
            local ly = sy(r * (1 + g) + g)
            if ly >= p.vy0 - 1 and ly + p.scale <= p.vy0 + p.vh + 1 then
                out[#out + 1] = { op = 'text', s = tostring(rows - r),
                                  x = 0, y = ly, w = LABEL_W - 2,
                                  h = p.scale, size = math.min(16, p.scale),
                                  color = lc, align = 1 }
            end
        end
    end''', 1),
    # 列标签: 整列可见才画(防越出左右缘)
    ('''    if p.scale >= 18 then
        for c = c0, c1 do
            out[#out + 1] = { op = 'text', s = tostring(c + 1),
                              x = sx(c), y = 0, w = p.scale, h = LABEL_H - 2,
                              size = 14, color = lc, align = 1 }
        end
    end''',
     '''    if p.scale >= 18 then
        for c = c0, c1 do
            local lx = sx(c)
            if lx >= p.vx0 - 1 and lx + p.scale <= p.vx0 + p.vw + 1 then
                out[#out + 1] = { op = 'text', s = tostring(c + 1),
                                  x = lx, y = 0, w = p.scale, h = LABEL_H - 2,
                                  size = 14, color = lc, align = 1 }
            end
        end
    end''', 1),
    # 格内文字: 整格可见才画
    ('''                    out[#out + 1] = { op = 'text', s = s, x = sx(c),
                                      y = sy(r * (1 + g) + g), w = p.scale,
                                      h = p.scale, size = 16,
                                      color = mapdraw.rgb565(255, 255, 255),
                                      align = 1 }''',
     '''                    local tx0, ty0 = sx(c), sy(r * (1 + g) + g)
                    if tx0 >= p.vx0 and ty0 >= p.vy0
                       and tx0 + p.scale - 1 <= vx1
                       and ty0 + p.scale - 1 <= vy1 then
                        out[#out + 1] = { op = 'text', s = s, x = tx0,
                                          y = ty0, w = p.scale,
                                          h = p.scale, size = 16,
                                          color = mapdraw.rgb565(255, 255, 255),
                                          align = 1 }
                    end''', 1),
    # 起点标记: 整格可见才画(4线+V整体在视区内)
    ('''       and os_.c >= c0 and os_.c <= c1 then
        local x0 = sx(os_.c)
        local y0 = sy(os_.r * (1 + g) + g)
        local x1 = x0 + p.scale - 1
        local y1 = y0 + p.scale - 1
        local oc = mapdraw.rgb565(mapdraw.COLORS.outset[1],
                                  mapdraw.COLORS.outset[2],
                                  mapdraw.COLORS.outset[3])''',
     '''       and os_.c >= c0 and os_.c <= c1 then
        local x0 = sx(os_.c)
        local y0 = sy(os_.r * (1 + g) + g)
        local x1 = x0 + p.scale - 1
        local y1 = y0 + p.scale - 1
        if x0 < p.vx0 or y0 < p.vy0 or x1 > vx1 or y1 > vy1 then
            return out, p                            -- 起点格不全在视区: 不画
        end
        local oc = mapdraw.rgb565(mapdraw.COLORS.outset[1],
                                  mapdraw.COLORS.outset[2],
                                  mapdraw.COLORS.outset[3])''', 1),
])

# ---------------------------------------------------------------- page_taskmgr
patch('page_taskmgr.lua', [
    # 列表只显任务名
    ('''        local lines = {}
        for i = W.top + 1, math.min(#W.items, W.top + LIST_ROWS) do
            local _, _, pct = STORE.task_progress(W.items[i])
            local ln = (i == W.sel + 1 and ">" or " ")
                .. W.items[i] .. " " .. tostring(pct or 0) .. "%"
            lines[#lines + 1] = string.sub(ln, 1, 15)
        end''',
     '''        local lines = {}
        for i = W.top + 1, math.min(#W.items, W.top + LIST_ROWS) do
            -- M48: 只显任务名(原带完成率%, 完成率看详情)
            lines[#lines + 1] = (i == W.sel + 1 and ">" or " ") .. W.items[i]
        end''', 1),
    # 前置声明refit
    ('local dlg_init, dlg_refresh',
     'local dlg_init, dlg_refresh, refit', 1),
    # refresh里回适(内容/选中变化)
    ('''        wstr(LW.TM.list, table.concat(lines, "\\r\\n"))
        w16(LW.TM.count, #W.items)
        w16(LW.TM.selidx, W.sel)
    end''',
     '''        wstr(LW.TM.list, table.concat(lines, "\\r\\n"))
        w16(LW.TM.count, #W.items)
        w16(LW.TM.selidx, W.sel)
        if refit then refit() end               -- M48: 切换即回"适"
    end''', 1),
    # refit定义(画布常数之后)
    ('''    ---------------------------------------------------------------- 画布
    local CANVAS_W, CANVAS_H = 465, 400   -- 2026-10-26用户重排(M46, 与画面1同)''',
     '''    ---------------------------------------------------------------- 画布
    local CANVAS_W, CANVAS_H = 465, 400   -- 2026-10-26用户重排(M46, 与画面1同)

    ---------------------------------------------------------------- 视图回适(M48)
    -- 切换任务即回"适"(fit底档整图居中), 与"适"按钮同一目标视图
    refit = function()
        local n = W.items and W.items[W.sel + 1]
        local t = n and STORE.tasks[n]
        local m = t and STORE.maps[t.map]
        W.mv = m and MAPDRAW.fit_view(m, CANVAS_W, CANVAS_H, false) or nil
    end''', 1),
    # on_enter: 去M47内联fit(refresh已refit)
    ('''    function page:on_enter()
        W.sel, W.top = 0, 0
        local n0, t0 = cur_task()
        local m0 = n0 and STORE.maps[t0 and t0.map]
        W.mv = m0 and MAPDRAW.fit_view(m0, CANVAS_W, CANVAS_H, false) or nil
        refresh()
        render_detail()
        mark_dirty()
    end''',
     '''    function page:on_enter()
        W.sel, W.top = 0, 0
        refresh()
        render_detail()
        mark_dirty()
    end''', 1),
])

# ---------------------------------------------------------------- page_map
patch('page_map.lua', [
    ('''    local function refresh()''',
     '''    local refit                             -- 前置声明(M48): 切换地图即回适
    local function refresh()''', 1),
    ('''        W.sel, W.top = 0, 0
        render_list()
        wstr(LW.MAP.detail, "")
    end''',
     '''        W.sel, W.top = 0, 0
        render_list()
        wstr(LW.MAP.detail, "")
        if refit then refit() end               -- M48: 列表内容变化即回"适"
    end''', 1),
    # refit定义(show_detail之后)
    ('''        wstr(LW.MAP.detail, table.concat(L, "\\r\\n"))
    end''',
     '''        wstr(LW.MAP.detail, table.concat(L, "\\r\\n"))
    end

    -- 切换地图即回"适"(M48): 与"适"按钮同一目标视图
    refit = function()
        local n0 = selected_name()
        local m0 = n0 and STORE and STORE.map_get(n0)
        W.mv = m0 and MAPDRAW.fit_view(m0, CANVAS_W, CANVAS_H, false) or nil
    end''', 1),
    # 上下键联动回适
    ('''        if addr == LW.MAP.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
            show_detail()
        elseif addr == LW.MAP.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()
            show_detail()''',
     '''        if addr == LW.MAP.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
            show_detail()
            refit()
        elseif addr == LW.MAP.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()
            show_detail()
            refit()''', 1),
    # on_enter: 去M47内联fit(refit已覆盖)
    ('''    function page:on_enter()
        refresh()
        show_detail()                       -- 自动显示选中详情(M44: 原
                                            --   选中查看按钮职责并入上下键)
        local n0 = selected_name()          -- 进页复位适配视图(M47统一梯)
        local m0 = n0 and STORE and STORE.map_get(n0)
        W.mv = m0 and MAPDRAW.fit_view(m0, CANVAS_W, CANVAS_H, false) or nil
        canvas_dirty = true
    end''',
     '''    function page:on_enter()
        refresh()                           -- (M48: refresh内已回"适")
        show_detail()                       -- 自动显示选中详情(M44: 原
                                            --   选中查看按钮职责并入上下键)
        canvas_dirty = true
    end''', 1),
])
print('M48 补丁完成')
