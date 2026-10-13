# -*- coding: utf-8 -*-
"""M4修复2(画面XML): 需VisualHMI编辑器关闭后执行。

1) 画面9[新建任务]功能按钮补执行通知(tm_btn_new=1): 弹窗不触发
   on_screen_change, 页面侧靠通知初始化弹窗数据(地图列表/默认名)。
2) 画面1地图导入页上画布(用户提议, 对齐QT FormMap):
   - $map_detail详情文本挪到左侧中栏(253,84,237x180)
   - 新增动态绘图控件 ID=1 (495,4,294x270) ReadAddr=LW1C79
   - 新增视图下拉 $map_view (495,278,100x26) 排列/编号/密度
执行后自动跑 sync-labels(map_view标签入addrlabels)。
"""
import hmiprj_tool as T
import hmiprj_build as B


def main():
    xml = T.load()

    # ---- 1) 画面9新建任务按钮补通知
    xml = B.patch_widget(
        xml, 9, {'Text': '新建任务'},
        {'NotifyWrite': '1', 'NotifyWriteAddr': '$tm_btn_new',
         'NotifyWriteValue': '1'})

    # ---- 2) 画面1: 详情挪位 + 画布 + 视图下拉
    xml = B.patch_widget(
        xml, 1, {'ReadAddr': '$map_detail'},
        {'Left': '253', 'Top': '84', 'Width': '237', 'Height': '180'})
    canvas = T.build_basic_graph(
        xml, {'Left': '495', 'Top': '4', 'Width': '294', 'Height': '270',
              'ReadAddr': 'LW1C79', 'ID': '1'})
    sel = B.mk(xml, 3, {'ReadAddr': '$pu_antennatype'},
               {'ReadAddr': '$map_view', 'WriteAddr': '$map_view',
                'Text': '排列;编号;密度;', 'ItemCount': '3',
                'ValueMap': '0,1,2', 'Left': '495', 'Top': '278',
                'Width': '100', 'Height': '26'})
    sp = T.screen_span(xml, 1)
    close_i = xml.rfind('</screen>', sp[2], sp[3] + len('</screen>'))
    ins = canvas + sel
    xml = xml[:close_i] + ins + xml[close_i:]

    T.save(xml)
    print('画面9通知已补; 画面1画布/视图下拉已加; .bak已镜像')

    import subprocess
    import sys
    r = subprocess.run([sys.executable, 'hmiprj_tool.py', 'sync-labels'],
                       capture_output=True, text=True)
    print(r.stdout.strip())


if __name__ == '__main__':
    main()
