# -*- coding: utf-8 -*-
"""sync_mods.py —— 把源码模块重新内嵌进 main.lua 的 _MODS 兜底区。

背景: main.lua 由 deploy_screen.py 生成(该脚本已不在仓库), 其 _MODS 区以
      _MODS["<名>.lua"] = [==[ ...源码... ]==] 形式内嵌全部模块作为兜底;
      源码与内嵌会漂移(本次 codec/csv/logger/protocol 修改后即如此)。
      本工具按源码现状重写指定模块的内嵌条目。

用法:  python sync_mods.py codec csv logger protocol     # 重内嵌指定模块
       python sync_mods.py --check                       # 只报告漂移
       python sync_mods.py                               # 同步全部已知模块
注意: 工程文件为 GB2312/GB18030 + CRLF, 本工具按字节操作并保持该约定。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(HERE, 'Project')
MAIN = os.path.join(PROJ, 'main.lua')

MODULES = ['lwmap', 'protocol', 'codec', 'csv', 'fileio', 'store', 'app',
           'pathalgo', 'jobrun', 'logger', 'parastore', 'page_task',
           'page_map', 'page_userparam', 'page_manuparam', 'page_continuous',
           'page_testdiag', 'page_history', 'page_logview']

# 防再犯(2026-09-30): main.lua加载列表的模块必须在上面清单里, 否则
# _MODS兜底区缺源码 -> 真机/虚拟屏load_mod失败 -> 功能静默降级为旧行为
# (本次parastore未嵌入即此因, 用户实测虚拟屏进测试不发0x27暴露)
def _crosscheck():
    import re
    mt = open(os.path.join(PROJ, 'main.lua'), 'rb').read().decode('gb18030')
    loaded = set(re.findall(r'"(\w+\.lua)"', mt[:6000]))
    missing = [n for n in sorted(loaded) if n[:-4] not in MODULES]
    if missing:
        raise SystemExit('[sync_mods] 清单缺模块(将导致内嵌缺失): %s' % missing)


def crlf(b):
    return b.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')


def find_span(raw, name):
    """返回 (head_end, body_start, body_end); 找不到返回 None。"""
    head = ('_MODS["%s.lua"] = [==[' % name).encode('ascii')
    i = raw.find(head)
    if i < 0:
        return None
    start = i + len(head) + 2                      # 跳过 [==[ 后的 \r\n
    j = raw.find(b']==]', start)
    if j < 0:
        return None
    end = j
    while end > start and raw[end - 1] in (10, 13):
        end -= 1
    return i + len(head), start, end


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    check_only = '--check' in sys.argv
    removing = '--remove' in sys.argv
    names = args or MODULES

    raw = open(MAIN, 'rb').read()
    changed = False
    if removing:
        # --remove <模块名...>: 从 main.lua 删除指定内嵌条目(源文件自行删除)
        for n in names:
            span = find_span(raw, n)
            if not span:
                print('%-14s 无内嵌条目' % n)
                continue
            i, _, _ = span
            # 回退到条目起始行首, 向后吃到 ]==] 行尾(含换行)
            ls = raw.rfind(b'\n', 0, i) + 1
            e = raw.find(b']==]', i)
            if e < 0:
                print('%-14s 条目损坏(无]==])' % n)
                continue
            le = raw.find(b'\n', e)
            le = le + 1 if le >= 0 else len(raw)
            raw = raw[:ls] + raw[le:]
            changed = True
            print('%-14s 内嵌条目已删除' % n)
        if changed:
            open(MAIN, 'wb').write(raw)
            print('main.lua 已更新 (%dB)' % len(raw))
        return 0

    for n in names:
        src_path = os.path.join(PROJ, n + '.lua')
        if not os.path.exists(src_path):
            print('%-14s 源码不存在, 跳过' % n)
            continue
        span = find_span(raw, n)
        if not span:
            # 新模块: 在最后一个 _MODS 条目之后插入新条目
            src = crlf(open(src_path, 'rb').read()).rstrip(b'\r\n')
            if b']==]' in src:
                print('%-14s 源码含 ]==], 不能内嵌!' % n)
                continue
            last = raw.rfind(b']==]')
            if last < 0:
                print('%-14s main.lua 无_MODS区, 跳过' % n)
                continue
            eol = raw.find(b'\n', last)
            eol = eol + 1 if eol >= 0 else len(raw)
            entry = ('\r\n_MODS["%s.lua"] = [==[\r\n' % n).encode('ascii') \
                + src + b'\r\n]==]\r\n'
            if not check_only:
                raw = raw[:eol] + entry + raw[eol:]
                changed = True
            print('%-14s 新增内嵌条目 (%dB)%s'
                  % (n, len(src), ' [仅检查]' if check_only else ' [已插入]'))
            continue
        _, start, end = span
        # 内嵌正文按原约定不带尾换行(后面紧跟 \r\n]==] )
        src = crlf(open(src_path, 'rb').read()).rstrip(b'\r\n')
        cur = raw[start:end]
        # 内容里出现 ]==] 会破坏长括号, 防御性检查
        if b']==]' in src:
            print('%-14s 源码含 ]==], 不能内嵌!' % n)
            continue
        if cur == src:
            print('%-14s 已一致 (%dB)' % (n, len(src)))
        else:
            print('%-14s 漂移: 内嵌%dB -> 源码%dB%s'
                  % (n, len(cur), len(src), ' [仅检查]' if check_only else ' [已同步]'))
            if not check_only:
                raw = raw[:start] + src + raw[end:]
                changed = True
    if changed:
        open(MAIN, 'wb').write(raw)
        print('main.lua 已更新 (%dB)' % len(raw))
    return 0


if __name__ == '__main__':
    sys.exit(main())
