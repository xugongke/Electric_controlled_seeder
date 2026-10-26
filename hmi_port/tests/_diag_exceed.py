# -*- coding: utf-8 -*-
"""图外播种诊断: 试验田1(4排x12列 bet=6) + 屏端jobrun(QT逐式移植) × seeder_sim.

对照用户实测现象: 图外开播 行程-198/行号2 -> 行程500+行号2计数 ->
行程1000+行号1计数 -> 播种结束.
"""
import os
import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = os.path.join(ROOT, 'HIMproject', 'Project').replace('\\', '/')
SIM = os.path.join(ROOT, 'seeder_sim')
sys.path.insert(0, SIM)

from lupa import lua53 as lupa_lua          # noqa: E402

from device import Device                    # noqa: E402
from workproc import WorkProc                # noqa: E402
import protocol as SP                        # noqa: E402
import layout as SL                          # noqa: E402

HARNESS = r'''
LW   = assert(loadfile("__HIM/lwmap.lua"))()
CSV  = assert(loadfile("__HIM/csv.lua"))()
STR  = assert(loadfile("__HIM/store.lua"))()
PA   = assert(loadfile("__HIM/pathalgo.lua"))()
MD   = assert(loadfile("__HIM/mapdraw.lua"))()
CD   = assert(loadfile("__HIM/codec.lua"))()
JR   = assert(loadfile("__HIM/jobrun.lua"))()
CD.init { rows = 6 }
REG = {}
function w16(a, v) REG[a] = v end
function w32(a, v) REG[a] = v; REG[a + 1] = 0 end
function wstr(a, s) REG[a] = s end
__FS = {}
FIO = {
    write_all = function(p, d) __FS[p] = d return true end,
    read_all  = function(p) return __FS[p] end,
    append    = function(p, d) __FS[p] = (__FS[p] or "") .. d return true end,
    remove    = function(p) __FS[p] = nil return true end,
}
STR.init(FIO, CSV, "3:")
__SENT = {}
__PROTO = {
    FNC = { GET_BZ_STATUS = 0x21, GET_TER_PARA = 0x26, STORE_AB = 0x23,
            SET_BZ_PARA = 0x20, SET_AB = 0x24, GDDD_ENABLE = 0x31,
            QZDD_ENABLE = 0x29, CMD_START_BZ = 0x0A, CMD_STOP_BZ = 0x0B },
    send = function(fnc, payload)
        payload = payload or ""
        __SENT[#__SENT + 1] = { fnc = fnc,
                                hex = (payload:gsub(".", function(c)
            return string.format("%02x", string.byte(c)) end)) }
    end,
}
__APP = { sub_always = function() end, register = function() end,
          set_always_poll = function() end, cur = nil }
JR.init {
    APP = __APP, PROTOCOL = __PROTO, CODEC = CD,
    STORE = STR, PATHALGO = PA, LOGGER = {
        log = function(tag, msg) print("[lua] " .. tag .. " " .. msg) end },
    LW = LW, w16 = w16, w32 = w32, wstr = wstr,
    now = function() return "2026-10-26 12:00:00" end,
}
'''.replace('__HIM', HIM)


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    map_text = open(os.path.join(ROOT, 'hmi_port', 'tests', '_map_t1.csv'),
                    'rb').read().decode('gbk')
    lua.globals().__HEXM = map_text.encode('gbk').hex()
    lua.execute('''
local s = (function(h)
    local o = ""
    for i = 1, #h, 2 do
        o = o .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return o
end)(__HEXM)
local pm = CSV.parse_map(s)
local _m = STR.map_import_text(pm.name, s)
print("map: " .. tostring(_m ~= nil) .. " name=" .. pm.name)
__MAPNAME = pm.name
''')

    dev = Device(state_file=None, rows=6)
    dev.bd.StartState = 1
    wp = WorkProc(dev)

    def process_frame(fnc, data):
        if fnc == SP.FNC_SET_BZ_PARA and len(data) == SL.SZ_BZ_CELL_PARA:
            wp.set_bz_para(SL.BzCellPara.unpack(data))
        elif fnc == SP.FNC_SET_AB and len(data) == SL.SZ_BD_PARA:
            dev.bd = SL.BdPara.unpack(data)
        elif fnc == SP.FNC_CMD_START_BZ:
            wp.cmd_start_bz()
        elif fnc == SP.FNC_CMD_STOP_BZ:
            wp.cmd_stop_bz()
        elif fnc == SP.FNC_GDDD_ENABLE and data:
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
        lua.globals().__STHX = payload.hex()
        lua.execute('''
local h = __STHX
local s = ""
for i = 1, #h, 2 do
    s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
end
JR._feed { data = s }
''')

    # 任务: 梭形(0), positive=0(UI正), 图外播种=1
    lua.execute('''
STR.task_create("t1", __MAPNAME, 0, 0, 1, 0, 0, "2026-10-26")
local ok, err = JR.start("t1", {})
print("start: " .. tostring(ok) .. " " .. tostring(err))
''')
    drain()

    t = [1000]
    trace = []
    last20 = None
    def run(limit_ms=200000):
        n = 0
        while n * 10 < limit_ms:
            t[0] += 10
            wp.step(t[0])
            n += 1
            if n % 20 == 0:
                feed_status()
                drain()
                st = wp.get_bz_status()
                trace.append((t[0] - 1000, st['row_num'], st['off_len'],
                              '%x' % st['run_state'],
                              sum(st['louzh']), sum(st['loufei']),
                              wp.debug[:14]))
                # 打印0x20关键字段变化
                nonlocal last20
                if wp.bz_cell.RowNum != last20:
                    last20 = wp.bz_cell.RowNum
                    z = wp.bz_cell
                    print('  0x20->RowNum=%d Next=%d StartPOS=%d CellLen=%d '
                          'InS=%d Final=%d NextFinal=%d TXF=%d'
                          % (z.RowNum, z.NextRowNum, z.StartPOS, z.CellLen,
                             z.InS, z.FinalFlag, z.NextFinalFlag, z.TXFlag))
                if wp.debug.startswith('播种结束'):
                    return True
        return False

    print('=== 图外播种 启动(正/梭形, 起点列组0) ===')
    ok = run(200000)
    print('趟1结束:', ok)
    print('--- 轨迹采样(时刻ms 行号 行程 状态 漏种和 漏肥和 调试) ---')
    for row in trace:
        print('  %6d %3d %6d %s %3d %3d %s' % row)
    lua.execute('''
local d, tot, pct = STR.task_progress("t1")
print(string.format("进度: %d/%d %d%%", d, tot, pct))
''')
    return 0


if __name__ == '__main__':
    sys.exit(main())
