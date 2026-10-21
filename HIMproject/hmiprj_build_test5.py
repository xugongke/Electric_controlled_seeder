# -*- coding: utf-8 -*-
"""hmiprj_build_test5.py — 测试诊断页(画面5)重设计: 对齐QT formtest双栏。
左栏 输入状态(15项具名输入灯+报警灯) | 中栏 计数+漏种漏肥表 | 右栏 输出控制(17按钮+报警灯)。
删除: 3条位图灯排(96灯)、进/出测试按钮。幂等性不做(重建脚本, 重复跑前先git还原)。
用后即删(画面落定后本脚本归档于git历史)。"""
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hmiprj_tool as T

SID = 5


def attrs(w):
    return dict(re.findall(r'(\w+)="([^"]*)"', w))


def rm_widgets(seg):
    """删除段内全部widget(自闭合与带status子元的成对两种)。"""
    seg = re.sub(r'<widget [^>]*>', lambda m: m.group(0), seg)  # no-op占位
    # 先删成对
    seg = re.sub(r'<widget [^>]*>.*?</widget>', '', seg)
    # 再删自闭合
    seg = re.sub(r'<widget [^>]*/>', '', seg)
    return seg


def main():
    xml = T.load()

    s5 = xml.find('ScreenID="%d"' % SID)
    assert s5 > 0
    s5 = xml.rfind('<screen', 0, s5)
    e5 = xml.find('<screen', s5 + 10)
    open_tag = xml[s5:xml.find('>', s5) + 1]
    seg = xml[s5:e5]

    # ---- 模板(删除前抓取) ----
    for kind, cond in (('text', 'Text=编码器计数'), ('num', '$td_encodercnt'),
                       ('lamp', 'LW171C.0'), ('btn', '$td_enter')):
        assert T.tmpl_loc(xml, SID, **{'Text': '编码器计数'} if kind == 'text'
                          else {'ReadAddr': cond} if kind in ('num', 'lamp')
                          else {'WriteAddr': cond}), '模板缺失:' + cond

    TM = {'text': {'Text': '编码器计数'},
          'num': {'ReadAddr': '$td_encodercnt'},
          'lamp': {'ReadAddr': 'LW171C.0'},
          'btn': {'WriteAddr': '$td_enter'}}

    def W(kind, **ov):
        """按匹配条件定位画面5模板控件, 克隆并覆盖属性(GUID换新)。"""
        return T.clone_widget(xml, T.tmpl_loc(xml, SID, **TM[kind]), ov)

    def HEX(i):
        return '0123456789ABCDEF'[i]

    ws = []

    # ---- 左栏 输入状态 ----
    ws.append(W('text', Text='输入状态', Left='4', Top='2',
                Width='140', Height='26', TextFontSize='20'))
    names = ['零位开关1', '零位开关2', '零位开关3', '零位开关4',
             '自动供种接近开关', '预留输入', '钢索1', '钢索2', '压力',
             '风机', '脚踏板', '一键初始化按钮', '北斗',
             '零位开关5', '零位开关6']
    for i, nm in enumerate(names):
        y = 32 + i * 29
        ws.append(W('text', Text=nm, Left='4', Top=str(y + 3),
                    Width='118', Height='22', TextFontSize='14'))
        ws.append(W('lamp', ReadAddr='LW171C.%s' % HEX(i),
                    Left='128', Top=str(y), Width='22', Height='22'))
        ws.append(W('lamp', ReadAddr='LW171E.%s' % HEX(i),
                    Left='160', Top=str(y), Width='22', Height='22'))

    # ---- 中栏 计数 + 漏种漏肥表 ----
    ws.append(W('text', Text='编码器', Left='310', Top='10',
                Width='60', Height='24', TextFontSize='16'))
    ws.append(W('num', ReadAddr='$td_encodercnt', Left='374', Top='4',
                Width='100', Height='34'))
    ws.append(W('text', Text='北斗', Left='310', Top='52',
                Width='60', Height='24', TextFontSize='16'))
    ws.append(W('num', ReadAddr='$td_bdcnt', Left='374', Top='46',
                Width='100', Height='34'))
    ws.append(W('text', Text='漏种', Left='394', Top='100',
                Width='76', Height='24', TextFontSize='16'))
    ws.append(W('text', Text='漏肥', Left='474', Top='100',
                Width='76', Height='24', TextFontSize='16'))
    for i in range(6):
        y = 130 + i * 34
        ws.append(W('text', Text='第%d行' % (i + 1), Left='318',
                    Top=str(y + 4), Width='70', Height='22',
                    TextFontSize='14'))
        ws.append(W('num', ReadAddr='$td_louzh%d' % (i + 1),
                    Left='394', Top=str(y), Width='76', Height='30'))
        ws.append(W('num', ReadAddr='$td_loufei%d' % (i + 1),
                    Left='474', Top=str(y), Width='76', Height='30'))

    # ---- 右栏 输出控制(17按钮+报警灯) ----
    ws.append(W('text', Text='输出控制', Left='568', Top='2',
                Width='140', Height='26', TextFontSize='20'))
    col1 = [('预落种', '$td_sw0', 'LW171E.0'), ('倒种', '$td_sw1', 'LW171E.1'),
            ('清种', '$td_sw2', 'LW171E.2'), ('刮种', '$td_sw3', 'LW171E.3'),
            ('预留1', '$td_sw4', 'LW171E.4'), ('预留2', '$td_sw5', 'LW171E.5'),
            ('喇叭', '$td_sw6', 'LW171E.6'), ('打点器', '$td_sw7', 'LW171E.7'),
            ('报警灯', '$td_sw8', 'LW171E.8')]
    col2 = [('运行指示灯', '$td_sw9', 'LW171E.9'),
            ('步进电机1', '$td_m1', 'LW171F.0'),
            ('步进电机2', '$td_m2', 'LW171F.1'),
            ('步进电机3', '$td_m3', 'LW171F.2'),
            ('步进电机4', '$td_m4', 'LW171F.3'),
            ('自动供种电机', '$td_m5', 'LW171F.4'),
            ('步进电机5', '$td_m6', 'LW171F.5'),
            ('步进电机6', '$td_m7', 'LW171F.6')]
    for r, (txt, wa, ala) in enumerate(col1):
        y = 32 + r * 34
        ws.append(W('btn', WriteAddr=wa, Text=txt, Left='568',
                    Top=str(y), Width='92', Height='30', TextFontSize='14'))
        ws.append(W('lamp', ReadAddr=ala, Left='664',
                    Top=str(y + 6), Width='18', Height='18'))
    for r, (txt, wa, ala) in enumerate(col2):
        y = 32 + r * 34
        ws.append(W('btn', WriteAddr=wa, Text=txt, Left='682',
                    Top=str(y), Width='92', Height='30', TextFontSize='14'))
        ws.append(W('lamp', ReadAddr=ala, Left='778',
                    Top=str(y + 6), Width='18', Height='18'))

    # ---- 标签区维护: 补td_sw9, 刷阀名TIP, 删enter/exit ----
    lbl = '<label NAME="td_sw9" ADDR="LW1738" TIP="按钮 运行指示灯阀(CtrlNo9)"/>'
    assert 'td_sw9' not in xml, 'td_sw9标签已存在'
    a8 = xml.find('<label NAME="td_sw8"')
    e8 = xml.find('/>', a8) + 2
    xml = xml[:e8] + lbl + xml[e8:]
    for name, tip in (('td_sw4', '按钮 预留1(CtrlNo4)'), ('td_sw5', '按钮 预留2(CtrlNo5)'),
                      ('td_sw6', '按钮 喇叭(CtrlNo6)'), ('td_sw7', '按钮 打点器(CtrlNo7)'),
                      ('td_sw8', '按钮 报警灯(CtrlNo8)')):
        i = xml.find('<label NAME="%s"' % name)
        assert i > 0, name
        j = xml.find('TIP="', i) + len('TIP="')
        k = xml.find('"', j)
        xml = xml[:j] + tip + xml[k:]
    for name in ('td_enter', 'td_exit'):
        i = xml.find('<label NAME="%s"' % name)
        assert i > 0, name
        j = xml.find('/>', i) + 2
        if xml[j] in chr(13) + chr(10):
            j += 1
        xml = xml[:i] + xml[j:]

    # ---- 重组画面段 ----
    new_seg = open_tag + ''.join(ws) + '</screen>'
    xml = xml[:s5] + new_seg + xml[e5:]

    ET.fromstring(xml)                              # 良构校验
    T.save(xml)

    # 复核
    xml2 = T.load()
    s = xml2.find('ScreenID="%d"' % SID)
    s = xml2.rfind('<screen', 0, s)
    e = xml2.find('<screen', s + 10)
    seg2 = xml2[s:e]
    n = len(re.findall(r'<widget ', seg2))
    nb = len(re.findall(r'td_sw9', seg2))
    print('画面5重建: %d控件(旧121), td_sw9引用%d, 良构OK' % (n, nb))


if __name__ == '__main__':
    main()
