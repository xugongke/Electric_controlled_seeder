# -*- coding: utf-8 -*-
"""HIM工程 屏端兼容改写的等价性验证 (lupa, Lua 5.3)。

背景: 屏端Lua不支持 string.rep/gsub/gmatch (文档LUA/000_Lua_Api), 工程源码里
codec.lua/csv.lua/logger.lua 原先用到这些函数。已手写等价实现, 本测试把改写后的
实现与 PC Lua 原生 gmatch/gsub 版本在同一输入矩阵上逐项比对。

运行: python hmi_port/tests/test_him_platform_compat.py
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


REF = r'''
-- PC原版(用被禁函数)作为行为基准
function ref_trim(s)      return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ref_iter(text)
    if text:sub(1, 3) == "\xEF\xBB\xBF" then text = text:sub(4) end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local r = {}
    for l in text:gmatch("([^\n]*)\n?") do r[#r+1] = l if #r > 4096 then break end end
    return r
end
function ref_split(line)
    local t = {}
    for f in line:gmatch("([^,]*)") do t[#t + 1] = ref_trim(f) if #t > 32 then break end end
    return t
end
function ref_fmt_num(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return (string.format("%.8f", v):gsub("%.?0+$", ""))
end
function ref_strip_digits(s) return (s:gsub("%d+$", "")) end
'''


def llist(t):
    return [t[i] for i in range(1, len(t) + 1)]


def main():
    lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(REF)
    g = lua.globals()

    # 加载改写后的 csv.lua, 并把局部 trim/fmt_num 暴露出来(仅测试)
    # 注意: 工程源码为 GB2312/GB18030 编码
    import tempfile
    tmpd = tempfile.mkdtemp()

    def load_patched(name, hook, ret):
        src = open(os.path.join(HIM, name), encoding='gb18030').read()
        assert ret in src
        src = src.replace(ret, hook + ' return ' + ret.split()[1].strip(), 1)
        p = os.path.join(tmpd, name).replace('\\', '/')
        with open(p, 'w', encoding='gb18030') as fp:
            fp.write(src)
        lua.globals().__P = p
        return lua.execute('local f = assert(loadfile(__P)); return f()')

    csv = load_patched('csv.lua', 'csv._trim = trim; csv._fmt_num = fmt_num;',
                       'return csv')
    check(csv is not None and csv['split'] is not None, 'csv.lua 改写后可加载')

    print('1) trim')
    for s in ('  a  ', '\t\t', '', ' a', 'a ', ' \t x \r\n ', 'ab'):
        check(csv['_trim'](s) == g.ref_trim(s), 'trim(%r)' % s)

    print('2) iter_lines')
    for s in ('a\nb', 'a\nb\n', 'a\r\nb', 'a\rb', '', 'x', '\n', 'a\n\nb',
              '\xEF\xBB\xBFa\nb', '\n\n'):
        got = []
        it = csv['iter_lines'](s)
        while True:
            v = it()
            if v is None:
                break
            got.append(v)
        check(got == llist(g.ref_iter(s)), 'iter_lines(%r) -> %r' % (s, got))

    print('3) split')
    for s in ('a,b', 'a,,b', '', 'x', ' a , b ', 'a,', ',a', ','.join(['f'] * 35)):
        check(llist(csv['split'](s)) == llist(g.ref_split(s)), 'split(%d字段)' % len(s))

    print('4) fmt_num / strip_digits')
    for v in (36.4, 117.0, -3.75, 1e-7, 0.5, 123.456789123, -0.0000001):
        check(csv['_fmt_num'](v) == g.ref_fmt_num(v),
              'fmt_num(%r) -> %s' % (v, csv['_fmt_num'](v)))

    # codec.lua 的 strip_digits 是局部函数, 经临时文件注入全局后验证
    src = open(os.path.join(HIM, 'codec.lua'), encoding='gb18030').read()
    assert 'return codec' in src
    src = src.replace('return codec', '__SD = strip_digits; return codec', 1)
    p = os.path.join(tmpd, 'codec_t.lua').replace('\\', '/')
    with open(p, 'w', encoding='gb18030') as fp:
        fp.write(src)
    lua.globals().__P = p
    lua.execute('local f = assert(loadfile(__P)); f()')
    sd = lua.globals().__SD
    for s in ('Density1', 'NextDensity12', 'abc', 'a1b2', '123', 'RowNum'):
        check(sd(s) == g.ref_strip_digits(s), 'strip_digits(%r) -> %r' % (s, sd(s)))

    print('5) 全工程不再使用禁用函数')
    bad = []
    for fn in os.listdir(HIM):
        if not fn.endswith('.lua') or fn == 'main.lua':
            continue
        text = open(os.path.join(HIM, fn), encoding='gb18030', errors='replace').read()
        # 先剔--[[ ]]块注释(mapdraw.lua头为块注释写法, 2026-10-13)
        while True:
            b = text.find('--[[')
            if b < 0:
                break
            e = text.find('--]]', b)
            text = text[:b] + (text[e + 4:] if e >= 0 else '')
        code = []
        for line in text.split('\n'):
            cut = line.find('--')                      # 剔除行注释再查
            code.append(line[:cut] if cut >= 0 else line)
        code = '\n'.join(code)
        for pat in (':rep(', 'string.rep', 'gmatch', 'gsub'):
            if pat in code:
                bad.append('%s: %s' % (fn, pat))
    check(not bad, '源码模块零残留(注释除外)' + ('' if not bad else ' -> %s' % bad))

    print()
    if FAIL:
        print('平台兼容改写: %d项失败' % FAIL)
    else:
        print('平台兼容改写: 全部通过 (%d项)' % PASS)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
