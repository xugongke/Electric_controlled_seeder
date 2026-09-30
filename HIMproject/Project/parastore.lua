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

屏端落地(2026-09-30双轨: RW机器快路径 + config.txt人类可读):
  参数页[保存] -> 下发0x27/0x25同时写RW副本(协议原值), 并重写
    3:config.txt(与QT config.ini同格式[Application]/[Device]组+同名键,
    UTF-8, 可导出U盘给QT直接当config.ini用);
  屏启动RW magic无效时从config.txt恢复副本(文件备份自愈);
  参数页进页先用副本预填表单(下位机离线/重启后不显示0), 在线时
    被0x26/0x28应答覆盖;
  启动链 parastore.begin(mode, override, done):
    user = RW副本(无副本用QT默认) + override(SOW时hj=地图col_gap覆盖)
    ter  = RW副本(无副本用QT默认)
    发0x27 -> ACK(1) -> 发0x25 -> ACK(1) -> done()原启动逻辑
    ACK(0)/超时(10tick=5s) -> 中止并log, 不调done
依赖注入 parastore.init{ APP, PROTOCOL, CODEC, LW, LOGGER, rw16, rw16w }
--]]

local parastore = {}

local APP, PROTOCOL, CODEC, LW, LOGGER, FILEIO
local rw16, rw16w
local LOGW                        -- wstr依赖, 可选

local CFG_PATH = "3:config.txt"   -- Flash区配置文件(QT config.ini兼容)
local USB_PATH = "2:config.txt"   -- U盘导出目标
-- 文件用UTF-8对齐QT setIniCodec(utf-8); 平台Lua字符串按字节拼接,
-- 中文固定词硬编码\u转义(Lua 5.3)
local GAP_TXT = { [0] = "\u{5173}", [1] = "\u{5F00}", [2] = "\u{95F4}\u{9694}" }
local DEV_TXT = { [4] = "4\u{884C}\u{673A}", [6] = "6\u{884C}\u{673A}" }
local cfg_write                 -- 前向声明(save_user在定义前调用)
local recovering = false         -- 自愈期间抑制cfg_write(防覆盖恢复源)

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
    cfg_write()                   -- 双轨: 同步刷新config.txt
    return true
end

function parastore.save_ter(t)
    if not rw_ok() then return false end
    local R = LW.RW
    for i, k in ipairs(TER_KEYS) do
        rw16w(R.ter + i - 1, t[k] & 0xFFFF)
    end
    rw16w(R.cfg_magic, 0x55A5)
    cfg_write()                   -- 双轨: 同步刷新config.txt
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

---------------------------------------------------------------- config.txt
-- 与QT config.ini同构: [Application]用户参数 / [Device]厂家参数, 键名与
-- formconfig.cpp:66~91/global.cpp:46~81一致, 数值=协议原值(距离cm/时间ms)。
-- UTF-8编码; GapPoint/DeviceType用中文值(QT同款), 屏端硬编码\u转义字节。
function parastore.set_fileio(fio)     -- FILEIO在B档才创建, 装配后补挂
    FILEIO = fio
end

-- 键序固定, 便于人工diff
local DEV_KEYS = {
    { "DropPortDistance", "A" },     { "SeedDropDistance", "B" },
    { "TransmissionRatio", "EncodeNum" }, { "EncoderDirection", "EncoderDir" },
    { "SowRouletteHole", "HoleNum" }, { "GearRatio", "GearRatio" },
    { "MicroStepValue", "MicroStepValue" }, { "X1", "X1" },
    { "BDiroff", "BDiroff" },        { "TappTrigOff", "TappTrigOff" },
    { "TapperTime", "TapperTime" },  { "PrePercent", "PrePercent" },
}

