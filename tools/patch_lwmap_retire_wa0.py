# -*- coding: utf-8 -*-
"""patch_lwmap_retire_wa0.py — lwmap.lua 退役 lamp_wa0 (M38)。

报警显示并入输入三态灯(2=报警)后, 独立walamp报警灯列与lamp_wa0
显示字(0x179F~0x17AD)不再使用; 标记退役防复用混淆。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PATH = r'F:\Cubemx_Project\Electric_controlled_seeder\HIMproject\Project\lwmap.lua'

OLD = "\r\n".join([
    '    -- 位分解显示字(2026-10-22): 平台"字.位"地址灯实测不可靠, 改由lua把',
    '    -- InputState/WarningState按位分解成0/1写入下列独立字, 位灯绑字地址',
    '    -- (0=灭 1=亮, 与rt_positive同款已验证机制); 对应工程位级标签',
    '    -- td_input0~14/td_warning0~14/td_warning_hi0~6',
    '    lamp_in0    = 0x1790,   -- 输入bit0~14显示字: 零位1~4/自动供种/预留/钢索1~2/',
    '                            --   压力/风机/脚踏板/初始化/北斗/零位5~6, 共15字',
    '    lamp_wa0    = 0x179F,   -- 输入报警bit0~14显示字, 共15字(0x179F~0x17AD)',
    '    lamp_hi0    = 0x17AE,   -- 电机报警bit16~22显示字(步进电机1~4/自动供种/',
    '                            --   步进电机5~6), 共7字(0x17AE~0x17B4)',
])

NEW = "\r\n".join([
    '    -- 三态显示字(2026-10-22 M38): 输入灯三态(2=报警alarm/1=触发enabled/',
    '    -- 0=未触发disabled), 报警位并入lamp_in0按优先级写入, 图=project.xico/5',
    '    -- 三帧(StatusCount=3按值选帧, 画面24路径方式灯同款); 独立walamp报警',
    '    -- 灯列随M38删除',
    '    lamp_in0    = 0x1790,   -- 输入bit0~14三态显示字: 零位1~4/自动供种/预留/',
    '                            --   钢索1~2/压力/风机/脚踏板/初始化/北斗/零位5~6,',
    '                            --   共15字(0x1790~0x179E)',
    '    -- (lamp_wa0 = 0x179F 退役M38: 0x179F~0x17AD共15字空闲, 勿复用)',
    '    lamp_hi0    = 0x17AE,   -- 电机报警bit16~22显示字(步进电机1~4/自动供种/',
    '                            --   步进电机5~6), 共7字(0x17AE~0x17B4)',
])

src = open(PATH, 'rb').read().decode('gb18030')
n = src.count(OLD)
assert n == 1, 'lwmap 目标文本出现%d次(期望1)' % n
open(PATH, 'wb').write(src.replace(OLD, NEW).encode('gb18030'))
print('lwmap.lua lamp_wa0 已退役(0x179F~0x17AD标记空闲)')
