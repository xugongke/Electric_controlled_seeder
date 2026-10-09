# -*- coding: utf-8 -*-
"""地图csv双格式回归: 2026-10-08区块式(QT xlsx导出布局)+旧#段式兼容。

被测: HIMproject/Project/csv.lua
  1. 区块式解析: 用户样例(信息/AB线/编号/密度/是否播种五区块,
     排长/过道藏信息区C/D列, 矩阵行倒序, 方向TRUE/FALSE, A点排/列)
  2. 回写再解析round-trip一致(render_map区块式)
  3. 旧#段式文件仍可解析(向后兼容已导入地图)
运行: python hmi_port/tests/test_him_mapcsv.py
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


SAMPLE_FIELDS = [
    ['信息', '', '', ''],
    ['类型', '播种', '排长(cm)', '过道长(cm)'],
    ['创建时间', '2026/9/18 8:41', '500', '100'],
    ['修改时间', '', '500', '100'],
    ['备注', '', '500', '100'],
    ['排', '5', '500', '100'],
    ['列', '2', '500', '100'],
    ['小区行数', '6', '', '100'],
    ['机器行数', '6', '', ''],
    ['行间距(cm)', '60', '', ''],
    ['', '', '', ''],
    ['AB线', '', '', ''],
    ['StartN', '36.4'], ['StartE', '117'], ['EndBN', '0'], ['EndBE', '0'],
    ['StartDir', '0'], ['CalcDir', '0'],
    ['StartState', '1'], ['CalcDirFlag', '0'],
    ['OffLen', '60'], ['BDOffTime', '100'],
    ['Resv', '0'], ['CrcCheck', '0'],
    ['A点排', '4'], ['A点列', '0'],
    ['方向', 'FALSE'], ['名称', 'AB'],
    ['', '', '', ''],
    ['编号', '', '', ''],
    ['', '1列', '2列'],
    ['5排', '', ''], ['4排', '', ''], ['3排', '', ''], ['2排', '', ''], ['1排', '', ''],
    ['', '', '', ''],
    ['密度', '', '', ''],
    ['', '1列', '2列'],
    ['5排', '4000', '4000'], ['4排', '4000', '4000'], ['3排', '4000', '4000'],
    ['2排', '4000', '4000'], ['1排', '4000', '4000'],
    ['', '', '', ''],
    ['是否播种', '', '', ''],
    ['', '1列', '2列'],
    ['5排', '1', '1'], ['4排', '1', '1'], ['3排', '1', '1'],
    ['2排', '1', '1'], ['1排', '1', '1'],
]

lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
lua.globals().__P = HIM.replace(chr(92), '/') + '/csv.lua'
lua.execute('__CSV = assert(loadfile(__P))()')

# python拼CSV文本(GBK转lua: 经hex中转, 避免编码边界)
text = '\r\n'.join(','.join(r) for r in SAMPLE_FIELDS) + '\r\n'
lua.globals().__HEX = text.encode('gbk').hex()
lua.execute(r'''
local h = __HEX
local s = ""
for i = 1, #h, 2 do s = s .. string.char(tonumber(h:sub(i, i + 1), 16)) end
__TEXT = s
__PM, __MSG = __CSV.parse_map(s)
''')
pm, msgs = lua.globals().__PM, lua.globals().__MSG
ml = [str(msgs[k]) for k in (msgs.keys() or [])] if msgs else []
check(not ml, '区块式样例解析零错误: %s' % (ml or '无'))

def g(k, d=None):
    return pm[k] if pm[k] is not None else d

check(g('rows') == 5 and g('cols') == 2 and g('machine_cols') == 6
          and g('block_col') == 6 and g('col_gap') == 60, '维度字段')
check(g('rows') == 5, '')
rl = pm['rowlen']
ai = pm['aisle']
nrl = lua.eval('#__PM.rowlen')
nai = lua.eval('#__PM.aisle')
check(nrl == 5 and nai == 6, '排长5条/过道6条')
ab = pm['ab']
check(ab['sn'] == 36.4 and ab['a_row'] == 4 and ab['a_col'] == 0
          and ab['abdir'] == 0 and ab['startstate'] == 1 and ab['offlen'] == 60,
      'AB全字段(含A点排/列/方向FALSE)')
b51 = pm['blocks'][4][0]
b11 = pm['blocks'][0][0]
check(b51['density'] == 4000 and b11['density'] == 4000
          and b11['num'] == 1 and pm['blocks'][4][1]['sow'] == 1,
      '矩阵(行倒序映射/编号顺位/播种)')

# 回写round-trip
lua.execute('__RT = __CSV.render_map(__PM)')
rt_hex = lua.execute('return (__RT:gsub(".", function(c) '
                     'return string.format("%02x", string.byte(c)) end))')
rt = bytes.fromhex(str(rt_hex)[::2] if len(str(rt_hex)) % 2 == 0 else str(rt_hex)).decode('gbk', errors='replace') \
    if False else None
# 简化: lua侧再parse回写产物对比关键字段
lua.execute('__PM2, __MSG2 = __CSV.parse_map(__RT)')
pm2 = lua.globals().__PM2
ab2 = pm2['ab']
ok = (pm2['rows'] == pm['rows'] and pm2['cols'] == pm['cols']
      and ab2['sn'] == ab['sn'] and ab2['a_row'] == ab['a_row']
      and ab2['abdir'] == ab['abdir'] and ab2['offlen'] == ab['offlen']
      and pm2['blocks'][4][0]['density'] == b51['density'])
check(ok, 'render回写再解析round-trip一致')

# 旧#段式兼容
old_text = ('#MAP,old\r\n#DIM,4,2,6,60\r\n'
            + ''.join('#ROWLEN,500\r\n' for _ in range(4))
            + ''.join('#AISLE,100\r\n' for _ in range(5))
            + '#AB,a,1,2,3,4,0,0,0,1,1,0,60,100\r\n#BLOCKS\r\n'
            + ''.join('%d,%d,%d,4000,1\r\n' % (r, c, (r - 1) * 2 + c)
                      for r in range(1, 5) for c in range(1, 3)))
lua.globals().__OLD = old_text
lua.execute('__PM3, __MSG3 = __CSV.parse_map(__OLD)')
pm3 = lua.globals().__PM3
check(pm3['rows'] == 4 and str(pm3['ab']['name']) == 'a', '旧#段式兼容')

# 编号区空(QT转存文件特征) -> 回写不固化顺位号(2026-10-09删AB线误删编号修复)
lua.execute('__M, __ = __CSV.parse_map(__TEXT)')
lua.execute('__M.ab = { name = "ab", sn = 1, se = 2, en = 3, ee = 4,'
            ' sdir = 0, cdir = 0, a_row = 0, a_col = 0, abdir = 1,'
            ' startstate = 1, calcdirflag = 0, offlen = 60, bdofftime = 100,'
            ' has = true }')
lua.execute('__RTB = __CSV.render_map(__M)')
lua.execute('__M.ab = nil')
lua.execute('__RTC = __CSV.render_map(__M)')
# 直接在python侧检查RT文本编号区
rth = lua.execute('return (__RTC:gsub(".", function(c) '
                  'return string.format("%02x", string.byte(c)) end))')
rth = rth[0] if isinstance(rth, tuple) else rth
rt_text = bytes.fromhex(rth).decode('gb2312', errors='replace')
lines2 = rt_text.splitlines()
i_num = lines2.index('编号,,,')
num_block = lines2[i_num + 2:i_num + 7]
check(all(l.split(',')[1] == '' for l in num_block),
      '编号区空文件回写后编号区仍空(顺位号不固化)')
check(pm['blocks'][4][0]['num'] == 9, '运行时编号顺位可用(内存: 5排1列=顺位9)')


def main():
    pass  # 主体已模块级执行


if __name__ == '__main__':
    if FAIL:
        print('地图csv双格式: %d项失败' % FAIL)
        sys.exit(1)
    print('地图csv双格式: 全部通过 (%d项)' % PASS)
