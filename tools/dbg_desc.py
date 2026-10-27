# -*- coding: utf-8 -*-
"""dbg_desc.py — 复现用户场景: 反向起始(趟1排1->排5)+图外播种, 追踪断点。"""
import io
import sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import os
from lupa import lua53 as lupa_lua

ROOT = os.getcwd()
HIM = os.path.join(ROOT, 'HIMproject', 'Project').replace('\\', '/')
SIM = os.path.join(ROOT, 'seeder_sim')
sys.path.insert(0, SIM)
from device import Device                    # noqa: E402
from workproc import WorkProc                # noqa: E402
import protocol as SP                        # noqa: E402
import layout as SL                          # noqa: E402

EX_MAP = '\r\n'.join([
    '信息,,,', '名称,e2eex', '类型,播种,排长(cm),过道长(cm)',
    '创建时间,,500,100', '修改时间,,500,100', '备注,,500,100',
    '排,5,500,100', '列,2,500,100', '小区行数,6,,100',
    '机器行数,6,,', '行间距(cm),60,,', ',,,',
    'AB线,,,', 'StartN,36.4', 'StartE,117', 'EndBN,36.438',
    'EndBE,117', 'StartDir,0', 'CalcDir,0', 'StartState,1',
    'CalcDirFlag,1', 'OffLen,0', 'BDOffTime,100', 'A点排,4', 'A点列,0',
    '方向,FALSE', '名称,AB', ',,,',
    '编号,,,', ',1列,2列', '5排,,,', '4排,,,', '3排,,,', '2排,,,',
    '1排,,,', ',,,',
    '密度,,,', ',1列,2列', '5排,3000,3000', '4排,3500,3500',
    '3排,4000,4000', '2排,4500,4500', '1排,5000,5000', ',,,',
    '是否播种,,,', ',1列,2列', '5排,1,1', '4排,1,1', '3排,1,1',
    '2排,1,1', '1排,1,1',
]) + '\r\n'

lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
lua.globals().__HIM = HIM
lua.globals().__HEXM = EX_MAP.encode('gbk').hex()
lua.execute('''
LW   = assert(loadfile("__HIM/lwmap.lua"))()
CSV  = assert(loadfile("__HIM/csv.lua"))()
STR  = assert(loadfile("__HIM/store.lua"))()
PA   = assert(loadfile("__HIM/pathalgo.lua"))()
FS = {}
FIO = { write_all=function(p,d) FS[p]=d return true end,
        read_all=function(p) return FS[p] end,
        append=function(p,d) FS[p]=(FS[p] or "")..d return true end,
        remove=function(p) FS[p]=nil return true end }
STR.init(FIO, CSV, "3:")
JOB = assert(loadfile("__HIM/jobrun.lua"))()
local s = ""
local h = __HEXM
for i = 1, #h, 2 do s = s .. string.char(tonumber(h:sub(i, i + 1), 16)) end
STR.map_import_text("e2eex", s)
STR.task_create("tdesc", "e2eex", 0, 0, 1, 4, 0, "T")   -- 反向+图外开+起点末排
__SENT = {}
PROT = { FNC = { GET_BZ_STATUS=0x21, SET_BZ_PARA=0x20, SET_AB=0x24,
                 CMD_START_BZ=0x0A, CMD_STOP_BZ=0x0B, GDDD_ENABLE=0x31 },
         send = function(fnc, d)
             __SENT[#__SENT + 1] = { fnc = fnc, hex = (d or ""):gsub(".",
                 function(c) return string.format("%02x", string.byte(c)) end) }
         end }
APP = { set_always_poll = function() end,
        sub_always = function() end,
        register = function() end,
        preset_sowrt_task = nil }
JR = JOB
JOB.init { APP = APP, PROTOCOL = PROT, CODEC = assert(loadfile("__HIM/codec.lua"))(),
           parastore = nil, STORE = STR, PATHALGO = PA, LOGGER = nil,
           mapdraw = nil, LW = LW, w16 = function() end,
           w32 = function() end, wstr = function() end,
           now = function() return "T" end }
'''.replace('__HIM', HIM))

dev = Device(state_file=None, rows=6)
dev.bd.StartState = 1
wp = WorkProc(dev)


def process_frame(fnc, data):
    if fnc == 0x20 and len(data) == 44:
        p = SL.BzCellPara.unpack(data)
        wp.set_bz_para(p)
        print('  0x20: RowNum=%-3s TX=%d Final=%d Next=%d NextD0=%d InS=%d CellLen=%d'
              % (p.RowNum, p.TXFlag, p.FinalFlag, p.NextRowNum,
                 p.NextDensity[0] if p.NextDensity[0] != -1 else -1,
                 p.InS, p.CellLen))
    elif fnc == 0x24:
        dev.bd = SL.BdPara.unpack(data)
    elif fnc == 0x0A:
        wp.cmd_start_bz()
    elif fnc == 0x0B:
        wp.cmd_stop_bz()
    elif fnc == 0x31 and data:
        dev.gddd_enable = data[0] != 0


def drain():
    n = lua.eval('#__SENT')
    for i in range(1, n + 1):
        fnc = lua.eval('__SENT[%d].fnc' % i)
        hx = str(lua.eval('(__SENT[%d].hex)' % i))
        process_frame(fnc, bytes.fromhex(hx))
    lua.execute('__SENT = {}')


def feed_status():
    st = wp.get_bz_status()
    payload = SL.pack_bz_status(**st)
    hx = payload.hex()
    s2 = ''
    for i in range(1, len(hx), 2):
        s2 += chr(int(hx[i:i + 2], 16))
    lua.globals().__STHX = s2
    lua.execute('JR._feed { data = __STHX }')


ok = bool(lua.eval('select(1, JR.start("tdesc", { gap = 0 }))'))
print('start:', ok)
drain()
t = [1000]
rows_seen = set()
for k in range(6000):
    t[0] += 10
    wp.step(t[0])
    if k % 20 == 0:
        feed_status()
        drain()
        st = wp.get_bz_status()
        rows_seen.add(st['row_num'])
        dbg = wp.debug if isinstance(wp.debug, str) else wp.debug.encode(
            'gbk', errors='replace').decode('gbk', errors='replace')
        if wp.seed_mode in (14, 15) or '不符' in dbg or '结束' in dbg:
            print('STOP@%dms: RowNum=%s mode=%s debug=%s pos=%.0f'
                  % (t[0], st['row_num'], wp.seed_mode, dbg, wp.pos_cm))
            break
print('完成块数:', lua.eval('select(1, STR.task_progress("tdesc"))'))
print('RowNum轨迹:', sorted(rows_seen))
