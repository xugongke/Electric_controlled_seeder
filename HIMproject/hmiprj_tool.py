# -*- coding: utf-8 -*-
"""hmiprj_tool.py —— Project.hmiprj 程序化读写工具(2026-10-13 任务向导拆页重构)

格式(逆向确认):
  文件 = 8字节头 + zlib流
  头   = 魔数 b"\\x01\\xdc\\x55\\xaa" + <I 解压后XML字节数(UTF-16LE字节数)
  XML  = UTF-16LE 无BOM无声明, 根元素 <project>, 尾部 "</project>\\r\\n"

原则:
  - 字符串级手术而非ElementTree全量重序列化(编辑器属性顺序/自闭合格式宽容,
    但全量重排diff噪音大; 现工程本就混用 "</screen><screen" 与换行分隔);
  - 控件模板从现有工程实例整体克隆(保全部默认属性), 只改必要属性+换GUID;
  - ScreenID 升序插入; 画面元素之间沿用现有分隔风格。

用法:
  python hmiprj_tool.py roundtrip            # 解包->打包 自测(字节级比对)
  python hmiprj_tool.py unpack -o out.xml    # 解包查看
  python hmiprj_tool.py pack in.xml          # 打包回写(含.bak镜像)
  python hmiprj_tool.py dump-screens         # 列出全部画面与控件统计
  python hmiprj_tool.py spike26              # M1: 加画面26绘图试验页+主页入口
"""
import os
import re
import struct
import sys
import uuid
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(HERE, 'Project')
HMIPRJ = os.path.join(PROJ, 'Project.hmiprj')
BAK = HMIPRJ + '.bak'

MAGIC = b'\x01\xdc\x55\xaa'


# ---------------------------------------------------------------- 容器I/O
def load(path=HMIPRJ):
    raw = open(path, 'rb').read()
    assert raw[:4] == MAGIC, '魔数不符: %s' % raw[:4].hex()
    size = struct.unpack('<I', raw[4:8])[0]
    data = zlib.decompress(raw[8:])
    assert len(data) == size, '长度字段%d≠实有%d' % (size, len(data))
    return data.decode('utf-16-le')


def save(xml, path=HMIPRJ, mirror_bak=True):
    data = xml.encode('utf-16-le')
    blob = MAGIC + struct.pack('<I', len(data)) + zlib.compress(data)
    open(path, 'wb').write(blob)
    if mirror_bak and os.path.exists(BAK):
        open(BAK, 'wb').write(blob)
    return blob


# ---------------------------------------------------------------- widget手术
WIDGET_OPEN = re.compile(r'<widget\s+([^>]*?)(/?)>')


def parse_attrs(open_tag_body):
    """opening tag属性体 -> 有序[(k,v)]; 保留重复外的全部字面"""
    return re.findall(r'(\w+)="([^"]*)"', open_tag_body)


def set_attrs(open_tag_body, overrides):
    """按原顺序就地替换/追加属性, 返回新属性体(顺序: 原序+新增尾部)"""
    pairs = parse_attrs(open_tag_body)
    seen = set()
    out = []
    for k, v in pairs:
        if k in overrides:
            out.append((k, overrides[k]))
        else:
            out.append((k, v))
        seen.add(k)
    for k, v in overrides.items():
        if k not in seen:
            out.append((k, v))
    return ' '.join('%s="%s"' % kv for kv in out)


def find_widget_span(xml, pred_start):
    """返回 (opening_tag整体(含<widget...>), open_body, selfclose, end偏移)"""
    i = pred_start()
    if i < 0:
        return None
    j = xml.find('>', i)
    tag = xml[i:j + 1]
    selfclose = tag.rstrip().endswith('/>')
    body = tag[len('<widget'):-2 if selfclose else -1].strip()
    end = j + 1
    if not selfclose:
        end = xml.find('</widget>', j) + len('</widget>')
    return tag, body, selfclose, i, end


def clone_widget(xml, src_loc, overrides):
    """从xml中克隆一个widget元素(含子status), 应用属性覆盖, 换新GUID"""
    span = find_widget_span(xml, src_loc)
    if not span:
        raise SystemExit('模板控件未找到')
    tag, body, selfclose, i, end = span
    ov = dict(overrides)
    ov['GUID'] = str(uuid.uuid4()).upper()
    new_body = set_attrs(body, ov)
    frag = xml[i:end]
    new_tag = '<widget %s%s>' % (new_body, '/' if selfclose else '')
    if selfclose:
        return new_tag
    inner = frag[len(tag):-len('</widget>')]
    return new_tag + inner + '</widget>'


