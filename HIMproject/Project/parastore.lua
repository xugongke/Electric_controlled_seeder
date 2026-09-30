--[[
parastore.lua -- 配置文件(3:config.txt) + 启动参数链状态机
================================================================================
2026-09-30按用户指示重构为QT模式单轨:
  QT设置页显示全部读config.ini(formconfig.cpp:66~91), 从不从下位机回显
  (communication.h:68 getUserParameter()只有声明无调用); [保存]只写ini,
  参数真正下发在每次进入工作模式前(0x27成功->0x25->动作, 固件0x27纯RAM
  不持久化 hd3005a1/Src/protocol.c:351)。
屏端对齐:
  参数页表单从config.txt读; [保存]只写文件(启动链统一下发);
  config.txt与QT QSettings(IniFormat+utf8 codec)字节级兼容:
    - 中文值\xXXXX转义(GapPoint=\x5f00"开"), 文件全ASCII
    - 开关ZeroSwitch/ScrapeSeed=1/0(实际config.ini同)
    - [ContinuousSowMode]Density 连播密度持久化
    - [Application]SerialPort/Alpha/SeedGapFineTuning等QT本地键不写
      (QT读缺省自愈); [TestWarning]告警屏蔽屏端无UI不写
  U盘导出: pu_cfgexp按钮 -> 2:config.txt (QT改名config.ini即可用)
依赖注入 parastore.init{ APP, PROTOCOL, CODEC, LW, LOGGER, wstr }
      FILEIO经set_fileio后补挂(B档装配后)
--]]

local parastore = {}

local APP, PROTOCOL, CODEC, LW, LOGGER, FILEIO
local LOGW

local CFG_PATH = "3:config.txt"   -- Flash区配置文件(QT config.ini兼容)
local USB_PATH = "2:config.txt"   -- U盘导出目标

-- 中文值直接写UTF-8字节(file_write字节直写, QT QSettings的utf8 codec
-- 读原始字节正常还原); 读时兼容QT写的\xXXXX转义文本
local GAP_UTF = { [0] = "\u{5173}", [1] = "\u{5F00}", [2] = "\u{95F4}\u{9694}" }
local DEV_UTF = { [4] = "4\u{884C}\u{673A}", [6] = "6\u{884C}\u{673A}" }
local GAP_ESC = { [0] = [[\x5173]], [1] = [[\x5f00]], [2] = [[\x95f4\x9694]] }
local DEV_ESC = { [4] = [[4\x884c\x673a]], [6] = [[6\x884c\x673a]] }

-- QT默认值(formconfig.cpp:187~199/204~221)
local DEF_USER = { DZTime = 1500, HJ = 60, RMP = 36,
                   AntennaType = 0, AntennaDistance = 0 }
local DEF_TER = { A = 60, B = 90, EncodeNum = 2000, EncoderDir = 0,
                  HoleNum = 9, GearRatio = 5, MicroStepValue = 800,
                  X1 = 150, BDiroff = 0, TappTrigOff = 20, TapperTime = 100,
                  ZeroPosEn = 1, GZEn = 1, PrePercent = 70, Resv1 = 4 }

local CHAIN_TIMEOUT = 10          -- tick数(500ms*10=5s)
local chain = nil                 -- { mode, step, cb, ticks}

local function log(tag, msg)
    if LOGGER then LOGGER.log(tag, msg) end
    if LOGW then LOGW(LW.A.log, msg) end
end

---------------------------------------------------------------- 文件层
local function read_lines()
    if not FILEIO or not FILEIO.read_lines then return nil end
    local ls = FILEIO.read_lines(CFG_PATH)
    if type(ls) ~= "table" then return nil end
    return ls
end

-- 首次保存(文件不存在)用骨架创建
local function ensure_lines()
    return read_lines() or { "[Application]", "", "[Device]", "",
                             "[ContinuousSowMode]", "Density=4000" }
end

local function write_lines(ls)
    if not FILEIO or not FILEIO.write_all then return false end
    return FILEIO.write_all(CFG_PATH, table.concat(ls, "\r\n") .. "\r\n") == true
end

