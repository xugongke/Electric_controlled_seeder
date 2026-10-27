# -*- coding: utf-8 -*-
r"""地图外播种(sow_exceed)回归: 2026-10-20 FinalFlag极性修复。

被测: HIMproject/Project/pathalgo.lua start_node + jobrun运行链×seeder_sim。
背景: 协议注释(QT protocol.h)规定"启用地图外播种FinalFlag恒0"; 固件语义
0=继续播下小区(work_proc.c:952 FinalFlag==0才DZ_ON), 1=最后一小区收尾。
此前屏端b=1时图内Final/NextFinal发1 -> 固件/sim第一小区即收尾停播,
图外播种整链无效(用户实测"功能没实现")。
QT源码 dialogrealtimetask.cpp:724 图内当前排(b||..)?1:0 与其自身协议注释
矛盾, 屏端不照抄该行; NextFinal行/图外行与注释一致, 照抄。

场景:
  1) 单元: start_node b=0/1 x 正/反向, 图内首/中/末排+图外虚拟排极性矩阵
  2) e2e: jobrun x seeder_sim WorkProc 虚拟时间全双工, 图外开5x2地图正向
     一趟: 首节点=图外虚拟排-1(驶入段密度=首小区, M55) -> 入图补发 -> 全趟5排完成
     (旧代码sim在首小区收尾, 完成不了 -> 本测试拦截回归)
运行: python hmi_port/tests/test_him_sow_exceed.py
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


UNIT = r'''
LW = assert(loadfile("__HIM/lwmap.lua"))()
PA = assert(loadfile("__HIM/pathalgo.lua"))()

__M = {
    rows = 5, cols = 2, machine_cols = 6, block_col = 6,
    rowlen = { 500, 500, 500, 500, 500 },
    aisle  = { 100, 100, 100, 100, 100, 100 },
    blocks = {},
}
for r = 0, 4 do
    __M.blocks[r] = {}
    for c = 0, 1 do
        -- 文件N排=内部rows-N: 内部0..4密度 3000/3500/4000/4500/5000
        __M.blocks[r][c] = { density = 3000 + r * 500 }
    end
end

__T1 = { sow_exceed = 1, blocks = {} }   -- 图外开
__T0 = { sow_exceed = 0, blocks = {} }   -- 图外关
for r = 0, 4 do
    __T1.blocks[r] = {}
    __T0.blocks[r] = {}
    for c = 0, 1 do
        __T1.blocks[r][c] = { state = 0, sow = 1 }
        __T0.blocks[r][c] = { state = 0, sow = 1 }
    end
end

__AB = { has = false, dir = false, a_row = 0 }
__PATH_P = PA.create_path(__M, 0, true)    -- 梭形左起, 列0正向(row 0->4)
__PATH_N = PA.create_path(__M, 0, false)   -- 列0反向(row 4->0)

function SN(t, path, row)
    return PA.start_node(t, __M, path, row, 0, __AB, nil)
end
'''.replace('__HIM', HIM)

E2E_HARNESS = r'''
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

# 密度按内部行0..4 = 3000..5000 递增(文件5排=内部0=3000 ... 文件1排=内部4=5000),
# 密度按内部行0..4=3000..5000递增: 正向驶入段应取内部0=3000(M55前误取内部4)
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


def unit_part():
    print('1) start_node FinalFlag 极性矩阵(单元)')
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(UNIT)
    # (task, path, row) -> (FinalFlag, NextFinalFlag)
    cases = [
        # b=1 图外开: 协议注释"恒0" —— 图内首/中/末排 + 图外虚拟排
        ('__T1', '__PATH_P', 0, (0, 0), 'b1正向首排(下一排图内)'),
        ('__T1', '__PATH_P', 3, (0, 0), 'b1正向中排(下一排=末排, 旧码Next=1)'),
        ('__T1', '__PATH_P', 4, (0, 0), 'b1正向末排(下一排出图)'),
        ('__T1', '__PATH_P', -1, (0, 0), 'b1图外虚拟排-1(首节点)'),
        ('__T1', '__PATH_P', 5, (0, 0), 'b1图外虚拟排5'),
        ('__T1', '__PATH_N', 0, (0, 0), 'b1反向首排(边界)'),
        # b=0 图外关: 原语义逐值不变
        ('__T0', '__PATH_P', 0, (0, 0), 'b0正向首排'),
        ('__T0', '__PATH_P', 3, (0, 1), 'b0正向中排(下一排=末排 Next=1)'),
        ('__T0', '__PATH_P', 4, (1, 1), 'b0正向末排(Final=1)'),
        ('__T0', '__PATH_P', -1, (1, 0), 'b0图外-1(下一排=图内首排 Next=0)'),
        ('__T0', '__PATH_N', 0, (1, 1), 'b0反向首排(边界 Final=1)'),
        ('__T0', '__PATH_N', 4, (0, 0), 'b0反向末排'),
    ]
    for tname, pname, row, (ef, enf), label in cases:
        lua.globals().__R = row
        lua.globals().__T = lua.eval(tname)
        lua.globals().__P = lua.eval(pname)
        lua.execute('__N = SN(__T, __P, __R)')
        f = lua.eval('__N.FinalFlag')
        nf = lua.eval('__N.NextFinalFlag')
        check(f == ef and nf == enf,
              '%s: Final=%d Next=%d (期望 %d/%d)'
              % (label, f, nf, ef, enf))
    # M55: 首节点(图外虚拟排)密度=驶入图内第一小区: 正向->内部首排3000
    lua.execute('__N = SN(__T1, __PATH_P, -1)')
    check(lua.eval('__N.Density[1]') == 3000,
          'b1图外-1正向: 驶入段密度=首小区3000(原钳位末排5000系反向, 已修)')
    check(lua.eval('__N.RowNum') == -1
          and lua.eval('__N.DisplayRowNum') == 6,
          'b1图外-1: RowNum=-1 DisplayRowNum=rows+1')
    lua.execute('__N = SN(__T1, __PATH_N, 5)')
    check(lua.eval('__N.Density[1]') == 5000,
          'b1图外5反向: 驶入段密度=末小区5000')
    lua.execute('__N = SN(__T1, __PATH_P, 0)')
    check(lua.eval('__N.Density[1]') == 3000,
          'b1入图首排: 密度=内部0行3000(不钳位)')


def e2e_part():
    print('2) e2e: 图外开正向一趟(jobrun x seeder_sim)')
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(E2E_HARNESS)
    lua.globals().__HEXM = EX_MAP.encode('gbk').hex()
    lua.execute('''
local _m = (function(h)
    local s = ""
    for i = 1, #h, 2 do
        s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return STR.map_import_text("e2eex", s)
end)(__HEXM)
__MOK = (_m ~= nil)
STR.task_create("tx", "e2eex", 0, 1, 1, 0, 0, "2026-10-20")
''')
    check(bool(lua.eval('__MOK')), '地图导入')
    if FAIL:
        return

    dev = Device(state_file=None, rows=6)
    dev.bd.StartState = 1
    wp = WorkProc(dev)
    bz20 = []                      # 收到的0x20组参(BzCellPara)

    def process_frame(fnc, data):
        if fnc == SP.FNC_SET_BZ_PARA and len(data) == SL.SZ_BZ_CELL_PARA:
            p = SL.BzCellPara.unpack(data)
            bz20.append(p)
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

    def run_until(pred, limit_ms=150000, label=''):
        n = 0
        while n * 10 < limit_ms:
            t[0] += 10
            wp.step(t[0])
            n += 1
            if n % 20 == 0:
                feed_status()
                drain()
                if pred():
                    return True
        return False

    def rows_done(col):
        lua.globals().__COL = col
        lua.execute('''
local t = STR.tasks["tx"]
__ND = 0
for r = 0, 4 do
    if t.blocks[r][__COL] and t.blocks[r][__COL].state == 2 then
        __ND = __ND + 1
    end
end
''')
        return lua.eval('__ND')

    ok = bool(lua.eval('select(1, JR.start("tx", {}))'))
    check(ok, 'start成功(图外开任务)')
    drain()

    check(len(bz20) >= 1, '首节点0x20已发')
    n0 = bz20[0]
    check(n0.RowNum == -1 and n0.NextRowNum == 0,
          '图外起播: 首节点RowNum=-1 Next=0 (实际 %s/%s)'
          % (n0.RowNum, n0.NextRowNum))
    check(n0.FinalFlag == 0 and n0.NextFinalFlag == 0,
          '图外起播: Final=0 Next=0(恒0)')
    check(n0.Density[0] == 3000,
          '图外起播: 驶入段密度=首小区3000(M55, 原误钳位末排, 实际 %s)'
          % n0.Density[0])
    check(n0.DisplayRowNum == 6, 'DisplayRowNum=rows+1=6')

    def entered_map():
        return any(p.RowNum == 0 for p in bz20)

    got = run_until(entered_map, label='入图')
    check(got, '机进入图内(0x21 RowNum=0)后补发入图首排')
    n_in = next(p for p in bz20 if p.RowNum == 0)
    check(n_in.FinalFlag == 0,
          '入图首排 FinalFlag=0 (旧码=1致sim首小区收尾停播)')
    check(n_in.NextFinalFlag == 0, '入图首排 NextFinalFlag=0(b=1恒0)')
    check(n_in.Density[0] == 3000, '入图首排密度=内部0行3000')

    def all_done():
        return rows_done(0) == 5

    got = run_until(all_done, limit_ms=150000, label='趟完成')
    check(got, '图外开整趟5排全部完成(播种链未被FinalFlag打断)')
    if got:
        lua.execute('__D = select(1, STR.task_progress("tx"))')
        d = lua.eval('__D')
        check(d == 5, '任务进度5/10块 (实际 %s)' % d)

    # M56: 趟间时序(手动帧驱动趟2; seeder_sim不支持掉头后反向步行,
    #      真机GNSS掉头为物理行驶无此限——本段验证的是作业引擎下发时序):
    #  趟1末排(内部0)完成帧为出图帧 -> 不下发新参数(保持末小区继续播);
    #  再入图新趟首排(内部4) -> 补发新趟首小区参数; 逐排完成至10/10
    lua.execute("__D = select(1, STR.task_progress('tx'))")
    check(lua.eval('__D') == 5, '趟1进度5/10')

    def feed_row(rownum):
        payload = SL.pack_bz_status(row_num=rownum, bd_state=1, speed=1000,
            louzh=[1, 1, 1, 1, 1, 1], loufei=[1, 1, 1, 1, 1, 1],
            vertical_off=0, off_len=0, run_state=0x81)
        lua.globals().__STHX = payload.hex()
        lua.execute("""
