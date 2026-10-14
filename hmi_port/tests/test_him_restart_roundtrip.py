# -*- coding: utf-8 -*-
"""重启round-trip回归: 2026-10-13用户实测虚拟屏重启后无法开播(假"作业中")。

根因链(全部锁定):
  会话1停止时保存AB线 -> store.map_save -> csv.render_map重渲染:
    ① D列(过道)在rows+1之后补0(rows<7地图) -> 重启重载过道条数E: -> m.aisle空
    ② 不写"名称"行 -> 重启重载m.name=nil
  -> jobrun启动链send_node内pathalgo.start_node对nil算术抛错(未pcall),
     launch_tail断在0x24之后, 0x20/0x31/0x0A全不发, J残留 -> 页面假"作业中"。

被测: HIMproject/Project/{csv,store,jobrun,pathalgo,codec,lwmap}.lua
修复点: render对齐hmi_export(D列仅rows+1行+名称行)/parse尾部补0自愈/
        boot名称回填/send_node全pcall/首节点失败安全回滚。
运行: python hmi_port/tests/test_him_restart_roundtrip.py

编码约定: 中文名/GBK内容一律经hex中转注入(__MAP等), 断言在Lua侧用
字节比较完成, 不经lupa默认utf-8解码读回中文。
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


def new_rt():
    return lupa_lua.LuaRuntime(unpack_returned_tuples=True)


def load(rt, fname, gname):
    rt.globals().__P = HIM + '/' + fname
    rt.execute('%s = assert(loadfile(__P))()' % gname)
    return rt.globals()[gname]


def to_hex(rt, expr):
    # 外层括号截断gsub的第二个返回值(替换计数)
    return str(rt.eval('((%s):gsub(".", function(c) '
                       'return string.format("%%02x", string.byte(c)) end))'
                       % expr))


def inject(rt, var, text):
    """python str(GBK可编码) -> Lua字节串变量"""
    rt.globals().__H = text.encode('gbk').hex()
    rt.execute('%s = (function(h) local s="" for i=1,#h,2 do '
               's=s..string.char(tonumber(h:sub(i,i+1),16)) end return s end)(__H)'
               % var)


def setup_store(rt, fs=None):
    """csv+store+内存fileio; fs: {path: hexstr} 跨运行时桥接的既有文件"""
    load(rt, 'csv.lua', 'csv')
    store = load(rt, 'store.lua', 'store')
    rt.execute('''
__FS = {}
__FIO = {
    write_all = function(p, d) __FS[p] = d return true end,
    read_all  = function(p) return __FS[p] end,
    append    = function(p, d) __FS[p] = (__FS[p] or "") .. d return true end,
    remove    = function(p) __FS[p] = nil return true end,
}
''')
    if fs:
        for p, hx in fs.items():
            rt.globals().__HX = hx
            rt.execute('__FS[%r] = (function(h) local s="" for i=1,#h,2 do '
                       's=s..string.char(tonumber(h:sub(i,i+1),16)) end '
                       'return s end)(__HX)' % p)
    rt.execute('store.init(__FIO, csv, "3:")')
    return store


def dump_fs(rt):
    rt.execute('__FK = {}\nfor k in pairs(__FS) do __FK[#__FK + 1] = k end\n'
               'table.sort(__FK)')
    n = rt.eval('#__FK')
    out = {}
    for i in range(1, n + 1):
        k = str(rt.globals().__FK[i])
        out[k] = to_hex(rt, '__FS[%r]' % k)
    return out


ASSEMBLE = '''
__SENT, __LOGS = {}, {}
__PROTO = {
    FNC = { GET_BZ_STATUS=0x21, GET_TER_PARA=0x26, STORE_AB=0x23,
            SET_BZ_PARA=0x20, SET_AB=0x24, GDDD_ENABLE=0x31,
            CMD_START_BZ=0x0A, CMD_STOP_BZ=0x0B },
    send = function(fnc, payload)
        __SENT[#__SENT + 1] = { fnc = fnc, payload = payload }
    end,
}
__APP = { sub_always = function() end, register = function() end,
          set_always_poll = function() end, cur = nil }
__LOG = { log = function(tag, msg) __LOGS[#__LOGS + 1] = tag .. " " .. msg end }
jobrun.init {
    APP = __APP, PROTOCOL = __PROTO, CODEC = codec,
    STORE = store, PATHALGO = pathalgo, LOGGER = __LOG, LW = lwmap,
    w16 = function() end, w32 = function() end, wstr = function() end,
    now = function() return "2026-10-13 00:00:00" end,
}
store.task_create("t1", __MAP, 0, 1, 0, 0, 0, "2026-10-13")
__STOK = pcall(jobrun.start, "t1")
'''


def sample_text():
    lines = [
        ['信息', '', '', ''],
        ['名称', '演示田5'],
        ['类型', '播种', '排长(cm)', '过道长(cm)'],
        ['创建时间', '', '500', '100'],
        ['修改时间', '', '500', '100'],
        ['备注', '', '500', '100'],
        ['排', '5', '500', '100'],
        ['列', '2', '500', '100'],
        ['小区行数', '6', '', '100'],
        ['机器行数', '6', '', ''],
        ['行间距(cm)', '60', '', ''],
        ['', '', '', ''],
        ['AB线', '', '', ''],
        ['StartN', '36.4'], ['StartE', '117'], ['EndBN', '36.438'],
        ['EndBE', '117'],
        ['StartDir', '0'], ['CalcDir', '0'], ['StartState', '1'],
        ['CalcDirFlag', '1'], ['OffLen', '0'], ['BDOffTime', '100'],
        ['A点排', '4'], ['A点列', '0'],
        ['方向', 'FALSE'], ['名称', 'AB'], ['', '', '', ''],
        ['编号', '', '', ''], ['', '1列', '2列'],
        ['5排', '', ''], ['4排', '', ''], ['3排', '', ''], ['2排', '', ''],
        ['1排', '', ''], ['', '', '', ''],
        ['密度', '', '', ''], ['', '1列', '2列'],
        ['5排', '4000', '4000'], ['4排', '4000', '4000'],
        ['3排', '4000', '4000'],
        ['2排', '4000', '4000'], ['1排', '4000', '4000'], ['', '', '', ''],
        ['是否播种', '', '', ''], ['', '1列', '2列'],
        ['5排', '1', '1'], ['4排', '1', '1'], ['3排', '1', '1'],
        ['2排', '1', '1'], ['1排', '1', '1'],
    ]
    return '\r\n'.join(','.join(r) for r in lines) + '\r\n'


def sent_fncs(rt):
    n = rt.eval('#__SENT')
    return [rt.globals().__SENT[i]['fnc'] for i in range(1, n + 1)]


def main():
    text = sample_text()

    print('1) csv级round-trip(rows=5地图, 修复前丢aisle)')
    rt = new_rt()
    load(rt, 'csv.lua', 'csv')
    inject(rt, '__TXT', text)
    inject(rt, '__MAP', '演示田5')
    rt.execute('''
__M1, _ = csv.parse_map(__TXT)
__RT = csv.render_map(__M1)
__M2, __MSG2 = csv.parse_map(__RT)
__RT2 = csv.render_map(__M2)
__M3, _ = csv.parse_map(__RT2)          -- 二次round-trip稳定性
''')
    for v in ('__M1', '__M2', '__M3'):
        rt.execute('__N_AI_%s = #%s.aisle' % (v[3:], v))
    check(rt.eval('#__M1.aisle') == 6 and rt.eval('#__M2.aisle') == 6
          and rt.eval('#__M3.aisle') == 6,
          '过道条数round-trip恒为6 (%d/%d/%d)' % (
              rt.eval('#__M1.aisle'), rt.eval('#__M2.aisle'),
              rt.eval('#__M3.aisle')))
    check(rt.eval('#__M1.rowlen') == 5 and rt.eval('#__M2.rowlen') == 5,
          '排长条数round-trip恒为5')
    check(bool(rt.eval('__M2.name == __MAP and __M3.name == __MAP')),
          '地图名round-trip保持(Lua侧字节比较)')
    check(rt.eval('__M2.aisle[1]') == 100 and rt.eval('__M2.aisle[6]') == 100,
          '过道数值无损(首/末=100)')
    check(rt.eval('__M2.ab.sn') == 36.4 and rt.eval('__M2.ab.a_row') == 4,
          'AB字段round-trip无损')
    check(rt.eval('__M2.blocks[4][0].density') == 4000,
          '密度矩阵round-trip无损')

    print('2) 旧版补0文件自愈(已落盘的损坏文件)')
    rt2 = new_rt()
    load(rt2, 'csv.lua', 'csv')
    bad = text.replace('机器行数,6,,', '机器行数,6,,0') \
              .replace('行间距(cm),60,,', '行间距(cm),60,,0')
    inject(rt2, '__BAD', bad)
    rt2.execute('''
__MB, __MSGB = csv.parse_map(__BAD)
__WCNT, __ECNT = 0, 0
for i = 1, #__MSGB do
    if __MSGB[i]:sub(1, 2) == "W:" then __WCNT = __WCNT + 1 end
    if __MSGB[i]:sub(1, 2) == "E:" then __ECNT = __ECNT + 1 end
end
''')
    check(rt2.eval('#__MB.aisle') == 6,
          '过道截断自愈至6条(实有%d)' % rt2.eval('#__MB.aisle'))
    check(rt2.eval('__WCNT') == 1 and rt2.eval('__ECNT') == 0,
          '1条W:告警0条E:致命(w=%d e=%d)' % (
              rt2.eval('__WCNT'), rt2.eval('__ECNT')))

    print('3) 会话1落盘(AB保存触发map_save重渲染)')
    rtA = new_rt()
    storeA = setup_store(rtA)
    inject(rtA, '__TXT', text)
    inject(rtA, '__MAP', '演示田5')
    rtA.execute('__OK = store.map_import_text(__MAP, __TXT)')
    check(bool(rtA.globals().__OK), '地图导入成功')
    rtA.execute('__SAVED = store.map_save(__MAP)')
    check(bool(rtA.globals().__SAVED), 'map_save重渲染落盘(等价AB保存路径)')
    fs = dump_fs(rtA)
    check(sum(1 for k in fs if 'map_' in k) == 1
          and any(k.startswith('3:index') for k in fs),
          '文件系统含地图与index(%d文件, 代际index01)' % len(fs))

    print('4) 会话2"重启"全链路: boot->建任务->start->0x20/0x0A')
    rtB = new_rt()
    storeB = setup_store(rtB, fs)
    inject(rtB, '__MAP', '演示田5')
    rep = storeB.boot()
    check(rep['maps'] == 1, 'boot装载1张地图(实有%d)' % rep['maps'])
    check(rtB.eval('#store.maps[__MAP].aisle') == 6,
          '重载地图过道6条(修复前为0)')
    check(bool(rtB.eval('store.maps[__MAP].name == __MAP')),
          '重载地图名保持(Lua侧比较)')
    check(bool(rtB.eval('store.maps[__MAP].ab ~= nil '
                        'and store.maps[__MAP].ab.has == true')),
          '重载地图AB绑定保持')
    load(rtB, 'pathalgo.lua', 'pathalgo')
    codecB = load(rtB, 'codec.lua', 'codec')
    load(rtB, 'lwmap.lua', 'lwmap')
    load(rtB, 'jobrun.lua', 'jobrun')
    codecB.init({'rows': 6})
    rtB.execute(ASSEMBLE)
    fncs = sent_fncs(rtB)
    check(bool(rtB.globals().__STOK), 'start未抛错(修复前launch_tail内炸)')
    check(0x20 in fncs, '0x20 SET_BZ_PARA已下发(修复前缺失): %s'
          % [hex(f) for f in fncs])
    check(0x24 in fncs and 0x0A in fncs, '0x24 AB与0x0A启动均在链上')
    check(bool(rtB.eval('jobrun.active()')), '作业现场建立')
    check(bool(rtB.eval('jobrun.snapshot() ~= nil '
                        'and jobrun.snapshot().sow_state == true')),
          'sow_state=true(真作业中, 非残留假象)')
    check(bool(rtB.eval('jobrun.snapshot().map == __MAP')),
          '快照地图名非nil(名称round-trip)')

    print('5) 不可自愈损坏的containment(过道尾部非0 -> E: -> aisle空)')
    rtC = new_rt()
    storeC = setup_store(rtC)
    worse = text.replace('机器行数,6,,', '机器行数,6,,7') \
                .replace('行间距(cm),60,,', '行间距(cm),60,,8')
    inject(rtC, '__WORSE', worse)
    inject(rtC, '__MAP', '演示田5')
    rtC.execute('__OK = store.map_import_text(__MAP, __WORSE)')
    check(bool(rtC.globals().__OK), '损坏地图导入(原样转存, 不经render)')
    fsC = dump_fs(rtC)
    rtD = new_rt()
    storeD = setup_store(rtD, fsC)
    inject(rtD, '__MAP', '演示田5')
    storeD.boot()
    check(rtD.eval('#store.maps[__MAP].aisle') == 0,
          '损坏地图boot后aisle空(实有%d, 属预期)' % rtD.eval(
              '#store.maps[__MAP].aisle'))
    load(rtD, 'pathalgo.lua', 'pathalgo')
    codecD = load(rtD, 'codec.lua', 'codec')
    load(rtD, 'lwmap.lua', 'lwmap')
    load(rtD, 'jobrun.lua', 'jobrun')
    codecD.init({'rows': 6})
    rtD.execute(ASSEMBLE)
    fncsD = sent_fncs(rtD)
    rtD.execute('__ERRCNT = 0\nfor i = 1, #__LOGS do '
                'if __LOGS[i]:sub(1, 4) == "ERR " then __ERRCNT = __ERRCNT + 1 end end')
    check(bool(rtD.globals().__STOK), 'start不抛错(组参失败被pcall)')
    check(0x0B in fncsD and 0x20 not in fncsD and 0x0A not in fncsD,
          '安全停机0x0B且无0x20/0x0A: %s' % [hex(f) for f in fncsD])
    check(not bool(rtD.eval('jobrun.active()')), '现场已回滚(无假"作业中")')
    check(rtD.eval('__ERRCNT') >= 1, 'ERR日志留痕(%d条)' % rtD.eval('__ERRCNT'))

    print()
    print('重启round-trip回归: %s (%d项)' % (
        '全部通过' if FAIL == 0 else '有失败', PASS))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