-- 组内键值替换(保留其他组与键): 键序由keys给定, kv={键=值串}
local function edit_group(ls, group, kv, keys)
    local gstart = nil
    for i, ln in ipairs(ls) do
        if ln:match("^%[" .. group .. "%]") then gstart = i break end
    end
    if not gstart then
        if #ls > 0 and ls[#ls] ~= "" then ls[#ls + 1] = "" end
        ls[#ls + 1] = "[" .. group .. "]"
        gstart = #ls
    end
    local gend = #ls + 1
    for i = gstart + 1, #ls do
        if ls[i]:find("[", 1, true) then gend = i break end
    end
    for _, key in ipairs(keys) do
        local val = kv[key]
        if val ~= nil then
            local hit = nil
            for i = gstart + 1, gend - 1 do
                if ls[i]:match("^" .. key .. "=") then hit = i break end
            end
            if hit then
                ls[hit] = key .. "=" .. val
            else
                table.insert(ls, gend, key .. "=" .. val)
                gend = gend + 1
            end
        end
    end
end

-- 取组内键值(手扫, gmatch禁用)
local function val_of(ls, group, key)
    local cur = nil
    for _, ln in ipairs(ls) do
        local g = ln:match("^%[(%w+)%]")
        if g then cur = g end
        local k, v = ln:match("^(%w+)=(.-)%s*$")
        if cur == group and k == key then return v end
    end
end

local function unesc2(utf, esc, s)
    if s == nil then return nil end
    for k, v in pairs(utf) do if v == s then return k end end
    for k, v in pairs(esc) do if v == s then return k end end
    return nil
end

---------------------------------------------------------------- 读写API
-- -> 协议原值表; 文件缺失/缺键用QT默认补全(参数页预填与启动链兜底)
function parastore.load_user()
    local ls = read_lines()
    if not ls then return nil end             -- 文件系统不可用/无文件
    local u = {}
    local function n(key, lo, hi)
        local v = tonumber(val_of(ls, "Application", key) or "")
        if not v or v < lo or v > hi then return nil end
        return v
    end
    u.DZTime = n("DropSeedTime", 0, 65535)
    u.HJ = n("SeedColumnGap", -32768, 32767)
    u.RMP = n("Rpm", 0, 0x7FFFFFFF)
    u.AntennaType = n("NavigationAntenna", 0, 65535)
    u.AntennaDistance = n("AntennaDistance", -32768, 32767)
    if u.DZTime == nil and u.HJ == nil and u.RMP == nil then return nil end
    for k, v in pairs(DEF_USER) do
        if u[k] == nil then u[k] = v end
    end
    return u
end

function parastore.load_ter()
    local ls = read_lines()
    if not ls then return nil end
    local t = {}
    local function n(key, lo, hi)
        local v = tonumber(val_of(ls, "Device", key) or "")
        if not v or v < lo or v > hi then return nil end
        return v
    end
    t.A = n("DropPortDistance", -32768, 32767)
    t.B = n("SeedDropDistance", -32768, 32767)
    t.EncodeNum = n("TransmissionRatio", 0, 65535)
    t.EncoderDir = n("EncoderDirection", 0, 1)
    t.HoleNum = n("SowRouletteHole", 0, 255)
    t.GearRatio = n("GearRatio", 0, 65535)
    t.MicroStepValue = n("MicroStepValue", -32768, 32767)
    t.X1 = n("X1", -32768, 32767)
    t.BDiroff = n("BDiroff", -32768, 32767)
    t.TappTrigOff = n("TappTrigOff", -32768, 32767)
    t.TapperTime = n("TapperTime", 0, 65535)
    t.ZeroPosEn = (n("ZeroSwitch", 0, 1) or 0) > 0 and 1 or 0
    t.GZEn = (n("ScrapeSeed", 0, 1) or 0) > 0 and 1 or 0
    t.PrePercent = n("PrePercent", 0, 255)
    t.Resv1 = unesc2(DEV_UTF, DEV_ESC, val_of(ls, "Device", "DeviceType")) or 4
    if t.A == nil and t.EncodeNum == nil then return nil end
    for k, v in pairs(DEF_TER) do
        if t[k] == nil then t[k] = v end
    end
    return t
end

function parastore.defaults_user()
    local u = {}
    for k, v in pairs(DEF_USER) do u[k] = v end
    return u
end

-- 过道打点三态(0关/1开/2间隔)
function parastore.load_gap()
    local ls = read_lines()
    if not ls then return 0 end
    return unesc2(GAP_UTF, GAP_ESC, val_of(ls, "Application", "GapPoint")) or 0
end

-- 连播密度([ContinuousSowMode]Density)
function parastore.load_density()
    local ls = read_lines()
    if not ls then return nil end
    return tonumber(val_of(ls, "ContinuousSowMode", "Density") or "")
end

local DEV_WRITE = { "DropPortDistance", "SeedDropDistance",
                    "TransmissionRatio", "EncoderDirection",
                    "SowRouletteHole", "GearRatio", "MicroStepValue",
                    "X1", "BDiroff", "TappTrigOff", "TapperTime",
                    "PrePercent", "ZeroSwitch", "ScrapeSeed", "DeviceType" }

function parastore.save_user(u, gp)
    local ls = ensure_lines()
    if not ls then return false end
    if gp == nil then gp = parastore.load_gap() end
    if gp ~= 1 and gp ~= 2 then gp = 0 end
    edit_group(ls, "Application", {
        DropSeedTime = tostring(u.DZTime),
        SeedColumnGap = tostring(u.HJ),
        Rpm = tostring(u.RMP),
        NavigationAntenna = tostring(u.AntennaType),
        AntennaDistance = tostring(u.AntennaDistance),
        GapPoint = GAP_UTF[gp],
    }, { "DropSeedTime", "SeedColumnGap", "Rpm", "NavigationAntenna",
         "AntennaDistance", "GapPoint" })
    return write_lines(ls)
end

function parastore.save_ter(t)
    local ls = ensure_lines()
    if not ls then return false end
    edit_group(ls, "Device", {
        DropPortDistance = tostring(t.A),
        SeedDropDistance = tostring(t.B),
        TransmissionRatio = tostring(t.EncodeNum),
        EncoderDirection = tostring(t.EncoderDir),
        SowRouletteHole = tostring(t.HoleNum),
        GearRatio = tostring(t.GearRatio),
        MicroStepValue = tostring(t.MicroStepValue),
        X1 = tostring(t.X1),
        BDiroff = tostring(t.BDiroff),
        TappTrigOff = tostring(t.TappTrigOff),
        TapperTime = tostring(t.TapperTime),
        PrePercent = tostring(t.PrePercent),
        ZeroSwitch = (t.ZeroPosEn ~= 0) and "1" or "0",
        ScrapeSeed = (t.GZEn ~= 0) and "1" or "0",
        DeviceType = DEV_UTF[t.Resv1] or DEV_UTF[4],
    }, DEV_WRITE)
    -- MachineColumnCount跟随DeviceType(QT建图默认, 兼容性占位)
    edit_group(ls, "Device",
        { MachineColumnCount = (t.Resv1 == 6) and "6" or "4" },
        { "MachineColumnCount" })
    return write_lines(ls)
end

function parastore.save_density(d)
    local ls = ensure_lines()
    if not ls then return false end
    edit_group(ls, "ContinuousSowMode", { Density = tostring(d) },
               { "Density" })
    return write_lines(ls)
end

---------------------------------------------------------------- 启动链
-- mode: "SOW"|"LXBZ"|"TEST"; over: {HJ=..}覆盖字段; done: 链完成回调(原启动)
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
                  CODEC.userpara.pack({
                      DZTime = u.DZTime, HJ = u.HJ, RMP = u.RMP,
                      AntennaType = u.AntennaType, U8Resv = 0,
                      AntennaDistance = u.AntennaDistance, CrcCheck = 0 }))
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

