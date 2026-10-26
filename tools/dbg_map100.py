# -*- coding: utf-8 -*-
"""dbg_map100.py — 复现用户100x100地图三症状(解析/建任务/路径)。"""
import io
import sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
from lupa import lua53 as lupa_lua

HIM = 'F:/Cubemx_Project/Electric_controlled_seeder/HIMproject/Project'
raw = open('tools/hmi_export/hmi_out/map_100_ACD4481F.csv', 'rb').read()
NAME = '试验田100'.encode('gbk')

lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
lua.globals().__HEXSTR = raw.hex()
lua.globals().__NAMEH = NAME.hex()
lua.execute('''
LW   = assert(loadfile("@H/lwmap.lua"))()
CSV  = assert(loadfile("@H/csv.lua"))()
STR  = assert(loadfile("@H/store.lua"))()
PA   = assert(loadfile("@H/pathalgo.lua"))()
FS = {}
FIO = { write_all=function(p,d) FS[p]=d return true end,
        read_all=function(p) return FS[p] end,
        append=function(p,d) FS[p]=(FS[p] or "")..d return true end,
        remove=function(p) FS[p]=nil return true end }
STR.init(FIO, CSV, "3:")
local s = ""
local h = __HEXSTR
for i = 1, #h, 2 do s = s .. string.char(tonumber(h:sub(i, i+1), 16)) end
local nm = ""
local nh = __NAMEH
for i = 1, #nh, 2 do nm = nm .. string.char(tonumber(nh:sub(i, i+1), 16)) end
local a, b = STR.map_import_text(nm, s)
local function hx(x)
    if x == nil then return "6e696c" end
    return (tostring(x):gsub(".", function(c)
        return string.format("%02x", string.byte(c)) end))
end
__A = hx(a)
__B = hx(b)
__M = STR.maps[nm]
__NAME = nm
'''.replace('@H', HIM))
a = bytes.fromhex(str(lua.eval('__A'))).decode('gbk', errors='replace')
b = bytes.fromhex(str(lua.eval('__B'))).decode('gbk', errors='replace')
print('导入返回 a:', a)
print('导入返回 b:', b)
print('地图在库:', lua.eval('__M ~= nil'))
print('rows/cols/machine/block:', lua.eval('__M.rows'), lua.eval('__M.cols'),
      lua.eval('__M.machine_cols'), lua.eval('__M.block_col'))
print('blocks[0][31].sow:', lua.eval('__M.blocks[0][31] and __M.blocks[0][31].sow'))
print('blocks[0][32].sow:', lua.eval('__M.blocks[0][32] and __M.blocks[0][32].sow'))
print('blocks[0][99].sow:', lua.eval('__M.blocks[0][99] and __M.blocks[0][99].sow'))
print('blocks[0]键数:', lua.eval('(function() local n=0 for _ in pairs(__M.blocks[0]) do n=n+1 end return n end)()'))
lua.execute('''
local t, err = STR.task_create("t100", __NAME, 0, 1, 0, 0, 0, "T")
__TC = (t ~= nil)
__T = t
''')
print('task_create:', lua.eval('__TC'))
lua.execute('''
local m = STR.maps[__NAME]
local okp, pp = pcall(PA.create_path, m, __T.path_type, __T.positive == 1)
__P_OK = okp
__P_N = pp and #pp or -1
__P_E = not okp and hx(pp) or ""
'''.replace('hx(pp)', 'tostring(pp)'))
print('create_path ok:', lua.eval('__P_OK'), '节点数:', lua.eval('__P_N'),
      lua.eval('__P_E'))
