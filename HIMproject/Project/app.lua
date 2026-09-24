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

-- ack 提示用命令名
local CMD_NAME = {
    [0x05]="设置时间", [0x09]="测试控制", [0x0A]="启动小区播种", [0x0B]="停止播种",
    [0x10]="重启设备", [0x0E]="进入测试模式", [0x0F]="退出测试模式",
    [0x11]="启动连续播种", [0x12]="停止连续播种", [0x20]="下发小区参数",
    [0x24]="下发AB线", [0x25]="写厂家参数", [0x27]="写用户参数",
    [0x29]="清零通道", [0x31]="滚动通道",
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
--      平时不轮询 0xA3(仅开机与重连各一次)
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
        ENV.wstr(LW.A.tip, "√ 通信恢复")
        PROTOCOL.send(PROTOCOL.FNC.GET_SOFT_VER)
    end
    -- 调试串显示(2026-09-24): 画面文本控件统一GB2312, 0x22应答本身即GB2312
    -- 字节流, 直通写入 LW.A.log 正确显示中文(原ASCII过滤已删, GB2312转码待办完结)
    ENV.wstr(LW.A.log, f.data)
    if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end   -- 页面显示照旧
end

local function hb_on_ver(f)
    ENV.wstr(LW.A.ver, f.data)              -- 任意页面都更新版本显示
    if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end
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
    APP.pages[page.id] = page
    if page.addrs then
        for _, a in ipairs(page.addrs) do APP.by_addr[a] = page end
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
-- 页面切换(on_screen_change 调用): 记录当前页 + 触发 on_enter
--------------------------------------------------------------------
function APP.set_screen(sid)
    APP.cur = APP.pages[sid]
    if APP.cur and APP.cur.on_enter then APP.cur:on_enter() end
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
            ENV.wstr(LW.A.tip, "× 通信中断")
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
    if APP.cur and APP.cur.on_tick then APP.cur:on_tick() end
end

--------------------------------------------------------------------
-- 帧分发总线(PROTOCOL.on_frame):
--   1) 命令类 1 字节应答 -> 统一 ack 提示(LW.A.ack + LW.A.tip) + on_ack
--   2) 其余 -> 当前页 on_frame
--------------------------------------------------------------------
function APP.feed_frame(f)
    APP.stat.rx = APP.stat.rx + 1
    ENV.w16(LW.A.rx_cnt, APP.stat.rx)
    local h = APP.always[f.fnc]                 -- 常驻订阅优先(作业0x21不随页面中断)
    if h then h(f) return end
    if #f.data == 1 and ACK_CMDS[f.fnc] then
        local ok = string.byte(f.data, 1)
        ENV.w16(LW.A.ack, ok)
        local name = CMD_NAME[f.fnc] or string.format("命令%#x", f.fnc)
        ENV.wstr(LW.A.tip, (ok == 1 and "√ " or "× ") .. name)
        if APP.cur and APP.cur.on_ack then APP.cur:on_ack(f.fnc, ok) end
        return
    end
    if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end
end

--------------------------------------------------------------------
-- 按钮事件(on_update 调用, v==1 已由 main.lua 过滤):
--   路由到声明该地址的页面, 处理后复位按钮(允许重复触发)
--   【根因教训】复位只对按钮地址写0, 绝不波及其他 LW(2026-08-28 事故)
--------------------------------------------------------------------
function APP.on_button(addr)
    local page = APP.by_addr[addr]
    if not page then return false end
    APP.diag(5)
    if page.on_update then page:on_update(addr, 1) end
    ENV.w16(addr, 0)                    -- 复位按钮
    return true
end

return APP
