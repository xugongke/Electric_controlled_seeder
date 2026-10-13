# -*- coding: utf-8 -*-
"""hmiprj_build.py —— M3画面生成: 画面9任务管理/画面24实时播种/画面25新建任务。

用法: python hmiprj_build.py          (幂等: 已存在则报错退出)
前置: lwmap.lua 已含 TM/NT/RT 地址; 控件模板克隆自现有工程实例。
附带: 主页[任务向导]改指画面9; 画面6删除(隐藏AB自动弹窗触发按钮迁画面24)。
"""
import hmiprj_tool as T


def set_statuses(frag, statuses):
    """替换widget的status子元素; statuses={id:(text,'r;g;b')}"""
    lines = []
    for i in sorted(statuses):
        txt, col = statuses[i]
        lines.append('<status ID="%d" Label="" Text="%s" TextColor="%s" '
                     'TextAlign="1" TextFlick="0" TextRoll="0" '
                     'TextRollSpeed="10"/>' % (i, txt, col))
    inner = ''.join(lines)
    gt = frag.find('>')
    if frag.rstrip().endswith('/>'):
        return frag.rstrip()[:-2] + '>' + inner + '</widget>'
    return frag[:gt + 1] + inner + '</widget>'


def mk(xml, sid, match, ov=None, statuses=None):
    w = T.clone_widget(xml, T.tmpl_loc(xml, sid, **match), ov or {})
    if statuses is not None:
        w = set_statuses(w, statuses)
    return w


def patch_widget(xml, sid, match, ov):
    """就地改画面sid中匹配控件的属性(不克隆)"""
    span = T.find_widget_span(xml, T.tmpl_loc(xml, sid, **match))
    tag, body, selfclose, i, end = span
    new_tag = '<widget %s%s>' % (T.set_attrs(body, ov),
                                 '/' if selfclose else '')
    return xml[:i] + new_tag + xml[i + len(tag):]


def delete_screen(xml, sid):
    span = T.screen_span(xml, sid)
    if not span:
        raise SystemExit('画面%d不存在' % sid)
    _, _, i, j = span
    end = j + len('</screen>')
    while end < len(xml) and xml[end] in '\r\n':
        end += 1
    return xml[:i] + xml[end:]


