# -*- coding: utf-8 -*-
"""patch_m51.py — 删"跟"按钮+开始任务自动跟随 + 版本号上屏 (M51, 2026-10-26)。

1) hmiprj: 删画面24"跟"按钮(WriteAddr=$mv_follow)与mv_follow地址标签;
2) lwmap: 删LW.MV.follow键; page_sowrt: 删follow分支/addrs项;
3) 开始任务(on_start成功)即W.follow=true——不用任何按钮, 作业推进
   自动居中; 手动平移/适仍退出跟随;
4) main.lua: 屏端版本串 0.5.0(2026.9.30) -> M51(2026.10.26),
   用户可在屏上核对固件是否刷到当前构建(部署错版排查)。
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

# 1) hmiprj
import os
sys.path.insert(0, 'HIMproject')
import hmiprj_tool as T
xml = T.load()
a = xml.find('WriteAddr="$mv_follow"')
assert a > 0, '跟按钮不存在(已删?)'
wi = xml.rfind('<widget', 0, a)
sp = T.find_widget_span(xml, lambda: wi)
_, _, _, i, end = sp
xml = xml[:i] + xml[end:]
import re
m = re.search(r'[\r\n\t ]*<label NAME="mv_follow"[^>]*/>', xml)
assert m, 'mv_follow标签未找到'
xml = xml[:m.start()] + xml[m.end():]
assert 'mv_follow' not in xml
T.save(xml)
print('hmiprj: 跟按钮+标签已删')

# 2) lwmap
patch('lwmap.lua', [
    ('''    follow   = 0x1F87,   -- 按钮 跟随开关(仅实时播种页放置: 自动居中当前作业块,
                         --   手动平移/缩放即退出跟随)
''', '', 1),
])

# 3) page_sowrt
patch('page_sowrt.lua', [
    # addrs去follow
    ('''            LW.MV.zin, LW.MV.zout, LW.MV.fit, LW.MV.follow,''',
     '''            LW.MV.zin, LW.MV.zout, LW.MV.fit,''', 1),
    # 删follow分支
    ('''        elseif addr == LW.MV.follow then
            W.follow = not W.follow
            log('INF', W.follow and '作业跟随: 开' or '作业跟随: 关')
            if W.follow then follow_now(m) end
''', '', 1),
    # 开始任务自动跟随
    ('''        local ok, err = JOBRUN.start(W.task)
        log(ok and "INF" or "ERR",
            ok and ("作业启动 " .. W.task)
               or ("启动失败: " .. tostring(err)))''',
     '''        local ok, err = JOBRUN.start(W.task)
        log(ok and "INF" or "ERR",
            ok and ("作业启动 " .. W.task)
               or ("启动失败: " .. tostring(err)))
        if ok then
            W.follow = true                     -- M51: 开始任务自动跟随
        end''', 1),
])

# 4) main.lua 版本串
patch('main.lua', [
    ('''wstr(LWMAP.A.appver, "0.5.0(2026.9.30)")  -- screen app version, QT formconfig.cpp:31-33''',
     '''wstr(LWMAP.A.appver, "M51(2026.10.26)")   -- 屏端构建版本(M51, 每里程碑更新:
                                         --   用户可核对下屏是否刷到当前构建)''', 1),
])
print('M51 补丁完成')
