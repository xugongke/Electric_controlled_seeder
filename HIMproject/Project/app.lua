--[[
app.lua —— 屏端应用框架：页面注册/轮询节流/帧分发/ack提示/按钮路由/诊断码
================================================================================
设计原则(与 protocol.lua 同): 纯逻辑、零平台依赖, 通过依赖注入接线 =>
  lupa 单测可完整驱动(POC/tests/test_app.lua), 屏端由 main.lua 装配。

页面契约(各 page_*.lua 返回 creator 函数, 收 ctx 返回 page 表):
  ctx = { APP, PROTOCOL, CODEC, LW, w16, w32, wstr, r16 }   -- LW 即 lwmap
  page = {
    id        = 画面号(LW.SCREEN.*),
    poll_cmds = { fnc, ... },          -- 仅本页可见时由 APP.tick 周期发送
    addrs     = { 按钮LW地址, ... },   -- 声明关注的按钮地址(用于路由)
    on_enter/on_frame/on_ack/on_update -- 【必须用冒号定义】function page:on_frame(f)
  }
  !! 冒号约定 !! APP 分发统一冒号调用(page:on_frame(f) 隐式传 self),
  页面定义若用点号(function page.on_frame(f)), 首参收到的是 page 表而非帧,
  所有 fnc 匹配静默失败(test_app T3 踩坑实录)。

诊断码(APP.diag 写 LW.A.diag, 沿用 POC 约定):
  0 = 脚本未执行   1 = on_init 已执行, 模块未加载完
  2 = 模块加载成功, 进入正常轮询
  3 = 模块加载失败(详情看 LW.A.log)
  5 = 按钮已触发 on_update   6 = 收到串口数据
--]]

local APP = {}

-- 装配依赖(wire/init 注入): 声明须在所有引用它的函数(含心跳)之前
local ENV, PROTOCOL, CODEC, LW

APP.pages    = {}   -- [screen_id] = page
APP.by_addr  = {}   -- [按钮地址]  = page
APP.cur      = nil  -- 当前页面
APP.stat     = { tx = 0, rx = 0 }
APP.diagv    = 0

-- 命令类 fnc(1字节 ack 应答判定用); 查询类(0x21/0x23/0x26/0x28/0x30/0x32/0x04/0x08/0xA3)不算
local ACK_CMDS = {
    [0x05]=true, [0x09]=true, [0x0A]=true, [0x0B]=true, [0x10]=true,
    [0x0E]=true, [0x0F]=true, [0x11]=true, [0x12]=true, [0x20]=true,
    [0x24]=true, [0x25]=true, [0x27]=true, [0x29]=true, [0x31]=true,
}

--------------------------------------------------------------------
-- 常驻订阅(B档): 作业状态机(0x21)不随页面切换中断
--   APP.sub_always(fnc, handler)  注册: 该 fnc 帧优先路由 handler, 不进页面
--   APP.set_always_poll(fnc|nil)  常驻轮询命令(tick 无论当前页都发送)
--------------------------------------------------------------------
APP.always       = {}     -- [fnc] = handler
APP.always_poll  = nil    -- fnc 或 nil

function APP.sub_always(fnc, handler) APP.always[fnc] = handler end
function APP.set_always_poll(fnc) APP.always_poll = fnc end