function parastore.on_frame(f)
    if not chain then return end
    local ok = f.data and #f.data >= 1 and string.byte(f.data, 1) == 1
    if f.fnc == PROTOCOL.FNC.SET_USER_PARA then
        if chain.step ~= 1 then return end
        if not ok then chain_abort("0x27被拒(ACK=0)") return end
        chain.step = 2
        log("INF", ("参数链[%s]: 0x27成功 发0x25"):format(chain.mode))
        local t = chain.ter
        local full = { Resv0 = 0, Resv1_ = 0, Resv2 = 0, CrcCheck = 0 }
        for k, v in pairs(DEF_TER) do full[k] = v end
        for k, v in pairs(t) do full[k] = v end
        PROTOCOL.send(PROTOCOL.FNC.SET_TER_PARA, CODEC.terpara.pack(full))
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

function parastore.tick()
    if not chain then return end
    chain.ticks = chain.ticks + 1
    if chain.ticks > CHAIN_TIMEOUT then
        chain_abort("超时无应答(5s)")
    end
end

-- 导出U盘: 3:config.txt -> 2:config.txt (参数页[导出配置]按钮)
function parastore.export_usb()
    if not FILEIO or not FILEIO.read_all or not FILEIO.write_all then
        log("ERR", "导出失败: 文件系统不可用")
        return false
    end
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

function parastore.set_logger(lg)
    LOGGER = lg
end

function parastore.set_fileio(fio)
    FILEIO = fio
end

function parastore.init(deps)
    APP, PROTOCOL, CODEC = deps.APP, deps.PROTOCOL, deps.CODEC
    LW, LOGGER = deps.LW, deps.LOGGER
    LOGW = deps.wstr
    if APP and PROTOCOL then
        APP.sub_always(PROTOCOL.FNC.SET_USER_PARA,
                       function(f) parastore.on_frame(f) end)
        APP.sub_always(PROTOCOL.FNC.SET_TER_PARA,
                       function(f) parastore.on_frame(f) end)
    end
    return parastore
end

return parastore
