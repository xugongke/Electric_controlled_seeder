--[[
parastore.lua -- 参数副本(RW掉电区) + 启动参数链状态机
================================================================================
2026-09-30对齐QT(用户实机观察QT行为后确认):
QT设置页[保存]只写config.ini不下发; 真正下发在每次进入工作模式前:
  测试页[进入测试]  0x27成功 -> 0x25 -> 0x0E   (formtest.cpp:43-49)
  连播页[开始]      0x27成功 -> 0x25 -> 0x11   (formcontinuoussow.cpp:31-38)
  实时任务[开始]    打开时0x27(HJ用地图行距, dialogrealtimetask.cpp:569
                    + common/map.cpp Map::getUserParameter), [开始]只补
                    0x25 -> 0x24/0x0A          (dialogrealtimetask.cpp:227-230)
根本原因: 固件0x27处理(hd3005a1/Src/protocol.c:351)只写RAM变量直接ACK,
掉电即丢; 0x25虽WriteTerPara持久化, 重发保证与屏端设置一致。
链式等ACK: 任一步失败即中止不进入工作模式(preMode语义, 屏端mode串)。

屏端落地:
  参数页[保存] -> 下发0x27/0x25同时写RW副本(协议原值);
  启动链 parastore.begin(mode, override, done):
    user = RW副本(无副本用QT默认) + override(SOW时hj=地图col_gap覆盖)
    ter  = RW副本(无副本用QT默认)
    发0x27 -> ACK(1) -> 发0x25 -> ACK(1) -> done()原启动逻辑
    ACK(0)/超时(10tick=5s) -> 中止并log, 不调done
依赖注入 parastore.init{ APP, PROTOCOL, CODEC, LW, LOGGER, rw16, rw16w }
--]]

local parastore = {}

local APP, PROTOCOL, CODEC, LW, LOGGER
local rw16, rw16w
local LOGW                        -- wstr依赖, 可选

-- QT默认值: 用户参数(formconfig.cpp:187~199) / 厂家参数(:204~221)
local DEF_USER = { DZTime = 1500, HJ = 60, RMP = 36,
                   AntennaType = 0, AntennaDistance = 0 }
local TER_KEYS = { "A", "B", "EncodeNum", "EncoderDir", "HoleNum",
                   "GearRatio", "MicroStepValue", "X1", "BDiroff",
                   "TappTrigOff", "TapperTime", "ZeroPosEn", "GZEn",
                   "PrePercent", "Resv1" }   -- devtype按协议字段名Resv1存
local DEF_TER = { A = 60, B = 90, EncodeNum = 2000, EncoderDir = 0,
                  HoleNum = 9, GearRatio = 5, MicroStepValue = 800,
                  X1 = 150, BDiroff = 0, TappTrigOff = 20, TapperTime = 100,
                  ZeroPosEn = 1, GZEn = 1, PrePercent = 70, Resv1 = 4 }

local CHAIN_TIMEOUT = 10          -- tick数(500ms*10=5s)

local chain = nil                 -- { mode, step, cb, ticks }

local function log(tag, msg)
    if LOGGER then LOGGER.log(tag, msg) end
    if LOGW then LOGW(LW.A.log, msg) end
end

local function rw_ok()
    return rw16 and rw16w and LW and LW.RW and LW.RW.cfg_magic
end

---------------------------------------------------------------- 副本读写
-- 存协议原值; 载荷组装时补齐结构体其余字段
function parastore.save_user(u)
    if not rw_ok() then return false end
    local R = LW.RW
    rw16w(R.pu_dztime, u.DZTime & 0xFFFF)
    rw16w(R.pu_hj, u.HJ & 0xFFFF)
    rw16w(R.pu_rmp, u.RMP & 0xFFFF)
    rw16w(R.pu_rmp + 1, (u.RMP >> 16) & 0xFFFF)
    rw16w(R.pu_antype, u.AntennaType & 0xFFFF)
    rw16w(R.pu_andist, u.AntennaDistance & 0xFFFF)
    rw16w(R.cfg_magic, 0x55A5)
    return true
end

function parastore.save_ter(t)
    if not rw_ok() then return false end
    local R = LW.RW
    for i, k in ipairs(TER_KEYS) do
        rw16w(R.ter + i - 1, t[k] & 0xFFFF)
    end
    rw16w(R.cfg_magic, 0x55A5)
    return true
end

local function s16(v)
    v = v & 0xFFFF
    if v >= 0x8000 then v = v - 0x10000 end
    return v
end