def screen_span(xml, sid):
    """返回画面元素的 (screen_open_tag, body, i, j); 不存在返回None"""
    for m in re.finditer(r'<screen ([^>]*?)/?>', xml):
        body = m.group(1)
        sidv = re.search(r'ScreenID="(\d+)"', body)
        if sidv and int(sidv.group(1)) == sid:
            i = m.start()
            j = xml.find('</screen>', i)
            if j < 0:                      # 自闭合screen(无控件)
                j = m.end()
                return m.group(0), '', i, j
            return m.group(0), body, i, j
    return None


def insert_screen(xml, screen_xml, sid):
    """按ScreenID升序插入完整<screen>...</screen>"""
    if screen_span(xml, sid):
        raise SystemExit('画面%d已存在' % sid)
    # 找第一个 ScreenID > sid 的画面, 插它前面; 否则插 </screens> 前
    pos = None
    for m in re.finditer(r'<screen ', xml):
        body = xml[m.start():xml.find('>', m.start())]
        sidv = re.search(r'ScreenID="(\d+)"', body)
        if sidv and int(sidv.group(1)) > sid:
            pos = m.start()
            break
    if pos is None:
        pos = xml.find('</screens>')
    return xml[:pos] + screen_xml + xml[pos:]


# ---------------------------------------------------------------- 模板定位
def attr_of(body, name):
    """精确取属性(词边界, 防ShowText误匹配Text)"""
    m = re.search(r'\b%s="([^"]*)"' % re.escape(name), body)
    return m.group(1) if m else None


def tmpl_loc(xml, sid, **match):
    """在画面sid中按属性等值找控件 -> clone_widget的loc参数。
    如 tmpl_loc(xml, 6, Text='任务状态') / tmpl_loc(xml, 0, DestScreen='8')"""
    span = screen_span(xml, sid)
    if not span:
        raise SystemExit('画面%d不存在' % sid)
    _, _, i, j = span
    seg = xml[i:j]

    def loc():
        for m in WIDGET_OPEN.finditer(seg):
            body = m.group(1)
            if all(attr_of(body, k) == v for k, v in match.items()):
                return i + m.start()
        return -1
    return loc


# ---------------------------------------------------------------- M1: 画面26
BASIC_GRAPH_COMMON = {
    'ID': '1', 'LineSize': '0', 'MultipleCmd': '0', 'PaintMode': '0',
    'PaintBackground': '255;255;255', 'PaintFinishNotify': '0',
    'ReadAddr': 'LW10A0', 'Tip': '绘图试验画布',
    'Left': '50', 'Top': '40', 'Width': '700', 'Height': '360',
}


def build_basic_graph(xml, overrides=None):
    """WidgetBasicGraph模板: 公共属性取自现有widget(全类型共通), 叠加专属属性。
    全工程无现成实例, 专属schema来自编辑器Widget.dll属性表(逆向提取)。"""
    ov = dict(BASIC_GRAPH_COMMON)
    ov['Type'] = 'WidgetBasicGraph'
    if overrides:
        ov.update(overrides)
    # 公共属性基底: 用画面6的"任务状态"Text控件opening tag(纯公共属性)
    return clone_widget(xml, tmpl_loc(xml, 6, Text='任务状态'), ov)


def cmd_spike26():
    xml = load()
    assert not screen_span(xml, 26), '画面26已存在'
    # screen壳: 克隆画面22的screen元素属性, 改ID/名称/尺寸/全屏
    s22 = screen_span(xml, 22)
    sbody = set_attrs(s22[1], {'ScreenID': '26', 'Name': '绘图试验',
                               'Width': '800', 'Height': '480',
                               'SpecialSize': '0'})
    w_canvas = build_basic_graph(xml)
    w_title = clone_widget(xml, tmpl_loc(xml, 6, Text='任务状态'),
                           {'Text': '绘图试验页(底座验证)', 'Left': '8',
                            'Top': '6', 'Width': '260', 'Height': '30'})
    w_btn = clone_widget(xml, tmpl_loc(xml, 6, WriteAddr='$tw_btn_ok'),
                         {'Left': '330', 'Top': '420',
                          'Width': '120', 'Height': '40',
                          'WriteAddr': 'LW10A1'})
    # 按钮显示文本在status子元素里(两处: status0=常态)
    w_btn = re.sub(r'(<status ID="0"[^>]*?Text=")[^"]*(")',
                   r'\g<1>切换图样\g<2>', w_btn)
    w_home = clone_widget(xml, tmpl_loc(xml, 6, DestScreen='0'),
                          {'Left': '660', 'Top': '420'})
    w_entry = clone_widget(xml, tmpl_loc(xml, 0, DestScreen='8'),
                           {'Left': '511', 'Top': '159', 'DestScreen': '26'})
    w_entry = re.sub(r'(<status ID="0"[^>]*?Text=")[^"]*(")',
                     r'\g<1>绘图试验\g<2>', w_entry)
    screen26 = ('<screen %s>%s%s%s%s%s</screen>\r\n\t\t'
                % (sbody, w_title, w_canvas, w_btn, w_home, w_entry))
    xml = insert_screen(xml, screen26, 26)
    # 主页入口按钮: 插到画面0末尾(状态栏容器之前)
    s0 = screen_span(xml, 0)
    cont_i = xml.rfind('<widget', s0[2], s0[3])
    xml = xml[:cont_i] + w_entry + xml[cont_i:]
    save(xml)
    print('画面26已加入(画布/标题/切换按钮/主页返回/主页入口), .bak已镜像')
    print('画布: ID=1 (50,40,700,360) ReadAddr=LW10A0 PaintMode=重绘')


