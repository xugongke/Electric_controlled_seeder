# -*- coding: utf-8 -*-
"""M17b: 画面7再平衡(编辑器关闭后执行)。

- hist_detail加宽为636x366(55字符x8px=440px@16号, 14列结果行完整显示)
- TextMaxLen=3072(对齐LW 0x2000~0x2BFF大字符串区)
- hist_list收窄150, 上/下移/刷新按钮随动
"""
import hmiprj_tool as T
import hmiprj_build as B


def main():
    xml = T.load()

    def mv(match, pos, extra=None):
        nonlocal xml
        ov = {'Left': str(pos[0]), 'Top': str(pos[1]),
              'Width': str(pos[2]), 'Height': str(pos[3])}
        if extra:
            ov.update(extra)
        xml = B.patch_widget(xml, 7, match, ov)

    mv({'ReadAddr': '$hist_detail'}, (160, 40, 636, 366),
       {'TextMaxLen': '3072', 'TextFontSize': '16'})
    mv({'ReadAddr': '$hist_list'}, (4, 40, 150, 330))
    mv({'WriteAddr': '$hist_btn_up'}, (4, 376, 70, 30))
    mv({'WriteAddr': '$hist_btn_down'}, (78, 376, 70, 30))
    mv({'WriteAddr': '$hist_btn_view'}, (160, 376, 80, 30))
    mv({'Text': '任务列表'}, (4, 12, 92, 26))
    mv({'Text': '结果表'}, (160, 12, 120, 26))

    T.save(xml)
    print('画面7再平衡完成(detail 636x366/MaxLen3072/16号, list 150)')


if __name__ == '__main__':
    main()