function parastore.load_user()
    if not rw_ok() then return nil end
    local R = LW.RW
    if rw16(R.cfg_magic) ~= 0x55A5 then return nil end
    return {
        DZTime = rw16(R.pu_dztime),
        HJ = s16(rw16(R.pu_hj)),
        RMP = rw16(R.pu_rmp) | (rw16(R.pu_rmp + 1) << 16),
        AntennaType = rw16(R.pu_antype),
        AntennaDistance = s16(rw16(R.pu_andist)),
    }
end

function parastore.load_ter()
    if not rw_ok() then return nil end
    local R = LW.RW
    if rw16(R.cfg_magic) ~= 0x55A5 then return nil end
    local t = {}
    for i, k in ipairs(TER_KEYS) do
        t[k] = rw16(R.ter + i - 1)
    end
    return t
end

function parastore.defaults_user()
    local u = {}
    for k, v in pairs(DEF_USER) do u[k] = v end
    return u
end

local function user_payload(u)
    return { DZTime = u.DZTime, HJ = u.HJ, RMP = u.RMP,
             AntennaType = u.AntennaType, U8Resv = 0,
             AntennaDistance = u.AntennaDistance, CrcCheck = 0 }
end

local function ter_payload(t)
    -- t为部分表(副本15字段), 补齐结构体其余字段
    local full = { Resv0 = 0, Resv1_ = 0, Resv2 = 0, CrcCheck = 0 }
    for k, v in pairs(DEF_TER) do full[k] = v end
    for k, v in pairs(t) do full[k] = v end
    return full
end

---------------------------------------------------------------- 启动链
-- mode: "SOW"|"LXBZ"|"TEST"; over: {hj=..}覆盖字段; done: 链完成回调(原启动)
function parastore.begin(mode, over, done)
    local u = parastore.load_user() or parastore.defaults_user()
    if over then
        for k, v in pairs(over) do u[k] = v end
    end
    local t = parastore.load_ter() or {}
    chain = { mode = mode, step = 1, cb = done, ticks = 0,
              user = u, ter = t }
    log("INF", ("参数链[%s]: 发0x27 HJ=%d"):format(mode, u.HJ or 0))
    PROTOCOL.send(PROTOCOL.FNC.SET_USER_PARA,
                  CODEC.userpara.pack(user_payload(u)))
    return true
end

function parastore.active()
    return chain ~= nil
end

local function chain_abort(msg)
    local m = chain and chain.mode or "?"
    chain = nil
    log("ERR", ("参数链[%s]中止: %s"):format(m, msg))
end

-- 由 APP.sub_always 路由进来的 0x27/0x25 应答(data[0]==1成功)
function parastore.on_frame(f)
    if not chain then return end
    local ok = f.data and #f.data >= 1 and string.byte(f.data, 1) == 1
    if f.fnc == PROTOCOL.FNC.SET_USER_PARA then
        if chain.step ~= 1 then return end
        if not ok then chain_abort("0x27被拒(ACK=0)") return end
        chain.step = 2
        log("INF", ("参数链[%s]: 0x27成功 发0x25"):format(chain.mode))
        PROTOCOL.send(PROTOCOL.FNC.SET_TER_PARA,
                      CODEC.terpara.pack(ter_payload(chain.ter)))
    elseif f.fnc == PROTOCOL.FNC.SET_TER_PARA then
        if chain.step ~= 2 then return end
        if not ok then chain_abort("0x25被拒(ACK=0)") return end
        local cb = chain.cb
        local m = chain.mode
        chain = nil
        log("INF", ("参数链[%s]: 完成"):format(m))
        if cb then cb() end
    end
end

-- on_run周期调用: 链超时保护(掉线/无应答时不会永久卡住按钮)
function parastore.tick()
    if not chain then return end
    chain.ticks = chain.ticks + 1
    if chain.ticks > CHAIN_TIMEOUT then
        chain_abort("超时无应答(5s)")
    end
end

function parastore.set_logger(lg)   -- LOGGER在B档才创建, 装配后补挂
    LOGGER = lg
end

---------------------------------------------------------------- init
function parastore.init(deps)
    APP, PROTOCOL, CODEC = deps.APP, deps.PROTOCOL, deps.CODEC
    LW, LOGGER = deps.LW, deps.LOGGER
    rw16, rw16w = deps.rw16, deps.rw16w
    LOGW = deps.wstr
    if APP and PROTOCOL then
        -- 常驻订阅: 参数应答无论当前页都进链状态机(对齐jobrun 0x21模式)
        APP.sub_always(PROTOCOL.FNC.SET_USER_PARA,
                       function(f) parastore.on_frame(f) end)
        APP.sub_always(PROTOCOL.FNC.SET_TER_PARA,
                       function(f) parastore.on_frame(f) end)
    end
    return parastore
end

return parastore
