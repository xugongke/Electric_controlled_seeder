# -*- coding: utf-8 -*-
r"""屏端jobrun×模拟器 e2e: 路径推进回归(2026-10-20跨趟自动续发)。

背景: 2026-10-20用户实测QT在100%完成后再开始, 模拟器按选定路径顺序走
下一趟(而非每次都重走趟1); 屏端旧trip_wait挂起+起点回退致趟2永不轮到。
对齐QT :306-307(停止续作指针=tempIndex=最后作业位置+1, 越尾回绕)后守:
  1) 趟1列0正向(0->4) -> 停止 -> 开始自动续趟2列1反向(4->0) -> 100%
  2) 100%后再开始: 回绕续驶下一趟(密度0驶过), 不重置不重复计数
  3) 中途停止 -> 开始: 续作扫描落在首个未完成排(2026-10-14六修回归)
  4) 导出结果校验(显示排号口径, QT :324)
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
    now = function() return "2026-10-20 12:00:00" end,
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


def seen_rows(trace):
    out = []
    for _, rn, _rs, _, _ in trace:
        if rn is not None and 0 <= rn <= 4:
            if not out or out[-1] != rn:
                out.append(rn)
    return out


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
__MOK = (_m ~= nil)
STR.task_create("t1", "e2e5x2", 0, 1, 0, 0, 0, "2026-10-20")
STR.task_create("t2", "e2e5x2", 0, 1, 0, 0, 0, "2026-10-20")
''')
    check(bool(lua.eval('__MOK')), '地图导入')

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

    t = [1000]
    trace = []          # (虚拟时刻, 模拟器当前引导RowNum, run_state, ...)

    def run_until(pred, limit_ms=250000, label=''):
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

    def rows_done(task, col):
        lua.globals().__TASK = task
        lua.globals().__COL = col
        lua.execute('''
local t = STR.tasks[__TASK]
__ND = 0
for r = 0, 4 do
    if t.blocks[r][__COL] and t.blocks[r][__COL].state == 2 then
        __ND = __ND + 1
    end
end
''')
        return lua.eval('__ND')

    def progress(task):
        lua.globals().__PT = task
        lua.execute('__D = select(1, STR.task_progress(__PT)); '
                    '__P = select(3, STR.task_progress(__PT))')
        return lua.eval('__D'), lua.eval('__P')

    def start(task):
        lua.globals().__TK = task
        lua.execute('local ok, err = JR.start(__TK, {}); '
                    '__OK, __E = ok, tostring(err)')
        ok = bool(lua.eval('__OK'))
        drain()
        return ok, str(lua.eval('__E'))

    def stop_and_settle():
        lua.execute('JR.stop()')
        drain()
        for _ in range(50):
            t[0] += 10
            wp.step(t[0])

    print('1) 趟1列0正向(0->4) -> 停止 -> 开始自动续趟2列1反向(4->0, QT :306-307)')
    ok, err = start('t1')
    check(ok, 'start#1成功: %s' % err)
    ok1 = run_until(lambda: rows_done('t1', 0) == 5, label='趟1')
    check(ok1 and rows_done('t1', 0) == 5,
          '趟1列0完成5/5(实有%d)' % rows_done('t1', 0))
    seq = seen_rows(trace)
    check(seq[:5] == [0, 1, 2, 3, 4], '趟1行序0->4(实见%s)' % seq[:6])
    stop_and_settle()
    trace.clear()
    ok, err = start('t1')
    check(ok, '趟2 start成功: %s' % err)
    ok1 = run_until(lambda: rows_done('t1', 1) == 5, label='趟2')
    check(ok1 and rows_done('t1', 1) == 5,
          '续作自动落在趟2列1并完成5/5(实有%d)' % rows_done('t1', 1))
    seq = seen_rows(trace)
    check(seq[:5] == [4, 3, 2, 1, 0], '趟2行序4->0(实见%s)' % seq[:6])
    d, p = progress('t1')
    check(d == 10 and p == 100, '任务完成10/10块 100%%(实有%d/%d%%)' % (d, p))

    print('2) 100%后再开始: 第1次回绕趟1(递增), 第2次回绕趟2(3000递减)——用户实测场景')
    stop_and_settle()
    trace.clear()
    ok, err = start('t1')
    check(ok, '100%%后第1次start成功: %s' % err)
    ok2 = run_until(lambda: rows_done('t1', 0) == 5 and
                    any(rn == 5 for _, rn, _, _, _ in trace), label='重驶趟1')
    check(ok2, '第1次重驶走趟1(递增, 密度0驶过)')
    seq2 = seen_rows(trace)
    check(seq2[:5] == [0, 1, 2, 3, 4], '第1次重驶行序0->4(实见%s)' % seq2[:6])
    stop_and_settle()
    trace.clear()
    ok, err = start('t1')
    check(ok, '100%%后第2次start成功: %s' % err)
    ok2 = run_until(lambda: rows_done('t1', 1) == 5 and
                    any(rn == -1 for _, rn, _, _, _ in trace), label='重驶趟2')
    check(ok2, '第2次重驶自动落在趟2(递减, 修复点: 锚点用机器实时位置)')
    seq2 = seen_rows(trace)
    check(seq2[:5] == [4, 3, 2, 1, 0], '第2次重驶行序4->0递减(实见%s)' % seq2[:6])
    d, p = progress('t1')
    check(d == 10 and p == 100, '任务未重置 仍10/10 100%%(实有%d/%d%%)' % (d, p))
    lua.execute('__EXH = (STR.export_task_text("t1"):gsub(".", function(c) return string.format("%02x", string.byte(c)) end))')
    exp = bytes.fromhex(str(lua.eval('(__EXH)'))).decode('gbk')
    CRLF = chr(13) + chr(10)
    res = [l for l in exp.split(CRLF)
           if l and len(l.split(',')) == 17 and l.split(',')[0].isdigit()]
    check(len(res) == 10, '重驶后结果仍10行(无重复计数, 实有%d)' % len(res))
    check(all(int(l.split(',')[5]) in (20, 21) for l in res),
          '重驶后计数无0值且为20/21')

    print('3) 中途停止 -> 开始: 续作扫描落在首个未完成排(六修回归)')
    stop_and_settle()
    trace.clear()
    ok, err = start('t2')
    check(ok, 't2 start成功: %s' % err)
    ok3 = run_until(lambda: rows_done('t2', 0) >= 2, label='t2前两排')
    check(ok3, 't2播完前两排')
    stop_and_settle()
    trace.clear()
    ok, err = start('t2')
    check(ok, 't2续作start成功: %s' % err)
    ok3 = run_until(lambda: rows_done('t2', 0) == 5, label='t2趟1余下')
    seq3 = seen_rows(trace)
    check(seq3[:3] == [2, 3, 4],
          '续作自首个未完成排row2起(实见%s)' % seq3[:4])
    check(ok3 and rows_done('t2', 0) == 5,
          '续作走完趟1余下(实有%d)' % rows_done('t2', 0))
    stop_and_settle()
    trace.clear()
    ok, err = start('t2')
    check(ok, 't2趟2 start成功: %s' % err)
    ok3 = run_until(lambda: rows_done('t2', 1) == 5, label='t2趟2')
    check(ok3 and rows_done('t2', 1) == 5,
          '续作跨组落在趟2并完成(实有%d)' % rows_done('t2', 1))
    d, p = progress('t2')
    check(d == 10 and p == 100, 't2完成10/10 100%%(实有%d/%d%%)' % (d, p))

    print('4) 导出结果校验(t2, 显示排号口径)')
    lua.execute('__EXH2 = (STR.export_task_text("t2"):gsub(".", function(c) return string.format("%02x", string.byte(c)) end))')
    exp4 = bytes.fromhex(str(lua.eval('(__EXH2)'))).decode('gbk')
    res_lines = [l for l in exp4.split(CRLF)
                 if l and len(l.split(',')) == 17
                 and l.split(',')[0].isdigit()]
    check(len(res_lines) == 10, '结果行数10(实有%d)' % len(res_lines))
    prs = set()
    for l in res_lines:
        f = l.split(',')
        prs.add((int(f[0]), int(f[1])))
    check(prs == {(r, c) for r in (1, 2, 3, 4, 5) for c in (1, 2)},
          '结果覆盖显示排1-5x列1-2')
    cnt_ok = sum(1 for l in res_lines if int(l.split(',')[5]) in (20, 21))
    check(cnt_ok == 10, '10行计数全为20/21(实有%d)' % cnt_ok)

    print()
    print('播种e2e回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
