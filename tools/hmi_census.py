# -*- coding: utf-8 -*-
"""普查 Project.hmiprj: 标签表 + 画面5控件绑定 + 地址冲突检测"""
import os
import re
import sys
import io

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'HIMproject'))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import hmiprj_tool as T

xml = T.load()
print('XML: %d chars' % len(xml))

print('=' * 70)
print('---- 标签表 (NAME -> ADDR) ----')
labels = re.findall(r'<label\s+NAME="([^"]+)"\s+ADDR="([^"]+)"([^>]*)/>', xml)
print('label 总数: %d' % len(labels))
bitlabels = []
for name, addr, rest in labels:
    mark = ''
    if '.' in addr:
        mark = '  <== 位地址'
        bitlabels.append((name, addr))
    print('  %-22s -> %-14s %s%s' % (name, addr, rest.strip()[:70], mark))

print('=' * 70)
print('---- 位地址标签汇总 (%d 个) ----' % len(bitlabels))
for name, addr in bitlabels:
    print('  %-22s -> %s' % (name, addr))

print('=' * 70)
print('---- 标签地址冲突检测 ----')
byaddr = {}
for name, addr, rest in labels:
    byaddr.setdefault(addr.upper(), []).append(name)
bad = 0
for addr, names in sorted(byaddr.items()):
    if len(names) > 1:
        bad += 1
        print('  冲突 %s : %s' % (addr, names))
if not bad:
    print('  无冲突')

print('=' * 70)
span5 = T.screen_span(xml, 5)
if not span5:
    print('!! 未找到画面5')
    sys.exit(0)
_, _, i5, j5 = span5
seg = xml[i5:j5]
print('---- 画面5 控件绑定普查 (段长 %d) ----' % len(seg))
n = 0
for m in T.WIDGET_OPEN.finditer(seg):
    body = m.group(1)
    kind = re.search(r'ID="([^"]*)"', body)
    keys = [k for k in ('Name', 'Text', 'ReadAddr', 'WriteAddr', 'StatusCount')
            if T.attr_of(body, k) is not None]
    vals = {k: T.attr_of(body, k) for k in keys}
    if not any(v for kk, v in vals.items() if kk != 'Name'):
        continue
    n += 1
    info = ' '.join('%s=%r' % (k, vals[k]) for k in keys)
    print('  [%2d] %-18s %s' % (n, kind.group(1) if kind else '?', info[:160]))

print('=' * 70)
print('---- 画面5 中 $引用 解析检查 ----')
refs = set(re.findall(r'\$([A-Za-z_]\w*)', seg))
names = set(nm for nm, _, _ in labels)
miss = sorted(r for r in refs if r not in names)
print('引用种类: %d, 未解析: %s' % (len(refs), miss if miss else '无'))
