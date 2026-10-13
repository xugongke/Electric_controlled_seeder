--[[
page_drawtest.lua —— 画面26 绘图试验页(2026-10-13 M1绘图底座验证)
================================================================================
目的: 虚拟屏/真机验证 WidgetBasicGraph + on_draw + draw_* API 底座:
  ① 重绘模式(PaintMode=0)下 on_draw 全量重画成立性(切图样/切画面恢复)
  ② draw_rect 填充/边框, draw_line 线宽, draw_circle(注意: fill=0实心),
     draw_text(GBK charcode=1)
  ③ RGB565 颜色自算口径
  ④ redraw() 触发时机(on_enter/on_update后生效)
图样0=状态色网格(任务地图色系) 1=线宽/圆/边框 2=文字规格。
布局: 画布控件ID=1 (50,40,700,360) ReadAddr=LW.A.drawtest;
      [切换图样]瞬态按钮 LW.A.drawtest_btn; [主页]返回;
      主页(511,159)临时入口(拆页重构完成后随本页一并撤或留作诊断)。
平台注意: set_pen_color等绘图API仅真机/虚拟屏存在, PC测试环境跳过绘制。
--]]

local function creator(ctx)
    local LW = ctx.LW
    local page = {}
    page.id = LW.SCREEN.DRAWTEST
    page.addrs = { LW.A.drawtest_btn }

    local pattern = 0                    -- 0状态色网格 1线条圆 2文字
    local dirty = true                  -- on_enter里redraw()时机过早无效
                                       -- (切页回来空白, 2026-10-13实测),
                                       -- 改由on_tick首拍补画

    local function rgb565(r, g, b)
        return ((r // 8) << 11) | ((g // 4) << 5) | (b // 8)
    end

    -- 画布原点包装(2026-10-13: draw_*为整画面坐标系, 画布在(50,40))
    local OX, OY = 50, 40
    local function d_rect(x0, y0, x1, y1, f)
        draw_rect(x0 + OX, y0 + OY, x1 + OX, y1 + OY, f)
    end
    local function d_line(x0, y0, x1, y1, w)
        draw_line(x0 + OX, y0 + OY, x1 + OX, y1 + OY, w)
    end
    local function d_circle(x, y, r, f)
        draw_circle(x + OX, y + OY, r, f)
    end
    local function d_text(s, x, y, w, h, f0, size, col, al, cc)
        draw_text(s, x + OX, y + OY, w, h, f0, size, col, al, cc)
    end

    local function draw_pat0()
        local cols = { { 192, 192, 192, "待播" }, { 0, 112, 192, "下发" },
                       { 34, 139, 34, "完成" }, { 237, 108, 36, "中断" },
                       { 64, 64, 64, "不播" }, { 255, 0, 0, "农机" } }
        for r = 0, 2 do
            for c = 0, 5 do
                local e = cols[c + 1]
                local x0, y0 = 20 + c * 110, 20 + r * 110
                set_pen_color(rgb565(e[1], e[2], e[3]))
                d_rect(x0, y0, x0 + 100, y0 + 100, 1)
                d_text(e[4], x0, y0 + 40, 100, 30, 0, 20,
                          rgb565(255, 255, 255), 1, 1)
            end
        end
        set_pen_color(0)
        d_text("图样0 状态色网格 RGB565自算", 20, 350, 420, 24, 0, 16, 0, 0, 1)
    end

    local function draw_pat1()
        for i = 1, 8 do
            set_pen_color(rgb565(255, 0, 0))
            d_line(20, 20 + i * 20, 300, 20 + i * 20, i)
        end
        set_pen_color(rgb565(0, 112, 192))
        d_circle(120, 220, 60, 0)          -- 实心(fill=0)
        set_pen_color(rgb565(34, 139, 34))
        d_circle(300, 220, 60, 3)          -- 空心(线厚3)
        set_pen_color(0)
        d_rect(400, 160, 650, 300, 0)      -- 边框
        d_text("图样1 线宽1-8/实心圆/空心圆/边框", 20, 350, 500, 24, 0, 16,
                  0, 0, 1)
    end

    local function draw_pat2()
        set_pen_color(0)
        d_rect(20, 20, 660, 340, 1)        -- 黑底
        d_text("16号字-左对齐", 30, 30, 300, 20, 0, 16,
                  rgb565(255, 255, 255), 0, 1)
        d_text("24号字-居中", 30, 70, 400, 30, 0, 24,
                  rgb565(255, 255, 0), 1, 1)
        d_text("32号字-右对齐", 30, 120, 500, 40, 0, 32,
                  rgb565(0, 255, 128), 2, 1)
        d_text("排列行程 12.34m 速度 1.5m/s", 30, 200, 400, 30, 0, 24,
                  rgb565(255, 255, 255), 0, 1)
        d_text("排5-2 列3 密度4000 编号17", 30, 250, 400, 30, 0, 24,
                  rgb565(255, 255, 255), 0, 1)
        d_text("图样2 文字规格", 30, 310, 300, 24, 0, 16,
                  rgb565(255, 255, 255), 0, 1)
    end

    local function paint()
        if set_pen_color == nil then return end
        if pattern == 0 then
            draw_pat0()
        elseif pattern == 1 then
            draw_pat1()
        else
            draw_pat2()
        end
    end

    function page:on_drawctrl(cid)
        if cid == 1 then paint() end           -- 画布控件ID=1
    end

    function page:on_enter()
        dirty = true
    end

    function page:on_tick()
        if dirty then
            dirty = false
            if redraw then redraw() end
        end
    end

    function page:on_update(addr, v)
        if addr == LW.A.drawtest_btn then
            pattern = (pattern + 1) % 3
            if redraw then redraw() end
        end
    end

    return page
end

return creator