def main():
    xml = T.load()
    for sid in (9, 24, 25):
        assert not T.screen_span(xml, sid), '画面%d已存在' % sid

    def Tt(txt, x, y, w, h, size=24):
        return mk(xml, 6, {'Text': '任务状态'},
                  {'Text': txt, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h),
                   'TextFontSize': str(size)})

    def NUMRO(addr, x, y, w, h):
        return mk(xml, 6, {'ReadAddr': '$tw_count'},
                  {'ReadAddr': addr, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h)})

    def NUM32(addr, x, y, w, h):
        return mk(xml, 2, {'ReadAddr': '$a_offlen'},
                  {'ReadAddr': addr, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h)})

    def NUMIN(addr, x, y, w, h):
        return mk(xml, 6, {'ReadAddr': '$tw_start_row'},
                  {'ReadAddr': addr, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h)})

    def TXTRO(addr, x, y, w, h):
        return mk(xml, 6, {'ReadAddr': '$tw_list'},
                  {'ReadAddr': addr, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h)})

    def TXTEDIT(addr, x, y, w, h):
        return mk(xml, 22, {'ReadAddr': '$abp_name'},
                  {'ReadAddr': addr, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h)})

    def BTN(addr, txt, x, y, w, h):
        return mk(xml, 6, {'WriteAddr': '$tw_btn_ok'},
                  {'WriteAddr': addr, 'Text': txt, 'Left': str(x),
                   'Top': str(y), 'Width': str(w), 'Height': str(h)},
                  {0: (txt, '0;0;0')})

    def SW(addr, txt, x, y, w, h, on='开'):
        return mk(xml, 6, {'ReadAddr': '$tw_sow_exceed'},
                  {'ReadAddr': addr, 'WriteAddr': addr, 'Text': txt,
                   'Left': str(x), 'Top': str(y), 'Width': str(w),
                   'Height': str(h)},
                  {0: (txt, '0;0;0'), 1: (on, '0;0;0')})

    def SEL(addr, opts, x, y, w, h):
        return mk(xml, 3, {'ReadAddr': '$pu_antennatype'},
                  {'ReadAddr': addr, 'WriteAddr': addr, 'Text': opts,
                   'ItemCount': str(opts.count(';')), 'ValueMap': '0,1,2',
                   'Left': str(x), 'Top': str(y), 'Width': str(w),
                   'Height': str(h)})

    def FB(dst, txt, x, y, w, h, usage='0'):
        return mk(xml, 6, {'DestScreen': '0'},
                  {'DestScreen': str(dst), 'ButtonUsage': usage, 'Text': txt,
                   'Left': str(x), 'Top': str(y), 'Width': str(w),
                   'Height': str(h)},
                  {0: (txt, '0;0;0')})

    def FBDLG(txt, x, y, w, h, notify, val):
        return mk(xml, 6, {'DestScreen': '22'},
                  {'Text': txt, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h),
                   'NotifyWriteAddr': notify, 'NotifyWriteValue': str(val)},
                  {0: (txt, '0;0;0')})

    def FBCLOSE(txt, x, y, w, h, notify):
        return mk(xml, 22, {'NotifyWriteAddr': '$abp_confirm'},
                  {'Text': txt, 'Left': str(x), 'Top': str(y),
                   'Width': str(w), 'Height': str(h),
                   'NotifyWriteAddr': notify, 'NotifyWriteValue': '1'},
                  {0: (txt, '0;0;0')})

    def GRAPH(x, y, w, h, addr, cid):
        return T.build_basic_graph(xml, {'Left': str(x), 'Top': str(y),
                                         'Width': str(w), 'Height': str(h),
                                         'ReadAddr': addr, 'ID': str(cid)})

    # ---------------- 画面9 任务管理
    s9 = [
        Tt('任务管理', 4, 2, 120, 26),
        Tt('列表', 4, 30, 46, 22), NUMRO('$tm_count', 52, 30, 50, 22),
        NUMRO('$tm_selidx', 106, 30, 50, 22),
        TXTRO('$tm_list', 4, 54, 226, 150),
        FB(25, '新建任务', 4, 210, 72, 34, '1'),
        BTN('$tm_btn_del', '删除', 80, 210, 72, 34),
        BTN('$tm_btn_imp', '导入U盘', 156, 210, 72, 34),
        BTN('$tm_btn_exp', '导出U盘', 4, 250, 72, 34),
        BTN('$tm_btn_reset', '重置', 80, 250, 72, 34),
        BTN('$tm_btn_up', '上移', 156, 250, 72, 34),
        BTN('$tm_btn_down', '下移', 4, 290, 72, 34),
        BTN('$tm_btn_sel', '刷新', 80, 290, 72, 34),
        Tt('任务详情', 236, 30, 100, 22),
        TXTRO('$tm_tname', 236, 54, 234, 24),
        TXTRO('$tm_tmap', 236, 82, 234, 24),
        TXTRO('$tm_tcreate', 236, 110, 234, 24),
        TXTRO('$tm_tlast', 236, 138, 234, 24),
        Tt('完成率%', 236, 166, 64, 26),
        NUMRO('$tm_pct', 302, 166, 80, 26),
        TXTRO('$tm_tremark', 236, 196, 234, 56),
        BTN('$tm_btn_start', '开始任务', 236, 320, 234, 60),
        SEL('$tm_view', '排列;编号;密度;', 474, 30, 100, 26),
        GRAPH(474, 60, 322, 360, 'LW1E95', 1),
        Tt('灰待播 蓝下发 绿完成 红中断 深灰不播 黄框=起点',
           474, 424, 322, 22, 16),
    ]
    # ---------------- 画面25 新建任务(弹窗400x280)
    s25 = [
        Tt('新建任务', 8, 4, 120, 24),
        Tt('任务名', 8, 38, 60, 26),
        TXTEDIT('$nt_name', 72, 38, 220, 30),
        Tt('地图', 8, 76, 60, 26),
        TXTRO('$nt_mapsel', 72, 76, 160, 30),
        NUMRO('$nt_count', 240, 76, 60, 26),
        BTN('$nt_btn_up', '上一个', 8, 114, 84, 30),
        BTN('$nt_btn_down', '下一个', 98, 114, 84, 30),
        FBCLOSE('确定', 120, 220, 120, 44, '$nt_btn_ok'),
        FBCLOSE('取消', 252, 220, 120, 44, '$nt_btn_cancel'),
    ]
    # ---------------- 画面24 实时播种
    s24 = [
        Tt('实时播种', 4, 2, 80, 24),
        TXTRO('$rt_tname', 86, 2, 150, 24),
        Tt('调试', 4, 30, 44, 20, 16),
        TXTRO('$a_log', 50, 30, 198, 40),
        Tt('排列cm', 4, 74, 50, 28, 16),
        NUM32('$a_offlen', 56, 74, 62, 28),
        Tt('列cm', 122, 74, 40, 28, 16),
        NUM32('$a_voff', 164, 74, 62, 28),
        Tt('速度', 4, 106, 44, 28, 16),
        NUMRO('$rt_speed', 50, 106, 62, 28),
        Tt('mm/s', 114, 106, 40, 28, 16),
        SW('$rt_positive', '反', 158, 106, 60, 28, '正'),
        mk(xml, 6, {'ReadAddr': '$tw_path_type'},
           {'ReadAddr': '$rt_path_type', 'Left': '4', 'Top': '138',
            'Width': '88', 'Height': '101'}),
        Tt('路线', 96, 160, 50, 28, 16),
        SEL('$rt_gapdot', '关;开;间隔;', 150, 138, 94, 28),
        SW('$rt_sow_exceed', '图外关', 4, 172, 76, 28, '图外开'),
        FBDLG('AB查看', 84, 172, 78, 30, '$abp_req', 2),
        FBDLG('AB保存', 166, 172, 78, 30, '$abp_req', 1),
        BTN('$rt_btn_abclr', 'AB清除', 4, 206, 78, 30),
        Tt('当前漏种1-6', 4, 240, 244, 18, 16),
    ]
    for k in range(6):
        s24.append(NUMRO('LW1F%02X' % (0x10 + k), 4 + k * 40, 258, 38, 24))
    s24.append(Tt('当前漏肥1-6', 4, 284, 244, 18, 16))
    for k in range(6):
        s24.append(NUMRO('LW1F%02X' % (0x16 + k), 4 + k * 40, 302, 38, 24))
    s24.append(Tt('最近漏种1-6', 4, 328, 244, 18, 16))
    for k in range(6):
        s24.append(NUMRO('LW1F%02X' % (0x1C + k), 4 + k * 40, 346, 38, 24))
    s24.append(Tt('最近漏肥1-6', 4, 372, 244, 18, 16))
    for k in range(6):
        s24.append(NUMRO('LW1F%02X' % (0x22 + k), 4 + k * 40, 390, 38, 24))
    s24 += [
        SEL('$rt_view', '排列;编号;密度;', 252, 2, 96, 26),
        SW('$rt_sp_enable', '改起点', 354, 2, 70, 26, '改起点'),
        NUMIN('$rt_sp_row', 428, 2, 46, 26),
        NUMIN('$rt_sp_col', 478, 2, 46, 26),
        BTN('$rt_btn_spply', '应用', 528, 2, 60, 26),
        FB(9, '返回', 738, 2, 56, 26),
        GRAPH(252, 32, 544, 360, 'LW1F5B', 1),
        Tt('灰待播 蓝下发 绿完成 红中断 深灰不播 绿框=轨迹 红块=农机 黄框=起点',
           252, 396, 544, 20, 16),
        BTN('$rt_btn_start', '开始', 252, 420, 110, 52),
        BTN('$rt_btn_stop', '停止', 368, 420, 110, 52),
        mk(xml, 6, {'ReadAddr': '$tw_sow_exceed'},
           {'ReadAddr': '$a_runstate', 'WriteAddr': '', 'WidgetUsage': '1',
            'StatusCount': '3', 'StatusValueMap': '0,1,129', 'Text': '停止',
            'Left': '484', 'Top': '420', 'Width': '70', 'Height': '52'},
           {0: ('停止', '192;0;0'), 1: ('准备', '224;180;0'),
            2: ('播种', '0;160;0')}),
        Tt('完成%', 560, 414, 60, 24, 16),
        NUMRO('$rt_pct', 560, 438, 60, 30),
        NUMRO('$rt_done', 624, 438, 60, 30),
        Tt('/', 688, 438, 12, 30, 16),
        NUMRO('$rt_tot', 700, 438, 60, 30),
        BTN('$rt_btn_result', '结果', 716, 414, 76, 28),
        BTN('$rt_btn_exp', '导出U盘', 716, 444, 76, 28),
        # 隐藏AB自动弹窗触发按钮(自画面6迁移: stop写auto_req=1条件弹出22)
        mk(xml, 6, {'Left': '834'}, {'Left': '834', 'Top': '6'}),
    ]

    def build_screen(sid, name, w, h, special, widgets):
        s22 = T.screen_span(xml, 22)
        sbody = T.set_attrs(s22[1], {'ScreenID': str(sid), 'Name': name,
                                     'Width': str(w), 'Height': str(h),
                                     'SpecialSize': str(special)})
        return '<screen %s>%s</screen>\r\n\t\t' % (sbody, ''.join(widgets))

    xml = T.insert_screen(xml, build_screen(9, '任务管理', 800, 480, 0, s9), 9)
    xml = T.insert_screen(xml, build_screen(24, '实时播种', 800, 480, 0, s24), 24)
    xml = T.insert_screen(xml, build_screen(25, '新建任务', 400, 280, 1, s25), 25)
    # 主页[任务向导]改指画面9
    xml = patch_widget(xml, 0, {'DestScreen': '6'}, {'DestScreen': '9'})
    # 删除画面6(退役; 隐藏弹窗触发按钮已迁画面24)
    xml = delete_screen(xml, 6)
    T.save(xml)
    print('画面9/24/25已生成; 主页改指画面9; 画面6已删除; .bak已镜像')
    print('画布: 画面9(474,60,322x360) 画面24(252,32,544x360) 控件ID=1')


if __name__ == '__main__':
    main()
