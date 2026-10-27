# -*- coding: utf-8 -*-
"""patch_m56b.py — page_sowrt: 图外播种AB线按压门槛(M56)。"""
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

OLD_ADDRS = (
    "        addrs = {\n"
    "            LW.RT.btn_start, LW.RT.btn_stop, LW.RT.btn_result,\n"
    "            LW.RT.btn_exp, LW.RT.btn_abclr, LW.RT.btn_spply,\n"
    "            LW.MV.up, LW.MV.down, LW.MV.left, LW.MV.right,\n"
    "            LW.MV.zin, LW.MV.zout, LW.MV.fit,\n"
    "        },"
)
NEW_ADDRS = (
    "        addrs = {\n"
    "            LW.RT.btn_start, LW.RT.btn_stop, LW.RT.btn_result,\n"
    "            LW.RT.btn_exp, LW.RT.btn_abclr, LW.RT.btn_spply,\n"
    "            LW.RT.sow_exceed,\n"
    "            LW.MV.up, LW.MV.down, LW.MV.left, LW.MV.right,\n"
    "            LW.MV.zin, LW.MV.zout, LW.MV.fit,\n"
    "        },"
)
OLD_GATE = "        elseif addr == LW.RT.btn_spply then"
NEW_GATE = (
    "        elseif addr == LW.RT.sow_exceed then\n"
    "            -- M56: 图外播种门槛——仅AB线存在时允许勾选(无AB拒绝, 弹回0)\n"
    "            local t0 = W.task and STORE.tasks[W.task] or nil\n"
    "            local m0 = t0 and task_map(t0)\n"
    "            if val == 1 and not (m0 and m0.ab and m0.ab.has) then\n"
    "                log('WRN', '无AB线, 图外播种不可用')\n"
    "            end\n"
    "        elseif addr == LW.RT.btn_spply then"
)
patch('page_sowrt.lua', [
    (OLD_ADDRS, NEW_ADDRS, 1),
    (OLD_GATE, NEW_GATE, 1),
])
print('page_sowrt AB门槛完成')
