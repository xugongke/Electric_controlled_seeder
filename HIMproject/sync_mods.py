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
           'pathalgo', 'jobrun', 'logger', 'page_home', 'page_task',
           'page_cellpara', 'page_continuous', 'page_history', 'page_params',
           'page_testdiag', 'page_abline', 'page_logview']


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
    names = args or MODULES

    raw = open(MAIN, 'rb').read()
    changed = False
    for n in names:
        src_path = os.path.join(PROJ, n + '.lua')
        if not os.path.exists(src_path):
            print('%-14s 源码不存在, 跳过' % n)
            continue
        span = find_span(raw, n)
        if not span:
            print('%-14s main.lua 中无内嵌条目, 跳过' % n)
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