function cfg_write()
    if recovering then return false end
    if not FILEIO or not FILEIO.write_all then return false end
    local u = parastore.load_user()
    local t = parastore.load_ter()
    if not u or not t then return false end     -- 无副本不生成半截文件
    local gp = 0
    if rw16 and LW.RW then
        gp = rw16(LW.RW.gap_point) or 0
        if gp ~= 1 and gp ~= 2 then gp = 0 end
    end
    local ck = function(v) return v and 2 or 0 end  -- QT checkState: 2勾/0空
    local L = {}
    L[#L+1] = "[Application]"
    L[#L+1] = ("DropSeedTime=%d"):format(u.DZTime)
    L[#L+1] = ("SeedColumnGap=%d"):format(u.HJ)
    L[#L+1] = ("Rpm=%d"):format(u.RMP)
    L[#L+1] = ("NavigationAntenna=%d"):format(u.AntennaType)
    L[#L+1] = ("AntennaDistance=%d"):format(u.AntennaDistance)
    L[#L+1] = "GapPoint=" .. (GAP_TXT[gp] or GAP_TXT[0])
    L[#L+1] = ""
    L[#L+1] = "[Device]"
    for _, kv in ipairs(DEV_KEYS) do
        L[#L+1] = ("%s=%d"):format(kv[1], t[kv[2]] or 0)
    end
    L[#L+1] = ("ZeroSwitch=%d"):format(ck(t.ZeroPosEn ~= 0))
    L[#L+1] = ("ScrapeSeed=%d"):format(ck(t.GZEn ~= 0))
    L[#L+1] = "DeviceType=" .. (DEV_TXT[t.Resv1] or DEV_TXT[4])
    local ok = FILEIO.write_all(CFG_PATH, table.concat(L, "\r\n") .. "\r\n")
    return ok == true, ok
end

-- 文本值反查: "关"=0 "开"=1 "间隔"=2; "4行机"=4 "6行机"=6
local function gap_of(s)
    for k, v in pairs(GAP_TXT) do if v == s then return k end end
    return 0
end
local function dev_of(s)
    for k, v in pairs(DEV_TXT) do if v == s then return k end end
    return 4
end

-- RW magic无效时从config.txt恢复(屏启动调用; 失败静默, 用默认值)
function parastore.recover()
    if not FILEIO or not FILEIO.read_lines then return false end
    if parastore.load_user() then return false end       -- RW已有效
    local lines = FILEIO.read_lines(CFG_PATH)
    if type(lines) ~= "table" or #lines < 5 then return false end
    local function val_of(group, key)      -- string.gmatch禁用, 手扫
        local cur = nil
        for _, ln in ipairs(lines) do
            local g = ln:match("^%[(%w+)%]")
            if g then cur = g end
            local k, v = ln:match("^(%w+)=(.-)%s*$")
            if cur == group and k == key then return v end
        end
    end
    local u, t = {}, {}
    local function n(group, key, lo, hi)
        local v = tonumber(val_of(group, key) or "")
        if not v or v < lo or v > hi then return nil end
        return v
    end
    u.DZTime = n("Application", "DropSeedTime", 0, 65535)
    u.HJ = n("Application", "SeedColumnGap", -32768, 32767)
    u.RMP = n("Application", "Rpm", 0, 0x7FFFFFFF)
    u.AntennaType = n("Application", "NavigationAntenna", 0, 65535)
    u.AntennaDistance = n("Application", "AntennaDistance", -32768, 32767)
    if u.DZTime == nil or u.HJ == nil or u.RMP == nil then return false end
    if u.AntennaType == nil then u.AntennaType = 0 end
    if u.AntennaDistance == nil then u.AntennaDistance = 0 end
    t.A = n("Device", "DropPortDistance", -32768, 32767)
    t.B = n("Device", "SeedDropDistance", -32768, 32767)
    t.EncodeNum = n("Device", "TransmissionRatio", 0, 65535)
    t.EncoderDir = n("Device", "EncoderDirection", 0, 1)
    t.HoleNum = n("Device", "SowRouletteHole", 0, 255)
    t.GearRatio = n("Device", "GearRatio", 0, 65535)
    t.MicroStepValue = n("Device", "MicroStepValue", -32768, 32767)
    t.X1 = n("Device", "X1", -32768, 32767)
    t.BDiroff = n("Device", "BDiroff", -32768, 32767)
    t.TappTrigOff = n("Device", "TappTrigOff", -32768, 32767)
    t.TapperTime = n("Device", "TapperTime", 0, 65535)
    t.PrePercent = n("Device", "PrePercent", 0, 255)
    t.ZeroPosEn = (n("Device", "ZeroSwitch", 0, 2) == 2) and 1 or 0
    t.GZEn = (n("Device", "ScrapeSeed", 0, 2) == 2) and 1 or 0
    t.Resv1 = dev_of(val_of("Device", "DeviceType") or "")
    if t.A == nil or t.EncodeNum == nil then return false end
    for k, v in pairs(DEF_TER) do
        if t[k] == nil then t[k] = v end       -- 缺键兜底默认
    end
    local gp = gap_of(val_of("Application", "GapPoint") or "")
    recovering = true                   -- save_*内部cfg_write不得重写源文件
    local ok1 = parastore.save_user(u)
    local ok2 = ok1 and parastore.save_ter(t) or false
    recovering = false
    if rw16w and LW.RW then rw16w(LW.RW.gap_point, gp) end
    log("INF", ("配置自愈: 从config.txt恢复(HJ=%d Resv1=%d)"):format(u.HJ, t.Resv1))
    return true
end

-- 导出U盘: 3:config.txt -> 2:config.txt (参数页[导出配置]按钮)
function parastore.export_usb()
    if not FILEIO or not FILEIO.read_all or not FILEIO.write_all then
        log("ERR", "导出失败: 文件系统不可用")
        return false
    end
    if not parastore.load_user() then
        log("ERR", "导出失败: 无已保存配置")
        return false
    end
    cfg_write()                                  -- 先刷新文件为最新副本
    local data = FILEIO.read_all(CFG_PATH)
    if not data then
        log("ERR", "导出失败: 读 " .. CFG_PATH)
        return false
    end
    local ok = FILEIO.write_all(USB_PATH, data)
    if ok then log("INF", "配置已导出 " .. USB_PATH)
    else log("ERR", "导出失败: 写 " .. USB_PATH) end
    return ok == true
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
