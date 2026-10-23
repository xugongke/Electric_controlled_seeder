# -*- coding: utf-8 -*-
"""任务管理/实时播种页面回归: 2026-10-13 M3拆页重构(画面9/25/24)。

被测: HIMproject/Project/{page_taskmgr,page_sowrt,store}.lua (lupa装配冒烟)
  1) page_taskmgr: 列表渲染/选中移动/删除/重置/开始预选+跳转
  2) 画面25新建: 默认名/确定创建(名称写入寄存器->task_create)/地图上下移
  3) page_sowrt: 预选进入/参数加载/无AB线图外强制关/开始收参调jobrun.start
     +gap直读/改起点应用(outset 0基换算)/结果跳转预选
  4) store: task_reset清0+结果清空; export->import往返
运行: python hmi_port/tests/test_him_taskmgr_sowrt.py
"""
import os
import sys

from lupa import lua53 as lupa_lua

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = os.path.join(ROOT, 'HIMproject', 'Project').replace('\\', '/')

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

-- 寄存器桩: w16/w32/wstr写入表, r16/rstr读回
REG = {}
function w16(a, v) REG[a] = v end
function w32(a, v) REG[a] = v; REG[a + 1] = 0 end
function wstr(a, s) REG[a] = s end
function r16(a) return REG[a] end
function rstr(a) return REG[a] end

FS = {}
FIO = {
    write_all = function(p, d) FS[p] = d return true end,
    read_all  = function(p) return FS[p] end,
    append    = function(p, d) FS[p] = (FS[p] or "") .. d; return true end,
    remove    = function(p) FS[p] = nil return true end,
}
STR.init(FIO, CSV, "3:")

-- jobrun桩
JR = { ver = 0, started = nil, stopped = 0, cleared = nil,
       act = false, snap = nil }
function JR.active() return JR.act end
function JR.snapshot() return JR.snap end
function JR.start(name, opts)
    JR.started = { name = name, opts = opts } return true
end
function JR.stop() JR.stopped = JR.stopped + 1 end
function JR.ab_clear_map(n) JR.cleared = n return true end
JR.draw_ver = 0

-- APP桩
APPX = { pages = {}, goto_sid = nil,
         register = function(pg) APPX.pages[pg.id] = pg end,
         goto_screen = function(sid) APPX.goto_sid = sid end }

CTX = { LW = LW, APP = APPX, STORE = STR, JOBRUN = JR, MAPDRAW = MD,
        LOGGER = nil, FILEIO = FIO, PROTOCOL = {
            FNC = { GET_BZ_STATUS = 0x21, CMD_START_BZ = 0x0A,
                QZDD_ENABLE = 0x29, GDDD_ENABLE = 0x31 },
            sent = {},
            send = function(fnc, p)
                table.insert(PROTO.sent, { fnc = fnc, p = p })
            end },
        w16 = w16, w32 = w32, wstr = wstr, r16 = r16, rstr = rstr,
        now = function() return "2026-10-13 12:00:00" end }
PROTO = CTX.PROTOCOL
'''

SAMPLE_MAP = '\r\n'.join([
    '信息,,,', '名称,demo5', '类型,播种,排长(cm),过道长(cm)',
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
    lua.globals().__HIM = HIM
    inject = lambda var, text: lua.execute(
        '%s = (function(h) local s="" for i=1,#h,2 do '
        's=s..string.char(tonumber(h:sub(i,i+1),16)) end return s end)(__V.%s)'
        % (var, var)) if False else None
    # 注入地图文本(hex中转)
    lua.globals().__V = {'M': SAMPLE_MAP.encode('gbk').hex()}
    lua.execute(HARNESS.replace('__HIM', HIM))
    lua.execute('''
__V = __V or {M = __HEXM}
''')
    # 简化: 直接在lua侧用hex解码
    lua.globals().__HEXM = SAMPLE_MAP.encode('gbk').hex()
    lua.execute('''
local _imported = (function(h)
    local s = ""
    for i = 1, #h, 2 do
        s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return STR.map_import_text("demo5", s)
end)(__HEXM)
P9 = (assert(loadfile("__HIM/page_taskmgr.lua"))())(CTX)
P24 = (assert(loadfile("__HIM/page_sowrt.lua"))())(CTX)
'''.replace('__HIM', HIM))

    print('1) 任务管理页(画面9)')
    lua.execute('P9:on_enter()')
    check(lua.eval('REG[LW.TM.count]') == 0, '初始无任务count=0')
    # 通过画面25创建任务
    print('2) 新建任务对话框(画面25)')
    lua.execute('''
