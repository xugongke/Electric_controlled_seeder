# -*- coding: utf-8 -*-
r"""半趟中断 -> 虚拟屏重启 -> 继续任务 回归(2026-10-21用户报修三连)。

守三处修复:
  1) 停止即中断标红: jobrun.stop将进行中(1)转中断(3)——旧版只在上电
     boot转换(store.boot 1->3), 红色要重启虚拟屏才出现
  2) EXCEED零值真值: csv.render_task旧式(t.sow_exceed and 1 or 0)因LUA
     0为真恒写#EXCEED,1, 重启后续作误走图外虚拟排(从-700起驶/卡同一趟)
  3) 续作扫描跳过中断(3): isSow对3为false密度0不补播(QT同), 不跳则永远
     锚在半趟块上无限重走趟1

双runtime模拟虚拟屏重启(文件系统经hex blob桥接; 中文名GBK hex中转坑⑪)。
地图: 用户实测试验田4(5排x2列, 梭形, A点排=4)。
运行: python hmi_port/tests/test_him_interrupt_resume.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = os.path.join(ROOT, 'HIMproject', 'Project').replace('\\', '/')
SIM = os.path.join(ROOT, 'seeder_sim')
sys.path.insert(0, SIM)

from lupa import lua53 as lupa_lua          # noqa: E402

from device import Device                    # noqa: E402
from workproc import WorkProc                # noqa: E402
import protocol as SP                        # noqa: E402
import layout as SL                          # noqa: E402

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


MAP_TXT = '\r\n'.join([
    '信息,,,', '名称,试验田4', '类型,播种,排长(cm),过道长(cm)',
    '创建时间,,500,100', '修改时间,,500,100', '备注,,500,100',
    '排,5,500,100', '列,2,500,100', '小区行数,6,,100',
    '机器行数,6,,', '行间距(cm),60,,', ',,,',
    'AB线,,,', 'StartN,36.4', 'StartE,117', 'EndBN,36.40083173',
    'EndBE,117', 'StartDir,0', 'CalcDir,0', 'StartState,1',
    'CalcDirFlag,1', 'OffLen,60', 'BDOffTime,100', 'A点排,4', 'A点列,0',
    '方向,FALSE', '名称,ASDAD', ',,,',
    '编号,,,', ',1列,2列', '5排,,,', '4排,,,', '3排,,,', '2排,,,',
    '1排,,,', ',,,',
    '密度,,,', ',1列,2列', '5排,4000,4000', '4排,4000,4000',
    '3排,4000,4000', '2排,4000,4000', '1排,4000,4000', ',,,',
    '是否播种,,,', ',1列,2列', '5排,1,1', '4排,1,1', '3排,1,1',
    '2排,1,1', '1排,1,1',
]) + '\r\n'

HARNESS = r'''
function FROMHX(h)
    local s = ""
    for i = 1, #h, 2 do
        s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return s
end
function DUMP_FILES()
    local out = {}
    for p, d in pairs(__FILES) do
        local hp, hd = "", ""
        for i = 1, #p do hp = hp .. string.format("%02x", p:byte(i)) end
        for i = 1, #d do hd = hd .. string.format("%02x", d:byte(i)) end
        out[#out + 1] = hp .. " " .. hd
    end
    return table.concat(out, "\n")
end
function LOAD_FILES(blob)
    __FILES = {}
    for line in blob:gmatch("[^\n]+") do
        local sp = line:find(" ", 1, true)
        __FILES[FROMHX(line:sub(1, sp - 1))] = FROMHX(line:sub(sp + 1))
    end
end
LW   = assert(loadfile("__HIM/lwmap.lua"))()
CSV  = assert(loadfile("__HIM/csv.lua"))()
STR  = assert(loadfile("__HIM/store.lua"))()
PA   = assert(loadfile("__HIM/pathalgo.lua"))()
MD   = assert(loadfile("__HIM/mapdraw.lua"))()
CD   = assert(loadfile("__HIM/codec.lua"))()
JR   = assert(loadfile("__HIM/jobrun.lua"))()
CD.init { rows = 6 }
__FILES = __FILES or {}
REG = {}
function w16(a, v) REG[a] = v end
function w32(a, v) REG[a] = v; REG[a + 1] = 0 end
function wstr(a, s) REG[a] = s end
FIO = {
    write_all = function(p, d) __FILES[p] = d return true end,
    read_all  = function(p) return __FILES[p] end,
    append    = function(p, d) __FILES[p] = (__FILES[p] or "") .. d return true end,
    remove    = function(p) __FILES[p] = nil return true end,
}
STR.init(FIO, CSV, "3:")
__SENT = {}
__PROTO = {
    FNC = { GET_BZ_STATUS = 0x21, GET_TER_PARA = 0x26, STORE_AB = 0x23,
            SET_BZ_PARA = 0x20, SET_AB = 0x24, GDDD_ENABLE = 0x31,
            QZDD_ENABLE = 0x29,
            CMD_START_BZ = 0x0A, CMD_STOP_BZ = 0x0B },
    send = function(fnc, payload)
        payload = payload or ""
        __SENT[#__SENT + 1] = { fnc = fnc,
                                hex = (payload:gsub(".", function(c)
            return string.format("%02x", string.byte(c)) end)) }
    end,
}
__APP = { sub_always = function() end, register = function() end,
          set_always_poll = function() end, cur = nil }
__LOGS = {}
JR.init {
    APP = __APP, PROTOCOL = __PROTO, CODEC = CD,
    STORE = STR, PATHALGO = PA, LOGGER = {
        log = function(tag, msg) __LOGS[#__LOGS + 1] = tag .. " " .. msg end },
    LW = LW, w16 = w16, w32 = w32, wstr = wstr,
    now = function() return "2026-10-21 12:00:00" end,
}
'''.replace('__HIM', HIM)


def make_session(with_map, blob=None):
    """一次"开机": 新lua态+新sim; blob=None且with_map时导入地图建任务。"""
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    if blob is not None:
        lua.globals().__BLOB = blob
        lua.execute('LOAD_FILES(__BLOB)')
    if with_map:
        lua.globals().__HEXM = MAP_TXT.encode('gbk').hex()
        lua.globals().__MHX = '试验田4'.encode('gbk').hex()
        lua.execute('''
local _m = STR.map_import_text(FROMHX(__MHX), FROMHX(__HEXM))
assert(_m ~= nil, "地图导入失败")
STR.task_create("t1", FROMHX(__MHX), 0, 1, 0, 0, 0, "2026-10-21")
''')

    dev = Device(state_file=None, rows=6)
    dev.bd.StartState = 1
    wp = WorkProc(dev)
    nodes = []

    def process_frame(fnc, data):
        if fnc == SP.FNC_SET_BZ_PARA and len(data) == SL.SZ_BZ_CELL_PARA:
            p = SL.BzCellPara.unpack(data)
            nodes.append(p.RowNum)
            wp.set_bz_para(p)
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

    def feed():
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

    t = [1000]
    walk = []

    def run_until(pred, limit_ms=200000, label=''):
        n = 0
        while n * 10 < limit_ms:
            t[0] += 10
            wp.step(t[0])
            n += 1
            if n % 20 == 0:
                feed()
                drain()
                rn = wp.bz_curr.RowNum
                if not walk or walk[-1][1] != rn:
                    walk.append((t[0], rn))
                if pred():
                    return True
        return False

    def start(task):
        del nodes[:]
        lua.globals().__TK = task
        lua.execute('local ok, err = JR.start(__TK, {}); '
                    '__OK, __E = ok, tostring(err)')
        ok = bool(lua.eval('__OK'))
        drain()
        return ok, str(lua.eval('__E'))

    def stop():
        lua.execute('JR.stop()')
        drain()
        for _ in range(50):
            t[0] += 10
            wp.step(t[0])

    def states():
        lua.execute('''
__ST = {}
local t = STR.tasks["t1"]
for r = 0, 4 do
  for c = 0, 1 do
    __ST[#__ST + 1] = t.blocks[r][c].state
  end
end
''')
        return list(lua.eval('__ST').values())

    def rows_done():
        return sum(1 for s in states() if s == 2)

    def dump():
        return str(lua.eval('DUMP_FILES()'))

    return dict(lua=lua, wp=wp, nodes=nodes, walk=walk, run_until=run_until,
                start=start, stop=stop, states=states, rows_done=rows_done,
                dump=dump)


def main():
    print('1) 会话A: 趟1播种至row3中途(半小区)停止')
    s = make_session(True)
    ok, err = s['start']('t1')
    check(ok, 'start成功: %s' % err)
    ok1 = s['run_until'](lambda: s['wp'].bz_curr.RowNum == 3, label='驶入row3')
    check(ok1, '机器驶入row3')
    # 再走一小段让row3播一部分
    for _ in range(5):
        s['run_until'](lambda: False, limit_ms=200)
    s['stop']()
    st = s['states']()
    check(st[6] == 3, '停止即中断标红: 半趟块state=3(实有%s)' % st[6])
    check(st[0] == 2 and st[2] == 2 and st[4] == 2, '前3排完成state=2')

    print('2) 虚拟屏重启: boot转换 + EXCEED不被污染')
    blob = s['dump']()
    s2 = make_session(False, blob)
    lua2 = s2['lua']
    lua2.execute('STR.boot()')
    st2 = s2['states']()
    check(st2[6] == 3, '重启后中断块保持3')
    lua2.execute('__EXC = STR.tasks["t1"].sow_exceed')
    check(lua2.eval('__EXC') == 0,
          'EXCEED零值真值: 重启后sow_exceed=0(实有%s)' % lua2.eval('__EXC'))

    print('3) 继续任务: 续作跳过中断块, 落在row4实播')
    ok, err = s2['start']('t1')
    check(ok, '续作start成功: %s' % err)
    check(s2['nodes'][:1] == [4],
          '续作首节点=中断块下一排row4(实有%s)' % s2['nodes'][:3])
    ok3 = s2['run_until'](lambda: s2['rows_done']() >= 4, label='续作row4')
    check(ok3 and s2['states']()[8] == 2, 'row4完成实播(实有%s)' % s2['states']()[8])
    check(s2['states']()[6] == 3, '中断块保持3(密度0不补播, QT同)')

    print('4) 停止 -> 再开始: 跨到趟2(4->3->2->1->0递减)')
    s2['stop']()
    del s2['walk'][:]
    ok, err = s2['start']('t1')
    check(ok, '趟2 start成功: %s' % err)
    ok4 = s2['run_until'](lambda: s2['rows_done']() >= 9, label='趟2')
    seq = []
    for _, rn in s2['walk']:
        if isinstance(rn, int) and 0 <= rn <= 4:
            if not seq or seq[-1] != rn:
                seq.append(rn)
    check(ok4 and seq[:5] == [4, 3, 2, 1, 0],
          '趟2行序4->0递减(实见%s)' % seq[:6])
    check(s2['rows_done']() >= 9,
          '趟2完成(进度>=9/10, 实有%d)' % s2['rows_done']())

    print()
    print('中断续作回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
