# -*- coding: utf-8 -*-
"""HIM工程 文件名ASCII化修复验证 (lupa, Lua 5.3)。

背景: 真机实测屏端文件系统对含中文(GB2312)的文件名 open 失败
      ("task_任务1.csv" 创建失败 / U盘 "map_对照田.csv" 导入失败)。
修复: store.lua 落盘文件名一律 slug 化(ASCII段+FNV1a哈希), 显示名保留中文;
      map_import_file 以 #MAP 内容名为显示名; boot 兼容旧命名回退;
      page_history 导出U盘文件名同样 slug 化。

本测试用 ASCII-only 的 mock fileio 复刻真机限制做全链路回归:
  1) slug 性质(确定性/纯ASCII/区分度/长度)
  2) 中文名地图导入+任务创建+结果追加 全部落盘成功且文件名纯ASCII
  3) boot 掉电恢复(中文显示名找回, 块状态/结果保留)
  4) 旧命名(纯ASCII原名直拼)兼容回退
  5) U盘中文名文件的针对性报错; ASCII文件名+中文内容显示名导入

运行: python hmi_port/tests/test_him_filenames.py
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


MOCK_LUA = r'''
-- 模拟真机文件系统: 路径含非ASCII字节(>126)时 open/write 失败
MOCKFS = {}
local function ascii_ok(p)
    for i = 1, #p do
        if string.byte(p, i) > 126 then return false end
    end
    return true
end
MOCK = {}
function MOCK.write_all(p, s)
    if not ascii_ok(p) then return nil, "open失败" end
    MOCKFS[p] = s
    return true
end
function MOCK.append(p, s)
    if not ascii_ok(p) then return nil, "open失败" end
    MOCKFS[p] = (MOCKFS[p] or "") .. s
    return true
end
function MOCK.read_all(p)
    if not ascii_ok(p) then return nil, "open失败" end
    return MOCKFS[p]
end
function MOCK.remove(p)
    if not ascii_ok(p) then return nil, "open失败" end
    MOCKFS[p] = nil
    return true
end
'''

MAP_CSV = '#MAP,对照田\r\n#DIM,5,2,6,60\r\n#ROWLEN,500,500,500,500,500\r\n' \
          '#AISLE,100,100,100,100,100,100\r\n#BLOCKS\r\n' + \
          '\r\n'.join('%d,%d,%d,4000,1' % (r, c, (r - 1) * 2 + c)
                      for r in range(1, 6) for c in range(1, 3))


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK_LUA)

    def load(name):
        lua.globals().__P = os.path.join(HIM, name).replace('\\', '/')
        return lua.execute('local f = assert(loadfile(__P)); return f()')

    def call(fn, *args):
        """统一 (ok, err): Lua成功单值返回表, 失败 nil[,err] -> lupa二元组。"""
        rv = fn(*args)
        if isinstance(rv, tuple):
            return rv[0], (rv[1] if len(rv) > 1 else None)
        return rv, None

    csv = load('csv.lua')
    lua.execute('local f = assert(loadfile(__P)); return f()')  # noqa
    store = load('store.lua')
    store['init'](lua.globals().MOCK, csv, '3:')
    g = lua.globals()

    print('1) slug 性质')
    s1 = store['slug']('任务1')
    s2 = store['slug']('任务1')
    s3 = store['slug']('甲1')
    s4 = store['slug']('乙1')
    s5 = store['slug']('field')
    ok_ascii = all(ord(ch) < 127 for s in (s1, s3, s4, s5) for ch in str(s))
    check(ok_ascii and s1 == s2 and s1 != s3 != s4 and s5.startswith('field_'),
          '纯ASCII/确定性/区分度: 任务1->%s 甲1->%s 乙1->%s field->%s'
          % (s1, s3, s4, s5))
    check(len(s5) <= 25, '长度上限: %d' % len(s5))

    print('2) 中文名全链路(ASCII-only 文件系统)')
    m, err = call(store['map_import_text'], '对照田', MAP_CSV)
    check(m is not None, '中文名地图导入(旧代码此处落盘失败): %s'
          % (err or 'OK ' + store['slug']('对照田')))
    t, err = call(store['task_create'], '任务1', '对照田', 0, 0, 0, 0, 0, 'T0')
    check(t is not None, '中文名任务创建(用户报告的故障点): %s' % (err or 'OK'))
    ok, err3 = call(store['task_mark_dispatched'], '任务1', 0, 0)
    ent = lua.table()
    ent['seed'] = lua.table(*[24, 23, 23, 23, 23, 24])
    ent['fert'] = lua.table(*[0] * 6)
    ent['state'] = 2
    ent['start_t'] = 'T0'
    ent['end_t'] = 'T1'
    ok2, err4 = call(store['task_mark_row_done'], '任务1', 0, 0, lua.table(ent), 'T1')
    # 2026-10-15: 落盘改停止时统一写入(flush)——模拟用户点停止
    okf, errf = call(store['task_flush'], '任务1')
    check(ok and ok2 is not None and okf is not None,
          '下发标记+排完成+结果追加+停止flush: %s' % (errf or 'OK'))
    fs = g.MOCKFS
    files = [fs[k] for k in list(fs.keys())]
    names = [str(k) for k in list(fs.keys())]
    nonascii = [n for n in names if any(ord(c) > 126 for c in n)]
    check(len(names) >= 4 and not nonascii,
          '落盘文件全部纯ASCII(%d个): %s' % (len(names), ', '.join(sorted(names))))

    print('3) boot 掉电恢复')
    lua.execute('STORE2 = nil')
    lua.execute('_G.STORE2 = (loadfile(__P))()')
    lua.execute('STORE2.init(MOCK, csv or _GCSV, "3:")')
    # csv 模块在 lua 侧没有全局名, 重新加载给 boot 用
    lua.globals().__P = os.path.join(HIM, 'csv.lua').replace('\\', '/')
    lua.execute('_G.GCSV = (loadfile(__P))()')
    lua.execute('STORE2.init(MOCK, GCSV, "3:")')
    st2 = lua.globals().STORE2
    r = st2['boot']()
    maps = st2['map_list']()
    tasks = st2['task_list']()
    t1 = st2['task_get']('任务1')
    blk_state = t1['blocks'][0][0]['state']
    res = st2['results']['任务1']
    check(maps is not None and maps[1] == '对照田' and tasks[1] == '任务1',
          '中文显示名经index找回: 地图=%s 任务=%s' % (maps[1], tasks[1]))
    check(blk_state == 2 and len(res) >= 1,
          '块状态(完成=2)与结果记录保留: state=%s 结果%d条' % (blk_state, len(res)))

    print('4) 旧命名兼容回退')
    # 十五修代际index: 先清全部代际文件, 仅留旧版index.txt验回退
    for k in [k for k in list(g.MOCKFS.keys())
              if str(k).startswith('3:index')]:
        del g.MOCKFS[k]
    g.MOCKFS['3:map_field.csv'] = MAP_CSV.replace('对照田', 'field')
    g.MOCKFS['3:index.txt'] = 'M,field\r\n'
    for k in [k for k in list(g.MOCKFS.keys())
              if str(k).startswith('3:map_') and 'field' not in str(k)]:
        del g.MOCKFS[k]
    r2 = st2['boot']()
    maps2 = st2['map_list']()
    check(maps2 is not None and maps2[1] == 'field',
          '旧命名(原名直拼)文件经回退装载: %s' % (maps2[1] if len(maps2) else '无'))

    print('5) U盘导入口径')
    # 错误消息是GB2312字节, lupa按UTF-8解码会崩, 经Lua包装转hex比对
    lua.globals().ST = store
    lua.execute('''
function __TRY(path, name)
    local ok, err = ST.map_import_file(path, name)
    if type(err) == "string" then
        local h = {}
        for i = 1, #err do h[i] = string.format("%02X", string.byte(err, i)) end
        return ok, table.concat(h)
    end
    return ok, err
end''')
    tr = lua.globals().__TRY
    ok5, err5 = tr('2:map_对照田.csv', '对照田')
    want = '纯英文'.encode('gb2312').hex().upper()
    check(ok5 is None and want in str(err5),
          'U盘中文名文件针对性报错(hex含"纯英文"): %s' % err5)
    g.MOCKFS['2:map_field.csv'] = MAP_CSV          # ASCII文件名, #MAP显示名=对照田
    ok6, err6 = call(store['map_import_file'], '2:map_field.csv', 'field')
    ml = store['map_list']()
    check(ok6 is not None and '对照田' in [ml[i] for i in range(1, len(ml) + 1)],
          'ASCII文件名+中文#MAP显示名导入: %s' % (err6 or 'OK'))

    print()
    if FAIL:
        print('文件名ASCII化: %d项失败' % FAIL)
    else:
        print('文件名ASCII化: 全部通过 (%d项)' % PASS)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