--------------------------------------------------------------------
-- 链路心跳(B档, 2026-09-23): 全局0x22探测 + 掉线判定 + 恢复在线补读版本
--   设计(对齐QT"任意页面都在轮询"的观测, 按联调结论裁剪):
--   1) 每个探测周期(约1s)无论当前页面都发 0x22 —— 兼作心跳探针与调试串刷新
--      (0x22 为纯查询, 固件无副作用; 调试串只在状态切换时变化, 1s足够)
--   2) 连续 OFFLINE_AFTER 个周期未收到 0x22 应答 -> 判掉线:
--      LW.A.link=0 + "× 通信中断"提示; 0x21等常驻轮询照发(链路恢复即自动续上)
--   3) 掉线期间维持 0x22 探测; 收到 0x22 应答 -> 恢复在线(LW.A.link=1),
--      并补发一次 0xA3 读版本(覆盖"下位机固件升级后立即取新版本号"场景);
--      平时不轮询 0xA3(仅开机与重连各一次)--------------------------------------------------------------------
-- 页面回调异常防护(2026-09-30): 任何 on_enter/on_frame/on_update/on_tick
-- 抛错只降级为log, 不炸穿系统回调(虚拟屏RW抛错曾中断parastore启动链)
--------------------------------------------------------------------
local function safe_call(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        print("[HMI] " .. name .. " err: " .. tostring(err))
        if ENV then ENV.wstr(LW.A.log, "× " .. name .. "异常") end
    end
    return ok
end


--------------------------------------------------------------------
APP.hb = {
    online = false,   -- 上电视为离线, 首个0x22应答即转在线(并触发一次0xA3)
    ticks = 0,        -- APP.tick 计数(时间基准)
    last_rx = 0,      -- 最近一次0x22应答时的tick
    n = 0,            -- 周期内计数
    period = 5,       -- 探测周期(tick数), init按poll_ms折算为约1s
    offline_after = 3 -- 连续无应答周期数 -> 判掉线(约3s, 容忍偶发丢帧)
}

local function hb_on_debug(f)
    local hb = APP.hb
    hb.last_rx = hb.ticks
    if not hb.online then
        hb.online = true
        ENV.w16(LW.A.link, 1)
        PROTOCOL.send(PROTOCOL.FNC.GET_SOFT_VER)
    end
    -- 调试串显示(2026-09-24): 画面文本控件统一GB2312, 0x22应答本身即GB2312
    -- 字节流, 直通写入 LW.A.log 正确显示中文(原ASCII过滤已删, GB2312转码待办完结)
    ENV.wstr(LW.A.log, f.data)
    if APP.cur and APP.cur.on_frame then safe_call("on_frame", APP.cur.on_frame, APP.cur, f) end   -- 页面显示照旧
end

local function hb_on_ver(f)
    ENV.wstr(LW.A.ver, f.data)              -- 任意页面都更新版本显示
    if APP.cur and APP.cur.on_frame then safe_call("on_frame", APP.cur.on_frame, APP.cur, f) end
end

--------------------------------------------------------------------
-- 装配: main.lua 在 on_init 中调用(依赖全注入后才可 register)
--   env = { w16=, w32=, wstr=, r16=, tx=, poll_ms= }
--------------------------------------------------------------------
function APP.wire(deps)
    PROTOCOL, CODEC, LW = deps.PROTOCOL, deps.CODEC, deps.LW
end

function APP.init(env)
    ENV = env
    PROTOCOL.io.tx  = env.tx            -- 注入发送层
    PROTOCOL.on_frame = APP.feed_frame  -- 注册收帧回调
    -- 心跳装配: 周期按实际 poll_ms 折算约1s; 0x22/0xA3 走常驻路由
    APP.hb.period = math.max(1, math.floor(1000 / (env.poll_ms or 200) + 0.5))
    APP.sub_always(PROTOCOL.FNC.RD_DEBUG_INFO, hb_on_debug)
    APP.sub_always(PROTOCOL.FNC.GET_SOFT_VER, hb_on_ver)
    ENV.w16(LW.A.link, 0)               -- 上电离线, 首个0x22应答转在线
end

function APP.register(page)
    -- 2026-09-29防再犯: id为nil(SCREEN表缺键)时明确报错跳过, 不中断后续页面加载
    -- (曾因lwmap缺USERPARAM键导致pages[nil]抛错, 用户参数页之后所有页面未注册)
    if type(page.id) ~= "number" then
        print("[HMI] page register FAILED: id=nil (lwmap.LW.SCREEN missing key)")
        if ENV then ENV.wstr(LW.A.log, "page id nil: SCREEN表缺键") end
        return nil
    end
    APP.pages[page.id] = page
    if page.addrs then
        -- (2026-10-08防再犯: ipairs遇nil截断会漏注册其后全部地址
        --  -- page_task曾因addrs首项引用已删键致按钮全无反应)
        page.addrset = {}
        for i = 1, #page.addrs do
            local a = page.addrs[i]
            if type(a) == "number" then
                APP.by_addr[a] = page
                page.addrset[a] = true     -- M45: 当前页优先路由用
            end
        end
    end
    return page
end

--------------------------------------------------------------------
-- 诊断码(只升不降, 保留最高级别现场)
--------------------------------------------------------------------
function APP.diag(v)
    if v > APP.diagv then APP.diagv = v end
    if ENV then ENV.w16(LW.A.diag, APP.diagv) end
end

--------------------------------------------------------------------
-- 页面切换(两个入口, 2026-09-29拆分):
--   APP.set_screen(sid)  内部状态更新(系统on_screen_change回调专用):
--                          记录当前页+触发on_enter, 不切物理画面
--   APP.goto_screen(sid) 主动切画面(密码确认等代码发起): 调用大彩系统API
--                          set_screen切物理画面 -> 系统回调on_screen_change
--                          -> 自然走set_screen完成状态同步, 不会双触发
--------------------------------------------------------------------
function APP.set_screen(sid)
    local prev = APP.cur
    APP.cur = APP.pages[sid]
    -- 离页契约(2026-10-22补): 此前从不调用on_leave, 页面离页动作(如测试页
    -- 自动退出测试模式0x0F)无从触发(用户实测); 仅切到不同页面时触发
    if prev and prev ~= APP.cur and prev.on_leave then
        safe_call("on_leave", prev.on_leave, prev)
    end
    if APP.cur and APP.cur.on_enter then safe_call("on_enter", APP.cur.on_enter, APP.cur) end
end

function APP.goto_screen(sid)
    if type(set_screen) == "function" then
        set_screen(sid)          -- 大彩系统API: 物理切画面, 回调走on_screen_change
    else
        print("[HMI] set_screen API unavailable, fallback internal")
        APP.set_screen(sid)      -- PC测试环境兜底(无系统API)
    end
end


--------------------------------------------------------------------
-- 周期心跳(on_run 调用): 心跳计数 + 仅对可见页发 poll_cmds(轮询节流)
--------------------------------------------------------------------
function APP.tick()
    APP.stat.tx = APP.stat.tx + 1
    ENV.w16(LW.A.tx_cnt, APP.stat.tx)
    -- 心跳: 周期到 -> 先做掉线判定再发探测(掉线期间探测继续)
    local hb = APP.hb
    hb.ticks = hb.ticks + 1
    hb.n = hb.n + 1
    if hb.n >= hb.period then
        hb.n = 0
        if hb.online and (hb.ticks - hb.last_rx) >= hb.period * hb.offline_after then
            hb.online = false
            ENV.w16(LW.A.link, 0)
            ENV.wstr(LW.A.log, "× 通信中断")
        end
        PROTOCOL.send(PROTOCOL.FNC.RD_DEBUG_INFO)
    end
    if APP.always_poll then PROTOCOL.send(APP.always_poll) end
    if APP.cur and APP.cur.poll_cmds then
        for _, fnc in ipairs(APP.cur.poll_cmds) do
            if fnc ~= APP.always_poll then      -- 避免与常驻轮询重复发帧
                PROTOCOL.send(fnc)
            end
        end
    end
    -- 页面 tick 钩子(B档): 0x21 被常驻订阅截获后, 页面级轻刷新走这里
    if APP.cur and APP.cur.on_tick then safe_call("on_tick", APP.cur.on_tick, APP.cur) end
end

--------------------------------------------------------------------
-- 帧分发总线(PROTOCOL.on_frame):
--   1) 命令类 1 字节应答 -> 页面 on_ack (ack/tip提示随状态栏收敛已删)
--   2) 其余 -> 当前页 on_frame
--------------------------------------------------------------------
function APP.feed_frame(f)
    APP.stat.rx = APP.stat.rx + 1
    ENV.w16(LW.A.rx_cnt, APP.stat.rx)
    local h = APP.always[f.fnc]                 -- 常驻订阅优先(作业0x21不随页面中断)
    if h then safe_call("always_0x" .. string.format("%02X", f.fnc), h, f) return end
    if #f.data == 1 and ACK_CMDS[f.fnc] then
        local ok = string.byte(f.data, 1)
        if APP.cur and APP.cur.on_ack then APP.cur:on_ack(f.fnc, ok) end
        return
    end
    if APP.cur and APP.cur.on_frame then safe_call("on_frame", APP.cur.on_frame, APP.cur, f) end