local dlg = APPX.pages[LW.SCREEN.NEWTASK]
dlg:on_enter()
wstr(LW.NT.name, "t1")
-- 选定地图为第1张(演示田5)
''')
    lua.execute('APPX.pages[LW.SCREEN.NEWTASK]:on_update(LW.NT.btn_ok, 1)')
    check(bool(lua.eval('STR.tasks["t1"] ~= nil')), '确定创建任务t1')
    lua.execute('P9:on_enter()')
    check(lua.eval('REG[LW.TM.count]') == 1, '列表count=1')
    lua.execute('''
__TDH = (REG[LW.TM.tdetail]:gsub(".", function(c)
    return string.format("%02x", string.byte(c)) end))
''')
    td = bytes.fromhex(str(lua.eval('__TDH'))).decode('gbk')
    check('t1' in td and '地图:demo5' in td and '完成率:0%' in td
          and '最近作业:' in td,
          '详情QT风格合并文本(M42, 实有%r)' % td[:60])
    check('TM.tpct' not in open(os.path.join(HIM, 'page_taskmgr.lua'),
                                encoding='gb18030').read()
          and 'TM.btn_sel' not in open(os.path.join(HIM, 'page_taskmgr.lua'),
                                       encoding='gb18030').read(),
          '旧六字段/刷新按钮引用已清(M42)')
    # 开始任务 -> 预选+跳24
    lua.execute('P9:on_update(LW.TM.btn_start, 1)')
    check(lua.eval('APPX.goto_sid') == lua.eval('LW.SCREEN.SOWRT'),
          '开始任务跳画面24')
    check(bool(lua.eval('APPX.preset_sowrt_task == "t1"')), '预选任务名传递')

    # 回归: 弹窗不触发on_enter, 靠[新建任务]执行通知初始化(2026-10-13实测地图数0)
    lua.execute('''
wstr(LW.NT.name, "")
w16(LW.NT.count, 0)
P9:on_update(LW.TM.btn_new, 1)
''')
    check(lua.eval('REG[LW.NT.count]') == 1, 'btn_new通知初始化: 地图数=1')
    lua.globals().__EXP = '任务2'.encode('gbk').hex()
    lua.execute('''
__NAMEOK = (REG[LW.NT.name] == (function(h)
    local s = ""
    for i = 1, #h, 2 do
        s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return s
end)(__EXP))
''')
    check(bool(lua.eval('__NAMEOK')), 'btn_new通知初始化: 默认名任务2(Lua侧比较)')

    print('3) 实时播种页(画面24)')
    lua.execute('P24:on_enter()')
    check(lua.eval('REG[LW.RT.tname]') == 't1', '任务名显示')
    check(lua.eval('REG[LW.RT.path_type]') == 0
          and lua.eval('REG[LW.RT.sp_row]') == 5,
          '参数加载(路径0/起始排默认=地图末排5)')
    # 设置参数后开始
    lua.execute('''
w16(LW.RT.path_type, 1)
w16(LW.RT.positive, 1)
w16(LW.RT.sow_exceed, 1)     -- 有AB线 -> 允许
w16(LW.RT.gapdot, 2)
P24:on_update(LW.RT.btn_start, 1)
''')
    st = lua.eval('JR.started')
    check(st is not None and st['name'] == 't1', 'jobrun.start(t1)被调')

    check(lua.eval('STR.tasks["t1"].path_type') == 1
          and lua.eval('STR.tasks["t1"].positive') == 1,
          '任务参数已收(path=1/正向)')
    check(lua.eval('STR.tasks["t1"].sow_exceed') == 1, '有AB线图外=1保留')
    # 改起点: sp_row=1(显示) -> outset.r = rows-1 = 4
    lua.execute('''
w16(LW.RT.sp_enable, 1)
w16(LW.RT.sp_row, 1)
w16(LW.RT.sp_col, 2)
P24:on_update(LW.RT.btn_spply, 1)
''')
    check(lua.eval('STR.tasks["t1"].outset.r') == 4
          and lua.eval('STR.tasks["t1"].outset.c') == 1,
          '起点应用(显示(1,2)->0基(4,1))')
    check(lua.eval('REG[LW.RT.sp_enable]') == 0, '应用后开关复位')

    print('4) 无AB线图外强制关')
    # python侧过滤AB线区块 -> hex注入(避免中文字面量跨编码边界)
    noab = []
    in_ab = False
    for ln in SAMPLE_MAP.split('\r\n'):
        if ln.startswith('AB线'):
            in_ab = True
            continue
        if in_ab and ln.startswith('编号'):
            in_ab = False
        if not in_ab:
            noab.append(ln)
    noab = ['名称,demo6' if ln == '名称,demo5' else ln for ln in noab]
    lua.globals().__HEX2 = ('\r\n'.join(noab)).encode('gbk').hex()
    lua.execute('''
