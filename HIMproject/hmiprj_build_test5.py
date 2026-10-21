# -*- coding: utf-8 -*-
"""hmiprj_build_test5.py — 测试诊断页(画面5)构建: 对齐QT formtest双栏(2026-10-21/22)。
左栏 输入状态: [状态灯|名称|报警灯]×15(QT顺序: 灯在左), 灯用标签引用$td_input/$td_warning;
中栏 计数(编码器/北斗) + 漏种/漏肥6路表;
右栏 输出控制: 17路图标按钮(无文字)+旁置名称标签(阀无报警, 电机7路配报警灯$td_warning_hi)。
进/出测试按钮不再放置(进出测试模式由进/出页面自动触发, lua保留手动钩子)。
可重复执行(整段重建)。"""
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hmiprj_tool as T

SID = 5


def main():
    xml = T.load()

    s5 = xml.find('ScreenID="%d"' % SID)
    assert s5 > 0
    s5 = xml.rfind('<screen', 0, s5)
    e5 = xml.find('<screen', s5 + 10)
    open_tag = xml[s5:xml.find('>', s5) + 1]

    TM = {'text': {'Text': '编码器'},
          'num': {'ReadAddr': '$td_encodercnt'},
          'lamp': {'ReadAddr': '$td_input0'},
          'btn': {'WriteAddr': '$td_sw0'}}

    def W(kind, **ov):
        return T.clone_widget(xml, T.tmpl_loc(xml, SID, **TM[kind]), ov)

    # 位级绑定用独立位标签(2026-10-22弃用$标签.位, 平台不支持):
    #   td_input0~14 / td_warning0~14 / td_warning_hi0~6, 见工程标签区

    ws = []

    # ---- 左栏 输入状态(QT顺序: 状态灯在左, 名称居中, 报警灯在右) ----
    ws.append(W('text', Text='输入状态', Left='4', Top='2',
                Width='140', Height='26', TextFontSize='20'))
    names = ['零位开关1', '零位开关2', '零位开关3', '零位开关4',
             '自动供种接近开关', '预留输入', '钢索1', '钢索2', '压力',
             '风机', '脚踏板', '一键初始化按钮', '北斗',
             '零位开关5', '零位开关6']
    for i, nm in enumerate(names):
        y = 32 + i * 26
        ws.append(W('lamp', ReadAddr='$td_input%d' % i,
                    Left='8', Top=str(y), Width='20', Height='20'))
        ws.append(W('text', Text=nm, Left='34', Top=str(y + 1),
                    Width='100', Height='22', TextFontSize='14'))
        ws.append(W('lamp', ReadAddr='$td_warning%d' % i,
                    Left='140', Top=str(y), Width='20', Height='20'))

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

    # ---- 右栏 输出控制(QT: 图标按钮+旁置名称标签; 阀无报警, 电机有) ----
    ws.append(W('text', Text='输出控制', Left='490', Top='2',
                Width='140', Height='26', TextFontSize='20'))
    col1 = ['预落种', '倒种', '清种', '刮种', '预留1',
            '预留2', '喇叭', '打点器', '报警灯']           # CtrlNo0~8
    for r, nm in enumerate(col1):
        y = 32 + r * 34
        ws.append(W('btn', WriteAddr='$td_sw%d' % r, Text='', Left='490',
                    Top=str(y), Width='46', Height='30'))
        ws.append(W('text', Text=nm, Left='540', Top=str(y + 5),
                    Width='66', Height='20', TextFontSize='12'))
    col2 = [('运行指示灯', 9, None),
            ('步进电机1', 16, '$td_warning_hi0'),
            ('步进电机2', 17, '$td_warning_hi1'),
            ('步进电机3', 18, '$td_warning_hi2'),
            ('步进电机4', 19, '$td_warning_hi3'),
            ('自动供种', 20, '$td_warning_hi4'),
            ('步进电机5', 21, '$td_warning_hi5'),
            ('步进电机6', 22, '$td_warning_hi6')]
    for r, (nm, no, ala) in enumerate(col2):
        y = 32 + r * 34
        wa = '$td_sw%d' % no if no <= 9 else '$td_m%d' % (no - 15)
        ws.append(W('btn', WriteAddr=wa, Text='', Left='620',
                    Top=str(y), Width='46', Height='30'))
        ws.append(W('text', Text=nm, Left='670', Top=str(y + 5),
                    Width='64', Height='20', TextFontSize='12'))
        if ala:
            ws.append(W('lamp', ReadAddr=ala, Left='740',
                        Top=str(y + 5), Width='16', Height='16'))

    # ---- 重组画面段 ----
    new_seg = open_tag + ''.join(ws) + '</screen>'
    xml = xml[:s5] + new_seg + xml[e5:]

    # ---- 标签区维护: 补td_sw9/td_warning_hi, 刷阀名TIP, 删enter/exit ----
    def insert_label(after_name, newlbl):
        nonlocal xml
        if newlbl.split('"')[1] in xml:
            return
        i = xml.find('<label NAME="%s"' % after_name)
        assert i > 0, after_name
        j = xml.find('/>', i) + 2
        xml = xml[:j] + newlbl + xml[j:]

    insert_label('td_sw8',
                 '<label NAME="td_sw9" ADDR="LW1738" '
                 'TIP="按钮 运行指示灯阀(CtrlNo9)"/>')
    insert_label('td_warning',
                 '<label NAME="td_warning_hi" ADDR="LW171F" '
                 'TIP="u32 报警位图高字(bit16~22: 步进电机1~6/自动供种步进电机)"/>')
    IN_NAMES = ['零位开关1', '零位开关2', '零位开关3', '零位开关4',
                '自动供种接近开关', '预留输入', '钢索1', '钢索2', '压力',
                '风机', '脚踏板', '一键初始化按钮', '北斗',
                '零位开关5', '零位开关6']
    MO_NAMES = ['步进电机1', '步进电机2', '步进电机3', '步进电机4',
                '自动供种步进电机', '步进电机5', '步进电机6']
    for i, nm in enumerate(IN_NAMES):
        insert_label('td_input%d' % i,
                     '<label NAME="td_input%d" ADDR="LW%03X" '
                     'TIP="位灯 输入bit%d %s"/>' % (i, 0x1790 + i, i, nm))
        insert_label('td_warning%d' % i,
                     '<label NAME="td_warning%d" ADDR="LW%03X" '
                     'TIP="位灯 报警bit%d %s"/>' % (i, 0x179F + i, i, nm))
    for i, nm in enumerate(MO_NAMES):
        insert_label('td_warning_hi%d' % i,
                     '<label NAME="td_warning_hi%d" ADDR="LW%03X" '
                     'TIP="位灯 报警bit%d %s"/>' % (i, 0x17AE + i, i, nm))
    for name, tip in (('td_sw4', '按钮 预留1(CtrlNo4)'),
                      ('td_sw5', '按钮 预留2(CtrlNo5)'),
                      ('td_sw6', '按钮 喇叭(CtrlNo6)'),
                      ('td_sw7', '按钮 打点器(CtrlNo7)'),
                      ('td_sw8', '按钮 报警灯(CtrlNo8)')):
        i = xml.find('<label NAME="%s"' % name)
        assert i > 0, name
        j = xml.find('TIP="', i) + len('TIP="')
        k = xml.find('"', j)
        xml = xml[:j] + tip + xml[k:]
    for name in ('td_enter', 'td_exit'):
        i = xml.find('<label NAME="%s"' % name)
        if i > 0:
            j = xml.find('/>', i) + 2
            if xml[j] in chr(13) + chr(10):
                j += 1
            xml = xml[:i] + xml[j:]

    ET.fromstring(xml)
    T.save(xml)

    xml2 = T.load()
    s = xml2.find('ScreenID="%d"' % SID)
    s = xml2.rfind('<screen', 0, s)
    e = xml2.find('<screen', s + 10)
    seg2 = xml2[s:e]
    print('画面5重建: %d控件, 标签引用灯%d/按钮%d, enter/exit残留%d, 良构OK' % (
        len(re.findall(r'<widget ', seg2)),
        len(re.findall(r'ReadAddr="\$td_(input|warning|warning_hi)\.', seg2)),
        len(re.findall(r'WriteAddr="\$td_(sw|m)', seg2)),
        len(re.findall(r'td_enter|td_exit', seg2))))


if __name__ == '__main__':
    main()
