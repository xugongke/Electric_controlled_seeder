# -*- coding: utf-8 -*-
"""hmiprj_fix_3state.py — 测试页输入灯三态化 + walamp报警灯列退役 (M38)。

对齐QT formtest三态指示灯: 0=未触发(disabled禁行帧) 1=触发(enabled绿帧)
2=报警(alarm警号帧), 图=project.xico/5三帧容器(用户已导入, 帧序经md5核实),
控件写法照抄画面24路径方式灯先例(ImageLib=单帧容器引用 + StatusCount=N +
N个status子元素, StatusValueMap空, 按值选帧)。

步骤:
  1) 15个输入灯(td_input0~14, Left=8): StatusCount 2->3, ImageLib=xico/5,
     ImageLib0/1清空(先例如此), 补status ID=2子元素;
  2) 删除15个walamp报警灯控件($td_walamp0~14绑定);
  3) 删除addrlabels中td_walamp0~14标签;
可重复执行(目标状态幂等)。
"""
import os
import re
import sys
import io

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'HIMproject'))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import hmiprj_tool as T


def main():
    xml = T.load()
    span5 = T.screen_span(xml, 5)
    assert span5, '画面5不存在'
    _, _, i5, j5 = span5

    # ---- 1) 输入灯三态化 ----
    n_lamp = 0
    for n in range(15):
        anchor = xml.find('ReadAddr="$td_input%d"' % n, i5, j5)
        assert anchor > 0, 'td_input%d 控件未找到' % n
        wi = xml.rfind('<widget', i5, anchor)
        sp = T.find_widget_span(xml, lambda: wi)
        assert sp, 'td_input%d span失败' % n
        tag_xml, body, selfclose, i, end = sp
        assert T.attr_of(body, 'StatusCount') == '2', \
            'td_input%d StatusCount=%s(期望2, 幂等保护)' % (
                n, T.attr_of(body, 'StatusCount'))
        new_body = T.set_attrs(body, {'ImageLib': 'project.xico/5',
                                      'ImageLib0': '', 'ImageLib1': '',
                                      'StatusCount': '3'})
        if selfclose:
            raise SystemExit('输入灯不应为自闭合: td_input%d' % n)
        inner = xml[i + len(tag_xml):end - len('</widget>')]
        # 补status ID=2(克隆ID=1子元素换ID)
        m1 = re.search(r'<status ID="1"[^>]*/>', inner)
        assert m1, 'td_input%d 缺status ID=1' % n
        st2 = m1.group(0).replace('ID="1"', 'ID="2"', 1)
        assert 'ID="2"' not in inner, 'td_input%d 已有ID=2' % n
        inner = inner[:m1.end()] + st2 + inner[m1.end():]
        xml = xml[:i] + '<widget %s>' % new_body + inner + '</widget>' + xml[end:]
        n_lamp += 1
        span5 = T.screen_span(xml, 5)
        _, _, i5, j5 = span5
    print('输入灯三态化: %d / 15' % n_lamp)

    # ---- 2) 删walamp控件 ----
    n_del = 0
    while True:
        a = xml.find('ReadAddr="$td_walamp')
        if a < 0:
            break
        wi = xml.rfind('<widget', 0, a)
        sp = T.find_widget_span(xml, lambda: wi)
        assert sp, 'walamp span失败'
        _, _, _, i, end = sp
        xml = xml[:i] + xml[end:]
        n_del += 1
    print('walamp控件删除: %d / 15' % n_del)
    assert n_del == 15, 'walamp删除数异常'

    # ---- 3) 删td_walamp标签 ----
    n_lbl = 0
    while True:
        m = re.search(r'[\r\n\t ]*<label NAME="td_walamp\d+"[^>]*/>', xml)
        if not m:
            break
        xml = xml[:m.start()] + xml[m.end():]
        n_lbl += 1
    print('td_walamp标签删除: %d / 15' % n_lbl)
    assert n_lbl == 15, '标签删除数异常'

    # ---- 验证 ----
    assert xml.count('$td_walamp') == 0, '仍残留$td_walamp引用'
    assert 'td_walamp' not in xml, '仍残留td_walamp'
    span5 = T.screen_span(xml, 5)
    _, _, i5, j5 = span5
    seg = xml[i5:j5]
    n3 = 0
    for m in T.WIDGET_OPEN.finditer(seg):
        b = m.group(1)
        ra = T.attr_of(b, 'ReadAddr') or ''
        if not ra.startswith('$td_input'):
            continue
        assert T.attr_of(b, 'StatusCount') == '3', ra
        assert T.attr_of(b, 'ImageLib') == 'project.xico/5', ra
        assert T.attr_of(b, 'ImageLib0') == '' and T.attr_of(b, 'ImageLib1') == '', ra
        n3 += 1
    assert n3 == 15, '三态灯数量%d≠15' % n3
    assert seg.count('<status ID="2"') == 15, 'status ID=2数量异常'
    assert seg.count('<widget') == seg.count('</widget>') + \
        len(re.findall(r'<widget [^>]*/>', seg)), 'widget配对异常'
    T.save(xml)
    print('验证通过(15灯三态/无walamp残留/widget配对), 已保存, .bak已镜像')


if __name__ == '__main__':
    main()
