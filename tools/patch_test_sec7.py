# -*- coding: utf-8 -*-
"""patch_test_sec7.py — test_him_taskmgr_sowrt.py 第7段改写: mv_get断言(M41)。"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
PATH = r'F:\Cubemx_Project\Electric_controlled_seeder\hmi_port\tests\test_him_taskmgr_sowrt.py'

src = open(PATH, encoding='utf-8').read()
a = src.find("    print('7) 视口/跟随(M40)")
b = src.find("    print()\r\n    print('任务管理/实时播种回归")
if b < 0:
    b = src.find("    print()\n    print('任务管理/实时播种回归")
assert 0 < a < b, '第7段定位失败(%d,%d)' % (a, b)

NEW = """    print('7) 视口/跟随(M41): mv_get钩子断言+脏标重绘+缩底无异常')
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
    big60 = '\\r\\n'.join(rows60) + '\\r\\n'
    lua.globals().__HEXB = big60.encode('gbk').hex()
    lua.execute(\'\'\'
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
\'\'\')
    check(lua.eval('__MV0 == nil and __FL0 == true'),
          '进页: 适配视图+跟随默认开')
    lua.execute('P24:on_update(LW.MV.zin, 1)')
    lua.execute('__MV1, __FL1 = P24.mv_get()')
    check(float(lua.eval('__MV1.scale')) == 8.0, '放大一档: scale=8')
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
    check(float(lua.eval('__MV9.scale')) == 8.0 and lua.eval('__MV9F') is None,
          '任务管理页: 放大路由scale=8/适配复位')

"""

src = src[:a] + NEW + src[b:]
open(PATH, 'w', encoding='utf-8', newline='').write(src)
print('第7段已改写为M41断言')
