# -*- coding: utf-8 -*-
"""patch_m51b.py — M51 剩余部分: lwmap删follow键 / sowrt删分支+开始自动跟随 / 版本串。"""
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

patch('lwmap.lua', [
    ("    follow = 0x1F87,   -- 按钮 跟随开关(仅实时播种页放置: 自动居中当前作业块,\n"
     "                       --   手动平移/缩放即退出跟随)\n", '', 1),
])

patch('page_sowrt.lua', [
    ("            LW.MV.zin, LW.MV.zout, LW.MV.fit, LW.MV.follow,",
     "            LW.MV.zin, LW.MV.zout, LW.MV.fit,", 1),
    ("        elseif addr == LW.MV.follow then\n"
     "            W.follow = not W.follow\n"
     "            log('INF', W.follow and '作业跟随: 开' or '作业跟随: 关')\n"
     "            if W.follow then follow_now(m) end\n", '', 1),
    ("        local ok, err = JOBRUN.start(W.task)\n"
     "        log(ok and \"INF\" or \"ERR\",\n"
     "            ok and (\"作业启动 \" .. W.task)\n"
     "               or (\"启动失败: \" .. tostring(err)))",
     "        local ok, err = JOBRUN.start(W.task)\n"
     "        log(ok and \"INF\" or \"ERR\",\n"
     "            ok and (\"作业启动 \" .. W.task)\n"
     "               or (\"启动失败: \" .. tostring(err)))\n"
     "        if ok then\n"
     "            W.follow = true                     -- M51: 开始任务自动跟随\n"
     "        end", 1),
])

patch('main.lua', [
    ('wstr(LWMAP.A.appver, "0.5.0(2026.9.30)")  -- screen app version, QT formconfig.cpp:31-33',
     'wstr(LWMAP.A.appver, "M51(2026.10.26)")   -- 屏端构建版本(M51, 每里程碑更新:\n'
     '                                         --   用户可核对下屏是否刷到当前构建)', 1),
])
print('M51 剩余补丁完成')