end

--------------------------------------------------------------------
-- 按钮事件(on_update 调用, v==1 已由 main.lua 过滤):
--   路由到声明该地址的页面, 处理后复位按钮(允许重复触发)
--   【根因教训】复位只对按钮地址写0, 绝不波及其他 LW(2026-08-28 事故)
--------------------------------------------------------------------
function APP.on_button(addr, v)
    -- M45: 当前页优先——三地图页共用MV导航地址(0x1F80~87), by_addr
    -- "后注册覆盖"致只有最后注册页收得到(另两页按大/小全程无反应的
    -- 根因); cur声明了该地址就派发给cur, 未声明再回落by_addr
    local page = APP.cur
    if not (page and page.addrset and page.addrset[addr]) then
        page = APP.by_addr[addr]
    end
    if not page then return false end
    APP.diag(5)
    -- v默认1(按钮写1); ABP.req等功能通知可携带模式值(2=查看),
    -- 页面on_update按需读r16获取(2026-10-08: 查看AB线曾被v~=1过滤丢弃)
    v = v or 1
    if page.on_update then safe_call("on_update", page.on_update, page, addr, v) end
    -- 复位按钮(写0): 状态开关页(no_reset)跳过——开关单元需保持0/1状态显示;
    -- 页面亦可声明 hold_addrs(自保持开关集合, 如$rt_sow_exceed), 同样跳过
    -- (M57: 注册进addrs的开关此前被本复位打回0, 表现为"按了没反应")
    if not page.no_reset and not (page.hold_addrs and page.hold_addrs[addr]) then
        ENV.w16(addr, 0)
    end
    return true
end

return APP
