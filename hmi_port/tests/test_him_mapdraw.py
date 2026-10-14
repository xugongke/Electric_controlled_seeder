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
__OS = false
for i = 1, #__CMDS do
    local c = __CMDS[i]
    if c.op == "rect" and c.fill == 0
       and c.color == MD.rgb565(255,200,0) then __OS = true end
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
    check(bool(lua.eval('__OS')), '起点标记(黄色空心框)')
    check(lua.eval('__MCNT') == 3, '农机箭头3笔红色线段(杆+双翼, 替换方块)')
    check(lua.eval('__ACNT') == 2, '轨迹2格半透明叠加')

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

    print()
    print('地图绘制回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
