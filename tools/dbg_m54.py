# -*- coding: utf-8 -*-
"""dbg_m54.py — 复现 section 12: btn_down 后 cur_task 是谁。"""
import io
import sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import os
from lupa import lua53 as lupa_lua

ROOT = os.getcwd()
HIM = os.path.join(ROOT, 'HIMproject', 'Project')

spec = open('hmi_port/tests/test_him_taskmgr_sowrt.py', encoding='utf-8').read()
head = spec.split('def main')[0]
g = {'__file__': os.path.abspath('hmi_port/tests/test_him_taskmgr_sowrt.py')}
exec(head, g)

lua = g['lua'] = g['lupa_lua'].LuaRuntime(unpack_returned_tuples=True)
HIMF = HIM.replace(chr(92), '/')
lua.globals().__HIM = HIMF
lua.globals().__HEXM = g['SAMPLE_MAP'].encode('gbk').hex()
lua.execute(g['HARNESS'].replace('__HIM', HIMF))
lua.execute('''
local s = ""
local h = __HEXM
for i = 1, #h, 2 do s = s .. string.char(tonumber(h:sub(i, i+1), 16)) end
STR.map_import_text("demo5", s)
P9 = (assert(loadfile("__HIM/page_taskmgr.lua"))())(CTX)
P24 = (assert(loadfile("__HIM/page_sowrt.lua"))())(CTX)
'''.replace('__HIM', HIMF))

# 造任务 t2/t3/t4 (demo6不存在则用demo5)
# demo6导入会失败(内容x无效), 改用demo5建任务
for n in ('t2', 't3', 't4'):
    lua.globals().__N = n
    lua.execute('local t = STR.task_create(__N, "demo5", 0, 1, 0, 0, 0, "T") '
                '__TC = (t ~= nil)')

lua.execute('''
P9:on_enter()
print('task_list:', table.concat(STR.task_list(), ","))
print('W.sel初始(经selidx寄存器):', REG[LW.TM.selidx])
P9:on_update(LW.TM.btn_down, 1)
print('btn_down后 selidx:', REG[LW.TM.selidx])
__N2 = STR.task_list()[2]
print('__N2 =', __N2)
P9:on_update(LW.TM.btn_start, 1)
print('preset:', APPX.preset_sowrt_task)
P24:on_enter()
print('tname:', REG[LW.RT.tname])
P9:on_enter()
print('返回后 selidx:', REG[LW.TM.selidx])
''')