local _m2 = (function(h)
    local s = ""
    for i = 1, #h, 2 do
        s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
    end
    return STR.map_import_text("demo6", s)
end)(__HEX2)
STR.task_create("t2", "demo6", 0, 1, 0, 0, 0, "2026-10-13")
APPX.preset_sowrt_task = "t2"
P24:on_enter()
w16(LW.RT.sow_exceed, 1)
P24:on_update(LW.RT.btn_start, 1)
''')
    check(lua.eval('STR.tasks["t2"] ~= nil'), '无AB地图任务t2已建')
    check(lua.eval('STR.tasks["t2"].sow_exceed') == 0,
          '无AB线: 图外播种强制0')

    print('5) store 重置/导入导出往返')
    lua.execute('''
w16(LW.RT.sp_enable, 0)
STR.tasks["t1"].blocks[0][0].state = 2
local ok = STR.task_reset("t1")
''')
    check(bool(lua.eval('STR.tasks["t1"].blocks[0][0].state') == 0),
          '重置清块状态')
    lua.execute('''
local txt = STR.export_task_text("t1")
local t2x, err = STR.task_import_text(txt)
IMP = { ok = t2x ~= nil, err = err }
''')
    check(bool(lua.eval('IMP.ok')), '导出->导入往返成功')
    # 新Excel格式形状: 信息/状态/是否播种/结果四区 + √标记 + 1基结果行
    # (导出为GB2312字节, Lua字面量是UTF-8不可直接比, hex中转到python断言)
    lua.execute('''
local txt = STR.export_task_text("t2")
__EXPH = (txt:gsub(".", function(c)
    return string.format("%02x", string.byte(c)) end))
''')
    exp_txt = bytes.fromhex(str(lua.eval('(__EXPH)'))).decode('gbk')
    check(all(k in exp_txt for k in
              ('信息\r\n名称,', '\r\n状态\r\n', '\r\n是否播种\r\n', '\r\n结果\r\n',
               '√', '排,列,开始时间,完成时间,状态,1行播种,2行播种',
               '1行漏肥,2行漏肥', '路线方向,反')),
          '导出格式含信息/状态/是否播种/结果区+√+双表头+方向')
    # 删除(非作业中)
    lua.execute('''
P9:on_enter()
P9:on_update(LW.TM.btn_del, 1)
''')
    check(lua.eval('REG[LW.TM.count]') == 1, '删除后剩1个任务(t2)')

    print('6) rstr真实布局回归(2026-10-14用户dump实证)')
    # 源码级断言: 页面ctx必须含rstr(五修漏配曾被PC桩遮蔽)
    msrc = open(os.path.join(HIM, 'main.lua'), 'rb').read().decode('gb18030')
    ci = msrc.find('local ctx = {')
    check('rstr = rstr' in msrc[ci:ci + 500], 'main.lua页面ctx含rstr注入')
    # 从main.lua提取rstr函数体, 在lupa里以真实布局执行
    CRLF = chr(13) + chr(10)
    i = msrc.find('local function rstr')
    j = msrc.find(CRLF + 'end' + CRLF, i) + len(CRLF + 'end' + CRLF)
    fn_src = msrc[i:j] + CRLF + 'return rstr'
    lua.globals().__FN = fn_src
    lua.execute('''
__RSTR = (loadstring or load)(__FN)()
-- 用户dump: C8CE CEF1 3100 0000... = "任务1"(每字2字节高在前, 半字NUL止)
__WORDS = { 0xC8CE, 0xCEF1, 0x3100, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000 }
__WI = 0
function __g16(vt, a)
    __WI = __WI + 1
    return __WORDS[__WI]
end
VT_LW = 1
__ENV_RSTR = (function()
    local get_uint16 = __g16
    local f = (loadstring or load)((__FN):gsub('return rstr', ''))
    return nil
end)()
''')
    # get_uint16是全局名: 直接注入全局再重载
    lua.execute('''
get_uint16 = __g16
__RSTR = (loadstring or load)(__FN)()
function try_words(ws, len)
    __WORDS = ws
    __WI = 0
    return __RSTR(0x1000, len or 16)
end
__GBK = try_words({ 0xC8CE, 0xCEF1, 0x3100, 0 }, 16)
__ASCII = try_words({ 0x6162, 0x6300 }, 16)
__EMPTY = try_words({ 0x0000 }, 16)
__HEXG = (__GBK:gsub(".", function(c)
    return string.format("%02x", string.byte(c)) end))
