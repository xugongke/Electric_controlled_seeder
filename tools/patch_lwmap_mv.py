# -*- coding: utf-8 -*-
"""patch_lwmap_mv.py — lwmap.lua 新增 LW.MV 地图视口导航按钮段 (M40)。

三地图画布页(导入/任务管理/实时播种)共用的视口按钮地址:
上/下/左/右(半屏平移)/放大/缩小/适配/跟随。0x1F80起(RT区0x1F65后,
RW区前, 空闲段)。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PATH = r'F:\Cubemx_Project\Electric_controlled_seeder\HIMproject\Project\lwmap.lua'

ANCHOR = '--==================== RW 掉电保持区'

BLOCK = """--==================== 地图视口导航(0x1F80~, M40三地图页共用) ====================
LW.MV = {
    up     = 0x1F80,   -- 按钮 视口上移半屏(地图导入/任务管理/实时播种页)
    down   = 0x1F81,   -- 按钮 视口下移半屏
    left   = 0x1F82,   -- 按钮 视口左移半屏
    right  = 0x1F83,   -- 按钮 视口右移半屏
    zin    = 0x1F84,   -- 按钮 放大一档
    zout   = 0x1F85,   -- 按钮 缩小一档(最小档再缩回落适配)
    fit    = 0x1F86,   -- 按钮 适配整图(回到fit)
    follow = 0x1F87,   -- 按钮 跟随开关(仅实时播种页放置: 自动居中当前作业块,
                       --   手动平移/缩放即退出跟随)
}

"""

src = open(PATH, 'rb').read().decode('gb18030')
assert 'LW.MV' not in src, 'LW.MV 已存在'
i = src.find(ANCHOR)
assert i > 0, 'RW区锚点未找到'
open(PATH, 'wb').write((src[:i] + BLOCK + src[i:]).encode('gb18030'))
print('lwmap.lua 已加 LW.MV(0x1F80~0x1F87)')