local h = __STHX
local s2 = ""
for i = 1, #h, 2 do
    s2 = s2 .. string.char(tonumber(h:sub(i, i + 1), 16))
end
JR._feed { data = s2 }
""")
        drain()

    # 每排两帧: 入图帧(分发state=1) + 下一排帧(触发完成+advance补发)
    feed_row(4)
    n_t2 = [p for p in bz20 if p.RowNum == 4]
    check(len(n_t2) >= 1 and n_t2[-1].Density[0] == 5000,
          '再入图新趟首排: 补发首小区参数(密度5000)')
    for rn in (4, 3, 3, 2, 2, 1, 1, 0, -1):
        feed_row(rn)
    lua.execute("__D = select(1, STR.task_progress('tx'))")
    check(lua.eval('__D') == 10, '趟2逐排完成: 进度10/10(实际 %s)'
          % lua.eval('__D'))
    lua.execute('JR.stop()')
    drain()

    drain()

def dump_sim(wp):
    dbg = wp.debug if isinstance(wp.debug, str) else         wp.debug.encode('gbk', errors='replace').decode('gbk', errors='replace')
    print('SIM: mode=%s pos=%.1f debug=%s'
          % (wp.seed_mode, wp.pos_cm, dbg))


def main():
    unit_part()
    e2e_part()
    print()
    if FAIL:
        print('地图外播种: %d项失败' % FAIL)
        return 1
    print('地图外播种: 全部通过 (%d项)' % PASS)
    return 0


if __name__ == '__main__':
    sys.exit(main())