''')
    hexg = str(lua.eval('(__HEXG)'))
    check(hexg == 'c8cecef131', 'dump字列解码=任务1(%s)' % hexg)
    check(lua.eval('__ASCII') == b'abc'.decode('latin1')
          or bytes(bytearray([ord(c) & 0xFF for c in str(lua.eval('__ASCII'))])) == b'abc',
          'ASCII布局解码abc')
    check(lua.eval('#__EMPTY') == 0, '空串')

    print('7) 视口/跟随(M41): mv_get钩子断言+脏标重绘+缩底无异常')
    # 60排×2列大图(演示田太小, 视口永不裁剪)
    rows60 = ['信息,,,', '名称,big60', '类型,播种,排长(cm),过道长(cm)',
              '创建时间,,500,100', '修改时间,,500,100', '备注,,500,100',
              '排,60,500,100', '列,2,500,100', '小区行数,6,,100',
              '机器行数,6,,', '行间距(cm),60,,', ',,,',
              'AB线,,,', 'StartN,36.4', 'StartE,117', 'EndBN,36.438',
              'EndBE,117', 'StartDir,0', 'CalcDir,0', 'StartState,1',
              'CalcDirFlag,1', 'OffLen,0', 'BDOffTime,100', 'A点排,59',
              'A点列,0', '方向,FALSE', '名称,AB', ',,,', '编号,,,',
              ',1列,2列']
    for r in range(60, 0, -1):
        rows60.append('%d排,,,' % r)
    rows60 += [',,,', '密度,,,', ',1列,2列']
    for r in range(60, 0, -1):
        rows60.append('%d排,4000,4000' % r)
    rows60 += [',,,', '是否播种,,,', ',1列,2列']
    for r in range(60, 0, -1):
        rows60.append('%d排,1,1' % r)
    big60 = '\r\n'.join(rows60) + '\r\n'
    lua.globals().__HEXB = big60.encode('gbk').hex()
    lua.execute('''
local s = ""
local h = __HEXB
for i = 1, #h, 2 do
    s = s .. string.char(tonumber(h:sub(i, i + 1), 16))
end
STR.map_import_text("big60", s)
STR.task_create("t3", "big60", 0, 1, 0, 0, 0, "2026-10-13")
APPX.preset_sowrt_task = "t3"
P24:on_enter()
__MV0, __FL0 = P24.mv_get()
''')
    check(lua.eval('__MV0 == nil and __FL0 == true'),
          '进页: 适配视图+跟随默认开')
    lua.execute('P24:on_update(LW.MV.zin, 1)')
    lua.execute('__MV1, __FL1 = P24.mv_get()')
    check(6.5 < float(lua.eval('__MV1.scale')) < 7.2,
          '放大一档: scale=fit4.55x1.5=%s' % lua.eval('__MV1.scale'))
    check(lua.eval('__FL1') is True, '放大保持跟随')
    check(lua.eval('REG[LW.RT.canvas]') == 1, '画布脏标已写(重绘触发,M41)')
    lua.execute('P24:on_update(LW.MV.down, 1)')
    lua.execute('__MV2, __FL2 = P24.mv_get()')
    check(lua.eval('__FL2') is False
          and float(lua.eval('__MV2.cy')) > float(lua.eval('__MV1.cy')),
          '下移半屏: cy增大+跟随退出')
    lua.execute('''
local ok = pcall(function()
    for i = 1, 10 do P24:on_update(LW.MV.zout, 1) end
end)
__OK, __MVF = ok, P24.mv_get()
''')
    check(bool(lua.eval('__OK')) and lua.eval('__MVF') is None,
          '连续缩小至底: 无on_update异常且回落适配(M41修nil比较崩溃)')
    lua.execute('''
JR.snap = { cur_row = 30, cur_col = 1 }
P24:on_update(LW.MV.follow, 1)
__MVF2, __FLF = P24.mv_get()
''')
    check(lua.eval('__FLF') is True
          and abs(float(lua.eval('__MVF2.cy')) - 37.32) < 20,
          '跟随开: 居中第30排(cy=%s)' % lua.eval('__MVF2.cy'))
    lua.execute('P24:on_update(LW.MV.fit, 1)')
    lua.execute('__MV3, __FL3 = P24.mv_get()')
    check(lua.eval('__MV3 == nil and __FL3 == false'), '适配: 视图清+跟随退出')
    lua.execute('''
P9:on_enter()
P9:on_update(LW.MV.zin, 1)
__MV9 = P9.mv_get()
P9:on_update(LW.MV.fit, 1)
__MV9F = P9.mv_get()
''')
    check(abs(float(lua.eval('__MV9.scale')) - 48) < 0.01
          and lua.eval('__MV9F') is None,
          '任务管理页: 放大路由scale=%s(小图fit顶32x1.5)/适配复位=%s'
          % (lua.eval('__MV9 and __MV9.scale'), lua.eval('__MV9F')))

    print()
    print('任务管理/实时播种回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
