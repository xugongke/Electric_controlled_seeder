# -*- coding: utf-8 -*-
"""M6画面XML补丁: 画面1重布局(大画布384x396) + 画面25确定按钮改瞬态。

画面1新布局(2026-10-14, 对齐QT FormMap三栏, 状态栏0,430):
  顶行: [地图数][数值][选中行][数值]
  左栏: 列表(4,30,190x326) + 上移/下移(4,362)
  中栏: 详情(200,60,200x170) + 视图下拉 + AB查看/AB清除 + 选中查看/扫描U盘/删除地图
  右栏: 画布(412,30,384x396)
同时修正6个按钮的status文本(历史克隆残留: 连续播种/参数设置等错文案)。

画面25: [确定](FBCLOSE关闭+通知——弹窗上FunctionButton执行通知实测不可达)
  改为瞬态位按钮[创建](写nt_btn_ok, 不关窗, 反馈显示在地图候选行),
  [取消]改文案[关闭](仅ButtonUsage=2关窗)。
"""
import re

import hmiprj_tool as T
import hmiprj_build as B


def set_status0(xml, sid, match, txt):
    """就地改画面sid中匹配控件status ID=0的Text"""
    loc = T.tmpl_loc(xml, sid, **match)
    span = T.find_widget_span(xml, loc)
    tag, body, selfclose, i, end = span
    seg = xml[i:end]
    seg2 = re.sub(r'(<status ID="0"[^>]*?Text=")[^"]*(")',
                  lambda m: m.group(1) + txt + m.group(2), seg, count=1)
    return xml[:i] + seg2 + xml[end:]


def main():
    xml = T.load()

    def mv(sid, match, pos):
        nonlocal xml
        xml = B.patch_widget(xml, sid, match,
                             {'Left': str(pos[0]), 'Top': str(pos[1]),
                              'Width': str(pos[2]), 'Height': str(pos[3])})

    # ---------------- 画面1 重布局
    S = 1
    mv(S, {'Text': '地图数'}, (4, 4, 60, 22))
    mv(S, {'ReadAddr': '$map_count'}, (66, 4, 60, 22))
    mv(S, {'Text': '选中行'}, (130, 4, 60, 22))
    mv(S, {'ReadAddr': '$map_selidx'}, (192, 4, 60, 22))
    mv(S, {'ReadAddr': '$map_list'}, (4, 30, 190, 326))
    mv(S, {'ReadAddr': '$map_detail'}, (200, 60, 200, 170))
    mv(S, {'ReadAddr': '$map_view'}, (200, 34, 100, 26))
    mv(S, {'WriteAddr': '$map_btn_up'}, (4, 362, 60, 30))
    mv(S, {'WriteAddr': '$map_btn_down'}, (68, 362, 60, 30))
    mv(S, {'WriteAddr': '$map_btn_sel'}, (200, 236, 94, 30))
    mv(S, {'WriteAddr': '$map_btn_usb'}, (300, 236, 94, 30))
    mv(S, {'WriteAddr': '$map_btn_del'}, (200, 272, 94, 30))
    mv(S, {'WriteAddr': '$map_ab_clear'}, (300, 272, 94, 30))
    mv(S, {'NotifyWriteAddr': '$abp_req'}, (200, 308, 194, 34))
    mv(S, {'Type': 'WidgetBasicGraph'}, (412, 30, 384, 396))
    # status文本修正(历史克隆残留)
    for match, txt in (({'WriteAddr': '$map_btn_up'}, '上移'),
                       ({'WriteAddr': '$map_btn_down'}, '下移'),
                       ({'WriteAddr': '$map_btn_sel'}, '选中查看'),
                       ({'WriteAddr': '$map_btn_usb'}, '扫描U盘'),
                       ({'WriteAddr': '$map_btn_del'}, '删除地图'),
                       ({'WriteAddr': '$map_ab_clear'}, 'AB清除')):
        xml = set_status0(xml, S, match, txt)

    # ---------------- 画面25: 确定改瞬态[创建], 取消文案[关闭]
    # 删除原FBCLOSE确定按钮, 原位放瞬态按钮
    sp25 = T.screen_span(xml, 25)
    loc = T.tmpl_loc(xml, 25, **{'NotifyWriteAddr': '$nt_btn_ok'})
    span = T.find_widget_span(xml, loc)
    i, end = span[3], span[4]
    btn = B.mk(xml, 9, {'WriteAddr': '$tm_btn_del'},
               {'WriteAddr': '$nt_btn_ok', 'Text': '创建',
                'Left': '120', 'Top': '220', 'Width': '120', 'Height': '44'},
               {0: ('创建', '0;0;0'), 1: ('创建', '0;0;0')})
    xml = xml[:i] + btn + xml[end:]
    xml = set_status0(xml, 25, {'NotifyWriteAddr': '$nt_btn_cancel'}, '关闭')

    T.save(xml)
    print('画面1重布局+按钮文案修正; 画面25确定->瞬态[创建]; .bak已镜像')
    import subprocess
    import sys
    r = subprocess.run([sys.executable, 'hmiprj_tool.py', 'sync-labels'],
                       capture_output=True, text=True)
    print(r.stdout.strip())


if __name__ == '__main__':
    main()
