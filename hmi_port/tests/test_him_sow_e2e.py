# -*- coding: utf-8 -*-
"""屏端jobrun×模拟器 e2e: 跨列续作路径回归(2026-10-14用户报修)。

场景(用户实测): QT+模拟器正常; 屏+模拟器"播完一列->停止->开始"后
模拟器不按选定路径走。虚拟时间全双工联调屏端jobrun与seeder_sim
WorkProc, 断言(QT dialogrealtimetask语义):
  趟1(列0, 梭形左起positive): rows 0->4 完成, trip_wait挂起
  停止 -> 开始(无resume参数, 对齐画面24开始按钮): 必须从列1续作
  (QT指针nextPathIndex跨启停延续 :275/:306-307, 不回卷到path[1])
  趟2(列1): rows 4->0, 全任务100%
运行: python hmi_port/tests/test_him_sow_e2e.py
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
    now = function() return "2026-10-14 12:00:00" end,
}
'''.replace('__HIM', HIM)

SAMPLE_MAP = '\r\n'.join([
    '信息,,,', '名称,e2e5x2', '类型,播种,排长(cm),过道长(cm)',
    '创建时间,,500,100', '修改时间,,500,100', '备注,,500,100',
    '排,5,500,100', '列,2,500,100', '小区行数,6,,100',
    '机器行数,6,,', '行间距(cm),60,,', ',,,',
    'AB线,,,', 'StartN,36.4', 'StartE,117', 'EndBN,36.438',
    'EndBE,117', 'StartDir,0', 'CalcDir,0', 'StartState,1',
    'CalcDirFlag,1', 'OffLen,0', 'BDOffTime,100', 'A点排,4', 'A点列,0',
    '方向,FALSE', '名称,AB', ',,,',
    '编号,,,', ',1列,2列', '5排,,,', '4排,,,', '3排,,,', '2排,,,',
    '1排,,,', ',,,',
    '密度,,,', ',1列,2列', '5排,4000,4000', '4排,4000,4000',
    '3排,4000,4000', '2排,4000,4000', '1排,4000,4000', ',,,',
    '是否播种,,,', ',1列,2列', '5排,1,1', '4排,1,1', '3排,1,1',
    '2排,1,1', '1排,1,1',
]) + '\r\n'


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    lua.globals().__HEXM = SAMPLE_MAP.encode('gbk').hex()
    lua.execute('''
local _m = (function(h)
    local s = ""
    for i = 1, #h, 2 do
        s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return STR.map_import_text("e2e5x2", s)
end)(__HEXM)
STR.task_create("t1", "e2e5x2", 0, 1, 0, 0, 0, "2026-10-14")
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
        # 0x27/0x25/0x29与路径无关, 忽略

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

    t = [1000]
    trace = []          # (虚拟时刻, 模拟器当前引导RowNum, run_state)

    def run_until(pred, limit_ms=150000, label=''):
        n = 0
        while n * 10 < limit_ms:
            t[0] += 10
            wp.step(t[0])
            n += 1
            if n % 20 == 0:               # 200ms轮询
                feed_status()
                drain()
                trace.append((t[0], wp.bz_curr.RowNum,
                              wp.get_bz_status()['run_state'],
                              wp.get_bz_status()['off_len'],
                              wp.debug[:16]))
                if pred():
                    return True
        return False

    def trip_wait():
        return bool(lua.eval(
            'JR.snapshot() ~= nil and JR.snapshot().trip_wait == true'))

    def rows_done(col):
        lua.execute('''
local t = STR.tasks["t1"]
__ND = 0
for r = 0, 4 do
    if t.blocks[r][COL] and t.blocks[r][COL].state == 2 then
        __ND = __ND + 1
    end
end
'''.replace('COL', str(col)))
        return lua.eval('__ND')

    print('1) 趟1(列0)正向播种至完成')
    lua.execute('local ok, err = JR.start("t1", {}); __OK, __E = ok, tostring(err)')
    check(bool(lua.eval('__OK')), 'start#1成功: %s' % lua.eval('__E'))
    drain()
    ok1 = run_until(lambda: trip_wait() or rows_done(0) >= 5, label='趟1')
    check(ok1 and rows_done(0) == 5,
          '趟1列0完成5/5(实有%d)' % rows_done(0))
    print('    trace采样:', trace[:6], '...', trace[-3:])
    trip1_row_seq = [rn for _, rn, rs, _, _ in trace
                     if rs == 0x81 and rn is not None and 0 <= rn <= 4]
    seen1 = []
    for r in trip1_row_seq:
        if not seen1 or seen1[-1] != r:
            seen1.append(r)
    check(seen1[:5] == [0, 1, 2, 3, 4], '趟1行序0->4(实见%s)' % seen1[:6])

    print('2) 停止 -> 开始(画面24开始按钮, 无resume参数)')
    lua.execute('JR.stop()')
    drain()
    for _ in range(50):
        t[0] += 10
        wp.step(t[0])
    trace.clear()
    lua.execute('local ok, err = JR.start("t1", {}); __OK2, __E2 = ok, tostring(err)')
    check(bool(lua.eval('__OK2')), 'start#2成功: %s' % lua.eval('__E2'))
    drain()
    ok2 = run_until(lambda: trip_wait() or rows_done(1) >= 5, label='趟2')
    check(ok2 and rows_done(1) == 5,
          '趟2列1完成5/5(实有%d)' % rows_done(1))
    trip2_row_seq = [rn for _, rn, rs, _, _ in trace
                     if rs == 0x81 and rn is not None and 0 <= rn <= 4]
    seen2 = []
    for r in trip2_row_seq:
        if not seen2 or seen2[-1] != r:
            seen2.append(r)
    check(seen2[:5] == [4, 3, 2, 1, 0],
          '趟2行序4->0(列1反向, 实见%s)' % seen2[:6])
    lua.execute('local a,b,c = STR.task_progress("t1"); __P = c')
    check(lua.eval('__P') == 100, '任务完成率100%%(实有%d%%)' % lua.eval('__P'))

    print('3) 导出结果校验(显示排号口径, QT :324)')
    lua.execute('''
local txt = STR.export_task_text("t1")
__EXPH = (txt:gsub(".", function(c)
    return string.format("%02x", string.byte(c)) end))
''')
    exp = bytes.fromhex(str(lua.eval('(__EXPH)'))).decode('gbk')
    CRLF = chr(13) + chr(10)
    res_lines = [l for l in exp.split(CRLF)
                 if l and len(l.split(',')) == 17
                 and l.split(',')[0].isdigit()]
    check(len(res_lines) == 10, '结果行数10(实有%d)' % len(res_lines))
    pairs = set()
    for l in res_lines:
        f = l.split(',')
        pairs.add((int(f[0]), int(f[1])))
    check(pairs == {(r, c) for r in (1, 2, 3, 4, 5) for c in (1, 2)},
          '结果覆盖显示排1-5x列1-2(显示排号口径)')
    bad_time = [l for l in res_lines if len(l.split(',')) < 5
                or not l.split(',')[2]]
    check(not bad_time, '结果行含开始时间')

    print()
    print('播种e2e回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