# ---------------------------------------------------------------- CLI
def cmd_roundtrip():
    xml = load()
    blob = save(xml, path=os.path.join(HERE, '_roundtrip_tmp.hmiprj'),
                mirror_bak=False)
    orig = open(HMIPRJ, 'rb').read()
    same = blob == orig
    print('解包XML: %d字符; 重打包: %dB vs 原 %dB -> %s'
          % (len(xml), len(blob), len(orig),
             '字节级一致' if same else '字节不同(内容等价, 编辑器用标准zlib可解)'))
    xml2 = load(os.path.join(HERE, '_roundtrip_tmp.hmiprj'))
    print('二次解包与原XML一致:', xml2 == xml)
    os.remove(os.path.join(HERE, '_roundtrip_tmp.hmiprj'))
    return 0 if xml2 == xml else 1


def cmd_dump_screens():
    xml = load()
    for m in re.finditer(r'<screen ([^>]*?)/?>', xml):
        body = m.group(1)
        sid = re.search(r'ScreenID="(\d+)"', body).group(1)
        name = re.search(r'Name="([^"]*)"', body)
        wh = (re.search(r'Width="(\d+)"', body).group(1),
              re.search(r'Height="(\d+)"', body).group(1))
        sp = re.search(r'SpecialSize="(\d+)"', body)
        i = m.start()
        j = xml.find('</screen>', i)
        if j < 0:
            j = m.end()
        nw = len(WIDGET_OPEN.findall(xml[i:j]))
        print('画面%-4s %-12s %sx%s 弹窗=%s 控件%d'
              % (sid, name.group(1) if name else '?', wh[0], wh[1],
                 sp.group(1) if sp else '?', nw))
    return 0


def cmd_unpack(out):
    xml = load()
    open(out, 'wb').write(xml.encode('utf-16-le'))
    print('已解包 -> %s (%d字符)' % (out, len(xml)))
    return 0


def cmd_pack(inp):
    data = open(inp, 'rb').read()
    xml = data.decode('utf-16-le')
    save(xml)
    print('已打包回写 %s (.bak已镜像)' % HMIPRJ)
    return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'roundtrip'
    if cmd == 'roundtrip':
        return cmd_roundtrip()
    if cmd == 'dump-screens':
        return cmd_dump_screens()
    if cmd == 'unpack':
        out = sys.argv[sys.argv.index('-o') + 1] if '-o' in sys.argv \
            else os.path.join(HERE, 'project_dump.xml')
        return cmd_unpack(out)
    if cmd == 'pack':
        return cmd_pack(sys.argv[2])
    if cmd == 'sync-labels':
        return cmd_sync_labels()
    if cmd == 'spike26':
        return cmd_spike26()
    print(__doc__)
    return 1




def cmd_sync_labels():
    """按标签表.csv重建hmiprj的<addrlabels>(编辑器解析$name的依据)"""
    import csv
    rows = list(csv.reader(open(os.path.join(HERE, '标签表.csv'),
                                encoding='gb18030')))
    assert rows and rows[0][0] == '标签名称', 'CSV表头异常'

    def esc(s):
        return (s.replace('&', '&amp;').replace('<', '&lt;')
                .replace('>', '&gt;').replace('"', '&quot;'))

    labels = ['<label NAME="标签名称" ADDR="变量地址" TIP="描述说明"/>']
    for r in rows[1:]:
        if len(r) < 2 or not r[0] or not r[1]:
            continue
        labels.append('<label NAME="%s" ADDR="%s" TIP="%s"/>'
                      % (esc(r[0]), esc(r[1]), esc(r[2]) if len(r) > 2 else ''))
    xml = load()
    i = xml.find('<addrlabels>')
    j = xml.find('</addrlabels>')
    assert i >= 0 and j > i, 'addrlabels块未找到'
    xml = xml[:i] + '<addrlabels>\r\n\t\t' \
        + '\r\n\t\t'.join(labels) + '\r\n\t' + xml[j:]
    save(xml)
    print('addrlabels已重建: %d个标签(含表头占位)' % len(labels))


if __name__ == '__main__':
    sys.exit(main())
