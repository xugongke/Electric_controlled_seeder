# -*- coding: utf-8 -*-
"""hmiprj_fix_detail.py — 详情QT风格控件合并手术 (M42)。

画面9: 删 $tm_btn_sel + 5个分立详情控件(tmap/tcreate/tlast/tpct/tremark),
  tm_tname 改绑 $tm_tdetail(TextMaxLen 32->196字节, 高度24->168盖住原字段区)。
画面1: $map_detail TextMaxLen 64->256(地址迁0x1C80由lwmap承担)。
addrlabels: 删 tm_tname/tmap/tcreate/tlast/tpct/tremark/btn_sel 7个,
  增 tm_tdetail(LW1E32), map_detail 改址 LW1C80。
"""
import os
import re
import sys
import io

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'HIMproject'))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import hmiprj_tool as T

DEL_READADDRS = ['$tm_tmap', '$tm_tcreate', '$tm_tlast', '$tm_tpct',
                 '$tm_tremark']
DEL_WRITEADDRS = ['$tm_btn_sel']


def main():
    xml = T.load()

    # ---- 画面9 删分立详情控件 ----
    n_del = 0
    for tag in DEL_READADDRS:
        while True:
            a = xml.find('ReadAddr="%s"' % tag)
            if a < 0:
                break
            wi = xml.rfind('<widget', 0, a)
            sp = T.find_widget_span(xml, lambda: wi)
            assert sp, '%s span失败' % tag
            _, _, _, i, end = sp
            xml = xml[:i] + xml[end:]
            n_del += 1
    for tag in DEL_WRITEADDRS:
        while True:
            a = xml.find('WriteAddr="%s"' % tag)
            if a < 0:
                break
            wi = xml.rfind('<widget', 0, a)
            sp = T.find_widget_span(xml, lambda: wi)
            assert sp, '%s span失败' % tag
            _, _, _, i, end = sp
            xml = xml[:i] + xml[end:]
            n_del += 1
    print('删除控件: %d (期望6)' % n_del)
    assert n_del == 6

    # ---- 画面9 tm_tname -> tm_tdetail ----
    a = xml.find('ReadAddr="$tm_tname"')
    assert a > 0, 'tm_tname未找到'
    wi = xml.rfind('<widget', 0, a)
    sp = T.find_widget_span(xml, lambda: wi)
    tag_xml, body, selfclose, i, end = sp
    new_body = T.set_attrs(body, {'ReadAddr': '$tm_tdetail',
                                  'TextMaxLen': '196', 'Height': '168'})
    new_open = '<widget %s%s>' % (new_body, '/' if selfclose else '')
    if selfclose:
        xml = xml[:i] + new_open + xml[end:]
    else:
        inner = xml[i + len(tag_xml):end - len('</widget>')]
        xml = xml[:i] + new_open + inner + '</widget>' + xml[end:]
    print('tm_tname -> $tm_tdetail (196B, H=168)')

    # ---- 画面1 map_detail 容量扩容 ----
    a = xml.find('ReadAddr="$map_detail"')
    assert a > 0, 'map_detail未找到'
    wi = xml.rfind('<widget', 0, a)
    sp = T.find_widget_span(xml, lambda: wi)
    tag_xml, body, selfclose, i, end = sp
    new_body = T.set_attrs(body, {'TextMaxLen': '256'})
    new_open = '<widget %s%s>' % (new_body, '/' if selfclose else '')
    if selfclose:
        xml = xml[:i] + new_open + xml[end:]
    else:
        inner = xml[i + len(tag_xml):end - len('</widget>')]
        xml = xml[:i] + new_open + inner + '</widget>' + xml[end:]
    print('map_detail TextMaxLen -> 256')

    # ---- addrlabels 更新 ----
    for name in ('tm_tname', 'tm_tmap', 'tm_tcreate', 'tm_tlast',
                 'tm_tpct', 'tm_tremark', 'tm_btn_sel'):
        m = re.search(r'[\r\n\t ]*<label NAME="%s"[^>]*/>' % name, xml)
        assert m, '标签未找到: %s' % name
        xml = xml[:m.start()] + xml[m.end():]
    i = xml.find('<label NAME="tm_btn_start"')
    assert i > 0, '标签锚点未找到'
    j = xml.find('/>', i) + 2
    newlbl = ('\r\n\t\t<label NAME="tm_tdetail" ADDR="LW1E32" '
              'TIP="字符串 任务详情QT风格合并文本(98字=196字节, 多行\\r\\n, '
              'M42六控件合一)"/>')
    xml = xml[:j] + newlbl + xml[j:]
    m = re.search(r'<label NAME="map_detail" ADDR="LW1C44"([^>]*)/>', xml)
    assert m, 'map_detail标签未找到'
    xml = (xml[:m.start()]
           + '<label NAME="map_detail" ADDR="LW1C80" TIP="字符串 选中地图'
             '详情QT风格(128字=256字节, M42迁址扩容)"/>'
           + xml[m.end():])

    # ---- 验证 ----
    for tag in DEL_READADDRS + DEL_WRITEADDRS:
        assert tag not in xml, '仍残留%s' % tag
    assert 'NAME="tm_tdetail"' in xml and '$tm_tdetail' in xml
    assert 'ADDR="LW1C44"' not in xml
    T.save(xml)
    print('验证通过, 已保存, .bak已镜像')


if __name__ == '__main__':
    main()
