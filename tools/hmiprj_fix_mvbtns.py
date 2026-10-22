# -*- coding: utf-8 -*-
"""hmiprj_fix_mvbtns.py — 三地图页加视口导航按钮簇 (M40)。

画面1(地图导入): 画布左下空区(x200..394,y352..424) 2行7钮(无跟随)
画面9(任务管理): 画布上方右侧空条(x580..,y31) 单行7钮(无跟随)
画面24(实时播种): 画布内左下角悬浮(x260..,y326) 2行8钮(含跟随,
  避开右侧缩略条; 悬浮遮挡属地图App常态)
模板=各屏现有文本按钮(纯Text无图), 只改 WriteAddr/Text/矩形。
addrlabels 补 mv_up~mv_follow(LW1F80~0x1F87)。
"""
import os
import re
import sys
import io

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'HIMproject'))
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import hmiprj_tool as T

# 每屏: (模板WriteAddr, [(tag, text, L, T, W, H), ...])
PLANS = [
    (1, '$map_btn_sel', [
        ('mv_up',   '上', 200, 356, 46, 32),
        ('mv_down', '下', 248, 356, 46, 32),
        ('mv_left', '左', 296, 356, 46, 32),
        ('mv_right', '右', 344, 356, 46, 32),
        ('mv_zin',  '大', 200, 392, 46, 32),
        ('mv_zout', '小', 248, 392, 46, 32),
        ('mv_fit',  '适', 296, 392, 46, 32),
    ]),
    (9, '$tm_btn_del', [
        ('mv_up',   '上', 580, 31, 28, 28),
        ('mv_down', '下', 610, 31, 28, 28),
        ('mv_left', '左', 640, 31, 28, 28),
        ('mv_right', '右', 670, 31, 28, 28),
        ('mv_zin',  '大', 700, 31, 28, 28),
        ('mv_zout', '小', 730, 31, 28, 28),
        ('mv_fit',  '适', 760, 31, 28, 28),
    ]),
    (24, '$rt_btn_result', [
        ('mv_up',   '上', 260, 326, 44, 28),
        ('mv_down', '下', 306, 326, 44, 28),
        ('mv_left', '左', 352, 326, 44, 28),
        ('mv_right', '右', 398, 326, 44, 28),
        ('mv_zin',  '大', 260, 357, 44, 28),
        ('mv_zout', '小', 306, 357, 44, 28),
        ('mv_fit',  '适', 352, 357, 44, 28),
        ('mv_follow', '跟', 398, 357, 44, 28),
    ]),
]

ADDRS = [('mv_up', 'LW1F80'), ('mv_down', 'LW1F81'), ('mv_left', 'LW1F82'),
         ('mv_right', 'LW1F83'), ('mv_zin', 'LW1F84'), ('mv_zout', 'LW1F85'),
         ('mv_fit', 'LW1F86'), ('mv_follow', 'LW1F87')]


def main():
    xml = T.load()

    # ---- 幂等保护 ----
    assert '$mv_up' not in xml, 'mv按钮已存在'

    for sid, tmpl_wa, btns in PLANS:
        sp = T.screen_span(xml, sid)
        assert sp, '画面%d不存在' % sid
        _, _, i5, j5 = sp
        tmpl = T.tmpl_loc(xml, sid, WriteAddr=tmpl_wa)
        frags = []
        for tag, text, l, t, w, h in btns:
            frag = T.clone_widget(xml, tmpl, {
                'WriteAddr': '$' + tag, 'Text': text,
                'Left': str(l), 'Top': str(t),
                'Width': str(w), 'Height': str(h),
            })
            # status子元素文字一并替换(模板两态文字都换成本钮文字)
            frag = re.sub(r'(<status ID="\d+"[^>]*?Text=")[^"]*(")',
                          lambda m: m.group(1) + text + m.group(2), frag)
            frags.append(frag)
        xml = xml[:j5] + ''.join(frags) + xml[j5:]

    # ---- addrlabels 补 mv_* ----
    anchor_i = xml.find('<label NAME="rt_btn_spply"')
    assert anchor_i > 0, '标签锚点未找到'
    j = xml.find('/>', anchor_i) + 2
    labels = ''.join('\r\n\t\t<label NAME="%s" ADDR="%s" TIP="按钮 %s"/>' %
                     (n, a, tt) for (n, a), tt in zip(
                         ADDRS, ['视口上移半屏', '视口下移半屏', '视口左移半屏',
                                 '视口右移半屏', '放大一档', '缩小一档',
                                 '适配整图', '作业跟随开关(实时播种页)']))
    xml = xml[:j] + labels + xml[j:]

    # ---- 验证 ----
    for sid, _, btns in PLANS:
        sp = T.screen_span(xml, sid)
        _, _, i5, j5 = sp
        seg = xml[i5:j5]
        for tag, _, _, _, _, _ in btns:
            assert ('WriteAddr="$%s"' % tag) in seg, \
                '画面%d缺%s' % (sid, tag)
        assert seg.count('<widget') == seg.count('</widget>') + \
            len(re.findall(r'<widget [^>]*/>', seg)), '画面%d配对异常' % sid
    for n, a in ADDRS:
        assert ('NAME="%s"' % n) in xml, '缺标签%s' % n
    assert xml.count('$mv_follow') == 1, 'mv_follow应恰为按钮1处引用'
    T.save(xml)
    print('三屏视口按钮簇已放置(7+7+8), mv_*标签已入addrlabels, .bak已镜像')


if __name__ == '__main__':
    main()
