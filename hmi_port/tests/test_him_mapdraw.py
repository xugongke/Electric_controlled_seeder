# -*- coding: utf-8 -*-
"""地图绘制纯函数回归: 2026-10-13 M2(任务向导拆页重构)。

被测: HIMproject/Project/mapdraw.lua (零平台依赖, on_draw适配层只翻译指令)
  1) rgb565 换算标准值
  2) layout fit-scale: 边界内/居中/过道带
  3) row_at 累计偏移反查(排内/过道nil/越界nil)
  4) cmds 指令序列: 状态色映射(0灰/1蓝/2绿/3中断/不播深灰)、排标签倒序、
     列标签1基、三视图格内文字、起点标记、轨迹叠加、农机标记、
     小格子降级(省略文字/网格)
运行: python hmi_port/tests/test_him_mapdraw.py
"""
import os
import sys

from lupa import lua53 as lupa_lua

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HIM = os.path.join(ROOT, 'HIMproject', 'Project')

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().__P = HIM.replace('\\', '/') + '/mapdraw.lua'
    lua.execute('MD = assert(loadfile(__P))()')

    print('1) rgb565')
    check(lua.eval('MD.rgb565(255,0,0)') == 0xF800, '红 0xF800')
    check(lua.eval('MD.rgb565(0,255,0)') == 0x07E0, '绿 0x07E0')
    check(lua.eval('MD.rgb565(0,0,255)') == 0x001F, '蓝 0x001F')
    check(lua.eval('MD.rgb565(255,255,255)') == 0xFFFF, '白 0xFFFF')
    check(lua.eval('MD.rgb565(0,0,0)') == 0, '黑 0x0000')

    print('2) 样例地图与layout')
    # 5排×4列, 排长500, 过道100(首过道100), 全部播种, 密度4000
    lua.execute('''
function mkmap(rows, cols)
    local m = { name = "t", rows = rows, cols = cols, machine_cols = 6,
                block_col = 1, col_gap = 60, rowlen = {}, aisle = {},
                blocks = {} }
    for r = 1, rows do m.rowlen[r] = 500 end
    for i = 1, rows + 1 do m.aisle[i] = 100 end
    for r = 0, rows - 1 do
        m.blocks[r] = {}
        for c = 0, cols - 1 do
            m.blocks[r][c] = { num = r * cols + c + 1, density = 4000, sow = 1 }
        end
    end
    return m
end
__M = mkmap(5, 4)
__G = MD.layout(__M, 530, 380)
''')
    g = lua.globals().__G
    check(g is not None and g['cw'] >= 6 and g['ch'] >= 6, '格宽高有效')
    ok = lua.eval('__G.x0 + __G.cw * __G.cols <= 530 and '
                  '__G.y0 + __G.rows * (__G.ch + __G.aisle) + __G.aisle <= 380')
    check(bool(ok), '整体在画布内(fit-scale)')
    ok2 = lua.eval('__G.x0 >= 22 and __G.y0 >= 18')   # 2026-10-14样式: LABEL 22x18+PAD
    check(bool(ok2), '标签边距预留')

    print('3) row_at 偏移反查')
    # 行起点: 0, 600, 1200, 1800, 2400; 行长500; 过道区间 (500,600)等
    check(lua.eval('MD.row_at(__M, 0)') == 0, 'off=0 -> 排0')
    check(lua.eval('MD.row_at(__M, 499)') == 0, 'off=499 -> 排0(末厘米)')
    check(lua.eval('MD.row_at(__M, 500)') is None, 'off=500 -> 过道nil')
    check(lua.eval('MD.row_at(__M, 600)') == 1, 'off=600 -> 排1')
    check(lua.eval('MD.row_at(__M, 2899)') == 4, 'off=2899 -> 末排4')
    check(lua.eval('MD.row_at(__M, 2900)') is None, 'off=2900 越界nil')
    check(lua.eval('MD.row_at(__M, -1)') is None, '负偏移nil')

    print('3b) row_at_edge 图外感知')
    check(lua.eval('MD.row_at_edge(__M, -50)') == -1, '图前off=-50 -> -1')
    check(lua.eval('MD.row_at_edge(__M, 500)') is None, '过道off=500 -> nil')
    check(lua.eval('MD.row_at_edge(__M, 2900)') == 5, '图后off=2900 -> rows=5')
    check(lua.eval('MD.row_at_edge(__M, 100)') == 0, '排内off=100 -> 0')

    print('4) cmds 状态色与结构')
    lua.execute('''
__T = { name = "t1", map = "t", path_type = 0, positive = 0,
        sow_exceed = 0, outset = { r = 1, c = 2 },
        blocks = {} }
for r = 0, 4 do
    __T.blocks[r] = {}
    for c = 0, 3 do __T.blocks[r][c] = { state = 0, sow = 1 } end
end
__T.blocks[0][0].state = 2      -- 完成
__T.blocks[1][1].state = 1      -- 已下发
__T.blocks[2][2].state = 3      -- 中断
__M.blocks[3][3].sow = 0        -- 不播
__CMDS, __CG = MD.cmds(__M, __T, { w = 530, h = 380, view = "arrange" })
''')
    check(lua.eval('#__CMDS') > 0, '指令序列非空(%d条)' % lua.eval('#__CMDS'))

    def cell_fill_cmd(r, c):
        # 小区填充指令: 第2条底白, 之后 rows+1 条过道带, 然后逐格填充
        base = 2 + 5 + r * 4 + c        # 5行4列图
        return base + 1                 # lua 1基

    lua.execute('''
function fillcmd(i) return __CMDS[i] end
__N = #__CMDS
''')
    # 颜色断言(lua侧比较, 避免浮点转换)
    check(lua.eval('__CMDS[2 + 5 + 0 * 4 + 0 + 1].color')
          == lua.eval('MD.rgb565(34,139,34)'), '(0,0)完成->绿')
    check(lua.eval('__CMDS[2 + 5 + 1 * 4 + 1 + 1].color')
          == lua.eval('MD.rgb565(0,112,192)'), '(1,1)下发->蓝')
    check(lua.eval('__CMDS[2 + 5 + 2 * 4 + 2 + 1].color')
          == lua.eval('MD.rgb565(237,108,36)'), '(2,2)中断->橙红(显示同运行色系)')
    check(lua.eval('__CMDS[2 + 5 + 3 * 4 + 3 + 1].color')
          == lua.eval('MD.rgb565(64,64,64)'), '(3,3)不播->深灰')
    check(lua.eval('__CMDS[2 + 5 + 4 * 4 + 0 + 1].color')
          == lua.eval('MD.rgb565(192,192,192)'), '(4,0)待播->灰')

    # 排标签倒序: 排0标签文本=rows-0=5
    lua.execute('''
function texts_of(pred)
    local out = {}
    for i = 1, #__CMDS do
        local c = __CMDS[i]
        if c.op == "text" and (pred == nil or pred(c)) then
            out[#out + 1] = c.s
        end
    end
    return out
end
__ROWLBL = {}
for i = 1, #__CMDS do
    local c = __CMDS[i]
    if c.op == "text" and c.x == 0 then __ROWLBL[#__ROWLBL + 1] = c.s end
end
''')
    rowlbl = [str(lua.globals().__ROWLBL[i])
              for i in range(1, lua.eval('#__ROWLBL') + 1)]
    check(rowlbl == ['5', '4', '3', '2', '1'],
          '排标签倒序(排0显示5): %s' % rowlbl)
    # 列标签 1..4 (y=0)
    lua.execute('''
__COLLBL = {}
for i = 1, #__CMDS do
    local c = __CMDS[i]
    if c.op == "text" and c.y == 0 then __COLLBL[#__COLLBL + 1] = c.s end
end
''')
    collbl = [str(lua.globals().__COLLBL[i])
              for i in range(1, lua.eval('#__COLLBL') + 1)]
    check(collbl == ['1', '2', '3', '4'], '列标签1基: %s' % collbl)

    print('5) 三视图格内文字')
    lua.execute('__C_NUM = MD.cmds(__M, __T, { w = 530, h = 380, view = "num" })')
    lua.execute('''
__NUMTXT = {}
for i = 1, #__C_NUM do
    local c = __C_NUM[i]
    if c.op == "text" and c.y ~= 0 and c.x ~= 0 then
        __NUMTXT[#__NUMTXT + 1] = c.s
    end
end
''')
    numtxt = [str(lua.globals().__NUMTXT[i])
              for i in range(1, lua.eval('#__NUMTXT') + 1)]
    check('1' in numtxt and '20' in numtxt and '5-1' not in numtxt,
          '编号视图出num(%s...)' % (numtxt[:5]))
    lua.execute('__C_DE = MD.cmds(__M, __T, { w = 530, h = 380, view = "density" })')
    lua.execute('''
__DEOK = false
for i = 1, #__C_DE do
    local c = __C_DE[i]
    if c.op == "text" and c.s == "4000" then __DEOK = true end
end
''')
    check(bool(lua.eval('__DEOK')), '密度视图出4000')
    # 排列视图在view=arrange的cmds里: "排显示-列" 形如 5-1
    lua.execute('''
__AROK = false
for i = 1, #__CMDS do
    local c = __CMDS[i]
    if c.op == "text" and c.s == "4-3" then __AROK = true end
end
''')
    check(bool(lua.eval('__AROK')), '排列视图(1,2)格显示"4-3"')

    print('6) 起点标记/轨迹/农机')
    # 起点(1,2): 黄色空心框; 轨迹/农机
    lua.execute('''
__OS = 0
for i = 1, #__CMDS do
    local c = __CMDS[i]
    if c.op == "line" and c.w == 3
       and c.color == MD.rgb565(255,200,0) then __OS = __OS + 1 end
end
__C2 = MD.cmds(__M, __T, { w = 530, h = 380, view = "arrange",
                           machine = { row = 2, col = 1 },
                           trail = { { row = 0, col = 0 }, { row = 2, col = 1 } } })
__MCNT, __ACNT = 0, 0
for i = 1, #__C2 do
    local c = __C2[i]
    if c.op == "line" and c.color == MD.rgb565(255,0,0) then __MCNT = __MCNT + 1 end
    if c.op == "arect" then __ACNT = __ACNT + 1 end
end
''')
    check(lua.eval('__OS') >= 4, '起点粗框4线w=3(黄色)')
    check(lua.eval('__MCNT') == 0, '农机标记已删除(无红色线段, 2026-10-15用户要求)')
    lua.execute('''
__EDGE = MD.cmds(__M, __T, { w = 530, h = 380, view = "arrange",
    machine = { row = -1, col = -1, dir = true } })
__EDGECNT = 0
for i = 1, #__EDGE do
    if __EDGE[i].op == "line" and __EDGE[i].color == MD.rgb565(255,0,0) then
        __EDGECNT = __EDGECNT + 1
    end
end
''')
    check(lua.eval('__EDGECNT') == 0, '图外显示已删除')
    check(lua.eval('__ACNT') == 0, '轨迹已移除(无半透明叠加, 用户要求)')

    print('7) 小格子降级')
    lua.execute('''
__BIG = mkmap(30, 40)     -- 40列x30排
__CB, __GB = MD.cmds(__BIG, nil, { w = 530, h = 380, view = "density" })
__TXTN = 0
for i = 1, #__CB do
    if __CB[i].op == "text" then __TXTN = __TXTN + 1 end
end
__FILLN = 0
for i = 1, #__CB do
    if __CB[i].op == "rect" and __CB[i].fill == 1 then __FILLN = __FILLN + 1 end
end
''')
    txt_n = lua.eval('__TXTN')
    fill_n = lua.eval('__FILLN')
    check(txt_n == 0, '40x30小格: 文本全省略(标签+格内), 实有%d' % txt_n)
    check(fill_n >= 40 * 30, '40x30: 色块全画(%d>=1200)' % fill_n)
    check(lua.eval('__GB ~= nil'), '大图layout仍成功(过道压缩)')

    print('8) 无任务纯地图(任务管理页选中即预览)')
    lua.execute('''
__C3, _ = MD.cmds(__M, nil, { w = 530, h = 380 })
__ANYRUN = false
for i = 1, #__C3 do
    local c = __C3[i]
    if c.op == "rect" and c.fill == 1 and c.color == MD.rgb565(0,112,192) then
        __ANYRUN = true
    end
end
''')
    check(not bool(lua.eval('__ANYRUN')), '无任务: 无已下发蓝色块')

    print('9) 视口渲染(M40): 大排列数指令量封顶/可见裁剪/缩略图/视图控制器')
    lua.execute('''
__BIG = mkmap(200, 16)                    -- 200排×16列: 整图模式必溢出
__N_FULL = #MD.cmds(__BIG, nil, { w = 530, h = 380 })
__N_VP = #MD.cmds(__BIG, nil, { w = 530, h = 380,
                                viewp = { cx = 8, cy = 122, scale = 8 },
                                minimap = true })
''')
    check(bool(lua.eval('__N_VP < __N_FULL and __N_VP < 3000')),
          '视口指令量%d < 整图%d 且 <3000封顶'
          % (lua.eval('__N_VP'), lua.eval('__N_FULL')))
    lua.execute('''
__CV = MD.cmds(__BIG, nil, { w = 530, h = 380, minimap = true,
                             viewp = { cx = 8, cy = 122, scale = 48 } })
__CELLS = 0
for i = 1, #__CV do
    local c = __CV[i]
    -- 只统计主视区(x1<缩略条起点444)的待播灰色块, 排除缩略行带
    if c.op == "rect" and c.fill == 1 and c.x1 < 430
       and c.color == MD.rgb565(192,192,192) then
        __CELLS = __CELLS + 1
    end
end
''')
    check(bool(lua.eval('__CELLS')) and lua.eval('__CELLS') <= 100,
          'scale=48主视区色块%d≤100(整图为3200)——只画视口相交区间'
          % lua.eval('__CELLS'))
    lua.execute('''
__HASMINI = false
for i = 1, #__CV do
    local c = __CV[i]
    if c.op == "rect" and c.fill == 0 and c.color == MD.rgb565(255,0,0) then
        __HASMINI = true
    end
end
''')
    check(bool(lua.eval('__HASMINI')), '缩略图视口红框存在')
    check(abs(float(lua.eval('MD.zoom_step(10, nil, 1)')) - 12) < 0.01,
          'fit=10放大进12档(纯档位等比, M46)')
    check(abs(float(lua.eval('MD.zoom_step(32, nil, 1)')) - 36) < 0.01,
          'fit=32放大进36档(纯档位: 32的上一档即36)')
    check(abs(float(lua.eval('MD.zoom_step(32, 48, 1)')) - 64) < 0.01,
          '48放大进64档(到顶)')
    check(abs(float(lua.eval('MD.zoom_step(32, 64, 1)')) - 64) < 0.01,
          '64再放大保持64(到顶保持)')
    check(abs(float(lua.eval('MD.zoom_step(32, 48, -1)')) - 36) < 0.01,
          '48缩小进36档(降序取下一档)')
    check(abs(float(lua.eval('MD.zoom_step(10, 48, -1)')) - 36) < 0.01,
          '48缩小(跨fit10)仍进36档不反向')
    check(abs(float(lua.eval('MD.zoom_step(10, 24, -1)')) - 18) < 0.01,
          '24缩小进18档')
    check(abs(float(lua.eval('MD.zoom_step(10, 12, -1)')) - 8) < 0.01,
          '12缩小进8档(低于fit也逐档, 不反向跳fit)')
    check(abs(float(lua.eval('MD.zoom_step(32, 8, -1)')) - 8) < 0.01,
          '表底8再缩保持8(绝不反向放大——M46真机反馈根因)')
    check(lua.eval('MD.zoom_step(10, nil, -1)') is None,
          '适配态再缩=适配(nil, 无从再缩)')
    lua.execute('''
__P1 = MD.pan({ cx = 8, cy = 122, scale = 8 }, __BIG, 530, 380, true,
              0, 100)                       -- 疯狂下移100屏
__WH = select(2, MD.world_size(__BIG))
''')
    check(bool(lua.eval('__P1.cy <= __WH + 1')),
          '平移夹取: cy=%s 不越出世界底%s+余量'
          % (lua.eval('__P1.cy'), lua.eval('__WH')))
    lua.execute('''
__C = MD.center_on({ cx = 8, cy = 122, scale = 48 }, __BIG, 530, 380,
                   true, 150, 3)
''')
    check(abs(float(lua.eval('__C.cy')) - (150 * 1.22 + 1.72)) < 1.5,
          'center_on(150排,3列)@scale48居中该格: cy=%s' % lua.eval('__C.cy'))
    check(abs(float(lua.eval('__C.cx')) - 3.5) < 0.1,
          'center_on列中心: cx=%s' % lua.eval('__C.cx'))

    print()
    print('地图绘制回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
