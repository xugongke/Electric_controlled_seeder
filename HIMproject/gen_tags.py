# -*- coding: utf-8 -*-
"""gen_tags.py —— 从 lwmap.lua 生成 VisualHMI 地址标签导入文件(XML/CSV)。

单一来源原则: lwmap.lua 是地址唯一权威, 本脚本解析它生成标签表,
地址改动后重跑即可保持画面标签与代码一致。

输出(HIMproject/目录, 均为 GB2312 编码——与工程文件约定一致):
  标签表.xml  每行 <TextLabel><label NAME="区_名" ADDR="LWxxxx" TIP="注释"/></TextLabel>
              (格式对齐官方文档 Resource/05_Address.html 的导入示例)
  标签表.csv  备用: 第1列标签名, 第2列地址, 第3列说明

跳过: LW.SCREEN(画面号非变量)、LW.RW(RW区由Lua直访, 标签体系不含RW)。
用法: python gen_tags.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
LWMAP = os.path.join(HERE, 'Project', 'lwmap.lua')

# XML特殊字符转义(TIP内含注释)
def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;') \
            .replace('"', '&quot;')


def parse_lwmap():
    raw = open(LWMAP, 'rb').read().decode('gb18030')
    region = None
    out = []          # (region, key, addr, tip)
    for line in raw.split('\n'):
        m = re.match(r'LW\.(\w+)\s*=\s*\{', line)
        if m:
            region = m.group(1)
            continue
        if region in (None, 'SCREEN', 'RW'):
            continue
        m = re.match(r'\s{4}(\w+)\s*=\s*0x([0-9A-Fa-f]+),\s*--\s*(.*)$', line)
        if m:
            key, addr, tip = m.group(1), m.group(2).upper(), m.group(3).strip()
            if key.startswith('rw_'):
                continue
            out.append((region, key, addr, tip))
    return out


def main():
    tags = parse_lwmap()
    xml = []
    csv = ['标签名称,变量地址,描述说明']
    for region, key, addr, tip in tags:
        name = '%s_%s' % (region, key)
        xml.append('<TextLabel><label NAME="%s" ADDR="LW%s" TIP="%s"/></TextLabel>'
                   % (name, addr, esc(tip)))
        csv.append('%s,LW%s,%s' % (name, addr, tip.replace(',', '，')))
    with open(os.path.join(HERE, '标签表.xml'), 'wb') as f:
        f.write('\r\n'.join(xml).encode('gb2312', errors='replace') + b'\r\n')
    with open(os.path.join(HERE, '标签表.csv'), 'wb') as f:
        f.write('\r\n'.join(csv).encode('gb2312', errors='replace') + b'\r\n')
    print('生成 %d 个标签 -> 标签表.xml / 标签表.csv' % len(tags))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
