# -*- coding: utf-8 -*-
"""patch_test_m48.py — 补 M48 测试: 任务列表只显名/切换回适 + 视区裁剪。"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# ---- taskmgr_sowrt: 第10段 ----
p = 'hmi_port/tests/test_him_taskmgr_sowrt.py'
s = open(p, encoding='utf-8').read()
anchor = "    print('9) app路由(M45): 共用MV地址按当前页派发——修后注册页独占路由')"
assert s.count(anchor) == 1, 'taskmgr锚点'
assert '10) M48' not in s, '第10段已存在'
LQ = chr(39)  # 单引号
NEW = (
    "    print('10) M48: 任务列表只显名+切换回适')\n"
    "    lua.execute('P9:on_enter()')\n"
    "    __LH2 = (REG[LW.TM.list]:gsub('.', function(c)\n"
    "        return string.format('%02x', string.byte(c)) end))\n"
    "    __MVREF = select(1, P9.mv_get())\n"
    "    l2 = bytes.fromhex(str(lua.eval('__LH2'))).decode('gbk')\n"
    "    check('%' not in l2 and ('t2' in l2 or 't3' in l2),\n"
    "          '任务列表只显任务名(无完成率, 实有%r)' % l2[:40])\n"
    "    check(lua.eval('__MVREF ~= nil')\n"
    "          and 5.0 < float(lua.eval('__MVREF.scale')) < 5.2,\n"
    "          '进页/切换任务自动回适(scale约5.09)')\n"
    "    lua.execute('P9:on_update(LW.TM.btn_down, 1)')\n"
    "    lua.execute('__MVREF2 = select(1, P9.mv_get())')\n"
    "    check(lua.eval('__MVREF2 ~= nil')\n"
    "          and 5.0 < float(lua.eval('__MVREF2.scale')) < 5.2,\n"
    "          '下键切换任务: 自动回新任务fit')\n\n"
)
s = s.replace(anchor, NEW + anchor)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('taskmgr_sowrt 第10段已加')

# ---- mapdraw: 第11段(视区裁剪) ----
p = 'hmi_port/tests/test_him_mapdraw.py'
s = open(p, encoding='utf-8').read()
anchor = "    print()\n    print('地图绘制回归: %s (%d项)' % ("
assert s.count(anchor) == 1, 'mapdraw锚点'
DQ = chr(34)
LUA = (
    "    lua.execute(\"\"\"\n"
    "__CV2 = MD.cmds(__BIG, nil, { w = 530, h = 380,\n"
    "    viewp = { cx = 14, cy = 240, scale = 64 } })\n"
    "__OOB = 0\n"
    "for i = 1, #__CV2 do\n"
    "    local c = __CV2[i]\n"
    "    if c.op == " + DQ + "rect" + DQ + " or c.op == " + DQ + "line" + DQ + " then\n"
    "        if c.x0 < 0 or c.y0 < 0 or c.x1 > 529 or c.y1 > 379 then\n"
    "            __OOB = __OOB + 1\n"
    "        end\n"
    "    end\n"
    "end\n"
    "\")\n"
    "    check(lua.eval('__OOB') == 0,\n"
    "          '高倍视区: 全部绘制指令都在画布内(M48视区裁剪, 实有越界%s)'\n"
    "          % lua.eval('__OOB'))\n\n"
)
NEW = "    print('11) M48视区裁剪: 高倍下所有绘制指令都在画布内')\n" + LUA
s = s.replace(anchor, NEW + anchor)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('mapdraw 第11段已加')
