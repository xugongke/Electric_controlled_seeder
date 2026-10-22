# -*- coding: utf-8 -*-
"""hmiprj_fix_outswitch.py — 画面5输出侧17路开关绑定修复(2026-10-22, M37)。

背景: 上次"按钮→位状态灯"转换手术只克隆了控件形态, ReadAddr/WriteAddr
全部为空(阀列9个还残留模板Text='进入测试'), 下屏后输出侧全死。
本脚本按既有工程先例(画面1地图按钮/画面2启动停止: StatusCount=2开关只绑
WriteAddr, 点击翻转写值, 显示跟随该字)补齐绑定; 用户布局(Left/Top)不动。

行映射(坐标已核实, 脚本内assert防错位):
  阀列  L=500 T=42..314 步进34 : 预落种/倒种/清种/刮种/预留1/预留2/喇叭/
                                 打点器/报警灯 -> td_sw0~8 (CtrlNo0~8)
  电机列 L=620 T=32..270 步进34: 运行指示灯 -> td_sw9(CtrlNo9),
                                 步进电机1~4/自动供种/步进电机5~6 -> td_m1~7
可重复执行(已绑定的目标值相同则幂等)。
"""
import os
import re
import sys
import io

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'HIMproject'))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import hmiprj_tool as T

# GUID -> (期望Left, 期望Top, 绑定标签)
FIX = [
    ('080255F4-A261-4826-9A38-4B2D9887A7EB', 500,  42, '$td_sw0'),
    ('18450804-BD46-4D98-97DB-C339F546FAEC', 500,  76, '$td_sw1'),
    ('D52EB8C1-0D71-40F3-A67D-E7AEC2BF9926', 500, 110, '$td_sw2'),
    ('EAD6E55D-CC4F-425B-AA40-D4C567376ECD', 500, 144, '$td_sw3'),
    ('3A4D1707-8017-43CA-8D3D-6AF791F6A90A', 500, 178, '$td_sw4'),
    ('F5D164BF-5FFD-4912-A89B-F174A79AAFA3', 500, 212, '$td_sw5'),
    ('A32EC139-9C2A-4227-96D9-CEC47BB2AF95', 500, 246, '$td_sw6'),
    ('538D426F-DD6A-4CB0-A2CE-13E7AE9CDA45', 500, 280, '$td_sw7'),
    ('FEFB4286-481F-4A6E-9B20-B670C82B5C32', 500, 314, '$td_sw8'),
    ('9C2277BE-7273-4116-A903-2923D44CB44E', 620,  32, '$td_sw9'),
    ('51C41ACE-60CD-47B0-BCF8-E591976290DC', 620,  66, '$td_m1'),
    ('15BBDD71-2DCB-4E53-B501-751652B27E17', 620, 100, '$td_m2'),
    ('89631407-8B51-40E7-80A0-0C9F424D985F', 620, 134, '$td_m3'),
    ('E0ACDA2D-2C60-4BB0-8534-3C6AA2D32749', 620, 168, '$td_m4'),
    ('ABEB193C-9218-4810-A234-8449A801F8AB', 620, 202, '$td_m5'),
    ('9A44777D-F80B-4BE8-996E-A8D0CA3118E5', 620, 236, '$td_m6'),
    ('178F9AEF-9C6A-469F-AEB9-7E7393C79996', 620, 270, '$td_m7'),
]


def main():
    xml = T.load()
    span5 = T.screen_span(xml, 5)
    assert span5, '画面5不存在'
    _, _, i5, j5 = span5

    fixed = 0
    for guid, el, et, tag in FIX:
        g = xml.find(guid, i5, j5)
        assert g > 0, 'GUID未找到: %s' % guid
        wi = xml.rfind('<widget', i5, g)
        sp = T.find_widget_span(xml, lambda: wi)
        assert sp, 'widget span失败: %s' % guid
        tag_xml, body, selfclose, i, end = sp
        # 坐标防错位断言
        assert T.attr_of(body, 'Left') == str(el), \
            '%s Left=%s 期望%s' % (guid, T.attr_of(body, 'Left'), el)
        assert T.attr_of(body, 'Top') == str(et), \
            '%s Top=%s 期望%s' % (guid, T.attr_of(body, 'Top'), et)
        assert T.attr_of(body, 'StatusCount') == '2', guid
        new_body = T.set_attrs(body, {'WriteAddr': tag, 'Text': ''})
        new_open = '<widget %s%s>' % (new_body, '/' if selfclose else '')
        if selfclose:
            frag_new = new_open
        else:
            inner = xml[i + len(tag_xml):end - len('</widget>')]
            # 清status子元素残留的按钮文字(Text属性, 防误伤TextFontSize等)
            inner = re.sub(r'(\s)Text="[^"]*"', r'\1Text=""', inner)
            frag_new = new_open + inner + '</widget>'
        if frag_new != xml[i:end]:
            xml = xml[:i] + frag_new + xml[end:]
            fixed += 1
        # 画面5段整体后移, 重新定位
        span5 = T.screen_span(xml, 5)
        _, _, i5, j5 = span5

    print('改动开关数: %d / %d' % (fixed, len(FIX)))

    # ---- 验证 ----
    span5 = T.screen_span(xml, 5)
    _, _, i5, j5 = span5
    seg = xml[i5:j5]
    n_sw = n_ok = 0
    for m in T.WIDGET_OPEN.finditer(seg):
        b = m.group(1)
        if not T.attr_of(b, 'StatusCount'):
            continue
        if int(T.attr_of(b, 'Left')) <= 400:
            continue
        n_sw += 1
        wa = T.attr_of(b, 'WriteAddr') or ''
        if wa.startswith('$td_'):
            n_ok += 1
    print('输出区开关: %d, 已绑$td_*: %d' % (n_sw, n_ok))
    assert n_sw == 17 and n_ok == 17, '绑定数量异常'
    assert '进入测试' not in seg, '画面5仍残留进入测试文本'
    assert seg.count('<widget') == seg.count('</widget>') + \
        len(re.findall(r'<widget [^>]*/>', seg)), 'widget配对异常'
    T.save(xml)
    print('已保存, .bak已镜像')


if __name__ == '__main__':
    main()
