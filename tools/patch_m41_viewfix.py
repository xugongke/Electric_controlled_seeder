# -*- coding: utf-8 -*-
"""patch_m41_viewfix.py — M41 视口实测问题修复(2026-10-23用户真机反馈)。

1) zoom_step: fit态按"小"nil比较崩溃("on_update异常"根因)——缩小于
   cur=nil(适配)直接返回nil;
2) 撤缩略图: 三页paint去minimap, 控制器pan/zoom/center_on的minimap
   参数同步false(视区矩形必须与绘制一致, 否则夹取/居中偏差96px);
3) 重绘加固: lwmap补MAP/TM/RT.canvas脏标键(画布ReadAddr=0x1C79/1E95/
   1F5B, 值变化触发重绘), view_hit后写脏标——不再单靠redraw内建;
   并加scale日志(INF)供真机排查"大"键。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
DIR = r'F:\Cubemx_Project\Electric_controlled_seeder\HIMproject\Project'


def patch(fname, subs):
    path = DIR + '\\' + fname
    src = open(path, 'rb').read().decode('gb18030').replace('\r\n', '\n')
    for old, new, cnt in subs:
        n = src.count(old)
        assert n == cnt, '%s 锚点%d次(期望%d): %r...' % (fname, n, cnt, old[:50])
        src = src.replace(old, new)
    open(path, 'wb').write(src.replace('\n', '\r\n').encode('gb18030'))
    print('%s 已打补丁(%d处)' % (fname, len(subs)))


# ---------------------------------------------------------------- mapdraw
patch('mapdraw.lua', [
    ('''    if dir > 0 then
        local base = cur or fit                 -- 从fit放大: 跳到首个>fit的档
        for i = 1, #ZOOMS do
            if ZOOMS[i] > base then return ZOOMS[i] end
        end
        return cur or fit                       -- 已到最大档
    end
    for i = #ZOOMS, 1, -1 do''',
     '''    if dir > 0 then
        local base = cur or fit                 -- 从fit放大: 跳到首个>fit的档
        for i = 1, #ZOOMS do
            if ZOOMS[i] > base then return ZOOMS[i] end
        end
        return cur or fit                       -- 已到最大档
    end
    if not cur then return nil end              -- 适配已最小(M41: 原nil比较
                                                --   崩溃, 真机报on_update异常)
    for i = #ZOOMS, 1, -1 do''', 1),
])

# ---------------------------------------------------------------- lwmap
patch('lwmap.lua', [
    ('''    view       = 0x1C78, -- u16 地图预览视图 0排列/1编号/2密度(下拉,''',
     '''    canvas     = 0x1C79, -- 画布重绘脏标(M41): 写值变化触发画面1画布重绘
    view       = 0x1C78, -- u16 地图预览视图 0排列/1编号/2密度(下拉,''', 1),
    ('''    view      = 0x1E94, -- u16 地图画布视图 0排列/1编号/2密度(下拉)''',
     '''    canvas    = 0x1E95, -- 画布重绘脏标(M41): 写值变化触发画面9画布重绘
    view      = 0x1E94, -- u16 地图画布视图 0排列/1编号/2密度(下拉)''', 1),
    ('''    tot       = 0x1F5A, -- u16 总块数''',
     '''    canvas    = 0x1F5B, -- 画布重绘脏标(M41): 写值变化触发画面24画布重绘
    tot       = 0x1F5A, -- u16 总块数''', 1),
])

# ---------------------------------------------------------------- 三页公共
MINIMAP_OLD = '            viewp = W.mv, minimap = true,   -- M40视口+缩略图(大排列数)\n'
MINIMAP_NEW = '            viewp = W.mv,                   -- M40视口(大排列数; 缩略图M41撤)\n'


def viewhit_common(old_tail, new_tail):
    return (old_tail, new_tail, 1)


# page_map
patch('page_map.lua', [
    (MINIMAP_OLD, MINIMAP_NEW, 1),
    # 控制器minimap参数 false(与paint视区一致)
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, -0.5)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, -0.5)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, 0.5)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, 0.5)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, -0.5, 0)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, -0.5, 0)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0.5, 0)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0.5, 0)', 1),
    ('MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, 1)',
     'MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, 1)', 1),
    ('MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, -1)',
     'MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, -1)', 1),
    # 脏标重绘 + scale日志
    ('''        canvas_dirty = true
        return true
    end''',
     '''        canvas_dirty = true
        w16(LW.MAP.canvas, (r16(LW.MAP.canvas) or 0) == 1 and 0 or 1)
        log('INF', '视口 scale=' .. tostring(W.mv and W.mv.scale or '适'))
        return true
    end''', 1),
])

# page_taskmgr
patch('page_taskmgr.lua', [
    (MINIMAP_OLD, MINIMAP_NEW, 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, -0.5)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, -0.5)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, 0.5)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, 0.5)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, -0.5, 0)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, -0.5, 0)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0.5, 0)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0.5, 0)', 1),
    ('MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, 1)',
     'MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, 1)', 1),
    ('MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, -1)',
     'MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, -1)', 1),
    ('''        mark_dirty()
        return true
    end''',
     '''        mark_dirty()
        w16(LW.TM.canvas, (r16(LW.TM.canvas) or 0) == 1 and 0 or 1)
        log('INF', '视口 scale=' .. tostring(W.mv and W.mv.scale or '适'))
        return true
    end''', 1),
])

# page_sowrt
patch('page_sowrt.lua', [
    (MINIMAP_OLD, MINIMAP_NEW, 1),
    ('MAPDRAW.center_on(W.mv, m, CANVAS_W, CANVAS_H, true,',
     'MAPDRAW.center_on(W.mv, m, CANVAS_W, CANVAS_H, false,', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, -0.5)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, -0.5)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, 0.5)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0, 0.5)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, -0.5, 0)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, -0.5, 0)', 1),
    ('MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0.5, 0)',
     'MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, false, 0.5, 0)', 1),
    ('MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, 1)',
     'MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, 1)', 1),
    ('MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, -1)',
     'MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, false, -1)', 1),
    ('''        if redraw then redraw() end
        return true
    end''',
     '''        -- M41: 写画布脏标触发重绘(redraw内建不可依赖)
        w16(LW.RT.canvas, (r16(LW.RT.canvas) or 0) == 1 and 0 or 1)
        if redraw then redraw() end
        log('INF', '视口 scale=' .. tostring(W.mv and W.mv.scale or '适'))
        return true
    end''', 1),
    # on_tick跟随重绘同样补脏标
    ('''            if W.follow then
                local t = W.task and STORE.tasks[W.task] or nil
                local m = t and task_map(t)
                if m then follow_now(m) end
            end
            if redraw then redraw() end''',
     '''            if W.follow then
                local t = W.task and STORE.tasks[W.task] or nil
                local m = t and task_map(t)
                if m then follow_now(m) end
            end
            w16(LW.RT.canvas, (r16(LW.RT.canvas) or 0) == 1 and 0 or 1)
            if redraw then redraw() end''', 1),
])

# mv_get 测试/诊断钩子(三页)
MV_GET = '''
    page.mv_get = function() return W.mv, W.follow end   -- 视口状态钩子(M41)
'''
patch('page_map.lua', [
    ('''    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        if view_hit(addr) then return end
        on_btn(addr, val)
    end''',
     '''    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        if view_hit(addr) then return end
        on_btn(addr, val)
    end
''' + MV_GET, 1),
])
patch('page_taskmgr.lua', [
    ('''    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end''',
     '''    page.mv_get = function() return W.mv, W.follow end   -- 视口状态钩子(M41)

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end''', 1),
])
patch('page_sowrt.lua', [
    ('''    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end
        if addr == LW.RT.btn_start then''',
     '''    page.mv_get = function() return W.mv, W.follow end   -- 视口状态钩子(M41)

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end
        if addr == LW.RT.btn_start then''', 1),
])
print('M41 视口修复补丁完成')
