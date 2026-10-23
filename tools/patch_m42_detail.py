# -*- coding: utf-8 -*-
"""patch_m42_detail.py — 任务/地图详情QT风格单文本合并 (M42, 2026-10-23用户需求)。

1) 任务详情六控件(tm_tname/tmap/tcreate/tlast/tpct/tremark)合并为一个
   文本显示控件 tm_tdetail(0x1E32~0x1E93, 98字=196字节), 多行QT风格:
   任务名/地图/创建/最近作业/完成率/排x列+AB;
2) 删 tm_btn_sel 刷新按钮(仅重应用列表触摸选中, 上下键已覆盖);
3) 地图详情迁址扩容 0x1C44(32字) -> 0x1C80(128字=256字节), QT风格:
   名称/排x列/小区行数+机器行数/一趟块数/行间距+列宽/AB线/创建/修改/备注;
4) csv.lua 补解析+回写 创建时间/修改时间/备注(ctime/mtime/mark)。
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
        assert n == cnt, '%s 锚点%d次(期望%d): %r...' % (fname, n, cnt, old[:60])
        src = src.replace(old, new)
    open(path, 'wb').write(src.replace('\n', '\r\n').encode('gb18030'))
    print('%s 已打补丁(%d处)' % (fname, len(subs)))


# ---------------------------------------------------------------- lwmap
patch('lwmap.lua', [
    ('''    tname     = 0x1E32, -- 字符串 详情:任务名(占0x1E32~0x1E41, 16字)
    tmap      = 0x1E42, -- 字符串 详情:地图名(16字)
    tcreate   = 0x1E52, -- 字符串 详情:创建时间(16字)
    tlast     = 0x1E62, -- 字符串 详情:上次工作时间(16字)
    tpct      = 0x1E72, -- u16 详情:完成率%
    tremark   = 0x1E74, -- 字符串 详情:备注(占0x1E74~0x1E93, 32字)''',
     '''    tdetail   = 0x1E32, -- 字符串 任务详情QT风格合并文本(0x1E32~0x1E93,
                        --   98字=196字节; M42六控件合一, 多行\\r\\n分隔)''', 1),
    ('''    btn_sel   = 0x1E9D, -- 按钮 选中查看
''', '', 1),
    ('''    detail     = 0x1C44, -- 字符串 选中地图详情(占0x1C44~0x1C63, 32字)''',
     '''    detail     = 0x1C80, -- 字符串 选中地图详情QT风格(0x1C80~0x1CFF,
                         --   128字=256字节; M42迁址扩容, 多行\\r\\n分隔)''', 1),
])

# ---------------------------------------------------------------- csv.lua
patch('csv.lua', [
    ('''elseif a1 == "小区行数" then m.block_col = num(f[2]) or 1''',
     '''elseif a1 == "创建时间" then m.ctime = f[2] or ""
elseif a1 == "修改时间" then m.mtime = f[2] or ""
elseif a1 == "备注" then m.mark = f[2] or ""
elseif a1 == "小区行数" then m.block_col = num(f[2]) or 1''', 1),
    ('''        elseif lab == "行间距(cm)" then b = fmt_num(m.col_gap or 60) end''',
     '''        elseif lab == "行间距(cm)" then b = fmt_num(m.col_gap or 60)
        elseif lab == "创建时间" then b = m.ctime or ""
        elseif lab == "修改时间" then b = m.mtime or ""
        elseif lab == "备注" then b = m.mark or ""''', 1),
])

# ---------------------------------------------------------------- page_taskmgr
patch('page_taskmgr.lua', [
    # render_detail 整体重写(QT风格单文本)
    ('''    local function render_detail()
        local n, t = cur_task()
        if not t then
            wstr(LW.TM.tname, "(无任务)")
            wstr(LW.TM.tmap, "")
            wstr(LW.TM.tcreate, "")
            wstr(LW.TM.tlast, "")
            w16(LW.TM.tpct, 0)
            wstr(LW.TM.tremark, "")
            return
        end
        local m = STORE.maps[t.map]
        wstr(LW.TM.tname, trim16(n))
        wstr(LW.TM.tmap, trim16(t.map))
        wstr(LW.TM.tcreate, trim16(t.create_time))
        wstr(LW.TM.tlast, trim16(t.last_work_time))
        local _, _, pct = STORE.task_progress(n)
        w16(LW.TM.tpct, pct or 0)
        local ab = m and m.ab and m.ab.has
        wstr(LW.TM.tremark, m and (string.format("%d排x%d列 AB:%s",
            m.rows or 0, m.cols or 0, ab and "有" or "无")) or "地图缺失")
    end''',
     '''    local function render_detail()
        -- QT风格任务详情单文本(M42): 任务名/地图/创建/最近作业/完成率/几何
        local n, t = cur_task()
        if not t then
            wstr(LW.TM.tdetail, "(无任务)")
            return
        end
        local m = STORE.maps[t.map]
        local _, _, pct = STORE.task_progress(n)
        local ab = m and m.ab and m.ab.has and "有" or "无"
        local geo = m and (string.format("%d排x%d列 AB:%s", m.rows or 0,
                              m.cols or 0, ab)) or "地图缺失"
        wstr(LW.TM.tdetail, table.concat({
            tostring(n),
            "地图:" .. tostring(t.map or ""),
            "创建:" .. tostring(t.create_time or ""),
            "最近作业:" .. tostring(t.last_work_time or ""),
            string.format("完成率:%d%%", pct or 0),
            geo,
        }, "\\r\\n"))
    end''', 1),
    # on_tick 完成率独立写入已并入详情
    ('''        local n = W.items[W.sel + 1]
        if n then
            local _, _, pct = STORE.task_progress(n)
            w16(LW.TM.tpct, pct or 0)
        end
''', '', 1),
    # addrs 去 btn_sel
    ('''            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_sel, LW.TM.btn_start,''',
     '''            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_start,''', 1),
    # on_update 去 btn_sel 分支
    ('''        elseif addr == LW.TM.btn_sel then
            refresh(); render_detail(); mark_dirty()
''', '', 1),
    # dlg 状态写 tdetail
    ('wstr(LW.TM.tremark, "创建失败: " .. tostring(err))',
     'wstr(LW.TM.tdetail, "创建失败: " .. tostring(err))', 1),
    ('wstr(LW.TM.tremark, "已创建 " .. name)',
     'wstr(LW.TM.tdetail, "已创建 " .. name)', 1),
])

# ---------------------------------------------------------------- page_map
patch('page_map.lua', [
    ('''        JOBRUN.ab_hint_map = n                  -- AB对话框的默认目标地图
        local ab = m.ab and ("已绑AB " .. (m.ab.name or "?"))
                       or "无AB线"
        wstr(LW.MAP.detail, ("%s %d排x%d列 %s"):format(n, m.rows, m.cols, ab))''',
     '''        JOBRUN.ab_hint_map = n                  -- AB对话框的默认目标地图
        -- QT风格地图详情单文本(M42): 名称/大小/行列数/一趟块数/行间距列宽/
        -- AB线/创建/修改/备注(时戳备注有则显示; 列宽=小区行数x行间距,QT同款)
        local cw = (m.block_col or 1) * (m.col_gap or 0)
        local g = m.col_gap or 0
        local L = {
            tostring(n),
            string.format("%d排x%d列", m.rows or 0, m.cols or 0),
            string.format("小区行数:%d 机器行数:%d", m.block_col or 1,
                          m.machine_cols or 0),
            string.format("一趟%d块", STORE.block_each_trip
                                       and STORE.block_each_trip(m) or 1),
            string.format("行间距:%d.%02dm 列宽:%d.%02dm",
                          g // 100, g % 100, cw // 100, cw % 100),
            m.ab and ("AB线:" .. (m.ab.name or "?")) or "AB线:无",
        }
        if m.ctime and m.ctime ~= "" then L[#L + 1] = "创建:" .. m.ctime end
        if m.mtime and m.mtime ~= "" then L[#L + 1] = "修改:" .. m.mtime end
        if m.mark and m.mark ~= "" then L[#L + 1] = "备注:" .. m.mark end
        wstr(LW.MAP.detail, table.concat(L, "\\r\\n"))''', 1),
])
print('M42 lua 补丁完成')
