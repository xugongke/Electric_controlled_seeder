# -*- coding: utf-8 -*-
"""patch_pages_viewport.py — 三地图页接入视口/缩略图/跟随 (M40)。

page_map/page_taskmgr/page_sowrt:
  - paint: cmds opts 增加 viewp=W.mv(视口,nil=适配) + minimap=true
  - addrs 追加 LW.MV 导航按钮
  - on_update 前置 view_hit 路由(平移/缩放/适配; 手动平移退出跟随)
  - on_enter 视图复位(适配)
  - sowrt: follow 开关 + on_tick作业推进自动居中当前作业块
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
DIR = r'F:\Cubemx_Project\Electric_controlled_seeder\HIMproject\Project'


def patch(fname, subs):
    path = DIR + '\\' + fname
    src = open(path, 'rb').read().decode('gb18030')
    assert '\r\n' in src
    src = src.replace('\r\n', '\n')          # 归一LF便于锚点匹配
    for old, new, cnt in subs:
        n = src.count(old)
        assert n == cnt, '%s 锚点出现%d次(期望%d): %r...' % (
            fname, n, cnt, old[:60])
        src = src.replace(old, new)
    open(path, 'wb').write(src.replace('\n', '\r\n').encode('gb18030'))
    print('%s 已打补丁(%d处)' % (fname, len(subs)))


CRLF = '\r\n'

# ---------------------------------------------------------- page_map.lua
MV_ADDR_LINE = ('            LW.MV.up, LW.MV.down, LW.MV.left, LW.MV.right,\r\n'
                '            LW.MV.zin, LW.MV.zout, LW.MV.fit,\r\n')
patch('page_map.lua', [
    # paint: 视口+缩略
    ('''            view = (v == 1 and "num") or (v == 2 and "density")
                   or "arrange",
        }), 412, 30)''',
     '''            view = (v == 1 and "num") or (v == 2 and "density")
                   or "arrange",
            viewp = W.mv, minimap = true,   -- M40视口+缩略图(大排列数)
        }), 412, 30)''', 1),
    # addrs 追加MV
    ('''        addrs = {
            LW.MAP.btn_up, LW.MAP.btn_down, LW.MAP.btn_sel, LW.MAP.btn_del,
            LW.MAP.btn_usb, LW.MAP.ab_import, LW.MAP.ab_clear,
        },''',
     '''        addrs = {
            LW.MAP.btn_up, LW.MAP.btn_down, LW.MAP.btn_sel, LW.MAP.btn_del,
            LW.MAP.btn_usb, LW.MAP.ab_import, LW.MAP.ab_clear,
''' + MV_ADDR_LINE + '        },', 1),
    # on_enter 视图复位
    ('''    function page:on_enter()
        refresh()
        canvas_dirty = true
    end''',
     '''    function page:on_enter()
        refresh()
        W.mv = nil                          -- 视图复位适配(M40)
        canvas_dirty = true
    end''', 1),
    # view_hit 路由(插在 local page = { 前)
    ('''    local page = {
        id = LW.SCREEN.MAP,''',
     '''    ---------------------------------------------------------------- 视口按钮(M40)
    -- LW.MV导航: 半屏平移/缩放档位/适配; 大排列数地图视口浏览
    local function view_hit(addr)
        local n = selected_name()
        local m = n and STORE and STORE.map_get(n)
        if not m then return false end
        if addr == LW.MV.up then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, -0.5)
        elseif addr == LW.MV.down then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, 0.5)
        elseif addr == LW.MV.left then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, -0.5, 0)
        elseif addr == LW.MV.right then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0.5, 0)
        elseif addr == LW.MV.zin then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, 1)
        elseif addr == LW.MV.zout then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, -1)
        elseif addr == LW.MV.fit then
            W.mv = nil
        else
            return false
        end
        canvas_dirty = true
        return true
    end

    local page = {
        id = LW.SCREEN.MAP,''', 1),
    # on_update 前置路由
    ('''    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        on_btn(addr, val)
    end''',
     '''    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        if view_hit(addr) then return end
        on_btn(addr, val)
    end''', 1),
])

# ---------------------------------------------------------- page_taskmgr.lua
patch('page_taskmgr.lua', [
    ('''        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
        }''',
     '''        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
            viewp = W.mv, minimap = true,   -- M40视口+缩略图(大排列数)
        }''', 1),
    ('''        addrs = {
            LW.TM.btn_new,
            LW.TM.btn_del, LW.TM.btn_imp, LW.TM.btn_exp, LW.TM.btn_reset,
            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_sel, LW.TM.btn_start,
        },''',
     '''        addrs = {
            LW.TM.btn_new,
            LW.TM.btn_del, LW.TM.btn_imp, LW.TM.btn_exp, LW.TM.btn_reset,
            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_sel, LW.TM.btn_start,
''' + MV_ADDR_LINE + '        },', 1),
    ('''    function page:on_enter()
        W.sel, W.top = 0, 0
        refresh()
        render_detail()
        mark_dirty()
    end''',
     '''    function page:on_enter()
        W.sel, W.top = 0, 0
        W.mv = nil                          -- 视图复位适配(M40)
        refresh()
        render_detail()
        mark_dirty()
    end''', 1),
    ('''    local page = {
        id = LW.SCREEN.TASKMGR,''',
     '''    ---------------------------------------------------------------- 视口按钮(M40)
    local function view_hit(addr)
        local n, t = cur_task()
        local m = n and STORE.maps[t and t.map]
        if not m then return false end
        if addr == LW.MV.up then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, -0.5)
        elseif addr == LW.MV.down then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, 0.5)
        elseif addr == LW.MV.left then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, -0.5, 0)
        elseif addr == LW.MV.right then
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0.5, 0)
        elseif addr == LW.MV.zin then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, 1)
        elseif addr == LW.MV.zout then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, -1)
        elseif addr == LW.MV.fit then
            W.mv = nil
        else
            return false
        end
        mark_dirty()
        return true
    end

    local page = {
        id = LW.SCREEN.TASKMGR,''', 1),
    ('''    function page:on_update(addr, val)
        if val ~= 1 then return end''',
     '''    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end''', 1),
])

# ---------------------------------------------------------- page_sowrt.lua
patch('page_sowrt.lua', [
    ('''    local W = { task = nil, ver = -1, qzdd = -1,
                last_pt = -1, last_pos = -1 }''',
     '''    local W = { task = nil, ver = -1, qzdd = -1,
                last_pt = -1, last_pos = -1,
                mv = nil, follow = true }   -- M40视口状态/作业跟随''', 1),
    ('''        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
        }''',
     '''        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
            viewp = W.mv, minimap = true,   -- M40视口+缩略图(大排列数)
        }''', 1),
    ('''        addrs = {
            LW.RT.btn_start, LW.RT.btn_stop, LW.RT.btn_result,
            LW.RT.btn_exp, LW.RT.btn_abclr, LW.RT.btn_spply,
        },''',
     '''        addrs = {
            LW.RT.btn_start, LW.RT.btn_stop, LW.RT.btn_result,
            LW.RT.btn_exp, LW.RT.btn_abclr, LW.RT.btn_spply,
            LW.MV.up, LW.MV.down, LW.MV.left, LW.MV.right,
            LW.MV.zin, LW.MV.zout, LW.MV.fit, LW.MV.follow,
        },''', 1),
    ('''        W.last_pt = r16(LW.RT.path_type) or 0
        W.last_pos = (r16(LW.RT.positive) == 1) and 1 or 0
        W.ver = -1''',
     '''        W.last_pt = r16(LW.RT.path_type) or 0
        W.last_pos = (r16(LW.RT.positive) == 1) and 1 or 0
        W.mv = nil                          -- 视图复位适配(M40)
        W.follow = true                     -- 进页默认跟随作业
        W.ver = -1''', 1),
    # 视图控制器(插在 local page = { 前)
    ('''    local page = {
        id = LW.SCREEN.SOWRT,''',
     '''    ---------------------------------------------------------------- 视口按钮(M40)
    -- 跟随: 视口居中当前作业块(jobrun.snapshot.cur_row/cur_col)
    local function follow_now(m)
        local s = JOBRUN and JOBRUN.snapshot and JOBRUN.snapshot()
        if s and s.cur_row and s.cur_col then
            W.mv = MAPDRAW.center_on(W.mv, m, CANVAS_W, CANVAS_H, true,
                                     s.cur_row, s.cur_col)
        end
    end

    -- 平移/适配/缩小退出跟随(地图App惯例), 放大保持跟随(就地缩放)
    local function view_hit(addr)
        local t = W.task and STORE.tasks[W.task] or nil
        local m = t and task_map(t)
        if not m then return false end
        if addr == LW.MV.up then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, -0.5)
        elseif addr == LW.MV.down then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0, 0.5)
        elseif addr == LW.MV.left then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, -0.5, 0)
        elseif addr == LW.MV.right then
            W.follow = false
            W.mv = MAPDRAW.pan(W.mv, m, CANVAS_W, CANVAS_H, true, 0.5, 0)
        elseif addr == LW.MV.zin then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, 1)
        elseif addr == LW.MV.zout then
            W.mv = MAPDRAW.zoom(W.mv, m, CANVAS_W, CANVAS_H, true, -1)
        elseif addr == LW.MV.fit then
            W.follow = false
            W.mv = nil
        elseif addr == LW.MV.follow then
            W.follow = not W.follow
            if W.follow then follow_now(m) end
        else
            return false
        end
        if redraw then redraw() end
        return true
    end

    local page = {
        id = LW.SCREEN.SOWRT,''', 1),
    # on_update 前置路由
    ('''    function page:on_update(addr, val)
        if val ~= 1 then return end
        if addr == LW.RT.btn_start then''',
     '''    function page:on_update(addr, val)
        if val ~= 1 then return end
        if view_hit(addr) then return end
        if addr == LW.RT.btn_start then''', 1),
    # on_tick 作业推进: 跟随居中后重绘
    ('''        local ver = JOBRUN and JOBRUN.draw_ver or 0
        if ver ~= W.ver then
            W.ver = ver
            if redraw then redraw() end
        end
    end

    function page:on_drawctrl(cid)''',
     '''        local ver = JOBRUN and JOBRUN.draw_ver or 0
        if ver ~= W.ver then
            W.ver = ver
            if W.follow then
                local t = W.task and STORE.tasks[W.task] or nil
                local m = t and task_map(t)
                if m then follow_now(m) end
            end
            if redraw then redraw() end
        end
    end

    function page:on_drawctrl(cid)''', 1),
])
print('三页视口接线完成')
