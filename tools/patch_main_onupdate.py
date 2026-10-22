# -*- coding: utf-8 -*-
"""patch_main_onupdate.py — main.lua 平台 on_update 放行 no_reset 页的 v=0 (M37)。

位状态开关(测试页17路输出)点"关"写0, 被平台接线的 `v==0 return` 守卫丢弃,
输出只能开不能关。守卫本意是滤按钮的 app 复位回声(no_reset=false 页才有),
开关页(no_reset=true) app 不复位, v=0 是真实用户关断, 必须透传。
"""
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PATH = r'F:\Cubemx_Project\Electric_controlled_seeder\HIMproject\Project\main.lua'

OLD = ("function on_update(slave, vtype, addr)\r\n"
       "    if vtype ~= VT_LW then return end\r\n"
       "    if not APP then return end\r\n"
       "    local v = r16(addr)\r\n"
       "    if v == 0 then return end              -- 0=复位态不响应\r\n"
       "    APP.on_button(addr, v)                 -- 路由到页面(v随addr传, ABP.req=2查看)\r\n"
       "end")

NEW = ("function on_update(slave, vtype, addr)\r\n"
       "    if vtype ~= VT_LW then return end\r\n"
       "    if not APP then return end\r\n"
       "    local v = r16(addr)\r\n"
       "    if v == 0 and not (APP.cur and APP.cur.no_reset) then\r\n"
       "        return                  -- 0=复位态不响应(按钮的app复位回声);\r\n"
       "                                -- 位状态开关页(no_reset)app不复位, v=0是\r\n"
       "                                -- 用户关断, 必须透传(2026-10-22 M37: 此前\r\n"
       "                                -- 被守卫丢弃, 测试页输出只能开不能关)\r\n"
       "    end\r\n"
       "    APP.on_button(addr, v)                 -- 路由到页面(v随addr传, ABP.req=2查看)\r\n"
       "end")

src = open(PATH, 'rb').read().decode('gb18030')
n = src.count(OLD)
assert n == 1, 'on_update 目标文本出现%d次(期望1), 手工核对' % n
open(PATH, 'wb').write(src.replace(OLD, NEW).encode('gb18030'))
print('main.lua on_update 已放行 no_reset 页 v=0')
