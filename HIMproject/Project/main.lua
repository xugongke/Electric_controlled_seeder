_ENCRYPT_=0    --LUA½Å±¾¼ÓÃÜ

--********************************************************************
-- µç¿Ø²¥ÖÖ»ú HMI Ö÷³ÌĞò(²¿Êğ¿Ç) ¡ª¡ª ´ó²Ê VisualHMI, ¶Ô½Ó hd3005a1 / sim_controller.py
--
-- Á´Â·: ĞéÄâÆÁ(´®¿Ú0, 115200) <== ĞéÄâ´®¿Ú¶Ô COM8<->COM9 ==>
--       python sim_controller.py --port COM9 --baud 115200
--
-- ¡¾¼Ü¹¹ 2026-09-02¡¿¶àÎÄ¼şÄ£¿é»¯(dofile ¹Ù·½Ö§³Ö, LUA API ¡ì9.1):
--   POC/lua/ ÎªÎ¨Ò»ÕæÔ´(protocol/codec/lwmap/app/page_*),
--   deploy_screen.py Í¬²½ÎÄ¼şµ½±¾Ä¿Â¼ + ×¢Èë _MODS ÄÚÇ¶¶µµ×Çø¡£
--   load_mod ÓÅÏÈ dofile Íâ²¿ÎÄ¼ş, Ê§°ÜÔò load() ÄÚÇ¶Ô´Âë¡£
--
-- ¡¾Áªµ÷Õï¶Ï¡¿»­ÃæÉÏ·ÅÊıÖµ¿Ø¼ş°ó LW0x1017, °´ÆäÖµ¶¨Î»¹ÊÕÏ»·½Ú:
--   0  = main.lua ÍêÈ«Ã»Ö´ĞĞ(¹¤³ÌÎ´±àÒë¸Ã½Å±¾, ¼ì²éVisualHMIÎÄ¼şÇåµ¥)
--   1  = on_init ÒÑÖ´ĞĞ, µ«Ä£¿é¼ÓÔØÊ§°Ü -> ¿´LW0x1060ÎÄ±¾
--   2  = Ä£¿é¼ÓÔØ³É¹¦, ½øÈëÕı³£ÂÖÑ¯; ´®¿ÚÖúÊÖÓ¦ÖÜÆÚÊÕµ½²éÑ¯Ö¡
--   5  = °´Å¥ÒÑ´¥·¢on_update   6  = ÊÕµ½´®¿ÚÊı¾İ
-- LW0x1018 = ·¢ËÍº¯ÊıÌ½²â: 1=uart_send¿ÉÓÃ 2=uart_send_data¿ÉÓÃ 0=¶¼Ã»ÓĞ(ÑÏÖØ)
--********************************************************************

--Êı¾İÀàĞÍ¶¨Òå
VT_LW = 1    --±äÁ¿µØÖ·
VT_RW = 2    --FLASH´æ´¢

--================ ÔËĞĞÅäÖÃ =================
local UART_CH       = 0      -- Ö÷´®¿Ú£¨ÏÂÎ»»ú½ÓÏß¿Ú£©
local POLL_MS       = 500    -- ×´Ì¬ÂÖÑ¯ÖÜÆÚ ms
local ROWS          = 4      -- ÏÂÎ»»úĞĞÊı: 4=hd3005a1Ô´Âë / 6=Æ½°å°æ; Áªµ÷Ä£ÄâÆ÷Ä¬ÈÏ4
local TX_ONE_BASED  = true   -- ·¢ËÍ×Ö½ÚÊı×éÏÂ±êÔ¼¶¨: true=´Ó1Æğ(´ó²ÊÎÄµµÓÃ·¨)

-- Ä£¿éÇåµ¥(ĞÂÒ³ÃæÔÚ´Ë×·¼Ó, deploy_screen.py Í¬²½É¨ÃèÍ¬ÁĞ±í)
local MODULES = {
    "lwmap.lua", "protocol.lua", "codec.lua", "app.lua",
    "page_params.lua", "page_continuous.lua",
    "page_testdiag.lua",
    -- BµµĞÂÔö: ÎÄ¼şIO/CSV/Êı¾İ²ã/Â·¾¶Ëã·¨/×÷Òµµ÷¶È/ÈÕÖ¾/3ĞÂÒ³Ãæ
    "fileio.lua", "csv.lua", "store.lua", "pathalgo.lua", "logger.lua", "jobrun.lua",
    "page_task.lua", "page_history.lua", "page_logview.lua",
    "page_map.lua",                            -- µØÍ¼µ¼ÈëÒ³(2026-09-24ĞÂÔö, »­Ãæ9)
}

--================ Æ½Ì¨ÊÊÅä²ã =================
local function w16(addr, v)
    if set_uint16 and v then set_uint16(VT_LW, addr, v & 0xFFFF) end
end
local function w32(addr, v)
    if set_int32 and v then set_int32(VT_LW, addr, v) end
end
local function wstr(addr, s)
    if set_string and s then pcall(set_string, VT_LW, addr, s) end
end
local function r16(addr)
    if get_uint16 then return get_uint16(VT_LW, addr) end
end
local function rstr(addr)                        -- ¶Á×Ö·û´®±äÁ¿(AB¶Ô»°¿òÃû³ÆµÈ)
    if get_string then
        local ok, s = pcall(get_string, VT_LW, addr)
        if ok and type(s) == "string" then return s end
    end
    return ""
end
local function r32(addr)
    if get_uint32 then return get_uint32(VT_LW, addr) end
    if get_uint16 then                            -- ½µ¼¶: Æ´Á½¸ö u16(Ğ¡¶Ë)
        local lo = get_uint16(VT_LW, addr) or 0
        local hi = get_uint16(VT_LW, addr + 1) or 0
        return hi * 0x10000 + lo
    end
end

-- RW µôµç±£³ÖÇø¶ÁĞ´(VT_RW=2); ĞéÄâÆÁÖ§³Ö´æÒÉ, ¿ÕÆ¬¶Á»Ø nil
local function rw16(addr)
    if get_uint16 then return get_uint16(VT_RW, addr) end
end
local function rw16w(addr, v)
    if set_uint16 then set_uint16(VT_RW, addr, v & 0xFFFF) end
end

-- string -> Æ½Ì¨×Ö½ÚÊı×é -> ·¢ËÍ£¨¼æÈİ uart_send / uart_send_data Á½ÖÖÆ½Ì¨º¯ÊıÃû£©
local function uart_tx(bytes)
    local fn = type(uart_send) == "function" and uart_send
            or type(uart_send_data) == "function" and uart_send_data
    if not fn then
        w16(0x1018, 0)                     -- ·¢ËÍº¯ÊıÌ½²â(=LW.A.txfn, ¼ÓÔØÇ°Ó²±àÂë)
        print("[HMI] uart_send/uart_send_data ¾ù²»´æÔÚ")
        return
    end
    local t = {}
    if TX_ONE_BASED then
        for i = 1, #bytes do t[i] = string.byte(bytes, i) end
    else
        for i = 1, #bytes do t[i - 1] = string.byte(bytes, i) end
    end
    if fn == uart_send then fn(UART_CH, t)
    else fn(t) end
end

-- Æ½Ì¨ packet Êı×é -> string£¨×Ô¶¯¼æÈİÏÂ±ê´Ó0/´Ó1Á½ÖÖÔ¼¶¨£©
local function packet_to_str(packet)
    if type(packet) ~= "table" then return tostring(packet) end
    local t, i = {}, 0
    while packet[i] ~= nil do             -- 0-based ±éÀú
        t[#t + 1] = string.char(packet[i] & 0xFF)
        i = i + 1
    end
    if #t == 0 then                       -- »ØÍË 1-based
        for j = 1, #packet do t[j] = string.char(packet[j] & 0xFF) end
    end
    return table.concat(t)
end

--================ ÄÚÇ¶Ä£¿éÇø(ÓÉ deploy_screen.py Éú³É, ÎğÊÖ¸Ä) =================
-- BEGIN _MODS (auto-generated, do not edit)
local _MODS = {}

_MODS["lwmap.lua"] = [==[
--[[
lwmap.lua ¡ª¡ª LW/RW ±äÁ¿µØÖ·¹æ»®µ¥Ò»À´Ô´£¨ËùÓĞÒ³ÃæÄ£¿éÒıÓÃ´Ë´¦£¬½ûÖ¹É¢Âä¶¨Òå£©
================================================================================
Ô¼¶¨:
  1. LW µØÖ·Ò»ÂÉÊ®Áù½øÖÆ; ÓÃ»§Çø >= 0x1000, ÏµÍ³Çø (<0x1000) ½ûĞ´
  2. VisualHMI ¿Ø¼şÊôĞÔÀïµÄ±äÁ¿µØÖ·°´Ê®Áù½øÖÆ½âÊÍ(Ìî"1019"=°ó¶¨0x1019),
     ¹Ê³£Á¿±ØĞëÓÃ 0x ×ÖÃæÁ¿, Óë¿Ø¼ş°ó¶¨ÖµÑÏ¸ñÒ»ÖÂ
  3. ¡¾Êµ²â½ûÓÃµØÖ·¡¿0x1000/0x1001(Ò³ÃæºÅÏµÍ³¼Ä´æÆ÷)Óë 0x1016 Ğ´ÈëÎŞĞ§/±»ÏµÍ³¸²¸Ç
  4. i32 ±äÁ¿Õ¼Á½¸ö LW(Ğ¡¶Ë), ¹æ»®Ê±Ô¤ÁôÁ¬ĞøÁ½×Ö
  5. ±¾ÎÄ¼şÊÇ°ó¶¨±íÉú³ÉÆ÷Êı¾İÔ´: ¸ÄµØÖ·±ØĞëÍ¬²½¸Ä VisualHMI ¿Ø¼ş°ó¶¨
  6. ¡¾LW ×îĞ¡µ¥Ôª 16 Î»¡¿Ò»¸ö LW µØÖ· = 2 ×Ö½Ú, ¿Ø¼şÎŞ u8 ÀàĞÍ, ×îĞ¡ UINT16;
     ×¢ÊÍÖĞµÄ "u8" Ö¸ÏÂÎ»»úĞ­Òé×Ö¶Î¿í¶È(1 ×Ö½Ú), LW ²àÒÔ 16 Î»³ĞÔØÈ¡Öµ 0/1,
     ¿Ø¼şÊı¾İÀàĞÍÒ»ÂÉÅä UINT16, lua ¶ÁĞ´Ò»ÂÉ r16/w16

·ÖÇø¹æ»®(ÓÃ»§Çø 0x1000~):
  0x1002~0x102F  È«¾Ö×´Ì¬Çø A_*(¿çÒ³Ãæ¿É¼û: ×´Ì¬/Õï¶Ï/°æ±¾/ÌáÊ¾)
  0x1030~0x10FF  Ô¤Áô(È«¾ÖÀ©Õ¹)
  0x1100~0x11FF  È«¾Ö°´Å¥Çø B_*(Ğ´1´¥·¢, ´úÂë×Ô¶¯¸´Î»)
  0x1200~0x12FF  Ò³Ãæ0 Ö÷Ò³À©Õ¹(×´Ì¬ÏÔÊ¾×ßÈ«¾ÖÇø, ÔİÎ´Õ¼ÓÃ)
  0x1300~0x13FF  Ò³Ãæ1 Ğ¡Çø²ÎÊı LW.CELL
  0x1400~0x14FF  Ò³Ãæ2 Á¬Ğø²¥ÖÖ LW.CONT
  0x1500~0x15FF  Ò³Ãæ3 ABÏß LW.AB
  0x1600~0x16FF  Ò³Ãæ4 ²ÎÊıÒ³ LW.PF / LW.PU
  0x1700~0x17FF  Ò³Ãæ5 ²âÊÔÕï¶Ï LW.TD
  0x1800~0x18FF  Ò³Ãæ6 ÈÎÎñÏòµ¼ LW.TW (BµµĞÂÔö: UÅÌCSVµØÍ¼µ¼Èë+4²½Ïòµ¼)
  0x1900~0x19FF  Ò³Ãæ7 ÀúÊ·¼ÇÂ¼ LW.HIST (BµµĞÂÔö: ·ÖÒ³ÁĞ±í+Ã÷Ï¸+UÅÌµ¼³ö)
  0x1A00~0x1AFF  Ò³Ãæ8 ÈÕÖ¾²é¿´ LW.LOGV (BµµĞÂÔö: ÈÕÖ¾ÁôºÛ²é¿´/µ¼³ö)
  0x1B00~0x1FFF  Ô¤Áô(Ò³ÃæÀ©Õ¹)
--]]

local LW = {}

--==================== »­ÃæºÅ(Óë VisualHMI »­ÃæÅäÖÃÒ»ÖÂ) ====================
LW.SCREEN = {
    HOME       = 0,   -- Ö÷Ò³(×÷Òµ¼àÊÓ+ÆôÍ£)
    -- »­Ãæ1(Ô­Ğ¡Çø²ÎÊı)/»­Ãæ3(Ô­ABÏß¹ÜÀí)ÒÑÉ¾³ı(2026-09-23: Ç°ÕßÎªÔçÆÚÊÖ¶¯
    -- ÏÂ·¢²ÎÊı²âÊÔÒ³; ºóÕß²¢ÈëÈÎÎñÒ³AB²Ù×÷, ¼û LW.TW.ab_*), »­ÃæºÅ²»¸´ÓÃ
    MAP        = 1,   -- µØÍ¼µ¼ÈëÒ³(2026-09-24ĞÂÔö, Ô­»­Ãæ1Ğ¡Çø²ÎÊıÒÑÉ¾, ¸´ÓÃ±àºÅ:
                      --   UÅÌµ¼Èë/ÁĞ±í/É¾³ı/AB°ó¶¨)
    CONTINUOUS = 2,   -- Á¬Ğø²¥ÖÖ
    -- »­Ãæ3¿ÕÏĞ(Ô­ABÏßÒ³ÒÑÉ¾, Áô×÷ºóĞøÀ©Õ¹)
    PARAMS     = 4,   -- ³§¼Ò/ÓÃ»§²ÎÊı
    TESTDIAG   = 5,   -- ²âÊÔÕï¶Ï
    TASK       = 6,   -- ÈÎÎñ×÷ÒµÒ³(2026-09-24ÖØ¹¹: Ñ¡µØÍ¼+²ÎÊı+´´½¨(²»×Ô¶¯¿ªÊ¼)
                      --   +¿ªÊ¼/Í£Ö¹+×÷ÒµÊÓÍ¼; Ô­4²½Ïòµ¼ÒÑÉ¾³ı)
    HISTORY    = 7,   -- ÀúÊ·¼ÇÂ¼(BµµĞÂÔö)
    LOGVIEW    = 8,   -- ÈÕÖ¾²é¿´(BµµĞÂÔö)
    -- »­Ãæ9¿ÕÏĞ(µØÍ¼µ¼ÈëÒ³ÔøÓÃ, 2026-09-24¸Ä·Å»­Ãæ1)
    ABDLG      = 22,  -- ABÏß¶Ô»°¿ò»­Ãæ(½ö×÷¹¦ÄÜ°´Å¥"´ò¿ª¶Ô»°¿ò"µÄµ¯³öÄÚÈİ)
}

--==================== È«¾Ö×´Ì¬Çø(0x1002~0x102F) ====================
-- Óë POC ½×¶Î main.lua Êµ²â¿ÉÓÃµØÖ·±£³ÖÒ»ÖÂ(Îğ¶¯ÒÑÑéÖ¤µØÖ·)
LW.A = {
    speed    = 0x1002, -- i32 ËÙ¶È mm/s       (Õ¼ 0x1002~0x1003) »­ÃæÅä3Î»Ğ¡Êı->m/s(QTÍ¬¿Ú¾¶)
    rownum   = 0x1004, -- u16 µ±Ç°ÅÅºÅ(ÏÔÊ¾ÅÅºÅrows-r,×÷ÒµÖĞÍ¼Íâ±£³Ö×î½üÍ¼ÄÚÖµ)
    offlen   = 0x1005, -- i32 ABĞĞ³ÌÆ«ÒÆcm    (Õ¼ 0x1005~0x1006) »­ÃæÅä2Î»Ğ¡Êı->m(=QTÅÅĞĞ³Ì)
    voff     = 0x1007, -- i32 ´¹Ö±Æ«ÒÆcm      (Õ¼ 0x1007~0x1008) »­ÃæÅä2Î»Ğ¡Êı->m(=QTÁĞĞĞ³Ì)
    -- 0x1009~0x100F Ô­Ö÷Ò³Â©·Ê/Â©ÖêÏÔÊ¾ÇøÒÑÉ¾³ı(2026-09-24: Ö÷Ò³´¿µ¼º½,
    -- ¼ÆÊıÏÔÊ¾Í³Ò»×ß²âÊÔÕï¶ÏÒ³ td_loufei1-6/td_louzh1-6), µØÖ·ÊÍ·Å¿É¸´ÓÃ
    tx_cnt   = 0x1014, -- u16 ·¢Ö¡¼ÆÊı(luaĞÄÌø, on_run»î×Å¾Í»á¶¯)
    rx_cnt   = 0x1015, -- u16 ÊÕÖ¡¼ÆÊı
    link     = 0x1013, -- u16 Á´Â·×´Ì¬ 0=Í¨ĞÅÖĞ¶Ï 1=ÔÚÏß(app.luaĞÄÌøÅĞ¶¨,
                       --   µôÏß=Á¬Ğø3¸ö1sÌ½²âÖÜÆÚÎŞ0x22Ó¦´ğ; »­Ãæ°óÖ¸Ê¾µÆ¿Ø¼ş)
    -- ×¢: LW>=0x1000 µÄ´æ´¢Æ÷µØÖ·¾ù¿ÉÕı³£¶ÁĞ´(ÔçÆÚ"0x1016½ûĞ´"ÎªÎóÅĞ, 2026-09-23¸üÕı)
    diag     = 0x1017, -- u16 Õï¶ÏÂë(¼û app.lua APP.diag)
    txfn     = 0x1018, -- u16 ·¢ËÍº¯ÊıÌ½²â 1=uart_send 2=uart_send_data 0=¶¼Ã»ÓĞ
    runstate = 0x1019, -- u16 ×÷Òµ×´Ì¬ RunState
    bdstate  = 0x101A, -- u16 ±±¶·×´Ì¬ BdState
    ack      = 0x101B, -- u16 ×î½üÃüÁîÓ¦´ğ(1³É¹¦/0Ê§°Ü)
    -- tip/ver Îª×Ö·û´®±äÁ¿, set_string °´´®³¤Ğ´Èë²»ÇåÎ², ±ØĞëÁô×ã¸ôÀëÇø:
    -- "¡Ì ÏÂ·¢Ğ¡Çø²ÎÊı"=15B Ğè 8 ¸ö LW ×Ö(0x101C~0x1023); ¾É¹æ»® tip Ö»ÓĞ
    -- 4 ×Ö, Òç³ö²È ver(0x1020) Ôì³ÉÁ½´®»¥È¾(Ö÷Ò³"¡ÌÏÂ·¢ÈäOC-SIM"ÂÒÂëÊµ´¸)
    tip      = 0x101C, -- ×Ö·û´® ²Ù×÷ÌáÊ¾(ack µ¯´°ÎÄ±¾, Õ¼0x101C~0x1023 ¹²8×Ö)
    ver      = 0x1024, -- ×Ö·û´® ÏÂÎ»»ú°æ±¾ºÅ(0xA3, Õ¼0x1024~0x102B ¹²8×Ö;
                       --   Ô­0x1020ÒÑ·Ï, »­Ãæ0°æ±¾ÎÄ±¾¿Ø¼ş°ó¶¨Ğë¸Ä0x1024)
    log      = 0x1060, -- ×Ö·û´® µ÷ÊÔĞÅÏ¢(0x22)/Ä£¿é¼ÓÔØ´íÎóÏêÇé
    taskinfo = 0x1030, -- ×Ö·û´® Ö÷Ò³ÈÎÎñ½ø¶ÈÎÄ±¾(Bµµ: "ÈÎÎñ1 12/24 50%", Õ¼0x1030~0x104F)
}

-- È«¾Ö°´Å¥Çø LW.B(0x1100~0x1103)ÒÑÉ¾³ı(2026-09-24): Ö÷Ò³¸ÄÎª´¿µ¼º½,
-- ÆôÍ£/°æ±¾/µ÷ÊÔ°´Å¥Ö°ÄÜ·Ö±ğÒÆÖÁÈÎÎñ×÷ÒµÒ³ÓëÈ«¾ÖĞÄÌø(app.lua),
-- 0x1100ÇøµØÖ·¿ÕÏĞ¿É¸´ÓÃ(»­ÃæÌø×ªÓÃ¹¦ÄÜ°´Å¥Ö±Åä, ²»Õ¼LW)¡£

-- 0x1300~0x13FF Ô­Ò³Ãæ1(Ğ¡Çø²ÎÊıÊÖ¶¯ÏÂ·¢²âÊÔÒ³)µØÖ·ÇøËæÒ³ÃæÒ»²¢É¾³ı(2026-09-23)

--==================== Ò³Ãæ2 Á¬Ğø²¥ÖÖ(0x1400~, LXBZParaType 12B) ====================
LW.CONT = {
    density = 0x1400,     -- i32 ÃÜ¶È Density
    celllen = 0x1402,     -- i32 ĞĞ³¤ CellLen
    hju     = 0x1404,     -- i32 ĞĞ¾à Hju(i16Óò, ÏÂ·¢½Ø¶Ï)
    zhushu  = 0x1406,     -- u32 ÖêÊı ZhuShu(u16Óò, ÏÂ·¢½Ø¶Ï)
    start   = 0x1410,     -- °´Å¥ Æô¶¯Á¬Ğø²¥ÖÖ -> 0x11
    stop    = 0x1411,     -- °´Å¥ Í£Ö¹Á¬Ğø²¥ÖÖ -> 0x12
}

--==================== ABÏßÏÔÊ¾Çø(0x1500~, BDParaType 56B) ====================
-- Ô­Ò³Ãæ3(ABÏß¹ÜÀí)ÒÑÉ¾³ı(2026-09-23): ÏÔÊ¾Çø±£Áô, ÓÉÈÎÎñÒ³³ĞÔØ;
-- ²Ù×÷°´Å¥ÔÚ LW.TW.ab_*(²é¿´/µ¼Èë/Çå³ı/±£´æ), ²É¼¯Ó¦´ğ¾­ jobrun È«¾Ö0x23Â·ÓÉ¡£
-- double/float ÆÁ¶ËÎŞÔ­Éú¿Ø¼ş: lua ¶ÁÖµºó string.format Ğ´×Ö·û´®¿Ø¼şÏÔÊ¾
LW.AB = {
    startn      = 0x1500, -- ×Ö·û´® StartN ÆğµãÎ³¶È
    starte      = 0x1502, -- ×Ö·û´® StartE Æğµã¾­¶È
    endbn       = 0x1504, -- ×Ö·û´® EndBN ÖÕµãÎ³¶È
    endbe       = 0x1506, -- ×Ö·û´® EndBE ÖÕµã¾­¶È
    startdir    = 0x1508, -- ×Ö·û´® StartDir ÆğÊ¼·½Ïò½Ç
    calcdir     = 0x150A, -- ×Ö·û´® CalcDir ¼ÆËã·½Ïò½Ç
    startstate  = 0x150C, -- u16 StartState
    calcdirflag = 0x150D, -- u16 CalcDirFlag
    offlen      = 0x150E, -- u16 OffLen Æ«ÒÆÁ¿
    bdofftime   = 0x150F, -- u16 BDOffTime
    -- Ô­ capture/send/save/load °´Å¥ËæÒ³Ãæ3É¾³ı, ²Ù×÷ÒÆÖÁ LW.TW.ab_*
}

--==================== Ò³Ãæ4 ²ÎÊıÒ³(0x1600~, TerParaType 40B + UserParaType 16B) ====================
-- ·¶Î§/Ä¬ÈÏÖµÁĞÓÉ params ÈÎÎñ´Ó hd3005a1/Src/para.c ParaLegalCheck ºË¶Ôºó¹Ì»¯
LW.PF = {                  -- ³§¼Ò²ÎÊı(Ö»¶ÁÕ¹Ê¾+ÊÚÈ¨ºó¿ÉĞ´)
    a           = 0x1600,  -- i16 A
    b           = 0x1601,  -- i16 B
    encodenum   = 0x1602,  -- u16 EncodeNum ±àÂëÆ÷Âö³å
    encoderdir  = 0x1603,  -- u8 ¿ª¹Ø EncoderDir
    holenum     = 0x1604,  -- u8 HoleNum ÅÅÖÖÅÌ¿×Êı
    gearratio   = 0x1605,  -- u16 GearRatio ´«¶¯±È
    microstep   = 0x1606,  -- i16 MicroStepValue Ï¸·Ö
    x1          = 0x1607,  -- i16 X1
    bdiroff     = 0x1608,  -- i16 BDiroff ±±¶·Æ«ÒÆ
    tapptrigoff = 0x1609,  -- i16 TappTrigOff
    tappertime  = 0x160A,  -- u16 TapperTime
    zeroposen   = 0x160B,  -- u8 ¿ª¹Ø ZeroPosEn
    gzen        = 0x160C,  -- u8 ¿ª¹Ø GZEn
    prepercent  = 0x160D,  -- u8 PrePercent Ô¤Ñ¹±È
    read        = 0x1640,  -- °´Å¥ ¶Á³§¼Ò²ÎÊı -> 0x26
    write       = 0x1641,  -- °´Å¥ Ğ´³§¼Ò²ÎÊı -> 0x25 (¶Á±íµ¥+·¶Î§Ğ£Ñé)
    pass        = 0x1650,  -- u32 ÃÜÂëÊäÈë(ÊıÖµÊäÈë, Õ¼2×Ö; Qt¶ËÃÜÂëÍ¬Ô´)
    unlock      = 0x1652,  -- °´Å¥ ½âËø³§¼Ò²ÎÊı(Ğ£ÑéÃÜÂë, Í¨¹ıºó·ÅĞĞĞ´)
                           -- ¡¾Îğ·Å0x1651¡¿passÕ¼0x1650~51, 0x1651ÊÇÆä¸ß×Ö, Ğ´ÃÜÂë»áÎó´¥·¢
}
LW.PU = {                  -- ÓÃ»§²ÎÊı
    dztime       = 0x1620, -- u16 DZTime µãÖÍÊ±¼ä
    hj           = 0x1621, -- i16 HJ
    rmp          = 0x1622, -- u32 RMP (Õ¼2×Ö)
    antennatype  = 0x1624, -- u8 AntennaType ÌìÏßÀàĞÍ
    antennadist  = 0x1625, -- i16 AntennaDistance ÌìÏß¾àÀë
    read         = 0x1642, -- °´Å¥ ¶ÁÓÃ»§²ÎÊı -> 0x28
    write        = 0x1643, -- °´Å¥ Ğ´ÓÃ»§²ÎÊı -> 0x27
}

--==================== Ò³Ãæ5 ²âÊÔÕï¶Ï(0x1700~, TestModeStateType 4ĞĞ52B) ====================
LW.TD = {
    encodercnt = 0x1700,   -- u32 ±àÂëÆ÷¼ÆÊı(Õ¼2×Ö)
    bdcnt      = 0x1702,   -- u32 ±±¶·¼ÆÊı(Õ¼2×Ö)
    -- Â©·Ê/Â©ÖÖ¸÷6Â·(2026-09-24À©Îª¶ÀÁ¢µØÖ·: ¼æÈİ6ĞĞ»ú, ±êÇ©²»¿ÉÏÂ±ê·ÃÎÊ);
    -- loufei1/louzh1 ÎªÊı×é»ùÖ·, ´úÂë°´ +(i-1)*2 ·ÃÎÊu32ÔªËØ
    loufei1    = 0x1704,   -- u32 Â©·Ê¼ÆÊıµÚ1Â· (0x1704~0x1705)
    loufei2    = 0x1706,   -- u32 Â©·Ê¼ÆÊıµÚ2Â·
    loufei3    = 0x1708,   -- u32 Â©·Ê¼ÆÊıµÚ3Â·
    loufei4    = 0x170A,   -- u32 Â©·Ê¼ÆÊıµÚ4Â·
    loufei5    = 0x170C,   -- u32 Â©·Ê¼ÆÊıµÚ5Â·(6ĞĞ»ú)
    loufei6    = 0x170E,   -- u32 Â©·Ê¼ÆÊıµÚ6Â·(6ĞĞ»ú)
    louzh1     = 0x1710,   -- u32 Â©Öê¼ÆÊıµÚ1Â· (0x1710~0x1711)
    louzh2     = 0x1712,   -- u32 Â©Öê¼ÆÊıµÚ2Â·
    louzh3     = 0x1714,   -- u32 Â©Öê¼ÆÊıµÚ3Â·
    louzh4     = 0x1716,   -- u32 Â©Öê¼ÆÊıµÚ4Â·
    louzh5     = 0x1718,   -- u32 Â©Öê¼ÆÊıµÚ5Â·(6ĞĞ»ú)
    louzh6     = 0x171A,   -- u32 Â©Öê¼ÆÊıµÚ6Â·(6ĞĞ»ú)
    -- Î»Í¼Èı¼ş(2026-09-24×Ô0x1714/16/18Ç¨ÖÁ0x171C/1E/20, 6Â·À©Õ¹ÈÃÎ»;
    -- »­Ãæ5µÄÎ»Ö¸Ê¾µÆ°ó¶¨ĞèÍ¬²½¸Ä!)
    input      = 0x171C,   -- u32 IOÊäÈëÎ»Í¼(Î»Ö¸Ê¾µÆ x32)
    warning    = 0x171E,   -- u32 ±¨¾¯Î»Í¼(Î»Ö¸Ê¾µÆ x32)
    ctrl       = 0x1720,   -- u32 Êä³öÎ»Í¼(Î»Ö¸Ê¾µÆ x32)
    -- µ÷ÊÔĞÅÏ¢×Ö·û´®¸´ÓÃÈ«¾Ö LW.A.log(0x1060)
    enter      = 0x1740,   -- °´Å¥ ½øÈë²âÊÔÄ£Ê½ -> 0x0E
    exit       = 0x1741,   -- °´Å¥ ÍË³ö²âÊÔÄ£Ê½ -> 0x0F
    jogno      = 0x1742,   -- u16 µã¶¯Í¨µÀºÅ CtrlNo(ÊıÖµÊäÈë, 0~31 Î»)
    jogon      = 0x1743,   -- u16 µã¶¯ State Ô­ÖµÍ¸´«(ÏÂÎ»»úÖ÷Ñ­»·Ïû·Ñ, ÆÁ¶Ë²»½âÊÍ)
    jogtrig    = 0x1744,   -- °´Å¥ ´¥·¢µã¶¯ -> 0x09 (×é°ü TestCMDType)
    debug      = 0x1745,   -- °´Å¥ ¶Áµ÷ÊÔĞÅÏ¢ -> 0x22
}

--==================== Ò³Ãæ6 ÈÎÎñÏòµ¼(0x1800~0x18FF, BµµĞÂÔö) ====================
-- 4²½×´Ì¬»ú: 1Ñ¡µØÍ¼ 2Ñ¡ABÏß 3Ñ¡Â·¾¶·½Ê½ 4Ñ¡ÆğÊ¼Ğ¡Çø
-- ÁĞ±í½»»¥: ¶àĞĞ×Ö·û´®¿Ø¼ş(Ñ¡ÖĞĞĞÇ°×º">")+ÉÏÏÂÒÆ°´Å¥, ²»ÒÀÀµ´¥ÃşÁĞ±í
-- ×Ö·û´®Õ¼ÓÃËµÃ÷: Õ¼ÓÃ×ÖÊı=¿Ø¼ş"×î´ó×Ö·ûÊı"ÅäÖÃ, GB2312ÏÂ1ºº×Ö=2×Ö½Ú=1LW,
--   ±íÄÚ×¢ÊÍ¿ç¶ÈÎª¹æ»®ÉÏÏŞ, ¿Ø¼şÅäÖÃ²»µÃ³¬¹ı
LW.TW = {
    tstate     = 0x1801, -- u16 ÈÎÎñ×´Ì¬ 0=ÎŞ 1=Ïòµ¼ÖĞ 2=×÷ÒµÖĞ 3=ÒÑÍê³É
    count      = 0x1802, -- u16 µ±Ç°ÁĞ±í¿ÉÑ¡ÏîÊı
    selidx     = 0x1803, -- u16 ÁĞ±íÑ¡ÖĞÏî(0»ù)
    path_type  = 0x1805, -- u16 Â·¾¶·½Ê½0~5(²½Öè3ÊıÖµÊäÈë: 0ËóĞÎ/1Í¬Ïò/2ÖĞ¼ä×ó/3ÓÒËó/4ÓÒÍ¬/5ÖĞ¼äÓÒ)
    positive   = 0x1806, -- u16 ĞĞ½ø·½Ïò 0=ÕıÏò 1=·´Ïò(²½Öè3¿ª¹Ø)
    start_row  = 0x1807, -- u16 ÆğÊ¼Ğ¡ÇøÅÅ(1»ùÏÔÊ¾ºÅ, ²½Öè4ÊıÖµÊäÈë, Ä¬ÈÏ=Ëã·¨Æğµã)
    start_col  = 0x1808, -- u16 ÆğÊ¼Ğ¡ÇøÁĞ(1»ù, ²½Öè4ÊıÖµÊäÈë)
    cur_row    = 0x1809, -- u16 ×÷ÒµÖĞ: µ±Ç°ÅÅ(ÏÔÊ¾ºÅ)
    cur_col    = 0x180A, -- u16 ×÷ÒµÖĞ: µ±Ç°ÁĞ(1»ù)
    done_cnt   = 0x180B, -- u16 ÒÑÍê³ÉĞ¡ÇøÊı
    total_cnt  = 0x180C, -- u16 ×ÜĞ¡ÇøÊı
    pct        = 0x180D, -- u16 Íê³ÉÂÊ%
    sow_exceed = 0x180E, -- u16 Í¼Íâ²¥ÖÖ¿ª¹Ø 0=¹Ø 1=¿ª(¶ÔÆëQT checkBoxSowExceedMap, startNode density()µÄb²ÎÊı)
    mapinfo    = 0x1810, -- ×Ö·û´® µØÍ¼¹æ¸ñÕªÒª(¹æ»®Õ¼0x1810~0x181F, 16×Ö)
    detail     = 0x1820, -- ×Ö·û´® Ñ¡ÖĞÏîÏêÇé(¹æ»®Õ¼0x1820~0x183F, 32×Ö)
    list       = 0x1840, -- ×Ö·û´® ÁĞ±í¶àĞĞÎÄ±¾(¹æ»®Õ¼0x1840~0x187F, 64×Ö¡Ö6ĞĞ)
    btn_up     = 0x1880, -- °´Å¥ Ñ¡ÏîÉÏÒÆ
    btn_down   = 0x1881, -- °´Å¥ Ñ¡ÏîÏÂÒÆ
    btn_sel    = 0x1882, -- °´Å¥ Ñ¡ÖĞ/½øÈëÏÂÒ»²½
    btn_ok     = 0x1884, -- °´Å¥ ´´½¨ÈÎÎñ(²½Öè4)
    btn_cancel = 0x1885, -- °´Å¥ È¡ÏûÏòµ¼
    btn_resume = 0x1886, -- °´Å¥ Ğø½ÓÎ´Íê³ÉÈÎÎñ
    -- ABÏß²Ù×÷(2026-09-23×Ôpage_ablineÇ¨ÒÆ; ÅäÖÃÆÚ×÷ÓÃÓÚËùÑ¡µØÍ¼, ×÷ÒµÆÚ×÷ÓÃÓÚµ±Ç°µØÍ¼;
    -- °ó¶¨ĞÅÏ¢ÏÔÊ¾¸´ÓÃ LW.AB µØÖ·Çø, ²é¿´/±£´æ×ßAB¶Ô»°¿ò»­Ãæ22)
    ab_import  = 0x1889, -- °´Å¥ ABÏßµ¼Èë: RW»º´æ°ó¶¨µ½µØÍ¼(#AB¶ÎÂäÅÌ)
    ab_clear   = 0x188A, -- °´Å¥ ABÏßÇå³ı: ½â³ıµØÍ¼°ó¶¨
    btn_start  = 0x188C, -- °´Å¥ ¿ªÊ¼×÷Òµ(ÈÎÎñ¾ÍĞ÷ºóÆô¶¯; ×÷ÒµÖĞ=ĞøÌËÂã·¢0x0A)
    btn_stop   = 0x188D, -- °´Å¥ Í£Ö¹×÷Òµ(ÊÕÎ²¶Ïµã+ÎŞABÏßÊ±µ¯±£´æ¶Ô»°¿ò)
}

--==================== Ò³Ãæ9 µØÍ¼µ¼Èë(0x1C00~, 2026-09-24ĞÂÔö) ====================
LW.MAP = {
    count      = 0x1C00, -- u16 µØÍ¼Êı
    selidx     = 0x1C01, -- u16 ÁĞ±íÑ¡ÖĞÏî(0»ù)
    list       = 0x1C04, -- ×Ö·û´® ÁĞ±í¶àĞĞÎÄ±¾(Õ¼0x1C04~0x1C43, 64×Ö)
    detail     = 0x1C44, -- ×Ö·û´® Ñ¡ÖĞµØÍ¼ÏêÇé(Õ¼0x1C44~0x1C63, 32×Ö)
    btn_up     = 0x1C70, -- °´Å¥ Ñ¡ÏîÉÏÒÆ
    btn_down   = 0x1C71, -- °´Å¥ Ñ¡ÏîÏÂÒÆ
    btn_sel    = 0x1C72, -- °´Å¥ ²é¿´ÏêÇé
    btn_del    = 0x1C73, -- °´Å¥ É¾³ıµØÍ¼
    btn_usb    = 0x1C74, -- °´Å¥ É¨ÃèUÅÌµ¼Èë
    ab_import  = 0x1C76, -- °´Å¥ ABÏßµ¼Èë(RW»º´æ°ó¶¨±¾Í¼)
    ab_clear   = 0x1C77, -- °´Å¥ ABÏßÇå³ı(½â°ó±¾Í¼)
}

--==================== ABÏß¶Ô»°¿ò½»»¥Çø(0x1D00~, »­Ãæ22³ĞÔØ) ====================
-- µ¯´°ÓÉ»­Ãæ²à¹¦ÄÜ°´Å¥("´ò¿ª¶Ô»°¿ò"Ä¿±ê=»­Ãæ22)´ò¿ª; ¶Ô»°¿òÄÚÈ·ÈÏ°´Å¥Îª
-- "¹Ø±Õ¶Ô»°¿ò"+Ö´ĞĞÍ¨Öª(Ğ´LW=1), ¾­ on_update Â·ÓÉµ½ jobrun ×¢²áµÄAB¶Ô»°¿òÒ³
LW.ABP = {
    mode     = 0x1D00, -- u16 ¶Ô»°¿òÄ£Ê½ 0=±£´æÃüÃû(ĞèÊäÈëÃû³Æ) 1=²é¿´(Ö»¶Á)
    auto_req = 0x1D01, -- u16 Í£Ö¹ºó×Ô¶¯µ¯´°ÇëÇó(Ìõ¼ş´¥·¢¹¦ÄÜ°´Å¥µÄÌõ¼şµØÖ·)
    name     = 0x1D02, -- ×Ö·û´® ABÏßÃû³Æ(±£´æ=ÊäÈë¿ò, ²é¿´=°ó¶¨µÄABÃû; Õ¼8×Ö)
    req      = 0x1D10, -- Í¨Öª ´ò¿ªÇëÇó(»­Ãæ°´Å¥Ö´ĞĞÍ¨Öª: 1=±£´æ 2=²é¿´)
    confirm  = 0x1D11, -- Í¨Öª È·ÈÏ(¹Ø±Õ¶Ô»°¿ò°´Å¥Ö´ĞĞÍ¨ÖªĞ´1)
    cancel   = 0x1D12, -- Í¨Öª È¡Ïû(¹Ø±Õ¶Ô»°¿ò°´Å¥Ö´ĞĞÍ¨ÖªĞ´1)
}

--==================== Ò³Ãæ7 ÀúÊ·¼ÇÂ¼(0x1900~0x19FF, BµµĞÂÔö) ====================
LW.HIST = {
    count    = 0x1900, -- u16 ÈÎÎñ×ÜÊı
    selidx   = 0x1901, -- u16 Ñ¡ÖĞÈÎÎñ(0»ù)
    list     = 0x1910, -- ×Ö·û´® ÈÎÎñÁĞ±í(¹æ»®Õ¼0x1910~0x194F, 64×Ö¡Ö6ĞĞ)
    detail   = 0x1950, -- ×Ö·û´® ÈÎÎñÃ÷Ï¸¶àĞĞ(¹æ»®Õ¼0x1950~0x19BF, 112×Ö¡Ö8ĞĞ: ¸÷ÅÅÑ¨Êı/·ÊÊı)
    btn_up   = 0x19C0, -- °´Å¥ ÉÏÒÆ
    btn_down = 0x19C1, -- °´Å¥ ÏÂÒÆ
    btn_view = 0x19C2, -- °´Å¥ ²é¿´Ã÷Ï¸
    btn_exp  = 0x19C3, -- °´Å¥ µ¼³öCSVµ½UÅÌ
    btn_del  = 0x19C4, -- °´Å¥ É¾³ıÈÎÎñ
}

--==================== Ò³Ãæ8 ÈÕÖ¾²é¿´(0x1A00~0x1AFF, BµµĞÂÔö) ====================
LW.LOGV = {
    count     = 0x1A00, -- u16 ÈÕÖ¾×ÜÌõÊı
    view      = 0x1A10, -- ×Ö·û´® ÈÕÖ¾´°¿Ú¶àĞĞ(¹æ»®Õ¼0x1A10~0x1A9F, 144×Ö¡Ö8ĞĞ)
    btn_up    = 0x1AB0, -- °´Å¥ ÉÏ·­Ò³
    btn_down  = 0x1AB1, -- °´Å¥ ÏÂ·­Ò³
    btn_top   = 0x1AB2, -- °´Å¥ Ìøµ½×îĞÂ
    btn_clear = 0x1AB3, -- °´Å¥ Çå¿ÕÈÕÖ¾
    btn_exp   = 0x1AB4, -- °´Å¥ µ¼³öÈÕÖ¾µ½UÅÌ
}

--==================== RW µôµç±£³ÖÇø(0x0000~0x7FFF, 64KB °´ÉÈÇø) ====================
-- ×¢Òâ: ±êÖ¾Î»ÓëÊı¾İĞëÍ¬ 4KB ÉÈÇø; ÉÏµç¶Á 0xFFFF Ğë»Ö¸´Ä¬ÈÏ; ÑÏ½û¸ßÆµĞ´
-- ABÏß BDParaType 56B=28×Ö: magic(0x55AA) + ÍêÕû pack ¾µÏñ(CrcCheckÖÃ0)
LW.RW = {
    ab_magic = 0x0000, -- u16 ABÏßÓĞĞ§±êÖ¾ 0x55AA
    ab_data  = 0x0001, -- 28×Ö BDParaType ÍêÕû¾µÏñ(page_abline pack, CrcCheck=0)
}

return LW

]==]

_MODS["protocol.lua"] = [==[
--[[
protocol.lua ¡ª¡ª µç¿Ø²¥ÖÖ»ú 0x68 Ğ­ÒéÖ¡ÒıÇæ£¨´¿Âß¼­£¬ÎŞÆ½Ì¨ÒÀÀµ£©
=================================================================
ÒÆÖ²×ÔÁ½²àÔ´Âë£¨ÒÑ×Ö½Ú¼¶ºË¶Ô£¬2026-08-27£©£º
  ÏÂÎ»»ú: hd3005a1/Src/protocol.c   (FrameConstruct / FrameAnalysis / CRC16_MODBUS)
  ÉÏÎ»»ú: SowSystem/tool/communication.cpp (addCrc / checkCrc / FrameAnalysis)

Ö¡¸ñÊ½£¨×Ü³¤ = DataLen + 7£©:
  +------+-----+-------------+------+---------------+------+
  | 0x68 | FNC | Len (u16LE) | Data | CRC16 (u16LE) | 0x0D |
  +------+-----+-------------+------+---------------+------+
  CRC: CRC-16/CCITT ·´ÉäÊ½£¨KERMIT ±äÌå£¬³õÖµ 0x0000£¬ÎŞÒì»òÊä³ö£©
       ¼ÆËã·¶Î§: ´ÓÖ¡Í· 0x68 µ½ Data Ä©Î²£¨²»º¬ CRC Óë 0x0D£©
       ±ê×¼Ğ£ÑéÖµ: CRC16("123456789") == 0x2189   (0x31C3 ÊÇXMODEMµÄÖµ, Îğ»ìÏı)

ÓÃ·¨£¨´ó²Ê VisualHMI ÆÁ¶Ë£¬¸±´®¿Ú ch1£©:
    -- main.lua:
    --   require("protocol")
    --   PROTOCOL.io.tx = function(bytes) uart_send(1, str_to_bytes(bytes)) end
    --   function on_uart_recv(ch, packet)
    --       if ch == 1 then PROTOCOL.feed_bytes(bytes_to_str(packet)) end
    --   end
    -- £¨str<->byteÊı×é ×ª»»º¯Êı¼ûÎÄ¼şÎ²²¿ PROTOCOL.util£©

ÓÃ·¨£¨PC ±ê×¼ Lua 5.3+ ×Ô²â£©:
    --   Ö±½Ó require ºóµ÷ PROTOCOL.feed_bytes(string)£¬¼û test_protocol.lua
--]]

local string = string
local table  = table

local PROTOCOL = {}

-- Ğ­Òé³£Á¿£¨Óë hd3005a1/Inc/protocol.h Í¬²½£©
PROTOCOL.FRAME_START     = 0x68
PROTOCOL.FRAME_END       = 0x0D
PROTOCOL.MAX_DATA_LEN    = 1400        -- FRAME_MAX_DATA_LEN

-- ¹¦ÄÜÂë£¨Á½²à protocol.h ²¢¼¯£¬ÒÔ×¢ÊÍ±ê×¢À´Ô´£©
PROTOCOL.FNC = {
    GET_RTC          = 0x04,   -- ÏÂÎ»»ú: »Ø u32 Ê±¼ä
    SET_RTC          = 0x05,   -- ÏÂÎ»»ú: ÊÕ u32 Ê±¼ä, »Ø ack
    GET_TEST_STATUS  = 0x08,   -- »Ø TestModeStateType
    CMD_SVCTRL       = 0x09,   -- ÊÕ TestCMDType, »Ø ack
    CMD_START_BZ     = 0x0A,   -- Æô¶¯Ğ¡Çø²¥ÖÖ, ¿ÕÓò, »Ø ack
    CMD_STOP_BZ      = 0x0B,   -- Í£Ö¹²¥ÖÖ, ¿ÕÓò, »Ø ack
    RESTART_TER      = 0x10,   -- ÖØÆôÉè±¸, »Ø ack£¨½öÏÂÎ»»úĞ­Òé±íÓĞ£©
    CMD_START_TEST   = 0x0E,   -- ½øÈë²âÊÔÄ£Ê½, ¿ÕÓò, »Ø ack
    CMD_STOP_TEST    = 0x0F,   -- ÍË³ö²âÊÔÄ£Ê½, ¿ÕÓò, »Ø ack
    CMD_START_LXBZ   = 0x11,   -- Á¬Ğø²¥ÖÖ, ÊÕ LXBZParaType, »Ø ack
    CMD_STOP_LXBZ    = 0x12,   -- Í£Ö¹Á¬Ğø²¥ÖÖ, ¿ÕÓò, »Ø ack
    SET_BZ_PARA      = 0x20,   -- ÊÕ BZCellParaType, »Ø ack(1/0)
    GET_BZ_STATUS    = 0x21,   -- »Ø BZStatusType
    RD_DEBUG_INFO    = 0x22,   -- »Øµ÷ÊÔ×Ö·û´®(GB2312, ²»º¬NUL; D5¾ö²ßºó¹Ì¼ş¸ÄUTF-8)
    STORE_AB         = 0x23,   -- ¿ÕÓò, »Ø BDParaType(µ±Ç°ABÏß)
    SET_AB           = 0x24,   -- ÊÕ BDParaType, »Ø ack
    SET_TER_PARA     = 0x25,   -- ÊÕ TerParaType, »Ø ack
    GET_TER_PARA     = 0x26,   -- ¿ÕÓò, »Ø TerParaType
    SET_USER_PARA    = 0x27,   -- ÊÕ UserParaType, »Ø ack
    GET_USER_PARA    = 0x28,   -- ¿ÕÓò, »Ø UserParaType
    QZDD_ENABLE      = 0x29,   -- ÊÕ1×Ö½Ú(0/1), »Ø ack
    GET_QZDD_STATE   = 0x30,   -- ¿ÕÓò, »Ø1×Ö½Ú£¨½öÏÂÎ»»úĞ­Òé±íÓĞ£©
    GDDD_ENABLE      = 0x31,   -- ÊÕ1×Ö½Ú(0/1), »Ø ack
    GET_GDDD_STATE   = 0x32,   -- ¿ÕÓò, »Ø1×Ö½Ú£¨½öÏÂÎ»»úĞ­Òé±íÓĞ£©
    UPDATE_START     = 0xA0,   -- IAP Éı¼¶£¨ÆÁ¶Ë²»ÊµÏÖ£¬½öÊ¶±ğ£©
    UPDATE_BIN       = 0xA1,
    UPDATE_END       = 0xA2,
    GET_SOFT_VER     = 0xA3,   -- »Ø "xxx,vol:n.n" + NUL (strlen+1)
}

--------------------------------------------------------------------
-- CRC-16/CCITT ·´ÉäÊ½£¨KERMIT ±äÌå, poly 0x8408, init 0x0000, xorout 0x0000£©
-- ÓëÏÂÎ»»ú CRC16_MODBUS() / ÉÏÎ»»ú CRC16_CCITTCalc() µÄ²é±íÍêÈ«µÈ¼Û
--------------------------------------------------------------------
local crc_table
local function crc_init()
    crc_table = {}
    for i = 0, 255 do
        local crc = i
        for _ = 1, 8 do
            if crc & 1 == 1 then crc = (crc >> 1) ~ 0x8408
            else                 crc =  crc >> 1
            end
        end
        crc_table[i] = crc & 0xFFFF
    end
end
crc_init()

function PROTOCOL.crc16(data, from, to)
    from = from or 1
    to   = to   or #data
    local crc = 0
    for i = from, to do
        crc = (crc >> 8) ~ crc_table[(crc ~ string.byte(data, i)) & 0xFF]
    end
    return crc & 0xFFFF
end

--------------------------------------------------------------------
-- ×éÖ¡: build_frame(fnc, data) -> ÍêÕûÖ¡¶ş½øÖÆ×Ö·û´®
--------------------------------------------------------------------
function PROTOCOL.build_frame(fnc, data)
    data = data or ""
    local n = #data
    assert(n <= PROTOCOL.MAX_DATA_LEN, "data too long: " .. n)
    local head = string.pack("<BB I2", PROTOCOL.FRAME_START, fnc, n)
    local crc  = PROTOCOL.crc16(head .. data)
    return head .. data .. string.pack("<I2", crc) .. string.char(PROTOCOL.FRAME_END)
end

--------------------------------------------------------------------
-- ·¢ËÍ½Ó¿Ú: send(fnc, data)
-- io.tx ×¢ÈëÊµ¼Ê´«Êä²ã£»Î´×¢ÈëÊ±»º´æµ½ io.pending£¨PC ×Ô²â¿É¶ÏÑÔ£©
--------------------------------------------------------------------
PROTOCOL.io = { tx = nil, pending = nil, tx_count = 0 }

function PROTOCOL.send(fnc, data)
    local frame = PROTOCOL.build_frame(fnc, data)
    PROTOCOL.io.tx_count = PROTOCOL.io.tx_count + 1
    if PROTOCOL.io.tx then
        PROTOCOL.io.tx(frame)
    else
        PROTOCOL.io.pending = PROTOCOL.io.pending or {}
        PROTOCOL.io.pending[#PROTOCOL.io.pending + 1] = frame
    end
    return frame
end

--------------------------------------------------------------------
-- ÊÕ°ü×´Ì¬»ú: feed_bytes(bytes) -> ½â³öµÄÖ¡ÁĞ±í {{fnc=..,data=..},...]
-- ÓïÒå¸´¿ÌÏÂÎ»»ú FrameAnalysis£¨do-while ÖğÖ¡ÌáÈ¡ + ¶ªÖ¡Í·ÖØÍ¬²½£©£º
--   1. ÕÒ²»µ½ 0x68         -> ¶ªÆúÈ«²¿£¨´¿ÔëÉù£©
--   2. ÀÛ¼Æ²»×ã 7 ×Ö½Ú      -> µÈ´ı¸ü¶àÊı¾İ
--   3. Len > 1400          -> ¶ªÆú¸Ã 0x68 ÖØÕÒ£¨·À³¤¶ÈÓòËğ»µ£©
--   4. ÀÛ¼Æ²»×ãÕûÖ¡         -> µÈ´ı¸ü¶àÊı¾İ
--   5. CRC ²»·û »ò Ö¡Î²´í   -> ¶ªÆú¸Ã 0x68 ÖØÕÒ£¨±ÈÉÏÎ»»ú¶àÑéÖ¡Î²£©
--   6. Ğ£ÑéÍ¨¹ı            -> ÅÉ·¢»Øµ÷, ¼ÌĞø´¦ÀíÊ£Óà£¨Õ³°ü£©
--------------------------------------------------------------------
PROTOCOL.rxbuf = ""
PROTOCOL.on_frame = nil          -- function(frame_table) ÓÉÉÏ²ã×¢²á

function PROTOCOL.feed_bytes(bytes)
    local rx = PROTOCOL.rxbuf .. bytes
    local frames = {}
    while true do
        -- 1) ÕÒÖ¡Í·
        local head = string.find(rx, string.char(PROTOCOL.FRAME_START), 1, true)
        if not head then rx = ""; break end
        if head > 1 then rx = string.sub(rx, head) end
        -- 2) ×îĞ¡Ö¡³¤ 7 ×Ö½Ú
        if #rx < 7 then break end
        -- 3) ³¤¶ÈÓòºÏ·¨ĞÔ
        local dlen = string.unpack("<I2", rx, 3)
        if dlen > PROTOCOL.MAX_DATA_LEN then
            rx = string.sub(rx, 2)          -- ¶ªµôÎ±Ö¡Í·£¬ÖØÕÒ
        else
            local total = dlen + 7
            -- 4) µÈ´ıÕûÖ¡
            if #rx < total then break end
            -- 5) CRC + Ö¡Î²Ğ£Ñé
            local body   = string.sub(rx, 1, dlen + 4)        -- 0x68..Data
            local crc_rx = string.unpack("<I2", rx, dlen + 5)
            local tail   = string.byte(rx, dlen + 7)
            if PROTOCOL.crc16(body) == crc_rx and tail == PROTOCOL.FRAME_END then
                local f = {
                    fnc  = string.byte(rx, 2),
                    data = string.sub(rx, 5, dlen + 4),
                    raw  = string.sub(rx, 1, total),
                }
                frames[#frames + 1] = f
                if PROTOCOL.on_frame then PROTOCOL.on_frame(f) end
                rx = string.sub(rx, total + 1)                -- ´¦ÀíÕ³°ü£º¼ÌĞø
            else
                rx = string.sub(rx, 2)      -- ¶ªÖ¡Í·ÖØÍ¬²½£¨¸´¿Ì buf.remove(0,1)£©
            end
        end
    end
    PROTOCOL.rxbuf = rx
    return frames
end

--------------------------------------------------------------------
-- ¹¤¾ß: ×Ö·û´® <-> ´ó²Ê packet ×Ö½ÚÊı×é£¨ÆÁ¶ËÊÊÅäÓÃ£©
-- ×¢Òâ: ´ó²ÊÎÄµµ±ê×¢ packet ÏÂ±ê´Ó 1 Æğ£¬Óë string.byte Ò»ÖÂ£»POC Êµ²âÈ·ÈÏ
--------------------------------------------------------------------
PROTOCOL.util = {}

function PROTOCOL.util.bytes_to_str(packet)
    local t = {}
    for i = 1, #packet do t[i] = string.char(packet[i] & 0xFF) end
    return table.concat(t)
end

function PROTOCOL.util.str_to_bytes(s)
    local t = {}
    for i = 1, #s do t[i] = string.byte(s, i) end
    return t
end

function PROTOCOL.util.hex(s, sep)
    sep = sep or " "
    local t = {}
    for i = 1, #s do t[#t + 1] = string.format("%02X", string.byte(s, i)) end
    return table.concat(t, sep)
end

return PROTOCOL

]==]

_MODS["codec.lua"] = [==[
--[[
codec.lua ¡ª¡ª Ğ­Òé½á¹¹Ìå <-> Lua table ±à½âÂë£¨string.pack ÊµÏÖ£©
================================================================================
×Ö½Ú²¼¾ÖÒÔ hd3005a2 ¹Ì¼ş(Inc/protocol.h, LINE_NUM=6 ±àÒë)Îª×¼, 2026-09-23 Õæ»ú
Áªµ÷ĞŞÕı: Èı¸öĞĞÊıÏà¹Ø½á¹¹ÌåºãÎª [6] Êı×é°æ±¾, **Óë4ĞĞ»ú/6ĞĞ»úÔËĞĞÄ£Ê½ÎŞ¹Ø**:
  BZCellParaType 92B / BZStatusType 84B(Resv2[4]) / TestModeStateType 68B
  4ĞĞ»úÖ»ÊÇ U8Resv2=4 µÄÔËĞĞ²ÎÊı(ÉÏÎ»»ú protocol.h Í¬¿Ú¾¶), Êı×éµÚ5/6Â·ºã0¡£
  (¾É°æ°´ hd3005a1 ¹Ì¼ş[4]²¼¾ÖÔÚ4ĞĞÄ£Ê½·¢76B°ü, hd3005a2/Ä£ÄâÆ÷°´92BĞ£Ñé
   Ö±½Ó ACK=0, ²¥ÖÖ¿ÕÅÜ"²¥ÖÖ½áÊø[0]" ¡ª¡ª Õæ»úÊµ²â¸´ÏÖ)
ÆäÓà½á¹¹Ìå: LXBZ 12 / TestCmd 4 / TerPara 40 / UserPara 16 / BDPara 56 B¡£
C ½á¹¹Ìå×ÔÈ»¶ÔÆëÎŞÌî³ä, string.pack ½ô´ÕÅÅÁĞÓëÆäÄÚ´æ¾µÏñÒ»ÖÂ¡£

ÓÃ·¨:
    local codec = require("codec")
    codec.init{ rows = 4 }                  -- rows Ö»×÷ÒµÎñÓïÒå(ÓĞĞ§Â·Êı), Ä¬ÈÏ4
    local s  = codec.bzcell.pack{ RowNum = 1, Density = {4000,4000,4000,4000} }
    local t  = codec.bzcell.unpack(s)       -- Density ºãÎª6ÔªËØ(4ĞĞ»úÄ©2Â·Îª0)
--]]

local string = string
local codec = {}

local ROWS = 4   -- ÒµÎñÓĞĞ§ĞĞÊı(4/6), ²»Ó°Ïì½á¹¹Ìå²¼¾Ö

-- Æ½Ì¨¼æÈİ: string.rep ÆÁ¶Ë²»¿ÉÓÃ(ÎÄµµLUA/000_Lua_Api), ÊÖĞ´µÈ¼ÛÊµÏÖ
-- (¶¨ÒåĞëÔÚ codec.init Ö®Ç°, init µÄº¯ÊıÌå´Ê·¨ÒıÓÃ±¾¾Ö²¿)
local function reps(c, n)
    local t = {}
    for i = 1, n do t[i] = c end
    return table.concat(t)
end

function codec.init(cfg)
    cfg = cfg or {}
    if cfg.rows ~= nil and cfg.rows ~= 4 and cfg.rows ~= 6 then
        error("rows must be 4 or 6")
    end
    ROWS = cfg.rows or ROWS
    codec.ROWS = ROWS
    -- ²¼¾ÖºãÎª[6]Êı×é°æ±¾(hd3005a2 ±àÒëÆÚ LINE_NUM=6), rows Ö»Ó°ÏìÒµÎñÓïÒå
    codec.bzcell.size  = 92
    codec.bzcell.fmt   = "<BBBB" .. "ii" .. reps("i", 6) .. "iii"
                               .. "ii" .. reps("i", 6) .. "iii"
    -- BZStatus: Resv2[4] ºã 84B (hd3005a2 para.h: Resv2[8-(LINE_NUM-4)*2], LINE_NUM=6)
    codec.bzstatus.size  = 84
    codec.bzstatus.resv2 = 4
    codec.bzstatus.fmt   = "<BBBBiiii" .. reps("I", 12) .. reps("i", 4)
    codec.teststate.size = 68
    codec.teststate.fmt  = "<II" .. reps("I", 12) .. "III"
end
codec.ROWS = ROWS

--------------------------------------------------------------------
-- Í¨ÓÃ: °´×Ö¶Î±í + ¸ñÊ½´®Éú³É pack/unpack
--   fields: ÓĞĞò×Ö¶ÎÃû; fmt: string.pack ¸ñÊ½´®; size: ×Ö½ÚÊı
--------------------------------------------------------------------
-- µÈ¼ÛÓÚ s:gsub("%d+$", ""): È¥µô×Ö·û´®Î²²¿Á¬ĞøÊı×Ö (string.gsub ÆÁ¶Ë²»¿ÉÓÃ)
local function strip_digits(s)
    local e = #s
    while e >= 1 do
        local c = string.byte(s, e)
        if c >= 48 and c <= 57 then e = e - 1 else break end
    end
    if e == 0 then return "" end
    return string.sub(s, 1, e)
end

local function make_struct(fields, fmt, size)
    local S = { fields = fields, fmt = fmt, size = size }
    function S.pack(t)
        local args = {}
        for i = 1, #fields do
            local v = t[fields[i]]
            if v == nil then error("missing field: " .. tostring(fields[i])) end
            args[i] = v
        end
        return string.pack(fmt, table.unpack(args))
    end
    function S.unpack(s)
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(fmt, s) }
        vals[#vals] = nil                       -- È¥µô string.unpack Î²²¿ÓÎ±ê
        local t = {}
        for i = 1, #fields do t[fields[i]] = vals[i] end
        return t
    end
    return S
end

--------------------------------------------------------------------
-- LXBZParaType Á¬Ğø²¥ÖÖ²ÎÊı£¨12B£¬Á½²àÒ»ÖÂ£©
-- hd3005a1/Inc/protocol.h:108
--------------------------------------------------------------------
codec.lxbz = make_struct(
    { "Density", "CellLen", "Hju", "ZhuShu" },
    "<iihH", 12)

--------------------------------------------------------------------
-- TerParaType ³§¼Ò²ÎÊı£¨40B£¬Á½²àÒ»ÖÂ£©
-- hd3005a1/Inc/para.h:147 / common/protocol.h
--------------------------------------------------------------------
codec.terpara = make_struct(
    { "A", "B", "EncodeNum", "EncoderDir", "HoleNum",
      "GearRatio", "MicroStepValue", "X1", "BDiroff", "TappTrigOff",
      "TapperTime", "ZeroPosEn", "GZEn", "PrePercent", "Resv1",
      "Resv0", "Resv1_", "Resv2", "CrcCheck" },
    "<hhHBBHHhhhHBBBBiiiI", 40)
-- ×¢: Resv[3] ²ğÎª Resv0/Resv1_/Resv2£¨±ÜÃâÓë u8 Resv1 ÖØÃû£©

--------------------------------------------------------------------
-- UserParaType ÓÃ»§²ÎÊı£¨16B£¬Á½²àÒ»ÖÂ£©
-- hd3005a1/Inc/para.h:172
--------------------------------------------------------------------
codec.userpara = make_struct(
    { "DZTime", "HJ", "RMP", "AntennaType", "U8Resv", "AntennaDistance", "CrcCheck" },
    "<HhIBBhI", 16)

--------------------------------------------------------------------
-- BDParaType ABÏß²ÎÊı£¨56B£¬Á½²àÒ»ÖÂ£©
-- hd3005a1/Inc/para.h:183
--------------------------------------------------------------------
codec.bdpara = make_struct(
    { "StartN", "StartE", "EndBN", "EndBE",        -- double x4
      "StartDir", "CalcDir",                        -- float  x2
      "StartState", "CalcDirFlag", "OffLen", "BDOffTime",  -- u16 x4
      "Resv", "CrcCheck" },                         -- u32 x2
    "<ddddffHHHHII", 56)

--------------------------------------------------------------------
-- TestCMDType ²âÊÔ¿ØÖÆÃüÁî£¨4B£¬Á½²àÒ»ÖÂ£©
--------------------------------------------------------------------
codec.testcmd = make_struct({ "CtrlNo", "State" }, "<HH", 4)

--------------------------------------------------------------------
-- BZCellParaType Ğ¡Çø²¥ÖÖ²ÎÊı£¨4ĞĞ76B / 6ĞĞ92B£©
-- hd3005a1/Inc/protocol.h:73  Density[4] vs Æ½°å Density[6]
--------------------------------------------------------------------
local function bzcell_fields(rows)
    local f = { "TXFlag", "FinalFlag", "NextFinalFlag", "isAfterNextZoneSow" }
    local function seg(prefix)
        f[#f+1] = prefix .. "RowNum"
        f[#f+1] = prefix .. "InS"
        for i = 1, rows do f[#f+1] = prefix .. "Density" .. i end
        f[#f+1] = prefix .. "CellLen"
        f[#f+1] = (prefix == "") and "StartPOS" or "NextCellStartPOS"
        f[#f+1] = prefix .. "DisplayRowNum"
    end
    seg("")           -- µ±Ç°ÅÅ
    seg("Next")       -- ÏÂÒ»ÅÅ
    return f
end

codec.bzcell = {
    fields_of = bzcell_fields,
    pack = function(t)
        -- °Ñ Density/NextDensity Êı×éÌ¯Æ½½øÓĞĞò²ÎÊı(ºã6ÔªËØ, ²»×ã²¹0)
        local flat = {}
        local function push(v) flat[#flat+1] = v end
        push(t.TXFlag); push(t.FinalFlag); push(t.NextFinalFlag); push(t.isAfterNextZoneSow)
        for _, p in ipairs({ "", "Next" }) do
            push(t[p .. "RowNum"]); push(t[p .. "InS"])
            local key = (p == "") and "Density" or "NextDensity"
            local d = t[key]
            assert(type(d) == "table" and #d >= 1 and #d <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do push(d[i] or 0) end
            push(t[p .. "CellLen"])
            push(p == "" and t.StartPOS or t.NextCellStartPOS)
            push(t[p .. "DisplayRowNum"])
        end
        return string.pack(codec.bzcell.fmt, table.unpack(flat))
    end,
    unpack = function(s)
        local size = codec.bzcell.size
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(codec.bzcell.fmt, s) }
        vals[#vals] = nil
        local names = bzcell_fields(6)
        local t = {}
        for i = 1, #names do
            local n = names[i]
            local base = strip_digits(n)
            if base == "Density" or base == "NextDensity" then
                local key = (base == "Density") and "Density" or "NextDensity"
                t[key] = t[key] or {}
                t[key][#t[key] + 1] = vals[i]
            else
                t[n] = vals[i]
            end
        end
        return t
    end,
}

--------------------------------------------------------------------
-- BZStatusType ²¥ÖÖ×´Ì¬£¨4ĞĞ84B / 6ĞĞ100B£©
-- hd3005a1/Inc/protocol.h:94
--------------------------------------------------------------------
codec.bzstatus = {
    pack = function(t)
        local flat = { t.RunState, t.BdState, t.ResvA, t.ResvB,
                       t.Speed, t.RowNum, t.OffLen, t.VerticalOff }
        for _, key in ipairs({ "LoufeiCnt", "LouZHCnt" }) do
            local a = t[key]
            assert(type(a) == "table" and #a >= 1 and #a <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do flat[#flat+1] = a[i] or 0 end   -- ºã6Â·, ²»×ã²¹0
        end
        for i = 1, codec.bzstatus.resv2 do flat[#flat+1] = t.Resv2[i] or 0 end
        return string.pack(codec.bzstatus.fmt, table.unpack(flat))
    end,
    unpack = function(s)
        local size = codec.bzstatus.size
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(codec.bzstatus.fmt, s) }
        vals[#vals] = nil
        local t = {
            RunState = vals[1], BdState = vals[2], ResvA = vals[3], ResvB = vals[4],
            Speed = vals[5], RowNum = vals[6], OffLen = vals[7], VerticalOff = vals[8],
            LoufeiCnt = {}, LouZHCnt = {}, Resv2 = {},
        }
        local k = 9
        for i = 1, 6 do t.LoufeiCnt[i] = vals[k]; k = k + 1 end
        for i = 1, 6 do t.LouZHCnt[i]  = vals[k]; k = k + 1 end
        for i = 1, codec.bzstatus.resv2 do t.Resv2[i] = vals[k]; k = k + 1 end
        return t
    end,
}

--------------------------------------------------------------------
-- TestModeStateType ²âÊÔÄ£Ê½×´Ì¬£¨4ĞĞ52B / 6ĞĞ68B£©
-- hd3005a1/Inc/protocol.h:118
--------------------------------------------------------------------
codec.teststate = {
    pack = function(t)
        local flat = { t.EncoderCnt, t.BdCnt }
        for _, key in ipairs({ "LoufeiCnt", "LouZHCnt" }) do
            local a = t[key]
            assert(type(a) == "table" and #a >= 1 and #a <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do flat[#flat+1] = a[i] or 0 end   -- ºã6Â·, ²»×ã²¹0
        end
        flat[#flat+1] = t.InputState
        flat[#flat+1] = t.WarningState
        flat[#flat+1] = t.CtrlState
        return string.pack(codec.teststate.fmt, table.unpack(flat))
    end,
    unpack = function(s)
        local size = codec.teststate.size
        if #s < size then error(("short %dB, expect %dB"):format(#s, size)) end
        local vals = { string.unpack(codec.teststate.fmt, s) }
        vals[#vals] = nil
        local t = { EncoderCnt = vals[1], BdCnt = vals[2],
                    LoufeiCnt = {}, LouZHCnt = {} }
        local k = 3
        for i = 1, 6 do t.LoufeiCnt[i] = vals[k]; k = k + 1 end
        for i = 1, 6 do t.LouZHCnt[i]  = vals[k]; k = k + 1 end
        t.InputState   = vals[k]; k = k + 1
        t.WarningState = vals[k]; k = k + 1
        t.CtrlState    = vals[k]
        return t
    end,
}

--------------------------------------------------------------------
-- µ÷ÊÔ×Ö·û´®(0x22): ¹Ì¼şÏÖ×´ GB2312£»D5 ¾ö²ßºó¸Ä UTF-8
-- Lua/LUA ÆÁ¶Ë×Ö·û´®¼´×Ö½ÚÁ÷£¬Ö±½ÓÍ¸´«£»ÏÔÊ¾ÖĞÎÄĞè±àÂë×ª»»£¨¼ûÆÀ¹À±¨¸æ C4£©
--------------------------------------------------------------------
function codec.debug_str(data)
    return data
end

-- ³õÊ¼»¯Ä¬ÈÏ±äÌå£¨4ĞĞ£¬¶ÔÊÖÍ·ÏÂÎ»»úÔ´Âë£©
codec.init{ rows = 4 }

return codec

]==]

_MODS["app.lua"] = [==[
--[[
app.lua ¡ª¡ª ÆÁ¶ËÓ¦ÓÃ¿ò¼Ü£ºÒ³Ãæ×¢²á/ÂÖÑ¯½ÚÁ÷/Ö¡·Ö·¢/ackÌáÊ¾/°´Å¥Â·ÓÉ/Õï¶ÏÂë
================================================================================
Éè¼ÆÔ­Ôò(Óë protocol.lua Í¬): ´¿Âß¼­¡¢ÁãÆ½Ì¨ÒÀÀµ, Í¨¹ıÒÀÀµ×¢Èë½ÓÏß =>
  lupa µ¥²â¿ÉÍêÕûÇı¶¯(POC/tests/test_app.lua), ÆÁ¶ËÓÉ main.lua ×°Åä¡£

Ò³ÃæÆõÔ¼(¸÷ page_*.lua ·µ»Ø creator º¯Êı, ÊÕ ctx ·µ»Ø page ±í):
  ctx = { APP, PROTOCOL, CODEC, LW, w16, w32, wstr, r16 }   -- LW ¼´ lwmap
  page = {
    id        = »­ÃæºÅ(LW.SCREEN.*),
    poll_cmds = { fnc, ... },          -- ½ö±¾Ò³¿É¼ûÊ±ÓÉ APP.tick ÖÜÆÚ·¢ËÍ
    addrs     = { °´Å¥LWµØÖ·, ... },   -- ÉùÃ÷¹Ø×¢µÄ°´Å¥µØÖ·(ÓÃÓÚÂ·ÓÉ)
    on_enter/on_frame/on_ack/on_update -- ¡¾±ØĞëÓÃÃ°ºÅ¶¨Òå¡¿function page:on_frame(f)
  }
  !! Ã°ºÅÔ¼¶¨ !! APP ·Ö·¢Í³Ò»Ã°ºÅµ÷ÓÃ(page:on_frame(f) ÒşÊ½´« self),
  Ò³Ãæ¶¨ÒåÈôÓÃµãºÅ(function page.on_frame(f)), Ê×²ÎÊÕµ½µÄÊÇ page ±í¶ø·ÇÖ¡,
  ËùÓĞ fnc Æ¥Åä¾²Ä¬Ê§°Ü(test_app T3 ²È¿ÓÊµÂ¼)¡£

Õï¶ÏÂë(APP.diag Ğ´ LW.A.diag, ÑØÓÃ POC Ô¼¶¨):
  0 = ½Å±¾Î´Ö´ĞĞ   1 = on_init ÒÑÖ´ĞĞ, Ä£¿éÎ´¼ÓÔØÍê
  2 = Ä£¿é¼ÓÔØ³É¹¦, ½øÈëÕı³£ÂÖÑ¯
  3 = Ä£¿é¼ÓÔØÊ§°Ü(ÏêÇé¿´ LW.A.log)
  5 = °´Å¥ÒÑ´¥·¢ on_update   6 = ÊÕµ½´®¿ÚÊı¾İ
--]]

local APP = {}

-- ×°ÅäÒÀÀµ(wire/init ×¢Èë): ÉùÃ÷ĞëÔÚËùÓĞÒıÓÃËüµÄº¯Êı(º¬ĞÄÌø)Ö®Ç°
local ENV, PROTOCOL, CODEC, LW

APP.pages    = {}   -- [screen_id] = page
APP.by_addr  = {}   -- [°´Å¥µØÖ·]  = page
APP.cur      = nil  -- µ±Ç°Ò³Ãæ
APP.stat     = { tx = 0, rx = 0 }
APP.diagv    = 0

-- ÃüÁîÀà fnc(1×Ö½Ú ack Ó¦´ğÅĞ¶¨ÓÃ); ²éÑ¯Àà(0x21/0x23/0x26/0x28/0x30/0x32/0x04/0x08/0xA3)²»Ëã
local ACK_CMDS = {
    [0x05]=true, [0x09]=true, [0x0A]=true, [0x0B]=true, [0x10]=true,
    [0x0E]=true, [0x0F]=true, [0x11]=true, [0x12]=true, [0x20]=true,
    [0x24]=true, [0x25]=true, [0x27]=true, [0x29]=true, [0x31]=true,
}

-- ack ÌáÊ¾ÓÃÃüÁîÃû
local CMD_NAME = {
    [0x05]="ÉèÖÃÊ±¼ä", [0x09]="²âÊÔ¿ØÖÆ", [0x0A]="Æô¶¯Ğ¡Çø²¥ÖÖ", [0x0B]="Í£Ö¹²¥ÖÖ",
    [0x10]="ÖØÆôÉè±¸", [0x0E]="½øÈë²âÊÔÄ£Ê½", [0x0F]="ÍË³ö²âÊÔÄ£Ê½",
    [0x11]="Æô¶¯Á¬Ğø²¥ÖÖ", [0x12]="Í£Ö¹Á¬Ğø²¥ÖÖ", [0x20]="ÏÂ·¢Ğ¡Çø²ÎÊı",
    [0x24]="ÏÂ·¢ABÏß", [0x25]="Ğ´³§¼Ò²ÎÊı", [0x27]="Ğ´ÓÃ»§²ÎÊı",
    [0x29]="ÇåÁãÍ¨µÀ", [0x31]="¹ö¶¯Í¨µÀ",
}

--------------------------------------------------------------------
-- ³£×¤¶©ÔÄ(Bµµ): ×÷Òµ×´Ì¬»ú(0x21)²»ËæÒ³ÃæÇĞ»»ÖĞ¶Ï
--   APP.sub_always(fnc, handler)  ×¢²á: ¸Ã fnc Ö¡ÓÅÏÈÂ·ÓÉ handler, ²»½øÒ³Ãæ
--   APP.set_always_poll(fnc|nil)  ³£×¤ÂÖÑ¯ÃüÁî(tick ÎŞÂÛµ±Ç°Ò³¶¼·¢ËÍ)
--------------------------------------------------------------------
APP.always       = {}     -- [fnc] = handler
APP.always_poll  = nil    -- fnc »ò nil

function APP.sub_always(fnc, handler) APP.always[fnc] = handler end
function APP.set_always_poll(fnc) APP.always_poll = fnc end

--------------------------------------------------------------------
-- Á´Â·ĞÄÌø(Bµµ, 2026-09-23): È«¾Ö0x22Ì½²â + µôÏßÅĞ¶¨ + »Ö¸´ÔÚÏß²¹¶Á°æ±¾
--   Éè¼Æ(¶ÔÆëQT"ÈÎÒâÒ³Ãæ¶¼ÔÚÂÖÑ¯"µÄ¹Û²â, °´Áªµ÷½áÂÛ²Ã¼ô):
--   1) Ã¿¸öÌ½²âÖÜÆÚ(Ô¼1s)ÎŞÂÛµ±Ç°Ò³Ãæ¶¼·¢ 0x22 ¡ª¡ª ¼æ×÷ĞÄÌøÌ½ÕëÓëµ÷ÊÔ´®Ë¢ĞÂ
--      (0x22 Îª´¿²éÑ¯, ¹Ì¼şÎŞ¸±×÷ÓÃ; µ÷ÊÔ´®Ö»ÔÚ×´Ì¬ÇĞ»»Ê±±ä»¯, 1s×ã¹»)
--   2) Á¬Ğø OFFLINE_AFTER ¸öÖÜÆÚÎ´ÊÕµ½ 0x22 Ó¦´ğ -> ÅĞµôÏß:
--      LW.A.link=0 + "¡Á Í¨ĞÅÖĞ¶Ï"ÌáÊ¾; 0x21µÈ³£×¤ÂÖÑ¯ÕÕ·¢(Á´Â·»Ö¸´¼´×Ô¶¯ĞøÉÏ)
--   3) µôÏßÆÚ¼äÎ¬³Ö 0x22 Ì½²â; ÊÕµ½ 0x22 Ó¦´ğ -> »Ö¸´ÔÚÏß(LW.A.link=1),
--      ²¢²¹·¢Ò»´Î 0xA3 ¶Á°æ±¾(¸²¸Ç"ÏÂÎ»»ú¹Ì¼şÉı¼¶ºóÁ¢¼´È¡ĞÂ°æ±¾ºÅ"³¡¾°);
--      Æ½Ê±²»ÂÖÑ¯ 0xA3(½ö¿ª»úÓëÖØÁ¬¸÷Ò»´Î)
--------------------------------------------------------------------
APP.hb = {
    online = false,   -- ÉÏµçÊÓÎªÀëÏß, Ê×¸ö0x22Ó¦´ğ¼´×ªÔÚÏß(²¢´¥·¢Ò»´Î0xA3)
    ticks = 0,        -- APP.tick ¼ÆÊı(Ê±¼ä»ù×¼)
    last_rx = 0,      -- ×î½üÒ»´Î0x22Ó¦´ğÊ±µÄtick
    n = 0,            -- ÖÜÆÚÄÚ¼ÆÊı
    period = 5,       -- Ì½²âÖÜÆÚ(tickÊı), init°´poll_msÕÛËãÎªÔ¼1s
    offline_after = 3 -- Á¬ĞøÎŞÓ¦´ğÖÜÆÚÊı -> ÅĞµôÏß(Ô¼3s, ÈİÈÌÅ¼·¢¶ªÖ¡)
}

local function hb_on_debug(f)
    local hb = APP.hb
    hb.last_rx = hb.ticks
    if not hb.online then
        hb.online = true
        ENV.w16(LW.A.link, 1)
        ENV.wstr(LW.A.tip, "¡Ì Í¨ĞÅ»Ö¸´")
        PROTOCOL.send(PROTOCOL.FNC.GET_SOFT_VER)
    end
    -- µ÷ÊÔ´®ÏÔÊ¾(2026-09-24): »­ÃæÎÄ±¾¿Ø¼şÍ³Ò»GB2312, 0x22Ó¦´ğ±¾Éí¼´GB2312
    -- ×Ö½ÚÁ÷, Ö±Í¨Ğ´Èë LW.A.log ÕıÈ·ÏÔÊ¾ÖĞÎÄ(Ô­ASCII¹ıÂËÒÑÉ¾, GB2312×ªÂë´ı°ìÍê½á)
    ENV.wstr(LW.A.log, f.data)
    if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end   -- Ò³ÃæÏÔÊ¾ÕÕ¾É
end

local function hb_on_ver(f)
    ENV.wstr(LW.A.ver, f.data)              -- ÈÎÒâÒ³Ãæ¶¼¸üĞÂ°æ±¾ÏÔÊ¾
    if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end
end

--------------------------------------------------------------------
-- ×°Åä: main.lua ÔÚ on_init ÖĞµ÷ÓÃ(ÒÀÀµÈ«×¢Èëºó²Å¿É register)
--   env = { w16=, w32=, wstr=, r16=, tx=, poll_ms= }
--------------------------------------------------------------------
function APP.wire(deps)
    PROTOCOL, CODEC, LW = deps.PROTOCOL, deps.CODEC, deps.LW
end

function APP.init(env)
    ENV = env
    PROTOCOL.io.tx  = env.tx            -- ×¢Èë·¢ËÍ²ã
    PROTOCOL.on_frame = APP.feed_frame  -- ×¢²áÊÕÖ¡»Øµ÷
    -- ĞÄÌø×°Åä: ÖÜÆÚ°´Êµ¼Ê poll_ms ÕÛËãÔ¼1s; 0x22/0xA3 ×ß³£×¤Â·ÓÉ
    APP.hb.period = math.max(1, math.floor(1000 / (env.poll_ms or 200) + 0.5))
    APP.sub_always(PROTOCOL.FNC.RD_DEBUG_INFO, hb_on_debug)
    APP.sub_always(PROTOCOL.FNC.GET_SOFT_VER, hb_on_ver)
    ENV.w16(LW.A.link, 0)               -- ÉÏµçÀëÏß, Ê×¸ö0x22Ó¦´ğ×ªÔÚÏß
end

function APP.register(page)
    APP.pages[page.id] = page
    if page.addrs then
        for _, a in ipairs(page.addrs) do APP.by_addr[a] = page end
    end
    return page
end

--------------------------------------------------------------------
-- Õï¶ÏÂë(Ö»Éı²»½µ, ±£Áô×î¸ß¼¶±ğÏÖ³¡)
--------------------------------------------------------------------
function APP.diag(v)
    if v > APP.diagv then APP.diagv = v end
    if ENV then ENV.w16(LW.A.diag, APP.diagv) end
end

--------------------------------------------------------------------
-- Ò³ÃæÇĞ»»(on_screen_change µ÷ÓÃ): ¼ÇÂ¼µ±Ç°Ò³ + ´¥·¢ on_enter
--------------------------------------------------------------------
function APP.set_screen(sid)
    APP.cur = APP.pages[sid]
    if APP.cur and APP.cur.on_enter then APP.cur:on_enter() end
end

--------------------------------------------------------------------
-- ÖÜÆÚĞÄÌø(on_run µ÷ÓÃ): ĞÄÌø¼ÆÊı + ½ö¶Ô¿É¼ûÒ³·¢ poll_cmds(ÂÖÑ¯½ÚÁ÷)
--------------------------------------------------------------------
function APP.tick()
    APP.stat.tx = APP.stat.tx + 1
    ENV.w16(LW.A.tx_cnt, APP.stat.tx)
    -- ĞÄÌø: ÖÜÆÚµ½ -> ÏÈ×öµôÏßÅĞ¶¨ÔÙ·¢Ì½²â(µôÏßÆÚ¼äÌ½²â¼ÌĞø)
    local hb = APP.hb
    hb.ticks = hb.ticks + 1
    hb.n = hb.n + 1
    if hb.n >= hb.period then
        hb.n = 0
        if hb.online and (hb.ticks - hb.last_rx) >= hb.period * hb.offline_after then
            hb.online = false
            ENV.w16(LW.A.link, 0)
            ENV.wstr(LW.A.tip, "¡Á Í¨ĞÅÖĞ¶Ï")
        end
        PROTOCOL.send(PROTOCOL.FNC.RD_DEBUG_INFO)
    end
    if APP.always_poll then PROTOCOL.send(APP.always_poll) end
    if APP.cur and APP.cur.poll_cmds then
        for _, fnc in ipairs(APP.cur.poll_cmds) do
            if fnc ~= APP.always_poll then      -- ±ÜÃâÓë³£×¤ÂÖÑ¯ÖØ¸´·¢Ö¡
                PROTOCOL.send(fnc)
            end
        end
    end
    -- Ò³Ãæ tick ¹³×Ó(Bµµ): 0x21 ±»³£×¤¶©ÔÄ½Ø»ñºó, Ò³Ãæ¼¶ÇáË¢ĞÂ×ßÕâÀï
    if APP.cur and APP.cur.on_tick then APP.cur:on_tick() end
end

--------------------------------------------------------------------
-- Ö¡·Ö·¢×ÜÏß(PROTOCOL.on_frame):
--   1) ÃüÁîÀà 1 ×Ö½ÚÓ¦´ğ -> Í³Ò» ack ÌáÊ¾(LW.A.ack + LW.A.tip) + on_ack
--   2) ÆäÓà -> µ±Ç°Ò³ on_frame
--------------------------------------------------------------------
function APP.feed_frame(f)
    APP.stat.rx = APP.stat.rx + 1
    ENV.w16(LW.A.rx_cnt, APP.stat.rx)
    local h = APP.always[f.fnc]                 -- ³£×¤¶©ÔÄÓÅÏÈ(×÷Òµ0x21²»ËæÒ³ÃæÖĞ¶Ï)
    if h then h(f) return end
    if #f.data == 1 and ACK_CMDS[f.fnc] then
        local ok = string.byte(f.data, 1)
        ENV.w16(LW.A.ack, ok)
        local name = CMD_NAME[f.fnc] or string.format("ÃüÁî%#x", f.fnc)
        ENV.wstr(LW.A.tip, (ok == 1 and "¡Ì " or "¡Á ") .. name)
        if APP.cur and APP.cur.on_ack then APP.cur:on_ack(f.fnc, ok) end
        return
    end
    if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end
end

--------------------------------------------------------------------
-- °´Å¥ÊÂ¼ş(on_update µ÷ÓÃ, v==1 ÒÑÓÉ main.lua ¹ıÂË):
--   Â·ÓÉµ½ÉùÃ÷¸ÃµØÖ·µÄÒ³Ãæ, ´¦Àíºó¸´Î»°´Å¥(ÔÊĞíÖØ¸´´¥·¢)
--   ¡¾¸ùÒò½ÌÑµ¡¿¸´Î»Ö»¶Ô°´Å¥µØÖ·Ğ´0, ¾ø²»²¨¼°ÆäËû LW(2026-08-28 ÊÂ¹Ê)
--------------------------------------------------------------------
function APP.on_button(addr)
    local page = APP.by_addr[addr]
    if not page then return false end
    APP.diag(5)
    if page.on_update then page:on_update(addr, 1) end
    ENV.w16(addr, 0)                    -- ¸´Î»°´Å¥
    return true
end

return APP

]==]


_MODS["page_params.lua"] = [==[
--[[
page_params.lua ¡ª¡ª ³§¼Ò/ÓÃ»§²ÎÊıÒ³: 0x26/0x28 ¶Á¿ìÕÕ, 0x25/0x27 Ğ´Èë+Ç°¶ËĞ£Ñé
================================================================================
·¶Î§±íÀ´Ô´(ÏÂÎ»»úÇ¿ÖÆ, hd3005a1/Src/para.c ParaLegalCheck, 2026-09 ºË¶Ô):
  GearRatio      <2  »ØÂä10   => [2, 65535]        para.c:168
  HoleNum        ==0 »ØÂä9    => [1, 255]          para.c:171
  HJ             10~5000 »ØÂä60                   para.c:174
  DZTime         100~10000 »ØÂä1500                para.c:177
  RMP            5~70 »ØÂä20                        para.c:180
  TapperTime     >1000 »ØÂä60 => [0, 1000]          para.c:183
  MicroStepValue >6400 »ØÂä800 => [0, 6400]          para.c:187
  EncodeNum      ==0 »ØÂä700  => [1, 65535]         para.c:191
  PrePercent     ÎŞĞ£Ñé, °´×¢ÊÍ [0,100]              para.h:165
  ÆäÓà×Ö¶ÎÎŞÏÂÎ»»úĞ£Ñé, ·ÅĞĞ(¸ºÖµ¾­ LW i16 ¿Ø¼şÓïÒå)
ÃÜÂëËø: ³§¼Ò²ÎÊıĞ´ÈëÇ°Ğë½âËø, ÃÜÂëÓë Qt ¶ËÒ»ÖÂ formconfig.cpp:172 ("515516")
CrcCheck: ´« 0 Õ¼Î», ÏÂÎ»»úĞ´ EEPROM Ç°ÖØËã(Qt Í¬´ËĞĞÎª)
·µ»Ø creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16, r32 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16, ctx.r32

    local PASSWORD = 515516
    local unlocked = false

    -- ×î½üÒ»´Î 0x26 ¿ìÕÕ: Ğ´»ØÊ±±£Áô¹Ì¼ş²àÎ¬»¤µÄ×Ö¶Î¡£
    -- Resv1 ¼´ĞĞÊı×Ö¶ÎU8Resv2(4/6), Ôø±»Ó²±àÂë0ÏÂ·¢, Õæ»úÊµ²â»á°ÑĞĞÊı³åµô
    -- (Ä£ÄâÆ÷×´Ì¬ÎÄ¼ş±»Ğ´³É U8Resv2=0 ¸´ÏÖ), ±ØĞë´Ó¿ìÕÕÔ­Ñù´ø»Ø¡£
    local last_ter = nil

    -- ·¶Î§±í: { ×Ö¶Î, ÏÂÏŞ, ÉÏÏŞ, ÖĞÎÄÃû }  nil ÏÂÏŞ/ÉÏÏŞ = ²»¼ì
    local RANGE_T = {
        { "GearRatio",      2,     65535, "´«¶¯±È" },
        { "HoleNum",        1,     255,   "ÅÅÖÖÅÌ¿×Êı" },
        { "EncodeNum",      1,     65535, "±àÂëÆ÷Âö³å" },
        { "MicroStepValue", 0,     6400,  "Ï¸·ÖÖµ" },
        { "TapperTime",     0,     1000,  "´òµãÊ±¼ä" },
        { "PrePercent",     0,     100,   "Ô¤Ñ¹±È" },
    }
    local RANGE_U = {
        { "HJ",     10, 5000,  "ĞĞ¼ä¾àHJ" },
        { "DZTime", 100, 10000, "µãÖÍÊ±¼ä" },
        { "RMP",    5,  70,    "²¥ÖÖÅÌ×ªËÙRMP" },
    }

    local function s16(v)                       -- u16 -> i16 ·ûºÅÀ©Õ¹
        v = v & 0xFFFF
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end

    local function check(t, ranges)
        for _, r in ipairs(ranges) do
            local name, lo, hi, cn = r[1], r[2], r[3], r[4]
            local v = t[name]
            if lo and v < lo then return name, ("²ÎÊı%s=%d µÍÓÚÏÂÏŞ%d"):format(cn, v, lo) end
            if hi and v > hi then return name, ("²ÎÊı%s=%d ³¬¹ıÉÏÏŞ%d"):format(cn, v, hi) end
        end
        return nil
    end

    -- ¶Á±íµ¥(LW) -> terpara ±í(i16 ×Ö¶Î·ûºÅÀ©Õ¹, Crc Õ¼Î»0)
    local function read_ter_form()
        local P = LW.PF
        local rows = last_ter and last_ter.Resv1
        if rows ~= 4 and rows ~= 6 then rows = 6 end   -- ÎŞ¿ìÕÕÊ±¶µµ×6ĞĞ
        return {
            A = s16(r16(P.a)), B = s16(r16(P.b)),
            EncodeNum = r16(P.encodenum), EncoderDir = r16(P.encoderdir),
            HoleNum = r16(P.holenum), GearRatio = r16(P.gearratio),
            MicroStepValue = s16(r16(P.microstep)),
            X1 = s16(r16(P.x1)), BDiroff = s16(r16(P.bdiroff)),
            TappTrigOff = s16(r16(P.tapptrigoff)), TapperTime = r16(P.tappertime),
            ZeroPosEn = r16(P.zeroposen), GZEn = r16(P.gzen),
            PrePercent = r16(P.prepercent),
            Resv1 = rows, Resv0 = 0, Resv1_ = 0, Resv2 = 0, CrcCheck = 0,
        }
    end

    -- ¶Á±íµ¥ -> userpara ±í
    local function read_user_form()
        local U = LW.PU
        return {
            DZTime = r16(U.dztime), HJ = s16(r16(U.hj)), RMP = r32(U.rmp),
            AntennaType = r16(U.antennatype), U8Resv = 0,
            AntennaDistance = s16(r16(U.antennadist)), CrcCheck = 0,
        }
    end

    -- 0x26/0x28 Ó¦´ğ -> LW ±íµ¥»ØÏÔ
    local function show_ter(p)
        local P = LW.PF
        w16(P.a, p.A & 0xFFFF);          w16(P.b, p.B & 0xFFFF)
        w16(P.encodenum, p.EncodeNum);   w16(P.encoderdir, p.EncoderDir)
        w16(P.holenum, p.HoleNum);       w16(P.gearratio, p.GearRatio)
        w16(P.microstep, p.MicroStepValue & 0xFFFF)
        w16(P.x1, p.X1 & 0xFFFF);        w16(P.bdiroff, p.BDiroff & 0xFFFF)
        w16(P.tapptrigoff, p.TappTrigOff & 0xFFFF)
        w16(P.tappertime, p.TapperTime); w16(P.zeroposen, p.ZeroPosEn)
        w16(P.gzen, p.GZEn);             w16(P.prepercent, p.PrePercent)
    end

    local function show_user(p)
        local U = LW.PU
        w16(U.dztime, p.DZTime);         w16(U.hj, p.HJ & 0xFFFF)
        w32(U.rmp, p.RMP);               w16(U.antennatype, p.AntennaType)
        w16(U.antennadist, p.AntennaDistance & 0xFFFF)
    end

    local page = {
        id        = LW.SCREEN.PARAMS,
        poll_cmds = {},                          -- ¿ìÕÕÊ½: ½øÒ³/ÊÖ¶¯¶Á, ²»ÂÖÑ¯
        addrs     = {
            LW.PF.read, LW.PF.write, LW.PF.pass, LW.PF.unlock,
            LW.PU.read, LW.PU.write,
        },
    }

    function page:on_enter()                     -- ½øÒ³¶ÁË«·İ¿ìÕÕ
        PROTOCOL.send(FNC.GET_TER_PARA)
        PROTOCOL.send(FNC.GET_USER_PARA)
    end

    function page:on_frame(f)
        local ok, p = pcall(CODEC.terpara.unpack, f.data)
        if f.fnc == FNC.GET_TER_PARA then
            if ok then show_ter(p); last_ter = p
            else wstr(LW.A.log, "terpara unpack err: len=" .. #f.data) end
        elseif f.fnc == FNC.GET_USER_PARA then
            local ok2, u = pcall(CODEC.userpara.unpack, f.data)
            if ok2 then show_user(u)
            else wstr(LW.A.log, "userpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        local P, U = LW.PF, LW.PU
        if addr == P.read then
            PROTOCOL.send(FNC.GET_TER_PARA)
        elseif addr == U.read then
            PROTOCOL.send(FNC.GET_USER_PARA)
        elseif addr == P.unlock then
            local pw = r32(P.pass)
            if pw == PASSWORD then
                unlocked = true
                wstr(LW.A.tip, "¡Ì ³§¼Ò²ÎÊıÒÑ½âËø")
            else
                unlocked = false
                wstr(LW.A.tip, "¡Á ÃÜÂë´íÎó")
            end
        elseif addr == P.write then
            if not unlocked then
                wstr(LW.A.tip, "¡Á ÇëÏÈÊäÈëÃÜÂë½âËø")
                return
            end
            local t = read_ter_form()
            local bad, msg = check(t, RANGE_T)
            if bad then wstr(LW.A.tip, "¡Á " .. msg) return end
            PROTOCOL.send(FNC.SET_TER_PARA, CODEC.terpara.pack(t))
        elseif addr == U.write then
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.tip, "¡Á " .. msg) return end
            PROTOCOL.send(FNC.SET_USER_PARA, CODEC.userpara.pack(t))
        end
    end

    return page
end

]==]


_MODS["page_continuous.lua"] = [==[
--[[
page_continuous.lua ¡ª¡ª Á¬Ğø²¥ÖÖÒ³: LXBZParaType ±íµ¥ -> 0x11 Æô¶¯ / 0x12 Í£Ö¹
================================================================================
±íµ¥: ÃÜ¶È(i32) ĞĞ³¤(i32) ĞĞ¾à(Hju i16Óò) ÖêÊı(ZhuShu u16Óò)
LW ±íµ¥¿Ø¼şÎª 32 Î», ÏÂ·¢Ê±°´Ğ­ÒéÓò½Ø¶Ï(Hju s16 / ZhuShu u16)
·µ»Ø creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local r32 = ctx.r32

    local function s32(v)
        v = v & 0xFFFFFFFF
        if v >= 0x80000000 then v = v - 0x100000000 end
        return v
    end
    local function s16(v)
        v = v & 0xFFFF
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end

    local page = {
        id        = LW.SCREEN.CONTINUOUS,
        poll_cmds = {},
        addrs     = { LW.CONT.start, LW.CONT.stop },
    }

    local function read_form()
        local C = LW.CONT
        return {
            Density = s32(r32(C.density)),
            CellLen = s32(r32(C.celllen)),
            Hju     = s16(r32(C.hju)),        -- Ğ­ÒéÓò h(s16)
            ZhuShu  = r32(C.zhushu) & 0xFFFF, -- Ğ­ÒéÓò H(u16)
        }
    end

    function page:on_update(addr)
        if addr == LW.CONT.start then
            PROTOCOL.send(FNC.CMD_START_LXBZ, CODEC.lxbz.pack(read_form()))
        elseif addr == LW.CONT.stop then
            PROTOCOL.send(FNC.CMD_STOP_LXBZ)  -- ¿ÕÓò
        end
    end

    return page
end

]==]


_MODS["page_testdiag.lua"] = [==[
--[[
page_testdiag.lua ¡ª¡ª ²âÊÔÕï¶ÏÒ³: ²âÊÔÄ£Ê½ÇĞ»» / 0x08 Î»Í¼ÂÖÑ¯ / 0x09 µã¶¯ / 0x22 µ÷ÊÔ´®
================================================================================
  ÂÖÑ¯  0x08 TestModeStateType -> ±àÂëÆ÷/±±¶·¼ÆÊı, Â©ÖÖÂ©ÖêxĞĞ, IO/±¨¾¯/Êä³öÎ»Í¼
        (poll_cmds »úÖÆ: ½ö±¾Ò³¿É¼ûÊ±ÂÖÑ¯, Àë¿ª×Ô¶¯Í£ ¡ª¡ª app.lua ¿ò¼Ü±£Ö¤)
  °´Å¥  TD.enter 0x1740 -> 0x0E ½øÈë²âÊÔÄ£Ê½(¿ÕÓò)
        TD.exit  0x1741 -> 0x0F ÍË³ö(¿ÕÓò)
        TD.jogtrig 0x1744 -> 0x09 TestCMDType{CtrlNo, State}(4B)
        TD.debug 0x1745 -> 0x22 ¶Áµ÷ÊÔĞÅÏ¢(¿ÕÓò)
  Ó¦´ğ  0x08 -> LW.TD ÇøË¢ĞÂ; 0x22 -> ASCII ¹ıÂËĞ´ LW.A.log(D5 ¾ö²ß)
        ×¢: Ö÷Ò³Ò²ÓĞ 0x22 °´Å¥; Ö¡°´µ±Ç°Ò³Â·ÓÉ, Á½Ò³¸÷×Ô´¦Àí×Ô¼º·¢³öµÄ 0x22
  State ÓïÒå: ÏÂÎ»»ú½ö´æ TestCMD ÓÉÖ÷Ñ­»·Ïû·Ñ(protocool.c:385), ÆÁ¶ËÍ¸´«²»½âÊÍ
·µ»Ø creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16

    local page = {
        id        = LW.SCREEN.TESTDIAG,
        poll_cmds = { FNC.GET_TEST_STATUS },         -- 0x08 ½ö±¾Ò³¿É¼ûÊ±ÂÖÑ¯
        addrs     = { LW.TD.enter, LW.TD.exit, LW.TD.jogtrig },
    }

    function page:on_frame(f)
        local d = f.data
        if f.fnc == FNC.GET_TEST_STATUS then        -- 0x08 ²âÊÔ×´Ì¬
            local ok, st = pcall(CODEC.teststate.unpack, d)
            if ok then
                w32(LW.TD.encodercnt, st.EncoderCnt)
                w32(LW.TD.bdcnt,      st.BdCnt)
                for i = 1, CODEC.ROWS do
                    w32(LW.TD.loufei1 + (i - 1) * 2, st.LoufeiCnt[i])
                    w32(LW.TD.louzh1 + (i - 1) * 2, st.LouZHCnt[i])
                end
                w32(LW.TD.input,   st.InputState)   -- Î»Ö¸Ê¾µÆ x32 °ó¶¨
                w32(LW.TD.warning, st.WarningState)
                w32(LW.TD.ctrl,    st.CtrlState)
            else
                wstr(LW.A.log, "teststate unpack err: len=" .. #d)
            end
        elseif f.fnc == FNC.RD_DEBUG_INFO then      -- 0x22 (D5: ASCII ¹ıÂË)
            local t = {}
            for i = 1, #d do
                local b = string.byte(d, i)
                if b < 0x80 then t[#t + 1] = string.char(b) end
            end
            wstr(LW.A.log, table.concat(t))
        end
    end

    function page:on_update(addr)
        if addr == LW.TD.enter then
            PROTOCOL.send(FNC.CMD_START_TEST)       -- ¿ÕÓò
        elseif addr == LW.TD.exit then
            PROTOCOL.send(FNC.CMD_STOP_TEST)        -- ¿ÕÓò
        elseif addr == LW.TD.jogtrig then
            local cmd = CODEC.testcmd.pack{
                CtrlNo = r16(LW.TD.jogno),
                State  = r16(LW.TD.jogon),
            }
            PROTOCOL.send(FNC.CMD_SVCTRL, cmd)
        elseif addr == LW.TD.debug then
            PROTOCOL.send(FNC.RD_DEBUG_INFO)        -- ¿ÕÓò
        end
    end

    return page
end

]==]

_MODS["fileio.lua"] = [==[
--[[
fileio.lua ¡ª¡ª ´ó²ÊÎÄ¼ş/USB API ·â×°£¨BµµÊı¾İ²ãµ××ù£©
================================================================================
ÒÀ¾İ: ¹Ù·½ LUA API ÎÄµµ(hmi-doc.gz-dc.com/LUA) + 2026-09-08 ĞéÄâÆÁÊµ²â¾À´í:
  ¡¾µ¥ÎÄ¼ş»á»°Ä£ĞÍ¡¿file_open Ö»·µ»Ø²¼¶û(³É¹¦ true/Ê§°Ü false); ´ò¿ª³É¹¦¼´
  Ñ¡ÖĞ"µ±Ç°ÎÄ¼ş", ºóĞø file_read/write/seek/size/close ¾ù²»´ø¾ä±ú²ÎÊı,
  ×÷ÓÃÓÚµ±Ç°ÎÄ¼ş¡£Í¬Ò»Ê±¿ÌÖ»ÓĞÒ»¸ö"µ±Ç°ÎÄ¼ş", ²»Ö§³Ö²¢·¢´ò¿ªÁ½¸öÎÄ¼ş¡£
  (¾ÉÔ¤ÑĞÎó¼ÇÎª"Êı×Ö¾ä±ú"ÓïÒå, Ôø°Ñ open µÄ true µ±¾ä±ú´«Èë file_read(fd,n)
   ¶à²Îµ÷ÓÃ, boolean ½ø C ²ã¶Î´íÎóÖ±½Ó±ÀµôĞéÄâÆÁ¡ª¡ª»­Ãæ8µ¼³ö°´Å¥Êµ²â)
ÓïÒåÆõÔ¼(Æ½Ì¨×¢Èë io ±í, ÆÁ¶Ë wire() °óÈ«¾Ö, PC µ¥²â×¢Èë mock):
  io.open(path, mode)  mode:0¶Á/1¸²¸Ç/2×·¼Ó -> true|false   Ç°×º 1:SD 2:UÅÌ 3:ÄÚ²¿Flash
  io.read(n<=2048)     -> ×Ö½ÚÊı×étable|nil   (1»ùÎªÖ÷, 0»ù¼æÈİ; nil=EOF»òÊ§°Ü)
  io.write(t<=2048)    -> bool
  io.seek(off)         -> bool   io.size() -> n|nil   io.close() -> bool
  io.delete(path)
  io.list(path)        ·¢ÆğÒì²½Ä¿Â¼É¨Ãè, Æ½Ì¨Ã¿·¢ÏÖÒ»¸öÌõÄ¿»Øµ÷Ò»´Î
                       on_list_dir(path, filename, type, fsize) ¡ª¡ª ÖğÌõÄ¿Á÷Ê½,
                       Á÷½áÊøÎŞÏÔÊ½ĞÅºÅ, ÓÉ pump() ¾²Ä¬³¬Ê±ÅĞ¶¨ÊÕ¸î
  io.dog()             Î¹¹·
·µ»Ø: ËùÓĞ²Ù×÷Í³Ò» (nil, "´íÎóÏûÏ¢") »ò (Öµ/true)
--]]

local FILEIO = {}

FILEIO.P_SD, FILEIO.P_USB, FILEIO.P_FLASH = "1:", "2:", "3:"
FILEIO.CHUNK    = 2048          -- µ¥´Î¶ÁĞ´ÉÏÏŞ(¹Ù·½)
FILEIO.MAX_FILE = 512 * 1024    -- ¶ÁÈë×ÜÁ¿»¤À¸(·ÀÒì³£ÎÄ¼şÍÏËÀÆÁ)

-- Æ½Ì¨ io ×¢Èëµã(Ä¬ÈÏ nil; ÆÁ¶Ë FILEIO.wire() / ²âÊÔ FILEIO.bind())
FILEIO.io = nil

-------------------------------------------------------------------- ×Ö½ÚÊÊÅä
local zero_based = nil           -- nil=Î´Ì½²â; true=Æ½Ì¨·µ»Ø0»ùÊı×é

local function bytes_to_str(t)
    if t == nil then return "" end
    if type(t) ~= "table" then return tostring(t) end
    if zero_based == nil then                     -- Ì½²â»ù×¼(½öÌáÊ¾Ò»´Î)
        zero_based = (t[0] ~= nil)
    end
    local out = {}
    if zero_based then
        local i = 0
        while t[i] ~= nil do out[#out + 1] = string.char(t[i] & 0xFF); i = i + 1 end
    else
        for i = 1, #t do out[i] = string.char(t[i] & 0xFF) end
    end
    return table.concat(out)
end

local function str_to_bytes(s)
    local t = {}
    for i = 1, #s do t[i] = string.byte(s, i) end
    return t
end

-------------------------------------------------------------------- ÄÚ²¿·â×°
local function dog()
    if FILEIO.io and FILEIO.io.dog then pcall(FILEIO.io.dog) end
end

local function fopen(path, mode)
    if not FILEIO.io or not FILEIO.io.open then
        return nil, ("openÊ§°Ü %s: Æ½Ì¨ÎŞfile_open"):format(path)
    end
    local ok, r = pcall(FILEIO.io.open, path, mode)
    -- ¹Ù·½ÓïÒå(2026-09-08 ÎÄµµºËÊµ+ĞéÄâÆÁÊµ²â): file_open ·µ»Ø²¼¶ûÖµ;
    -- true=´ò¿ª³É¹¦²¢Ñ¡ÖĞ"µ±Ç°ÎÄ¼ş", false=Ê§°Ü¡£
    -- ×¢Òâ¾ø²»ÄÜ°Ñ·µ»ØÖµµ±¾ä±ú´«¸ø read/write µÈ(µ¥»á»°Ä£ĞÍÎŞ¾ä±ú²ÎÊı)¡£
    if ok and r == true then return true end
    return nil, ("openÊ§°Ü %s mode=%d ret=%s"):format(path, mode, tostring(r))
end

-------------------------------------------------------------------- ¹«¿ª API
function FILEIO.read_all(path)
    local ok0, err = fopen(path, 0)
    if not ok0 then return nil, err end
    local parts, total, first = {}, 0, true
    while true do
        local ok, t = pcall(FILEIO.io.read, FILEIO.CHUNK)
        if not ok then break end                 -- Æ½Ì¨Òì³£°´EOFÊÕÎ²
        if t == nil then                         -- nil=EOF/Ê§°Ü(¹Ù·½)
            if first then                        -- Ê×ÂÖ¼´EOF: ¿Õ/²»¿É¶ÁÎÄ¼ş
                pcall(FILEIO.io.close)
                return nil, ("read¿Õ %s"):format(path)
            end
            break
        end
        local s = bytes_to_str(t)
        if #s == 0 then break end                -- ¿Õ±í=EOF(·ÀÓù)
        first = false
        total = total + #s
        if total > FILEIO.MAX_FILE then
            pcall(FILEIO.io.close)
            return nil, ("ÎÄ¼ş³¬ÏŞ %s >%d"):format(path, FILEIO.MAX_FILE)
        end
        parts[#parts + 1] = s
        dog()
        if #s < FILEIO.CHUNK then break end      -- ¶Ì¶Á=EOF
    end
    pcall(FILEIO.io.close)
    return table.concat(parts)
end

-- ÖğĞĞ¶ÁÎÄ±¾: ¼æÈİ \r\n Óë \n; Î²ĞĞÎŞ»»ĞĞÒ²ÊÕ; ¿ÕÎÄ¼ş·µ»Ø {}
-- ×¢: read_all ¶Ô¿ÕÎÄ¼ş·µ»Ø nil(EOFÆõÔ¼), ¹ÊÓÃ size Ô¤ÅĞ´æÔÚĞÔ;
--     string.gmatch Æ½Ì¨½ûÓÃ, ÊÖĞ´ find Ñ­»·
function FILEIO.read_lines(path)
    local sz = FILEIO.size(path)
    if sz == nil then return nil, ("read_lines: ÎŞ·¨´ò¿ª %s"):format(path) end
    if sz == 0 then return {} end
    local s = FILEIO.read_all(path)
    if s == nil then return {} end               -- ·ÀÓù: size>0 µ«¶Á¿Õ
    local out, pos = {}, 1
    while pos <= #s do
        local nl = s:find("\n", pos, true)
        if not nl then
            out[#out + 1] = s:sub(pos)
            break
        end
        local line = s:sub(pos, nl - 1)
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        out[#out + 1] = line
        pos = nl + 1
    end
    return out
end

function FILEIO.write_all(path, data)
    local fd, err = fopen(path, 1)
    if not fd then return nil, err end
    if #data == 0 then                           -- ¿Õ´®: ½¨¿ÕÎÄ¼ş¼´·µ»Ø
        pcall(FILEIO.io.close)
        return true
    end
    local off = 1
    while off <= #data do
        local seg = data:sub(off, off + FILEIO.CHUNK - 1)
        local ok, r = pcall(FILEIO.io.write, str_to_bytes(seg))
        if not ok or not r then
            pcall(FILEIO.io.close)
            return nil, ("writeÊ§°Ü %s@%d"):format(path, off)
        end
        off = off + #seg
        dog()
    end
    pcall(FILEIO.io.close)
    return true
end

function FILEIO.append(path, data)
    if #data == 0 then return true end
    local fd, err = fopen(path, 2)
    if not fd then return nil, err end
    -- ±£ÊØË«±£ÏÕ: ¹Ù·½ mode=2 ¼´Ä©Î²×·¼Ó, µ«ÀúÊ·Ô¤ÑĞÌáÊ¾Ğ´Ö¸Õë²»È·¶¨,
    -- ÏÔÊ½ seek µ½ size ÔÙĞ´(¼´Ê¹ÒÑÖ¸Ä©Î²Ò²ÎŞº¦)
    local ok, n = pcall(FILEIO.io.size)
    if ok and type(n) == "number" and n > 0 then pcall(FILEIO.io.seek, n) end
    local off = 1
    while off <= #data do
        local seg = data:sub(off, off + FILEIO.CHUNK - 1)
        local wok, r = pcall(FILEIO.io.write, str_to_bytes(seg))
        if not wok or not r then
            pcall(FILEIO.io.close)
            return nil, ("appendÊ§°Ü %s@%d"):format(path, off)
        end
        off = off + #seg
        dog()
    end
    pcall(FILEIO.io.close)
    return true
end

-- ´æÔÚĞÔ: size>0 ²ÅËã´æÔÚ(open ³É¹¦²»´ú±íÓĞÊı¾İ, ¹Ù·½ mode=0 ¿ÉÄÜ½¨¿ÕÎÄ¼ş)
function FILEIO.exists(path)
    local n = FILEIO.size(path)
    return (n ~= nil and n > 0)
end

function FILEIO.remove(path)
    if FILEIO.io and FILEIO.io.delete then pcall(FILEIO.io.delete, path) end
    return true
end

function FILEIO.size(path)
    local ok0, err = fopen(path, 0)
    if not ok0 then return nil, err end
    local ok, n = pcall(FILEIO.io.size)
    pcall(FILEIO.io.close)
    if ok and type(n) == "number" then return n end
    return nil
end

-- ¿½±´: µ¥»á»°Ä£ĞÍ²»ÄÜÍ¬Ê±¿ªÁ½ÎÄ¼ş -> Á½¶ÎÊ½(¶ÁÈ«Á¿->Ğ´È«Á¿)¡£
-- ÈÕÖ¾/µØÍ¼¾ùÎªĞ¡ÎÄ¼ş(<<MAX_FILE), ÄÚ´æÖĞ×ªÎŞÑ¹Á¦; ´óÎÄ¼şÁ÷Ê½ÁôÊµÎïÓÅ»¯
-- (¹Ù·½ÁíÓĞ file_copy(src,dst) ´ø on_copy_file_process ½ø¶È»Øµ÷, ¿ÉºóĞøÇĞ»»)¡£
function FILEIO.copy(src, dst)
    local data, err = FILEIO.read_all(src)
    if data == nil then
        print("[FILEIO] copy read fail " .. tostring(err))
        return nil, err
    end
    local ok, werr = FILEIO.write_all(dst, data)
    if not ok then print("[FILEIO] copy write fail " .. tostring(werr)) end
    return ok, werr
end

-------------------------------------------------------------------- Ä¿Â¼(ÌõÄ¿Á÷)
-- ¹Ù·½ list_dir(path) Òì²½É¨Ãè, Æ½Ì¨Ã¿·¢ÏÖÒ»¸öÌõÄ¿»Øµ÷Ò»´Î
--   on_list_dir(path, filename, type, fsize): type 0=ÎÄ¼ş¼Ğ 1=ÆÕÍ¨ÎÄ¼ş
-- Á÷½áÊøÎŞÏÔÊ½ĞÅºÅ -> pump() °´"¾²Ä¬ÆÚ+×Ü¶µµ×"ÊÕ¸î(µ¥¹ÒÆğÇëÇóÄ£ĞÍ)
local pend = nil                     -- { dir, cb, items, quiet, total }
FILEIO.LIST_IDLE_TICKS = 6           -- Á¬ĞøN´ÎpumpÎŞĞÂÌõÄ¿ => É¨ÃèÍê³É
FILEIO.LIST_MAX_TICKS  = 12          -- ·¢ÆğºóN´ÎpumpÇ¿ÖÆÊÕ¸î(¿Õ½éÖÊ/ÎŞUÅÌ)

function FILEIO.list_async(dir, cb)
    if not FILEIO.io or not FILEIO.io.list then return nil, "Æ½Ì¨ÎŞlist_dir" end
    pend = { dir = dir, cb = cb, items = {}, quiet = 0, total = 0 }
    local ok, err = pcall(FILEIO.io.list, dir)
    if not ok then
        pend = nil
        return nil, ("list_dirÊ§°Ü %s: %s"):format(dir, tostring(err))
    end
    return true
end

-- main.lua È«¾Ö on_list_dir(path, filename, type, fsize) ÖğÌõÄ¿×ª·¢µ½´Ë
function FILEIO.on_list_dir(path, filename, ftype, fsize)
    if not pend then return end
    if ftype == 1 and type(filename) == "string" then   -- Ö»ÊÕÆÕÍ¨ÎÄ¼ş
        pend.items[#pend.items + 1] = filename
        pend.quiet = 0
    end
end

-- ±Ã: main.lua on_run Ã¿ tick µ÷ÓÃÒ»´Î; ¾²Ä¬ÆÚÂú/×Ü¶µµ× => ÊÕ¸î¹ÒÆğÇëÇó
function FILEIO.pump()
    if not pend then return end
    pend.quiet = pend.quiet + 1
    pend.total = pend.total + 1
    if pend.quiet >= FILEIO.LIST_IDLE_TICKS or pend.total >= FILEIO.LIST_MAX_TICKS then
        local p = pend
        pend = nil
        pcall(p.cb, p.items, p.dir)
    end
end

-- ÓïÒå±ğÃû(ÆÁ¶ËÓëÒ³ÃæÍ³Ò»Èë¿Ú)
function FILEIO.list(dir, cb)
    return FILEIO.list_async(dir, cb)
end

-------------------------------------------------------------------- Æ½Ì¨°ó¶¨
-- Æ½Ì¨ÎÄ¼ş API ´æÔÚĞÔÌ½²â(main ×°ÅäÊ±´òÓ¡, ºËÏú¹æ¸ñ O-1 ¹Û²âµã)
function FILEIO.apis()
    local t = {}
    for _, n in ipairs { "file_open", "file_read", "file_write", "file_seek",
                         "file_size", "file_close", "file_delete", "list_dir", "feed_dog" } do
        t[n] = (type(_G[n]) == "function")
    end
    return t
end

-- ÆÁ¶Ë×°Åä(main.lua): FILEIO.wire() ¡ª¡ª ´ÓÈ«¾Öº¯Êı°ó¹Ù·½ API
-- °´´æÔÚĞÔ°ó¶¨: ĞéÄâÆÁ¿ÉÄÜÈ±Õû¸öÎÄ¼ş API ×å, È±Ê§Ïî±£³Ö nil,
-- ºóĞø²Ù×÷¾­ fopen/read/write Í³Ò»·ÀÓù·µ»Ø (nil, err) ¶ø·ÇÅ×Òì³£
function FILEIO.wire()
    local function bind(gname)
        local f = _G[gname]
        if type(f) ~= "function" then return nil end
        return function(...) return f(...) end
    end
    FILEIO.io = {
        open   = bind("file_open"),
        read   = bind("file_read"),
        write  = bind("file_write"),
        seek   = bind("file_seek"),
        size   = bind("file_size"),
        close  = bind("file_close"),
        delete = bind("file_delete"),
        list   = bind("list_dir"),
        dog    = bind("feed_dog"),
    }
    return FILEIO
end

-- ²âÊÔ×°Åä: FILEIO.bind(io_table) -> FILEIO(¿ÉÁ´Ê½)
function FILEIO.bind(io_table)
    zero_based = nil                              -- ÖØÖÃ»ù×¼Ì½²â
    pend = nil                                    -- ÖØÖÃ¹ÒÆğÉ¨Ãè
    FILEIO.io = io_table
    return FILEIO
end

return FILEIO

]==]

_MODS["csv.lua"] = [==[
--[[
csv.lua ¡ª¡ª CSV/ĞĞÎÄ±¾ ½âÎöÓëĞòÁĞ»¯£¨BµµÊı¾İ²ã, ´¿º¯ÊıÎŞ¸±×÷ÓÃ£©
================================================================================
ÒÀ¾İ: POC/docs/ÒÆÖ²¹æ¸ñ-Bµµ¶³½á.md ¡ì3.2 ¸ñÊ½¶³½á
Ô¼¶¨: ±àÂëGB2312(±¾Ä£¿éÖ»´¦Àí×Ö½ÚÁ÷, ²»×ö×ªÂë); »»ĞĞ\r\n»ò\n; ·Ö¸ô¶ººÅ;
      ×Ö¶Î½û¶ººÅ/»»ĞĞ(Ãû×ÖÀàĞ£Ñé check_name); ÎŞÒıºÅ×ªÒå¡£
µØÍ¼¸ñÊ½: #MAP/#DIM/#ROWLEN/#AISLE/#AB/#BLOCKS   (BLOCKS ÄÚ 1 »ù, ´æ´¢ 0 »ù)
ÈÎÎñ¸ñÊ½: #TASK/#MAP/#PATH/#EXCEED/#OUTSET/#LAST/#STATE/#TIME/#BLOCKS/#RESULTS (0 »ù)
·µ»Ø: parse_xxx(text) -> obj|nil, msgs(Êı×é, Ç°×º"E:"ÖÂÃü/"W:"¾¯¸æ)
--]]

local csv = {}

-------------------------------------------------------------------- »ù´¡
-- Æ½Ì¨¼æÈİ: string.gsub / string.gmatch / string.rep ÆÁ¶Ë²»¿ÉÓÃ(ÎÄµµLUA/000_Lua_Api),
-- ÒÔÏÂ¾ùÊÖĞ´µÈ¼ÛÊµÏÖ, ĞĞÎªÓëPC LuaÔ­°æÖğÒ»ÑéÖ¤Ò»ÖÂ(hmi_port/tests/test_him_equivalence.py)

local NL = string.char(10)
local CR = string.char(13)
local function is_space(c)
    return c == 32 or c == 9 or c == 13 or c == 10 or c == 11 or c == 12
end

local function trim(s)
    local i, j = 1, #s
    while i <= j and is_space(string.byte(s, i)) do i = i + 1 end
    while j >= i and is_space(string.byte(s, j)) do j = j - 1 end
    if i > j then return "" end
    return string.sub(s, i, j)
end

-- ĞĞµü´ú: °şBOM/Í³Ò»\r\n; ·µ»Øµü´úÆ÷ (µÈ¼ÛÔ­ gmatch("([^\n]*)\n?") ÓïÒå)
function csv.iter_lines(text)
    if text:sub(1, 3) == "\xEF\xBB\xBF" then text = text:sub(4) end
    if string.find(text, CR, 1, true) then        -- º¬\r²Å×ö¹éÒ»»¯(¿ìÂ·¾¶Ìø¹ı)
        local out, i, n = {}, 1, #text
        while i <= n do
            if string.byte(text, i) == 13 then
                out[#out + 1] = NL
                if i < n and string.byte(text, i + 1) == 10 then i = i + 1 end
            else
                out[#out + 1] = string.sub(text, i, i)
            end
            i = i + 1
        end
        text = table.concat(out)
    end
    local pos, empty_yielded = 1, false
    return function()
        if not empty_yielded and #text == 0 then
            empty_yielded = true
            return ""                             -- Ô­ÓïÒå: ¿ÕÎÄ±¾²úÒ»´Î¿ÕĞĞ
        end
        if pos > #text then return nil end
        local nl = string.find(text, NL, pos, true)
        if nl then
            local seg = string.sub(text, pos, nl - 1)
            pos = nl + 1
            return seg
        end
        local seg = string.sub(text, pos)
        pos = #text + 1
        return seg
    end
end

function csv.split(line)
    local t = {}
    local pos = 1
    while true do
        local c = string.find(line, ",", pos, true)
        if not c then
            t[#t + 1] = trim(string.sub(line, pos))
            break
        end
        t[#t + 1] = trim(string.sub(line, pos, c - 1))
        pos = c + 1
        if #t > 32 then break end                 -- ×Ö¶ÎÊı»¤À¸
    end
    return t
end

local function num(s)
    if s == nil then return nil end
    return tonumber(s)
end

-- Ãû×ÖĞ£Ñé: ·Ç¿Õ/ÎŞ¶ººÅ»»ĞĞ/<=31×Ö½Ú(GB2312ºº×Ö¡Ö15¸ö)
function csv.check_name(s)
    if type(s) ~= "string" or #s == 0 then return false, "¿ÕÃû×Ö" end
    if #s > 31 then return false, "Ãû×Ö³¬31×Ö½Ú" end
    if s:find("[,\r\n]") then return false, "Ãû×Öº¬¶ººÅ»ò»»ĞĞ" end
    return true
end

-- µÈ¼ÛÓÚÔ­ s:gsub("%.?0+$", ""): È¥Î²²¿Á¬Ğø'0', ÔÙÈ¥²ĞÁôµÄ'.'
local function trim_zeros(s)
    if string.find(s, ".", 1, true) then
        local e = #s
        while e >= 1 and string.byte(s, e) == 48 do e = e - 1 end   -- '0'
        if e >= 1 and string.byte(s, e) == 46 then e = e - 1 end    -- '.'
        return string.sub(s, 1, e)
    end
    return s
end

local function fmt_num(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
    end
    return trim_zeros(string.format("%.8f", v))  -- 8Î»Ğ¡Êı=GPSºÁÃ×¼¶, È¥Î²Áã
end

-------------------------------------------------------------------- µØÍ¼½âÎö
-- #DIM Ğ£Ñé½çÏŞ
local ROWS_MAX, COLS_MAX, MC_MAX = 200, 200, 16

function csv.parse_map(text)
    local msgs = {}
    local m = { name = nil, rows = nil, cols = nil, machine_cols = nil,
                col_gap = nil, rowlen = {}, aisle = {},
                blocks = {}, ab = nil, block_cnt = 0 }
    local in_blocks = false
    local seen = {}

    for line in csv.iter_lines(text) do
        if line ~= "" then
            local f = csv.split(line)
            local tag = f[1]
            if tag == "#BLOCKS" then
                in_blocks = true
            elseif in_blocks then
                local r, c, bnum, den, sow = num(f[1]), num(f[2]), num(f[3]), num(f[4]), num(f[5])
                if not (r and c and bnum ~= nil) then
                    msgs[#msgs + 1] = ("E:BLOCKSĞĞ·Ç·¨: %s"):format(line)
                elseif not m.rows then
                    msgs[#msgs + 1] = "E:#DIMÈ±Ê§(ÔÚBLOCKSÇ°)"
                elseif r < 1 or r > m.rows or c < 1 or c > m.cols then
                    msgs[#msgs + 1] = ("E:BLOCKSÔ½½ç r=%s c=%s"):format(tostring(f[1]), tostring(f[2]))
                else
                    local rr, cc = r - 1, c - 1                -- ×ª0»ù
                    if m.blocks[rr] and m.blocks[rr][cc] then
                        msgs[#msgs + 1] = ("W:ÖØ¸´¿é(%d,%d)¸²¸Ç"):format(r, c)
                    end
                    if not m.blocks[rr] then m.blocks[rr] = {} end
                    m.blocks[rr][cc] = { num = bnum,
                                         density = den or 0,
                                         sow = (sow == nil) and 1 or (sow ~= 0 and 1 or 0) }
                    m.block_cnt = m.block_cnt + 1
                end
            elseif tag == "#MAP" then
                m.name = f[2]
                if not (csv.check_name(f[2] or "")) then
                    msgs[#msgs + 1] = "E:#MAPÃû×Ö·Ç·¨"
                end
            elseif tag == "#DIM" then
                m.rows, m.cols, m.machine_cols, m.col_gap =
                    num(f[2]), num(f[3]), num(f[4]), num(f[5])
                m.block_col = num(f[6]) or 1       -- ¿ÉÑ¡: BlockColumn(Ğ¡ÇøĞĞÊı), Ä¬ÈÏ1
                if not (m.rows and m.cols and m.machine_cols and m.col_gap) then
                    msgs[#msgs + 1] = "E:#DIMĞè4¸öÊıÖµ(rows,cols,machine_cols,col_gap)"
                elseif m.rows < 1 or m.rows > ROWS_MAX
                    or m.cols < 1 or m.cols > COLS_MAX
                    or m.machine_cols < 1 or m.machine_cols > MC_MAX
                    or m.block_col < 1 or m.block_col > 8
                    or m.machine_cols % m.block_col ~= 0 then
                    msgs[#msgs + 1] = ("E:#DIMÔ½½ç %s"):format(line)
                end
                seen.DIM = true
            elseif tag == "#ROWLEN" or tag == "#AISLE" then
                local arr = (tag == "#ROWLEN") and m.rowlen or m.aisle
                for i = 2, #f do
                    local v = num(f[i])
                    if v == nil or v < 0 then
                        msgs[#msgs + 1] = ("E:%sÊıÖµ·Ç·¨: %s"):format(tag, tostring(f[i]))
                    else
                        arr[#arr + 1] = v
                    end
                end
            elseif tag == "#AB" then
                if #f >= 8 then
                    -- µÚ9×Ö¶Î: AB²Î¿¼ÅÅ(QT Map.ARow 0»ù), È±Ê¡0
                    -- µÚ10×Ö¶Î: AB·½Ïòbool(QT Map.ABLineDirection, 1=Í¬Ïò/AÔÚÅÅÉÏÑØ)
                    --   ¾ÉÎÄ¼şÈ±Ê¡ÓÉ a_row ·´ÍÆ(formmap.cpp:353 aRow=dir?0:rows-1)
                    m.ab = { name = f[2],
                             sn = num(f[3]), se = num(f[4]),
                             en = num(f[5]), ee = num(f[6]),
                             sdir = num(f[7]), cdir = num(f[8]),
                             a_row = num(f[9]) or 0,
                             abdir = num(f[10])
                                 or ((num(f[9]) or 0) == 0 and 1 or 0),
                             has = true }
                    local bad = (m.ab.sn == nil or m.ab.se == nil or m.ab.en == nil
                                 or m.ab.ee == nil or m.ab.sdir == nil or m.ab.cdir == nil)
                    if bad then
                        m.ab = nil
                        msgs[#msgs + 1] = "E:#AB×Ö¶ÎÊıÖµ·Ç·¨"
                    end
                else
                    msgs[#msgs + 1] = "W:#AB×Ö¶Î²»×ãÒÑºöÂÔ"
                end
            elseif tag:sub(1, 1) == "#" then
                -- Î´Öª±êÇ©: Èİ´íÌø¹ı(Ç°Ïò¼æÈİ)
            else
                msgs[#msgs + 1] = ("W:ÎŞ·¨Ê¶±ğĞĞÒÑºöÂÔ: %s"):format(line:sub(1, 24))
            end
        end
    end

    -- ½á¹¹Ğ£Ñé
    if not seen.DIM then msgs[#msgs + 1] = "E:È±#DIM" end
    if m.name == nil then msgs[#msgs + 1] = "E:È±#MAP" end
    if m.rows then
        if #m.rowlen ~= m.rows then
            msgs[#msgs + 1] = ("E:#ROWLENĞè%dÌõÊµÓĞ%d"):format(m.rows, #m.rowlen)
        end
        if #m.aisle ~= m.rows + 1 then
            msgs[#msgs + 1] = ("E:#AISLEĞè%dÌõÊµÓĞ%d"):format(m.rows + 1, #m.aisle)
        end
        local want = m.rows * m.cols
        if m.block_cnt < want then
            msgs[#msgs + 1] = ("W:BLOCKSÈ±%d/%d¿é,°´Ä¬ÈÏ²¹(ÃÜ¶È0²»²¥)"):format(want - m.block_cnt, want)
            for r = 0, m.rows - 1 do
                m.blocks[r] = m.blocks[r] or {}
                for c = 0, m.cols - 1 do
                    if not m.blocks[r][c] then
                        m.blocks[r][c] = { num = 0, density = 0, sow = 0 }
                    end
                end
            end
        end
    end

    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return m, msgs
end

-------------------------------------------------------------------- µØÍ¼ĞòÁĞ»¯
function csv.render_map(m)
    local L = {}
    L[#L + 1] = ("#MAP,%s"):format(m.name)
    if (m.block_col or 1) > 1 then
        L[#L + 1] = ("#DIM,%d,%d,%d,%s,%d"):format(
            m.rows, m.cols, m.machine_cols, fmt_num(m.col_gap), m.block_col)
    else
        L[#L + 1] = ("#DIM,%d,%d,%d,%s"):format(
            m.rows, m.cols, m.machine_cols, fmt_num(m.col_gap))
    end
    for r = 1, m.rows do L[#L + 1] = ("#ROWLEN,%s"):format(fmt_num(m.rowlen[r] or 0)) end
    for i = 1, m.rows + 1 do L[#L + 1] = ("#AISLE,%s"):format(fmt_num(m.aisle[i] or 0)) end
    if m.ab then
        L[#L + 1] = ("#AB,%s,%s,%s,%s,%s,%s,%s,%d,%d"):format(
            m.ab.name, fmt_num(m.ab.sn), fmt_num(m.ab.se), fmt_num(m.ab.en),
            fmt_num(m.ab.ee), fmt_num(m.ab.sdir), fmt_num(m.ab.cdir),
            m.ab.a_row or 0, m.ab.abdir or 1)
    end
    L[#L + 1] = "#BLOCKS"
    for r = 0, m.rows - 1 do
        for c = 0, m.cols - 1 do
            local b = (m.blocks[r] or {})[c] or { num = 0, density = 0, sow = 0 }
            L[#L + 1] = ("%d,%d,%d,%d,%d"):format(r + 1, c + 1, b.num, b.density, b.sow)
        end
    end
    return table.concat(L, "\r\n") .. "\r\n"
end

-------------------------------------------------------------------- ÈÎÎñ½âÎö
-- ½á¹ûĞĞ: r,c,state,start,end,seed[1..n],fert[1..n] (n=seedÁĞÊı, ×ÔÊÊÓ¦4/6)
local function parse_result_line(f)
    local r, c, st = num(f[1]), num(f[2]), num(f[3])
    if r == nil or c == nil or st == nil then return nil end
    local e = { r = r, c = c, state = st, start_t = f[4] or "", end_t = f[5] or "",
                seed = {}, fert = {} }
    local cols = #f - 5
    if cols < 2 or cols % 2 ~= 0 then return nil end
    local n = cols / 2
    for i = 1, n do e.seed[i] = num(f[5 + i]) or 0 end
    for i = 1, n do e.fert[i] = num(f[5 + n + i]) or 0 end
    return e
end

local function render_result_line(e)
    local t = { ("%d,%d,%d,%s,%s"):format(e.r, e.c, e.state, e.start_t, e.end_t) }
    for _, v in ipairs(e.seed) do t[#t + 1] = tostring(v) end
    for _, v in ipairs(e.fert) do t[#t + 1] = tostring(v) end
    return table.concat(t, ",")
end

function csv.parse_task(text)
    local msgs = {}
    local t = { name = nil, map = nil, path_type = 0, positive = 0, sow_exceed = 0,
                outset = { r = 0, c = 0 }, last = { r = -1, c = -1 },
                state = 0, create_time = "", last_work_time = "",
                blocks = {}, results = {} }
    local section = nil

    for line in csv.iter_lines(text) do
        if line ~= "" then
            local f = csv.split(line)
            local tag = f[1]
            if tag == "#BLOCKS" or tag == "#RESULTS" then
                section = tag
            elseif section == "#BLOCKS" then
                local r, c, st, sow = num(f[1]), num(f[2]), num(f[3]), num(f[4])
                if r == nil or c == nil or st == nil then
                    msgs[#msgs + 1] = ("E:BLOCKSĞĞ·Ç·¨: %s"):format(line)
                else
                    if not t.blocks[r] then t.blocks[r] = {} end
                    t.blocks[r][c] = { state = st, sow = (sow or 1) ~= 0 and 1 or 0 }
                end
            elseif section == "#RESULTS" then
                local e = parse_result_line(f)
                if e then
                    t.results[#t.results + 1] = e
                else
                    msgs[#msgs + 1] = ("W:RESULTSĞĞ·Ç·¨ÒÑºöÂÔ: %s"):format(line:sub(1, 24))
                end
            elseif tag == "#TASK" then
                t.name = f[2]
                if not csv.check_name(f[2] or "") then msgs[#msgs + 1] = "E:#TASKÃû×Ö·Ç·¨" end
            elseif tag == "#MAP" then
                t.map = f[2]
                if not csv.check_name(f[2] or "") then msgs[#msgs + 1] = "E:#MAPÃû×Ö·Ç·¨" end
            elseif tag == "#PATH" then
                local pt, po = num(f[2]), num(f[3])
                if pt == nil or pt < 0 or pt > 5 then
                    msgs[#msgs + 1] = ("E:#PATH·Ç·¨: %s"):format(line)
                else
                    t.path_type = pt
                    t.positive = (po and po ~= 0) and 1 or 0
                end
            elseif tag == "#EXCEED" then
                t.sow_exceed = (num(f[2]) or 0) ~= 0 and 1 or 0
            elseif tag == "#OUTSET" then
                local r, c = num(f[2]), num(f[3])
                if r == nil or c == nil then
                    msgs[#msgs + 1] = ("E:#OUTSET·Ç·¨: %s"):format(line)
                else
                    t.outset = { r = r, c = c }
                end
            elseif tag == "#LAST" then
                local r, c = num(f[2]), num(f[3])
                t.last = { r = r or -1, c = c or -1 }
            elseif tag == "#STATE" then
                t.state = num(f[2]) or 0
            elseif tag == "#TIME" then
                t.create_time, t.last_work_time = f[2] or "", f[3] or ""
            elseif tag:sub(1, 1) == "#" then
                -- Î´Öª±êÇ©Èİ´í
            else
                msgs[#msgs + 1] = ("W:½ÚÍâĞĞÒÑºöÂÔ: %s"):format(line:sub(1, 24))
            end
        end
    end

    if t.name == nil then msgs[#msgs + 1] = "E:È±#TASK" end
    if t.map == nil then msgs[#msgs + 1] = "E:È±#MAP" end
    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return t, msgs
end

-------------------------------------------------------------------- ÈÎÎñĞòÁĞ»¯
function csv.render_task(t)
    local L = {}
    L[#L + 1] = ("#TASK,%s"):format(t.name)
    L[#L + 1] = ("#MAP,%s"):format(t.map)
    L[#L + 1] = ("#PATH,%d,%d"):format(t.path_type, t.positive)
    L[#L + 1] = ("#EXCEED,%d"):format(t.sow_exceed and 1 or 0)
    L[#L + 1] = ("#OUTSET,%d,%d"):format(t.outset.r, t.outset.c)
    L[#L + 1] = ("#LAST,%d,%d"):format(t.last.r, t.last.c)
    L[#L + 1] = ("#STATE,%d"):format(t.state)
    L[#L + 1] = ("#TIME,%s,%s"):format(t.create_time, t.last_work_time)
    L[#L + 1] = "#BLOCKS"
    local rows = 0
    for r in pairs(t.blocks) do if r > rows then rows = r end end
    for r = 0, rows do
        if t.blocks[r] then
            local cols = 0
            for c in pairs(t.blocks[r]) do if c > cols then cols = c end end
            for c = 0, cols do
                local b = t.blocks[r][c]
                if b then
                    L[#L + 1] = ("%d,%d,%d,%d"):format(r, c, b.state, b.sow)
                end
            end
        end
    end
    if #t.results > 0 then
        L[#L + 1] = "#RESULTS"
        for _, e in ipairs(t.results) do
            L[#L + 1] = render_result_line(e)
        end
    end
    return table.concat(L, "\r\n") .. "\r\n"
end

csv.render_result_line = render_result_line
csv.parse_result_line  = parse_result_line

return csv

]==]

_MODS["store.lua"] = [==[
--[[
store.lua ¡ª¡ª Êı¾İ²ã: 9±í×¤ÁôÄ£ĞÍ + ĞĞÎÄ±¾³Ö¾Ã»¯ + Æô¶¯»Ö¸´£¨Bµµ£©
================================================================================
ÒÀ¾İ: POC/docs/ÒÆÖ²¹æ¸ñ-Bµµ¶³½á.md ¡ì3
ÄÚ´æÄ£ĞÍ: store.maps / store.tasks / store.results / store.cfg (×ø±êÈ« 0 »ù)
³Ö¾Ã»¯(ÄÚ²¿Flash "3:", prefix ¿É×¢Èë):
  map_<Ãû>.csv    µØÍ¼(Ô­Ñù×ª´æUÅÌµ¼ÈëÄÚÈİ)
  task_<Ãû>.csv   ÈÎÎñ¶¨Òå+¿é×´Ì¬(²»º¬½á¹û, ÅÅ¼¶ÖØĞ´)
  result_<Ãû>.csv ½á¹û¼ÇÂ¼(×·¼ÓÊ½)
  index.txt       "M,<Ãû>"/"T,<Ãû>" Çåµ¥(Æô¶¯ÃâÉ¨Ä¿Â¼)
¿é×´Ì¬: 0´ı²¥ 1ÒÑÏÂ·¢ 2Íê³É 3ÖĞ¶Ï(bootÊ±1¡ú3, ¶ÔÆëQT task.cpp:44 ÇÒĞŞÕıisSowº¬3)
ÒÀÀµ×¢Èë: store.init(fileioÄ£¿é, csvÄ£¿é, prefix) ¡ª¡ª ÆÁ¶Ë main.lua / PC ²âÊÔ¾ùÈç´Ë×°Åä
--]]

local store = {}

store.maps    = {}      -- [name] = map(csv.parse_map ²úÎï, Áíº¬ block_col)
store.tasks   = {}      -- [name] = task(csv.parse_task ²úÎï)
store.results = {}      -- [name] = { {r,c,state,start_t,end_t,seed={},fert={}} }
store.cfg     = { fine_tune = {} }   -- {{origin,specified,enabled}}

local F, C, PREFIX = nil, nil, "3:"

-------------------------------------------------------------------- ÎÄ¼şÃûASCII»¯
-- Õæ»úÊµ²â(2026-09): ÆÁ¶ËÎÄ¼şÏµÍ³¶Ôº¬ÖĞÎÄ(GB2312¶à×Ö½Ú)µÄÎÄ¼şÃû open Ö±½ÓÊ§°Ü,
-- ´¿ASCII³¤ÎÄ¼şÃûÕı³£¡£Òò´Ë: ÖĞÎÄÃû½ö×÷ÏÔÊ¾Ãû/Ë÷Òı¼ü(index.txtÄÚÈİ¿ÉÖĞÎÄ),
-- ÂäÅÌÎÄ¼şÃûÒ»ÂÉÓÃ slug = Ãû×ÖÖĞASCII×ÖÄ¸Êı×Ö¶Î(½ØÇ°16) + "_" + FNV-1a¹şÏ£8Î»hex¡£
-- Í¬Ãû±ØµÃÍ¬slug(boot»Ö¸´ÒÀÀµÈ·¶¨ĞÔ), ²»Í¬Ãû¹şÏ£²»Í¬(·ÀASCII¶ÎÅö×²)¡£
local function fnv1a(s)
    local h = 0x811C9DC5
    for i = 1, #s do
        h = ((h ~ string.byte(s, i)) & 0xFFFFFFFF) * 0x01000193 & 0xFFFFFFFF
    end
    return h
end

function store.slug(name)
    local ascii = {}
    for i = 1, #name do
        local c = string.byte(name, i)
        if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) then
            if #ascii < 16 then ascii[#ascii + 1] = string.char(c) end
        end
    end
    local head = (#ascii > 0) and table.concat(ascii) or "n"
    return head .. "_" .. string.format("%08X", fnv1a(name))
end

local function p_map(n)    return PREFIX .. "map_" .. store.slug(n) .. ".csv" end
local function p_task(n)   return PREFIX .. "task_" .. store.slug(n) .. ".csv" end
local function p_result(n) return PREFIX .. "result_" .. store.slug(n) .. ".csv" end
local function p_index()   return PREFIX .. "index.txt" end

-- ¾ÉÃüÃû¼æÈİ: ÔçÆÚ°æ±¾ÔøÓÃÔ­ÃûÖ±Æ´ÎÄ¼şÃû(½öASCIIÃûÄÜÂäÅÌ³É¹¦)¡£
-- boot ¶ÁÈ¡Ê± slug Â·¾¶²»´æÔÚÔò»ØÍË¾ÉÂ·¾¶, ±ÜÃâÉı¼¶ºó¾ÉÊı¾İÊ§Áª¡£
local function read_legacy(p_slug, p_old)
    local t = F.read_all(p_slug)
    if not t and p_old ~= p_slug then t = F.read_all(p_old) end
    return t
end

-------------------------------------------------------------------- ×°Åä
function store.init(fileio_mod, csv_mod, prefix)
    F, C, PREFIX = fileio_mod, csv_mod, prefix or "3:"
    return store
end

local function bet(map)   -- Ò»ÌË¸²¸ÇµÄÁĞÊı = MachineColumn/BlockColumn (QT blockEachTrip)
    return math.max(1, math.floor((map.machine_cols or 1) / (map.block_col or 1)))
end
store.block_each_trip = function(map) return bet(map) end

-- Êµ¼Ê×é¿í: Ä©ÌËÊ£ÓàÁĞ¿ÉÄÜĞ¡ÓÚ bet (QT ÆæÊıÊ£ÓàÌËÓïÒå)
local function grp(map, c0)
    local n = bet(map)
    if map.cols and c0 + n > map.cols then n = map.cols - c0 end
    return math.max(1, n)
end

-------------------------------------------------------------------- index Î¬»¤
local function index_write()
    local L = {}
    local names = {}
    for n in pairs(store.maps) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do L[#L + 1] = "M," .. n end
    names = {}
    for n in pairs(store.tasks) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do L[#L + 1] = "T," .. n end
    local s = table.concat(L, "\r\n")
    if #L > 0 then s = s .. "\r\n" end
    F.write_all(p_index(), s)
end

-------------------------------------------------------------------- µØÍ¼
-- µ¼Èë(ÎÄ±¾): ½âÎöĞ£Ñé ¡ú ×¤Áô ¡ú Ô­Ñù×Ö½Ú×ª´æÄÚ²¿Flash ¡ú ¸üĞÂindex
function store.map_import_text(name, text)
    if not select(1, C.check_name(name)) then
        return nil, "µØÍ¼Ãû·Ç·¨"
    end
    local m, msgs = C.parse_map(text)
    if not m then
        return nil, "µØÍ¼½âÎöÊ§°Ü: " .. (msgs[1] or "?")
    end
    if m.name ~= name then
        return nil, ("ÎÄ¼şÃûÓëÄÚÈİÃû²»·û(%s¡Ù%s)"):format(name, tostring(m.name))
    end
    local ok, err = F.write_all(p_map(name), text)      -- Ô­Ñù×ª´æ
    if not ok then return nil, "µØÍ¼ÂäÅÌÊ§°Ü: " .. tostring(err) end
    store.maps[name] = m
    index_write()
    return m, (#msgs > 0) and table.concat(msgs, "; ") or nil
end

-- µ¼Èë(UÅÌÎÄ¼ş): ¶ÁÈ«Á¿¡úµ¼Èë
-- UÅÌÎÄ¼şÃû±ØĞë´¿ASCII(¹Ì¼şÎÄ¼şÏµÍ³ÏŞÖÆ, Õæ»úÊµ²â); µØÍ¼ÏÔÊ¾ÃûÈ¡×Ô #MAP ĞĞ,
-- ¿ÉÎªÖĞÎÄ(ÎÄ¼şÄÚÈİ²»ÊÜÎÄ¼şÃûÏŞÖÆ)¡£
function store.map_import_file(path, name)
    local text, err = F.read_all(path)
    if not text then
        for i = 1, #name do
            if string.byte(name, i) > 126 then
                return nil, "ÎÄ¼şÃûº¬ÖĞÎÄ,Çë¸Ä´¿Ó¢ÎÄÊı×ÖÃûºóÖØÊÔ"
            end
        end
        return nil, "¶ÁÈ¡Ê§°Ü: " .. tostring(err)
    end
    -- ÏÔÊ¾ÃûÒÔÄÚÈİ #MAP Îª×¼(UÅÌÎÄ¼şÃûÖ»×÷ÔØÌå, ²»±ØÓëÏÔÊ¾ÃûÒ»ÖÂ)
    local m0 = C.parse_map(text)
    if not m0 then return nil, "µØÍ¼½âÎöÊ§°Ü" end
    if m0.name and select(1, C.check_name(m0.name)) then
        name = m0.name
    end
    return store.map_import_text(name, text)
end

-- µØÍ¼ÖØäÖÈ¾ÂäÅÌ(×¤Áô¶ÔÏóÒÑ¸Ä, ÈçÍ£Ö¹Ê±±£´æABÏß -> #AB ¶ÎĞ´»Ø)
function store.map_save(name)
    local m = store.maps[name]
    if not m then return nil, "µØÍ¼²»´æÔÚ" end
    return F.write_all(p_map(name), C.render_map(m))
end

function store.map_delete(name)
    store.maps[name] = nil
    F.remove(p_map(name))
    index_write()
end

function store.map_get(name) return store.maps[name] end

function store.map_list()
    local t = {}
    for n in pairs(store.maps) do t[#t + 1] = n end
    table.sort(t)
    return t
end

-- Ïòµ¼ÁĞ±íÕªÒª: "ÑİÊ¾Ìï 4ÅÅ¡Á6ÁĞ"
function store.map_spec(name)
    local m = store.maps[name]
    if not m then return "?" end
    return ("%dÅÅ¡Á%dÁĞ"):format(m.rows, m.cols)
end

-------------------------------------------------------------------- ÈÎÎñ
-- ´´½¨: ¿ËÂ¡µØÍ¼¿é×´Ì¬(sow) ¡ú È«0´ı²¥; last=-1; ÂäÅÌ
function store.task_create(name, map_name, path_type, positive, sow_exceed,
                           outset_r, outset_c, now)
    if not select(1, C.check_name(name)) then return nil, "ÈÎÎñÃû·Ç·¨" end
    if store.tasks[name] then return nil, "ÈÎÎñÒÑ´æÔÚ" end
    local m = store.maps[map_name]
    if not m then return nil, "µØÍ¼²»´æÔÚ" end
    if not (outset_r >= 0 and outset_r < m.rows and outset_c >= 0 and outset_c < m.cols) then
        return nil, "ÆğÊ¼Ğ¡ÇøÔ½½ç"
    end
    local t = {
        name = name, map = map_name,
        path_type = path_type or 0,
        positive = (positive and positive ~= 0) and 1 or 0,
        sow_exceed = (sow_exceed and sow_exceed ~= 0) and 1 or 0,
        outset = { r = outset_r, c = outset_c },
        last = { r = -1, c = -1 },
        state = 0, create_time = now or "", last_work_time = now or "",
        blocks = {}, results = {},
    }
    for r = 0, m.rows - 1 do
        t.blocks[r] = {}
        for c = 0, m.cols - 1 do
            t.blocks[r][c] = { state = 0, sow = m.blocks[r][c].sow }
        end
    end
    store.tasks[name] = t
    store.results[name] = {}
    local ok, err = store.task_save(name)
    if not ok then
        store.tasks[name], store.results[name] = nil, nil
        return nil, "ÈÎÎñÂäÅÌÊ§°Ü: " .. tostring(err)
    end
    index_write()
    return t
end

-- ¶¨Òå+¿é×´Ì¬ÂäÅÌ(²»º¬½á¹û; ½á¹û×ß×·¼ÓÎÄ¼ş)
function store.task_save(name)
    local t = store.tasks[name]
    if not t then return nil, "ÈÎÎñ²»´æÔÚ" end
    local plain = {}
    for k, v in pairs(t) do plain[k] = v end
    plain.results = {}
    return F.write_all(p_task(name), C.render_task(plain))
end

function store.task_get(name) return store.tasks[name] end

function store.task_list()
    local t = {}
    for n in pairs(store.tasks) do t[#t + 1] = n end
    table.sort(t)
    return t
end

function store.task_delete(name)
    store.tasks[name], store.results[name] = nil, nil
    F.remove(p_task(name))
    F.remove(p_result(name))
    index_write()
end

-- startNode ÏÂ·¢ºó±ê¼Ç: ×éÄÚ c0..c0+bet-1 ÖÃ1 (¶ÔÆë QT setBlockState(row,col,1))
-- ²¢ÂäÅÌ: ÏÂ·¢¼´µôµç ¡ú ÖØÆôÊ¶±ğÎªÖĞ¶Ï(3), Ö§³Ö¶ÏµãĞø×÷ (QT task.cpp:44)
function store.task_mark_dispatched(name, r, c0)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "¿é²»´æÔÚ" end
    local m = store.maps[t.map]
    local n = m and grp(m, c0) or 1
    for c = c0, c0 + n - 1 do
        if t.blocks[r][c] then t.blocks[r][c].state = 1 end
    end
    return store.task_save(name)
end

-- ÅÅÍê³É: ×éÄÚÖÃ2 + ×·¼Ó½á¹ûĞĞ + ¸üĞÂ¶Ïµã + ÕûÈÎÎñÂäÅÌ(ÅÅ¼¶Æµ¶È)
function store.task_mark_row_done(name, r, c0, entries, now)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "¿é²»´æÔÚ" end
    local m = store.maps[t.map]
    local n = m and grp(m, c0) or 1
    local lines = {}
    for c = c0, c0 + n - 1 do
        if t.blocks[r][c] then t.blocks[r][c].state = 2 end
        local e = entries and entries[c - c0 + 1]
        if e then
            e.r, e.c = r, c
            store.results[name][#store.results[name] + 1] = e
            lines[#lines + 1] = C.render_result_line(e) .. "\r\n"
        end
    end
    if #lines > 0 then
        local ok, err = F.append(p_result(name), table.concat(lines))
        if not ok then return nil, "½á¹ûÂäÅÌÊ§°Ü: " .. tostring(err) end
    end
    t.last = { r = r, c = c0 + n - 1 }
    if now then t.last_work_time = now end
    return store.task_save(name)
end

function store.task_set_last(name, r, c, now)
    local t = store.tasks[name]
    if not t then return nil end
    t.last = { r = r, c = c }
    if now then t.last_work_time = now end
    return store.task_save(name)
end

-- Íê³É¶È: ·Ö×Ó=state2¿éÊı, ·ÖÄ¸=×Ü¿éÊı(¶ÔÆëQT completionDegree¿Ú¾¶)
-- Íê³É¶È: ·ÖÄ¸=×÷ÒµÂ·¾¶¸²¸ÇµÄĞ¡ÇøÊı (QT dialogrealtimetask.cpp:916
-- trip=cols/blockEachTrip Õû³ı, ÓàÊıÁĞ²»½øÂ·¾¶²»×÷Òµ), Óë mark ¿Ú¾¶Ò»ÖÂ;
-- ·ÖÄ¸´í´ó»áµ¼ÖÂÈÎÎñÍê³ÉºóÍê³ÉÂÊ·â¶¥ <100% ÇÒÒÑÍê³ÉÈÎÎñÈÔ±»ÅĞ¶¨¿ÉĞø×÷¡£
function store.task_progress(name)
    local t = store.tasks[name]
    if not t then return 0, 0, 0 end
    local m = store.maps[t.map]
    local rows = (m and m.rows) or 0
    local cols = (m and m.cols) or 0
    local n = m and bet(m) or 1
    local cov = math.floor(cols / n) * n          -- ×÷Òµ¸²¸ÇÁĞÊı(Õû³ı, ¶ªÓàÊıÁĞ)
    if cov <= 0 then cov = cols end               -- ÍË»¯: ¸²¸Ç¿ÕÊ±°´È«ÁĞ¶µµ×
    local done, total = 0, 0
    for r = 0, rows - 1 do
        local rowb = t.blocks[r]
        if rowb then
            for c = 0, cov - 1 do
                local b = rowb[c]
                if b then
                    total = total + 1
                    if b.state == 2 then done = done + 1 end
                end
            end
        end
    end
    return done, total, (total > 0) and math.floor(done * 100 / total) or 0
end

-- USB µ¼³öÎÄ±¾: ÈÎÎñ¶¨Òå + È«²¿½á¹û(ºÏ²¢äÖÈ¾)
function store.export_task_text(name)
    local t = store.tasks[name]
    if not t then return nil, "ÈÎÎñ²»´æÔÚ" end
    t.results = store.results[name] or {}
    local s = C.render_task(t)
    t.results = {}
    return s
end

-------------------------------------------------------------------- ½á¹û/ÃÜ¶ÈÎ¢µ÷
function store.result_add(name, entry)
    local list = store.results[name]
    if not list then return nil, "ÈÎÎñ²»´æÔÚ" end
    list[#list + 1] = entry
    return F.append(p_result(name), C.render_result_line(entry) .. "\r\n")
end

-- ÃÜ¶ÈÎ¢µ÷Ó³Éä(QT global.cpp densityIsSpecified/specifiedDensity; Ê×ÂÖ¿Õ±í=ºãµÈ)
function store.apply_density(v)
    for _, ft in ipairs(store.cfg.fine_tune) do
        if ft.enabled and ft.origin == v then return ft.specified end
    end
    return v
end

-------------------------------------------------------------------- Æô¶¯»Ö¸´
-- ¶Á index ¡ú ×°ÔØÈ«²¿µØÍ¼/ÈÎÎñ/½á¹û; ¿ÕÆ¬ÎŞindex·µ»ØÁã; Ê§°ÜÏîÌø¹ı²¢¼ÆÊı
function store.boot()
    local warns = {}
    store.maps, store.tasks, store.results = {}, {}, {}

    local text = F.read_all(p_index())
    if not text or #text == 0 then
        return { maps = 0, tasks = 0, warns = { "¿ÕÆ¬»òÎŞindex" } }
    end

    local mnames, tnames = {}, {}
    for line in C.iter_lines(text) do
        if line ~= "" then
            local f = C.split(line)
            if f[1] == "M" and f[2] then mnames[#mnames + 1] = f[2]
            elseif f[1] == "T" and f[2] then tnames[#tnames + 1] = f[2] end
        end
    end

    for _, n in ipairs(mnames) do
        local raw = read_legacy(p_map(n), PREFIX .. "map_" .. n .. ".csv")
        local m
        if raw then m = C.parse_map(raw) end
        if m then
            store.maps[n] = m
        else
            warns[#warns + 1] = ("µØÍ¼%s×°ÔØÊ§°ÜÒÑÌø¹ı"):format(n)
        end
    end

    for _, n in ipairs(tnames) do
        local raw = read_legacy(p_task(n), PREFIX .. "task_" .. n .. ".csv")
        local t
        if raw then t = C.parse_task(raw) end
        if t then
            -- ÖĞ¶Ï×ª»»: 1¡ú3 (QT task.cpp:44); ÆÁ¶ËisSowº¬3, ĞŞÕı¶Ïµç»Ö¸´ÃÜ¶ÈÎó0
            for _, row in pairs(t.blocks) do
                for _, b in pairs(row) do
                    if b.state == 1 then b.state = 3 end
                end
            end
            store.tasks[n] = t
            store.results[n] = {}
            local rraw = read_legacy(p_result(n), PREFIX .. "result_" .. n .. ".csv")
            if rraw then
                for line in C.iter_lines(rraw) do
                    if line ~= "" and line:sub(1, 1) ~= "#" then
                        local e = C.parse_result_line(C.split(line))
                        if e then store.results[n][#store.results[n] + 1] = e end
                    end
                end
            end
        else
            warns[#warns + 1] = ("ÈÎÎñ%s×°ÔØÊ§°ÜÒÑÌø¹ı"):format(n)
        end
    end

    -- index ÓëÄÚ´æ¶ÔÆë(Ê§°ÜÏîÌŞ³ı)
    index_write()
    return { maps = #store.map_list(), tasks = #store.task_list(), warns = warns }
end

return store

]==]

_MODS["pathalgo.lua"] = [==[
--[[
pathalgo.lua ¡ª¡ª Â·¾¶Ëã·¨²ã: createPath ÁùÖÖ + startNode ÖğÅÅÔ¤ÖÃ²ÎÊı£¨Bµµ£©
================================================================================
Öğº¯Êı¶ÔÆë QT Ô´Âë:
  create_path      <- dialogrealtimetask.cpp:913 createPath(pathType 0~5)
  column_direction <- dialogrealtimetask.cpp:1180 (×÷ÒµÖĞ´Ó path ĞòÁĞ²éÁĞ·½Ïò)
  is_sow           <- task.cpp:344 Task::isSow (×éÄÚÈÎÒ»¿é sow ÇÒ state¡Ê{0,1})
  density          <- task.cpp:373 Task::density (Í¼Íâ/²»²¥/Î¢µ÷ÈıÌ¬)
  start_node       <- dialogrealtimetask.cpp:701 startNode (µ±Ç°ÅÅ+ÏÂÒ»ÅÅ²ÎÊı×é)
  fwd_start/bwd_start/start_pos <- map.cpp:733/747/755
×ø±êÈ« 0 »ù¡£´¿º¯ÊıÎŞ¸±×÷ÓÃ, ÒÀÀµÈ«²¿¾­²ÎÊı×¢Èë¡£
--]]

local pathalgo = {}

local function bet(m)   -- Ò»ÌË×é¿í = MachineColumn/BlockColumn
    return math.max(1, math.floor((m.machine_cols or 1) / (m.block_col or 1)))
end
pathalgo.block_each_trip = bet

-------------------------------------------------------------------- createPath
-- Éú³ÉÓĞĞò×÷ÒµĞòÁĞ { {row=, column=×éÆğµãÁĞ, positive=ĞĞ½ø·½Ïòbool} ... }
-- positive=true: row 0¡úrows-1 µİÔö; false: rows-1¡ú0 µİ¼õ
local function emit(path, rows, col, positive)
    if positive then
        for r = 0, rows - 1 do path[#path + 1] = { row = r, column = col, positive = true } end
    else
        for r = rows - 1, 0, -1 do path[#path + 1] = { row = r, column = col, positive = false } end
    end
end

function pathalgo.create_path(m, path_type, positive)
    local path = {}
    local b = bet(m)
    local rows = m.rows
    local trip = math.floor(m.cols / b)      -- QT: trip=cols/blockEachTrip Õû³ı
    local cols = {}
    local dirs = {}

    if path_type == 0 then
        -- ËóĞÎ½»Ìæ(×óÆğ): 0Õı,1·´,2Õı...
        local i = 0
        while i < trip do
            cols[#cols + 1] = b * i;  i = i + 1;  dirs[#dirs + 1] = positive
            if i == trip then break end
            cols[#cols + 1] = b * i;  i = i + 1;  dirs[#dirs + 1] = not positive
        end
    elseif path_type == 1 then
        -- È«Í¬Ïò(×óÆğ)
        for i = 0, trip - 1 do
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 2 then
        -- ÖĞ¼ä·ÖÁ½²à, ×ó°ëÏÈ(×ó¶Ë½ø³ö): 0Õı,trip-1·´,1Õı,trip-2·´...
        local i = 0
        while i < trip / 2 do
            cols[#cols + 1] = b * i;            dirs[#dirs + 1] = positive
            cols[#cols + 1] = b * (trip - 1 - i); dirs[#dirs + 1] = not positive
            i = i + 1
        end
        if trip % b == 1 then                   -- QT ÆæÊıÊ£ÓàÌËÅĞ¶Ï(ÕÕ³­)
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 3 then
        -- ËóĞÎ½»Ìæ(ÓÒÆğ): trip-1Õı,trip-2·´...
        local i = trip - 1
        while i >= 0 do
            cols[#cols + 1] = b * i;  i = i - 1;  dirs[#dirs + 1] = positive
            if i < 0 then break end
            cols[#cols + 1] = b * i;  i = i - 1;  dirs[#dirs + 1] = not positive
        end
    elseif path_type == 4 then
        -- È«Í¬Ïò(ÓÒÆğ)
        for i = trip - 1, 0, -1 do
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 5 then
        -- ÖĞ¼ä·ÖÁ½²à, ÓÒ°ëÏÈ(ÓÒ¶Ë½ø³ö): trip-1Õı,0·´,trip-2Õı,1·´...
        local i = 0
        while i < trip / 2 do
            cols[#cols + 1] = b * (trip - 1 - i); dirs[#dirs + 1] = positive
            cols[#cols + 1] = b * i;              dirs[#dirs + 1] = not positive
            i = i + 1
        end
        if trip % b == 1 then
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    else
        return nil, "Â·¾¶ÀàĞÍ·Ç·¨"
    end

    for k = 1, #cols do emit(path, rows, cols[k], dirs[k]) end
    return path
end

-- ×÷ÒµÖĞ²éÁĞ·½Ïò (dialogrealtimetask.cpp:1180)
function pathalgo.column_direction(path, column)
    for _, pn in ipairs(path) do
        if pn.column == column then return pn.positive end
    end
    return true
end

-------------------------------------------------------------------- isSow/density
-- task.blocks[r][c] = { state=0/1/2/3, sow=0/1 }
function pathalgo.is_sow(task, m, row, column, b)
    if row >= 0 and row < m.rows then
        for i = 0, bet(m) - 1 do
            local blk = task.blocks[row] and task.blocks[row][column + i]
            -- ×éÄÚÈÎÒ»Î´Íê³ÉÇÒĞè²¥ÖÖ ¡ú ¸Ã×éĞè²¥ (QT task.cpp:354)
            if blk and blk.sow == 1 and (blk.state == 0 or blk.state == 1) then
                return true
            end
        end
        return false
    end
    return b          -- Í¼Íâ: ÓÉ"³öÍ¼²¥ÖÖ"¿ª¹Ø¾ö¶¨
end

-- fine_tune: {{origin,specified,enabled}...} ÃÜ¶ÈÎ¢µ÷Ó³Éä(¿ÉÎªnil)
function pathalgo.density(task, m, row, column, b, fine_tune)
    local d
    if b then
        if row < 0 then
            d = m.blocks[0][column].density          -- Í¼ÍâÉÏ²à: Ê×ÅÅÃÜ¶È
        elseif row < m.rows then
            d = pathalgo.is_sow(task, m, row, column, b)
                and m.blocks[row][column].density or 0
        else
            d = m.blocks[m.rows - 1][column].density  -- Í¼ÍâÏÂ²à: Ä©ÅÅÃÜ¶È
        end
    else
        if row >= 0 and row < m.rows then
            d = pathalgo.is_sow(task, m, row, column, b)
                and m.blocks[row][column].density or 0
        else
            d = -1                                    -- Í¼Íâ²»²¥
        end
    end
    if fine_tune then
        for _, ft in ipairs(fine_tune) do
            if ft.enabled and ft.origin == d then return ft.specified end
        end
    end
    return d
end

-------------------------------------------------------------------- ÆğÊ¼Î»ÖÃ
-- ÕıÏòÀÛ¼Æ: row<0 Í¼Íâ°´Ê×ÅÅ+Ê×¹ıµÀµ¹ÍÆ; row>=0 Í¼ÄÚ sum(rowlen[i]+aisle[i+1])
function pathalgo.fwd_start(m, row)
    local d = 0
    if row < 0 then
        for _ = row + 1, -1 do                -- QT: i++<0 ¡ú row=-1 ¼Æ0´Î, row=-2 ¼Æ1´Î
            d = d - (m.rowlen[1] + m.aisle[1])
        end
    else
        for i = 0, row - 1 do
            if i < m.rows then
                d = d + m.rowlen[i + 1] + m.aisle[i + 2]
            else
                d = d + m.rowlen[m.rows] + m.aisle[m.rows + 1]
            end
        end
    end
    return d
end

-- ·´ÏòÆğµã = ÕıÏòÀÛ¼Æ + ±¾ÅÅÅÅ³¤ (Í¼Íâ¸ºÅÅÓÃÊ×ÅÅ³¤)
function pathalgo.bwd_start(m, row)
    if row < 0 then
        return pathalgo.fwd_start(m, row) + m.rowlen[1]
    end
    local ri = (row < m.rows) and row or (m.rows - 1)
    return pathalgo.fwd_start(m, row) + m.rowlen[ri + 1]
end

-- AB ²Î¿¼: ab = { has=bool, dir=bool, a_row=int } (ÎŞABÊ± a_row=outsetÅÅ)
function pathalgo.start_pos(m, row, d, ab)
    if d then
        if (not ab.has) or ab.dir then
            return pathalgo.fwd_start(m, row) - pathalgo.fwd_start(m, ab.a_row)
        end
        return pathalgo.bwd_start(m, ab.a_row) - pathalgo.fwd_start(m, row)
    end
    if (not ab.has) or (not ab.dir) then
        return pathalgo.bwd_start(m, ab.a_row) - pathalgo.bwd_start(m, row)
    end
    return pathalgo.bwd_start(m, row) - pathalgo.fwd_start(m, ab.a_row)
end

-------------------------------------------------------------------- startNode
-- ÖğÅÅÔ¤ÖÃ²ÎÊı×é (dialogrealtimetask.cpp:701 BZCellParaType_st ÓïÒå×Ö¶Î)
-- ·µ»Ø table ¹© codec.pack_bzcell ´ò°ü 0x20 ÏÂ·¢
-- task: store ÈÎÎñ(º¬ blocks/sow_exceed); m: µØÍ¼; path: create_path ²úÎï
-- row/column: µ±Ç°½Úµã 0 »ù; ab: AB ²Î¿¼; fine_tune: ÃÜ¶ÈÎ¢µ÷
function pathalgo.start_node(task, m, path, row, column, ab, fine_tune)
    local b = (task.sow_exceed == 1)          -- ³öÍ¼²¥ÖÖ¿ª¹Ø
    local d = pathalgo.column_direction(path, column)
    local rows = m.rows
    local bc = m.block_col or 1
    local ncol = m.machine_cols               -- maxSowColumn ²¥ÖÖĞĞÊı

    local function dens_vec(r)
        local t = {}
        for i = 0, ncol - 1 do
            t[i + 1] = pathalgo.density(task, m, r, column + math.floor(i / bc), b, fine_tune)
        end
        return t
    end

    local p = {}
    p.TXFlag = (not ab.has) and 1 or ((d == ab.dir) and 1 or 0)
    p.isAfterNextZoneSow = pathalgo.is_sow(task, m, d and (row + 2) or (row - 2), column, b) and 1 or 0
    p.RowNum = row
    p.DisplayRowNum = rows - row

    if row >= 0 and row < rows then
        -- µ±Ç°ÅÅÔÚÍ¼ÄÚ
        if d then
            p.FinalFlag = (b or row >= rows - 1) and 1 or 0
            p.InS = m.aisle[row + 1]
        else
            p.FinalFlag = (b or row <= 0) and 1 or 0
            p.InS = m.aisle[row + 2]
        end
        p.Density = dens_vec(row)
        p.CellLen = m.rowlen[row + 1]
    else
        -- µ±Ç°ÅÅÔÚÍ¼Íâ
        p.FinalFlag = b and 0 or 1
        if d then
            p.InS = m.aisle[rows + 1]
            p.Density = dens_vec(rows)        -- Í¼Íâ: Ä©ÅÅÃÜ¶È(t.density row>=rows ·ÖÖ§)
            p.CellLen = m.rowlen[rows]
        else
            p.InS = m.aisle[1]
            p.Density = dens_vec(0)           -- Í¼Íâ: Ê×ÅÅÃÜ¶È(·´Ïò row<=-1? Ö÷¶ÎÓÃ0ĞĞ)
            p.CellLen = m.rowlen[1]
        end
    end
    p.StartPOS = pathalgo.start_pos(m, p.RowNum, d, ab)

    p.NextRowNum = d and (row + 1) or (row - 1)
    p.NextDisplayRowNum = rows - p.NextRowNum
    local nr = p.NextRowNum
    if nr >= 0 and nr < rows then
        -- ÏÂÒ»ÅÅÔÚÍ¼ÄÚ
        if d then
            p.NextFinalFlag = ((not b) and nr < rows - 1) and 0 or 1
            p.NextInS = m.aisle[nr + 2]
        else
            p.NextFinalFlag = ((not b) and nr > 0) and 0 or 1
            p.NextInS = m.aisle[nr + 1]
        end
        p.NextDensity = dens_vec(nr)
        p.NextCellLen = m.rowlen[nr + 1]
    else
        -- ÏÂÒ»ÅÅÔÚÍ¼Íâ
        p.NextFinalFlag = b and 0 or 1
        if d then
            p.NextInS = m.aisle[rows + 1]
            p.NextDensity = dens_vec(rows)
            p.NextCellLen = m.rowlen[rows]
        else
            p.NextInS = m.aisle[1]
            p.NextDensity = dens_vec(-1)      -- QT: ·´ÏòÍ¼Íâ Next ÓÃ density(-1) ¡ú b?0:-1
            p.NextCellLen = m.rowlen[1]
        end
    end
    p.NextCellStartPOS = pathalgo.start_pos(m, nr, d, ab)
    return p
end

return pathalgo

]==]

_MODS["logger.lua"] = [==[
--[[
logger.lua ¡ª¡ª ²Ù×÷/¸æ¾¯ÈÕÖ¾ÁôºÛ(Bµµ)
================================================================================
- ÄÚ´æ»·ĞÎ»º³å cap Ìõ + µ¥ĞĞ×·¼ÓÎÄ¼ş(µÍÆµĞ´, ¶ÔÆë¹Ù·½ RW/Flash Ğ´Ô¼Êø)
- init Ê±´ÓÎÄ¼ş»Ö¸´×î½üÌõÄ¿(µôµç²»¶ªÒÑÂäÅÌÈÕÖ¾)
- ĞĞ¸ñÊ½: "<time> <tag> <msg>" CRLF; tag: INF/CMD/ERR/WRN
- ÒÀÀµ×¢Èë: init{ now=Ê±ÖÓº¯Êı, fileio=F, path="3:log.txt", cap=120 }
  (ÆÁ¶Ë now ÓÉ×°Åä²ãÌá¹©: ÓÅÏÈÏÂÎ»»ú 0x04 Ê±¼ä»º´æ; µ¥²â×¢Èë¼ÙÊ±ÖÓ)
--]]

local logger = {}

local F, PATH, CAP, NOW
local buf = {}          -- »·ĞÎ»º³å(1»ùÊı×é, #buf Îªµ±Ç°ÌõÊı, ÉÏÏŞ CAP)
local drop_cnt = 0      -- Òç³ö¶ªÆúÊı(ÎÄ¼şÈÔÔÚ)

local function now_s()
    if NOW then
        local ok, s = pcall(NOW)
        if ok and type(s) == "string" then return s end
    end
    return "00-00 00:00:00"
end

function logger.init(cfg)
    F     = cfg.fileio
    PATH  = cfg.path or "3:log.txt"
    CAP   = cfg.cap or 120
    NOW   = cfg.now
    buf, drop_cnt = {}, 0
    -- µôµç»Ö¸´: ¶Á»Ø×î½üÌõÄ¿ (ÊÖĞ´ĞĞÇĞ·Ö: string.gmatch ÆÁ¶Ë²»¿ÉÓÃ)
    local txt = F and F.read_all(PATH) or ""
    local lines = {}
    local pos = 1
    while pos <= #txt do
        local n1 = string.find(txt, "\n", pos, true)
        local n2 = string.find(txt, "\r", pos, true)
        local eol = (n1 and n2) and math.min(n1, n2) or n1 or n2
        local seg
        if eol then
            seg = string.sub(txt, pos, eol - 1)
            pos = eol + 1
        else
            seg = string.sub(txt, pos)
            pos = #txt + 1
        end
        if seg ~= "" then lines[#lines + 1] = seg end
    end
    local from = math.max(1, #lines - CAP + 1)
    for i = from, #lines do buf[#buf + 1] = lines[i] end
    return true
end

-- ×·¼ÓÒ»Ìõ: ÄÚ´æ»·ĞÎ + ÎÄ¼şµ¥ĞĞ×·¼Ó(¹Ù·½ÏİÚåÒÑÓÉ fileio.append ·â×°: seekµ½size)
function logger.log(tag, msg)
    local line = now_s() .. " " .. tag .. " " .. tostring(msg)
    if #buf >= CAP then table.remove(buf, 1); drop_cnt = drop_cnt + 1 end
    buf[#buf + 1] = line
    if F then
        local ok = F.append(PATH, line .. "\r\n")
        if not ok then drop_cnt = drop_cnt + 1 end
    end
    return true
end

function logger.count() return #buf end
function logger.dropped() return drop_cnt end

-- ²é¿´´°¿Ú: top=1»ùÆğÊ¼Ìõ, n=ÌõÊı; ·µ»ØÊı×é(¾É->ĞÂ)
function logger.view(top, n)
    top = math.max(1, top or 1)
    n = n or 8
    local out = {}
    for i = top, math.min(top + n - 1, #buf) do out[#out + 1] = buf[i] end
    return out
end

function logger.clear()
    buf, drop_cnt = {}, 0
    if F then F.write_all(PATH, "") end
    return true
end

-- µ¼³öµ½UÅÌ: È«Á¿ÖØĞ´(¶ÁÈ¡ÆÁÄÚÎÄ¼şÔ­ÎÄ, ²»¾­¹ıÄÚ´æÖØ×é, ·À´óÎÄ¼şÒç³ö)
function logger.export(udisk_path)
    if not F then return nil, "fileioÎ´×¢Èë" end
    local ok, err = F.copy(PATH, udisk_path)
    if not ok then return nil, err end
    return true
end

return logger

]==]

_MODS["jobrun.lua"] = [==[
--[[
jobrun.lua ¡ª¡ª ×÷Òµµ÷¶È×´Ì¬»ú(BµµºËĞÄ): ÖğÅÅÔ¤ÖÃÏÂ·¢ + ÅÅÍê³ÉÂä¿â + ¶ÏµãĞø×÷
================================================================================
Öğ·ÖÖ§¶ÔÆë QT dialogrealtimetask.cpp:
  start()      <- :269 signalStartSow(Í¼ÍâÆğ²¥ :285-300 / AB²Î¿¼ÎŞABÏßÊ±¸üĞÂ :278-284)
  on_status()  <- :330 signalGetSowStatus 200ms ×´Ì¬»ú (:399-473)
  stop()       <- :305 signalStopSow(µ±Ç°¿éÍê³ÉÔò»ØÍË nextPathIndex=tempIndex :306-307)
  _complete()  <- QTÓïÒå: path×ßÍê²»×Ô¶¯Í£»ú, µÈ²Ù×÷Ô±ÊÖ¶¯Í£Ö¹(Ö÷Ò³Í£Ö¹°´Å¥->stopÊÕÎ²)
  start_node() <- pathalgo.start_node + codec.bzcell.pack -> 0x20

QT è¦´ÃĞŞÕı(ÓĞÒâÎªÖ®, ÓëC++²îÒìµã):
  ÅÅÍÆ½øµ½ĞÂÁĞ×éÊ±Í¬²½ currentColumn = path[nextPathIndex].column
  (QT :469 Ö»¸üĞÂ row, ÁĞÇĞ»»Ë²¼ä startNode ÈÔÓÃ¾ÉÁĞÃÜ¶È, ÊôÉÏÓÎÒş»¼;
   BµµÍ³Ò» 0 »ù×ø±êÏµÊ±Ò»²¢ĞŞÕı, ¼û ÒÆÖ²¹æ¸ñ-Bµµ¶³½á.md)

ÒÀÀµ×¢Èë jobrun.init{ APP, PROTOCOL, CODEC, STORE, PATHALGO, LOGGER, LW,
                      w16, w32, wstr, now }
  now() -> "yyyy-MM-dd hh:mm:ss" ×Ö·û´®(ÆÁ¶ËÓÉ×°Åä²ãÌá¹©, µ¥²â×¢Èë¼ÙÊ±ÖÓ)
--]]

local jobrun = {}

local APP, PROTOCOL, CODEC, STORE, PATHALGO, LOGGER, LW
local w16, w32, wstr, NOW, rw16, rw16w, RSTR, r16

-- ×÷ÒµÏÖ³¡(µ¥¸ö»î¶¯ÈÎÎñ)
local J = nil
-- Í£Ö¹Á÷³Ì¹ÒÆğµÄAB²É¼¯ÇëÇó { map, a_row, dir } (ÉùÃ÷ÔÚÇ°¹© init ±Õ°üÒıÓÃ)
local pending_ab = nil
-- AB¶Ô»°¿ò×´Ì¬(»­Ãæ22): mode 0=ÎŞ 1=±£´æÃüÃû 2=²é¿´; map=±£´æÄ¿±êµØÍ¼
local ab_dlg_mode = 0
local ab_dlg_map = nil
-- J = { task=Ãû, m=µØÍ¼, path, ab, next_idx, cur_col, cur_read_row,
--       enter_map, sow_state, temp_idx, result_t0, fine, disp_row }
--       disp_row = ×î½üÍ¼ÄÚÅÅµÄÏÔÊ¾ÅÅºÅ(rows-r), Í¼ÍâÖ¡Ö÷Ò³ÅÅºÅ±£³Ö¸ÃÖµ

local function now_s()
    if NOW then
        local ok, s = pcall(NOW)
        if ok and type(s) == "string" then return s end
    end
    return "1970-01-01 00:00:00"
end

local function log(tag, msg)
    if LOGGER then LOGGER.log(tag, msg) end
end

function jobrun.init(deps)
    APP, PROTOCOL, CODEC = deps.APP, deps.PROTOCOL, deps.CODEC
    STORE, PATHALGO, LOGGER, LW = deps.STORE, deps.PATHALGO, deps.LOGGER, deps.LW
    w16, w32, wstr, NOW = deps.w16, deps.w32, deps.wstr, deps.now
    rw16, rw16w = deps.rw16, deps.rw16w
    RSTR, r16 = deps.rstr, deps.r16
    -- ³£×¤¶©ÔÄ: 0x21 Ö¡ÎŞÂÛµ±Ç°Ò³¶¼½ø×´Ì¬»ú(×÷ÒµÖĞÇĞÒ³²»¶ª)
    APP.sub_always(PROTOCOL.FNC.GET_BZ_STATUS, function(f) jobrun._feed(f) end)
    -- 0x23 ²É¼¯Ó¦´ğÈ«¾Ö´¦Àí: Ìî ab_cache Óë LW.AB ÏÔÊ¾Çø(¶Ô»°¿ò»­Ãæ22µÄÏÔÊ¾¿Ø¼ş
    -- °óÍ¬Ò»µØÖ·Çø)¡£2026-09-24 ÆğÍ£Ö¹²»ÔÙ×Ô¶¯ÂäÍ¼, ¸ÄÓÉ¶Ô»°¿òÈ·ÈÏ±£´æ
    APP.sub_always(PROTOCOL.FNC.STORE_AB, function(f)
        local ok, p = pcall(CODEC.bdpara.unpack, f.data)
        if not ok then
            wstr(LW.A.log, "bdpara unpack err: len=" .. #f.data)
            return
        end
        jobrun.ab_cache = p
        jobrun.ab_show(p)
        wstr(LW.A.tip, "¡Ì ABÏßÒÑ²É¼¯")
    end)
    -- AB¶Ô»°¿òÍ¨ÖªµØÖ·(»­Ãæ22µÄ¹¦ÄÜ°´Å¥Ö´ĞĞÍ¨ÖªĞ´LW=1) -> Ó°×ÓÒ³È«¾ÖÂ·ÓÉ
    APP.register({
        id = -900,                              -- ·ÇÕæÊµ»­ÃæºÅ, ÓÀ²»³ÉÎªµ±Ç°Ò³
        addrs = { LW.ABP.req, LW.ABP.confirm, LW.ABP.cancel },
        on_update = function(_, addr) jobrun._ab_dlg_on_update(addr) end,
    })
    -- creator Ê±»ú»Ö¸´ RW »º´æ(µôµç±£³Ö)
    jobrun.ab_cache = jobrun.ab_rw_load()
    return jobrun
end

function jobrun.active() return J ~= nil end

function jobrun.snapshot()
    if not J then return nil end
    local d, tot, pct = STORE.task_progress(J.task)
    return {
        task = J.task, map = J.m.name,
        rows = J.m.rows,
        cur_row = J.path[J.next_idx] and J.path[J.next_idx].row,
        cur_col = J.cur_col,
        done = d, total = tot, pct = pct,
        sow_state = J.sow_state,
        trip_wait = J.trip_wait and true or false,
        completed = J.completed and true or false,
    }
end

-------------------------------------------------------------------- ÏÂ·¢·â×°
local function send_node(row, column)
    local p = PATHALGO.start_node(STORE.tasks[J.task], J.m, J.path, row, column, J.ab, J.fine)
    local ok, bin = pcall(CODEC.bzcell.pack, p)
    if not ok then
        log("ERR", "startNode×é°üÊ§°Ü r=" .. row)
        return false
    end
    PROTOCOL.send(PROTOCOL.FNC.SET_BZ_PARA, bin)
    -- QT :318 signalSetSowParameters: ¼ÇÂ¼µ±Ç°×éÆğÊ¼Ê±¼ä(½á¹û±í startTime)
    J.result_t0 = now_s()
    return true
end

-------------------------------------------------------------------- ÍÆ½ø(¹²ÓÃ)
-- Í¼ÄÚ(:264 ¸Õ×ßÍê next_idx ÅÅ)ÓëÍ¼Íâ(±ß½çÅÅÂä¿âºó)Á½´¦ÊâÍ¾Í¬¹é:
--   Í¬ÌËÏÂÒ»ÅÅ -> ×Ô¶¯Ô¤ÖÃ(QT :469); ¿çÁĞ×é -> trip_wait ¹ÒÆğ(¶ÔÆë QT ÏÖ³¡
--   Êµ²Ù: ²¥ÍêÒ»ÌËÊÖ¶¯°´Í£Ö¹, µôÍ·ºóÔÙ°´¿ªÊ¼Ğø²¥); path ×ßÍê -> Íê³ÉÌ¬ÊÕ¿Ú
local function advance()
    if J.next_idx < #J.path then
        J.next_idx = J.next_idx + 1
        local np = J.path[J.next_idx]
        if np.column ~= J.cur_col then
            -- ¿çÌË(ÁĞ×éÇĞ»»): ¶ÏµãÍÆ½øµ½ÏÂÒ»ÌËÊ×½Úµãºó¹ÒÆğ, ²»×Ô¶¯ÏÂ·¢,
            -- 0x21 Ö»Ë¢ÏÔÊ¾, µÈ´ıÖ÷Ò³ Í£Ö¹->¿ªÊ¼ (Ğø²¥²ÎÊıµÈ¼Û QT :276/:299
            -- ÓÉ start(resume) ÖØĞÂÏÂ·¢, ¶ø·Ç¸´ÓÃ QT :469 µÄ¾ÉÁĞ×Ô¶¯ startNode)
            J.cur_col = np.column
            J.enter_map = false
            J.trip_wait = true
            J.sow_state = false               -- Í£ÍÆ½ø(µÈÊÖ¶¯), ±£Áô J
            local _, _, pct = STORE.task_progress(J.task)
            log("INF", ("±¾ÌËÍê³É ÏÂÒ»ÌËÁĞ×é=%d ½ø¶È%d%% ÇëÍ£Ö¹ºóµôÍ·ÔÙ¿ªÊ¼")
                :format(np.column + 1, pct or 0))
            jobrun._refresh_ui()
        else
            send_node(np.row, J.cur_col)      -- Í¬ÌËÏÂÒ»ÅÅ: QT :469 ×Ô¶¯
            -- QT ÓïÒå: startNode Ö»ÏÂ·¢²ÎÊı²»ÖÃ state=1(state ½öÓÉÔÚ²¥Ö¡
            -- RowNum==path[next].row ½¨Á¢, :456) -> ĞĞ³Ì²»·û(Î´×ßµ½Ô¤ÆÚÅÅ)
            -- Ê± :459 ÍÆ½øÌõ¼şÓÀ²»Âú×ã, Íê³ÉÂÊ¹Ò×¡; ÆÁ¶Ë´ËÇ°ÔÚ´ËÔ¤ÖÃ
            -- mark_dispatched(state=1)´ò´©¸Ã±£»¤, ÂÒĞòÅÅÖ¡Ò²»áÍÆ½øÂä¿â
            -- Ò»Â·µ½100%. 2026-09-11 ¶ÔÆë QT É¾Ô¤ÖÃ(ÓÃ»§Áªµ÷±©Â¶)
        end
    else
        jobrun._complete()                    -- path ×ßÍê: Íê³ÉÌ¬´ıÊÖ¶¯Í£Ö¹
    end
end

-------------------------------------------------------------------- ABÏß×ÓÏµÍ³
-- 2026-09-23 ×Ô page_abline(ÒÑÉ¾³ı)Ç¨ÒÆ: ²é¿´²É¼¯(0x23)/RWµôµç±£´æ/
-- µØÍ¼°ó¶¨ÓëÇå³ı/ÏÂ·¢(0x24)¡£ÏÔÊ¾¸´ÓÃ LW.AB µØÖ·Çø(ÈÎÎñÒ³³ĞÔØ)¡£
-- ÏÔÊ¾ÇøÓÉÈÎÎñÒ³³ĞÔØ, ÎŞÒ³ÃæÊ±½ö¸üĞÂ cache ²»Ğ´ÆÁ¡£

function jobrun.ab_show(p)
    if not (p and LW and LW.AB and wstr) then return end
    wstr(LW.AB.startn,   ("%.7f"):format(p.StartN))
    wstr(LW.AB.starte,   ("%.7f"):format(p.StartE))
    wstr(LW.AB.endbn,    ("%.7f"):format(p.EndBN))
    wstr(LW.AB.endbe,    ("%.7f"):format(p.EndBE))
    wstr(LW.AB.startdir, ("%.3f"):format(p.StartDir))
    wstr(LW.AB.calcdir,  ("%.3f"):format(p.CalcDir))
    w16(LW.AB.startstate,  p.StartState & 0xFFFF)
    w16(LW.AB.calcdirflag, p.CalcDirFlag & 0xFFFF)
    w16(LW.AB.offlen,      p.OffLen & 0xFFFF)
    w16(LW.AB.bdofftime,   p.BDOffTime & 0xFFFF)
end

local function ab_pack(p)
    local t = {}
    for k, v in pairs(p) do t[k] = v end
    t.Resv, t.CrcCheck = 0, 0                 -- Õ¼Î», ÏÂÎ»»ú×ÔĞĞ´¦Àí
    return CODEC.bdpara.pack(t)
end

-- RW ³Ö¾Ã»¯(28×Ö=56BĞ¡¶Ëu16ĞòÁĞ; ÏÈĞ´Êı¾İºóĞ´magic, µôµç°²È«²àÅĞÎŞĞ§)
function jobrun.ab_rw_save()
    if not jobrun.ab_cache then return nil, "ÎŞABÏß, ÇëÏÈ²É¼¯" end
    if not (rw16w and LW.RW) then return nil, "RW²»¿ÉÓÃ" end
    local data = ab_pack(jobrun.ab_cache)
    for i = 0, 27 do
        local b1 = string.byte(data, i * 2 + 1)
        local b2 = string.byte(data, i * 2 + 2)
        rw16w(LW.RW.ab_data + i, b1 | (b2 << 8))
    end
    rw16w(LW.RW.ab_magic, 0x55AA)
    return true
end

function jobrun.ab_rw_load()
    if not (rw16 and LW.RW) then return nil end
    if rw16(LW.RW.ab_magic) ~= 0x55AA then return nil end
    local bytes = {}
    for i = 0, 27 do
        bytes[#bytes + 1] = string.pack("<H", rw16(LW.RW.ab_data + i) & 0xFFFF)
    end
    local ok, p = pcall(CODEC.bdpara.unpack, table.concat(bytes))
    if not ok then return nil end
    return p
end

-- °Ñ cache °ó¶¨µ½µØÍ¼(QT FormMap µ¼ÈëÓïÒå: Ğ´ #AB ¶Î²¢ÂäÅÌ)
-- name: ABÏßÏÔÊ¾Ãû(¶Ô»°¿òÊäÈë); pa: Í£Ö¹¿ìÕÕ{a_row,dir}(ÓÅÏÈÓÚ×÷Òµ²Î¿¼)
function jobrun.ab_bind_map(map_name, name, pa)
    local p = jobrun.ab_cache
    if not p then return nil, "ÎŞABÏß, ÇëÏÈ²É¼¯»ò´ÓRW¶Á»Ø" end
    local m = STORE.maps[map_name]
    if not m then return nil, "µØÍ¼²»´æÔÚ" end
    local a_row, abdir = 0, 1
    if pa then
        a_row, abdir = pa.a_row or 0, (pa.dir and 1 or 0)
    elseif J and J.m and J.m.name == map_name and J.ab then
        a_row, abdir = J.ab.a_row or 0, (J.ab.dir and 1 or 0)
    end
    m.ab = { name = (name and name ~= "") and name or map_name,
             sn = p.StartN, se = p.StartE,
             en = p.EndBN, ee = p.EndBE, sdir = p.StartDir, cdir = p.CalcDir,
             a_row = a_row, abdir = abdir, has = true }
    if STORE.map_save and not STORE.map_save(map_name) then
        return nil, "µØÍ¼ÂäÅÌÊ§°Ü"
    end
    return true
end

-- Çå³ıµØÍ¼AB°ó¶¨
function jobrun.ab_clear_map(map_name)
    local m = STORE.maps[map_name]
    if not m then return nil, "µØÍ¼²»´æÔÚ" end
    m.ab = nil
    if STORE.map_save and not STORE.map_save(map_name) then
        return nil, "µØÍ¼ÂäÅÌÊ§°Ü"
    end
    return true
end

-- ÏÂ·¢µØÍ¼AB(0x24); ÎŞ°ó¶¨Ê±ÏÂ·¢È«Áã(StartState=0, ¹Ì¼şÇå¿Õ²¢µÈ´ıĞĞ³Ì¿ª¹ØÉèA)
function jobrun.ab_send_map(m)
    local t
    if m and m.ab and m.ab.has then
        t = { StartN = m.ab.sn, StartE = m.ab.se, EndBN = m.ab.en, EndBE = m.ab.ee,
              StartDir = m.ab.sdir, CalcDir = m.ab.cdir,
              StartState = 1, CalcDirFlag = 1, OffLen = 0, BDOffTime = 100 }
    else
        -- QT communication.cpp:591 setEmptyABLine: È«Áã, StartState=0
        -- -> ¹Ì¼ş protocol.c:284 Çå¿ÕBDParam, µØÍ·ĞĞ³Ì¿ª¹Ø´¥·¢ºó²ÅÉèAµã¿ª²¥
        t = { StartN = 0, StartE = 0, EndBN = 0, EndBE = 0,
              StartDir = 0, CalcDir = 0, StartState = 0, CalcDirFlag = 0,
              OffLen = 0, BDOffTime = 0 }
    end
    PROTOCOL.send(PROTOCOL.FNC.SET_AB, ab_pack(t))
end

-------------------------------------------------------------------- Æô¶¯(QT :269)
-- opts: { resume=bool } Ğø½ÓÊ± path ½ø¶ÈÓÉ store ¶ÏµãÍÆ
function jobrun.start(task_name, opts)
    opts = opts or {}
    if J then return nil, "ÒÑÓĞ×÷Òµ½øĞĞÖĞ" end
    local t = STORE.tasks[task_name]
    if not t then return nil, "ÈÎÎñ²»´æÔÚ" end
    local m = STORE.maps[t.map]
    if not m then return nil, "µØÍ¼È±Ê§" end

    local path, err = PATHALGO.create_path(m, t.path_type, t.positive == 1)
    if not path then return nil, err end

    -- ¶ÏµãĞø×÷: ÕÒµ½µÚÒ»¸öÎ´Íê³É×éµÄ½Úµã×÷ÎªÆğµã
    local start_idx = 1
    if opts.resume then
        local bet = PATHALGO.block_each_trip(m)
        for i, pn in ipairs(path) do
            local blk = t.blocks[pn.row] and t.blocks[pn.row][pn.column]
            if not blk or (blk.sow == 1 and blk.state ~= 2) then
                start_idx = i
                break
            end
        end
    end

    -- AB ²Î¿¼(QT :278-284: ÎŞABÏßÊ±Ã¿´ÎÆô¶¯ÓÃÆğµã¸üĞÂ aRow/·½Ïò)
    -- Õæ»ú»¯(2026-09-10): ·½Ïò¸ÄÓÃ #AB.abdir(QT ABLineDirection bool);
    -- ´ËÇ°ÎóÓÃ sdir(StartDir º½Ïò½Ç)==1 ºãfalse, ÇÒ has Î´ÖÃÎ»,
    -- ÆÁ¶ËÒ»Ö±°´"ÎŞABÏß"µ÷¶È(TXFlag/start_pos/·­×ªÈ«´í), sim ²»Ğ£Ñé¹ÊÎ´±©Â¶
    local ab
    if m.ab and m.ab.has then
        ab = { has = true, dir = (m.ab.abdir or 0) == 1,
               a_row = m.ab.a_row or 0 }
    else
        local pn = path[start_idx]
        ab = { has = false, dir = pn.positive, a_row = pn.row }
    end

    J = {
        task = task_name, m = m, path = path, ab = ab,
        next_idx = start_idx, cur_col = path[start_idx].column,
        cur_read_row = -1, enter_map = false, sow_state = false,
        temp_idx = start_idx, fine = STORE.cfg and STORE.cfg.fine_tune or nil,
        disp_row = m.rows - path[start_idx].row,
    }

    -- ×´Ì¬Õ¹Ê¾: Ö÷Ò³ taskinfo / TW Ò³
    if APP then APP.set_always_poll(PROTOCOL.FNC.GET_BZ_STATUS) end
    log("INF", ("×÷ÒµÆô¶¯ %s µØÍ¼=%s Â·¾¶=%d Æğµã×é=%d"):format(
        task_name, m.name, t.path_type, start_idx))

    -- 2026-09-23 ¶ÔÆëQT(dialogrealtimetask.cpp:559-568): Æô¶¯ÏÈÏÂ·¢ABÏß¡ª¡ª
    -- ÓĞ°ó¶¨->´æ´¢Öµ(StartState=1); ÎŞ°ó¶¨->È«Áã(StartState=0, ¹Ì¼şÇå¿ÕBDParam,
    -- µØÍ·µÈ´ıĞĞ³Ì¿ª¹Ø´¥·¢ÉèAµãºó²Å¿ª²¥)¡£´ËÇ°ÆÁ¶Ë´Ó²»·¢0x24, ÏÂÎ»»úÑØÓÃÉÏ´Î
    -- ³Ö¾Ã»¯µÄStartState=1, ÎŞABÏßÈÎÎñÌø¹ı´¥·¢Ö±½Ó¿ª²¥(ÓÃ»§Áªµ÷±©Â¶)¡£
    jobrun.ab_send_map(m)

    -- QT :275-300: Æô¶¯Ê±ÏÈÏÂ·¢Ê×¸ö½Úµã²ÎÊı(Í¼Íâ²¥ÖÖ=´ÓÍ¼ÍâÅÅ¿ªÊ¼, ·ñÔòÊ×ÅÅ)
    local pn = path[J.next_idx]
    if (t.sow_exceed == 1) then
        J.cur_read_row = pn.positive and -1 or m.rows   -- Í¼ÍâĞéÄâÅÅ
        J.enter_map = false
        send_node(J.cur_read_row, J.cur_col)
    else
        J.enter_map = true
        send_node(pn.row, J.cur_col)
    end
    -- ²»Ô¤ÖÃ mark_dispatched(QT state=1 ½öÓÉÔÚ²¥Ö¡½¨Á¢: ĞĞ³Ì²»·û±£»¤,
    -- ¼û advance() ÄÚ×¢ÊÍ; resume É¨Ãè°´ state~=2 ÅĞÎ´Íê³É, ²»ÊÜÓ°Ïì)
    PROTOCOL.send(PROTOCOL.FNC.CMD_START_BZ)       -- 0x0A
    J.sow_state = true
    return true
end

-------------------------------------------------------------------- Í£Ö¹(QT :305)
-- Ö÷Ò³Í£Ö¹°´Å¥Î¨Ò»ÊÕÎ²Èë¿Ú; 0x0B ÎŞÌõ¼ş¼±Í£(º¬ÎŞÈÎÎñÊ±Âã·¢),
-- ÓĞ×÷ÒµÊ±»ØÍË¶Ïµã(QT :306-307)+¹éµµ+ÇåÏÖ³¡(ÔÊĞíºóĞøĞÂÈÎÎñ/Ğø×÷)
-- QT :310-311: µØÍ¼ÎŞABÏßÊ±Í£Ö¹µ¯"ÊÇ·ñ±£´æABÏß?" -> 2026-09-24 ¶ÔÆë:
-- Í£Ö¹Ê±Ğ´ LW.ABP.auto_req=1, »­Ãæ²à"´ò¿ªAB¶Ô»°¿ò"¹¦ÄÜ°´Å¥ÒÔÌõ¼ş´¥·¢Áª¶¯µ¯³ö
-- (ÃÉ°æ°ëÍ¸Ã÷Ä£Ì¬), ÓÃ»§ÃüÃûºóÈ·ÈÏ²Å±£´æ(µÈ¼ÛQTµÄYes+Ãû³ÆÊäÈë), È¡ÏûÔò²»´æ¡£

function jobrun.stop()
    PROTOCOL.send(PROTOCOL.FNC.CMD_STOP_BZ)        -- 0x0B
    if not J then return true end
    -- ABÏß±£´æ½¨Òé(QT signalStopSow :310-311): ÎŞ°ó¶¨µØÍ¼ -> ²É¼¯ÌîÏÔÊ¾ + ÇëÇóµ¯´°
    if not (J.m.ab and J.m.ab.has) then
        pending_ab = { map = J.m.name, a_row = J.ab and J.ab.a_row or 0,
                       dir = J.ab and J.ab.dir or false }
        ab_dlg_mode = 1                            -- Ô¤ÖÃ±£´æÄ£Ê½(µ¯´°ÒÑ´øÄ¿µÄ)
        ab_dlg_map = J.m.name
        w16(LW.ABP.mode, 0)
        wstr(LW.ABP.name, "")
        PROTOCOL.send(PROTOCOL.FNC.STORE_AB)       -- 0x23 ²É¼¯ÌîÏÔÊ¾
        w16(LW.ABP.auto_req, 1)                    -- »­Ãæ¹¦ÄÜ°´Å¥Ìõ¼ş´¥·¢µ¯´°
        log("INF", "µØÍ¼ÎŞABÏß, Í£Ö¹ºó½¨Òé±£´æ: " .. J.m.name)
    end
    if not J.completed then
        -- QT :306-307: Í£Ö¹Ê±µ±Ç°¿éÒÑÍê³ÉÔò next_idx »ØÍËµ½ temp_idx(ÏÂ´ÎĞø×÷Æğµã)
        local pn = J.path[J.next_idx]
        if pn then
            local blk = STORE.tasks[J.task].blocks[pn.row]
                and STORE.tasks[J.task].blocks[pn.row][J.cur_col]
            if blk and blk.state == 2 then
                J.next_idx = J.temp_idx
            end
        end
    end
    J.sow_state = false
    log("INF", "×÷ÒµÍ£Ö¹ " .. J.task)
    jobrun.detach()
    J = nil
    return true
end

-- ±£ÁôÏÖ³¡½öÍ£ÂÖÑ¯(µôµç»Ö¸´/Ò³ÃæÕ¹Ê¾ÓÃ)
function jobrun.detach()
    if APP then APP.set_always_poll(nil) end
end

-------------------------------------------------------------------- ABÏß¶Ô»°¿ò(LW.ABP)
-- »­Ãæ22³ĞÔØ(¹¦ÄÜ°´Å¥"´ò¿ª¶Ô»°¿ò"µ¯³ö, ÃÉ°æ°ëÍ¸Ã÷Ä£Ì¬); ×Ö¶ÎÏÔÊ¾¿Ø¼ş°ó LW.AB Çø,
-- 0x23 Ó¦´ğ¾­È«¾ÖÂ·ÓÉ×Ô¶¯Ìî³ä¡£Ãû³ÆÊäÈëÎªÎÄ±¾¿Ø¼ş(ĞéÄâ¼üÅÌ)¶ÁĞ´ LW.ABP.name¡£
-- ½»»¥: »­Ãæ°´Å¥Ö´ĞĞÍ¨ÖªĞ´ LW.ABP.req(1±£´æ/2²é¿´) -> ²É¼¯+¿ª´°;
--       È·ÈÏ(¹Ø±Õ¶Ô»°¿ò+Í¨Öªconfirm) -> ÃüÃû±£´æµ½µØÍ¼+RW; È¡Ïû -> ¶ªÆú¡£
local function rstr_safe(addr)
    if RSTR then
        local ok, s = pcall(RSTR, addr)
        if ok and type(s) == "string" then return s end
    end
    return ""
end

function jobrun._ab_dlg_on_update(addr)
    if addr == LW.ABP.req then
        local v = (r16 and r16(LW.ABP.req)) or 1
        jobrun.ab_dlg_open(v == 2 and 2 or 1)
    elseif addr == LW.ABP.confirm then
        jobrun.ab_dlg_confirm()
    elseif addr == LW.ABP.cancel then
        ab_dlg_mode = 0
        pending_ab = nil
        w16(LW.ABP.auto_req, 0)
        wstr(LW.A.tip, "ABÏßÎ´±£´æ")
    end
end

-- ´ò¿ªÇëÇó(mode 1=±£´æÃüÃû 2=²é¿´): ÌîÄ£Ê½/Ãû³Æ, ·¢0x23²É¼¯
-- Ä¿±êµØÍ¼ÓÅÏÈ¼¶: ×÷ÒµÖĞ=µ±Ç°ÈÎÎñµØÍ¼ > Í£Ö¹¿ìÕÕ > Ò³ÃæÌáÊ¾(jobrun.ab_hint_map,
-- µØÍ¼µ¼ÈëÒ³Ñ¡ÖĞĞĞÉèÖÃ) > ±£³ÖÉÏ´Î
function jobrun.ab_dlg_open(mode)
    ab_dlg_mode = mode
    if J and J.m then ab_dlg_map = J.m.name
    elseif pending_ab then ab_dlg_map = pending_ab.map
    elseif jobrun.ab_hint_map then ab_dlg_map = jobrun.ab_hint_map end
    w16(LW.ABP.mode, mode == 2 and 1 or 0)      -- LW¿Ú¾¶: 0±£´æ 1²é¿´
    if mode == 2 then
        local m = ab_dlg_map and STORE.maps[ab_dlg_map]
        wstr(LW.ABP.name, (m and m.ab and m.ab.name) or "")
    else
        wstr(LW.ABP.name, "")
    end
    PROTOCOL.send(PROTOCOL.FNC.STORE_AB)
end

-- È·ÈÏ±£´æ: ÒÔ¶Ô»°¿òÊäÈëÃû³Æ°ó¶¨µØÍ¼(#AB¶ÎÂäÅÌ) + ´æRW; AÅÅ/·½ÏòÓÃÍ£Ö¹¿ìÕÕ
-- (ÑÏ¸ñÒªÇó±¾´Î¿ª´°ºóÒÑÓĞ0x23Ó¦´ğ, ²»»ØÍËRW¾É»º´æ¡ª¡ª±ÜÃâ±£´æ¹ıÆÚÊı¾İ)
function jobrun.ab_dlg_confirm()
    if ab_dlg_mode ~= 1 then
        ab_dlg_mode = 0
        w16(LW.ABP.auto_req, 0)
        return
    end
    ab_dlg_mode = 0
    w16(LW.ABP.auto_req, 0)
    if not (ab_dlg_map and STORE.maps[ab_dlg_map]) then
        wstr(LW.A.tip, "¡Á ÎŞÄ¿±êµØÍ¼")
        return
    end
    jobrun.ab_cache = jobrun.ab_cache
    if not jobrun.ab_cache then
        wstr(LW.A.tip, "¡Á ABÏß²É¼¯ÎŞÓ¦´ğ, Î´±£´æ")
        return
    end
    local name = rstr_safe(LW.ABP.name)
    if name == "" then name = ab_dlg_map end
    local pa = pending_ab
    local ok, err = jobrun.ab_bind_map(ab_dlg_map, name, pa)
    if ok then
        jobrun.ab_rw_save()
        wstr(LW.A.tip, "¡Ì ABÏßÒÑ±£´æ " .. name)
        log("INF", ("ABÏß±£´æ %s -> µØÍ¼%s"):format(name, ab_dlg_map))
    else
        wstr(LW.A.tip, "¡Á " .. tostring(err))
    end
    pending_ab = nil
end

-------------------------------------------------------------------- 200ms ×´Ì¬»ú
-- QT :330-473 signalGetSowStatus ºËĞÄ·ÖÖ§(È¥³ıÍÏÀ­»úÍ¼±ê/±í¸ñ¿ÉÊÓ»¯)
function jobrun._feed(f)
    local ok, st = pcall(CODEC.bzstatus.unpack, f.data)
    if not ok then return end

    -- È«¾Ö×´Ì¬ÇøË¢ĞÂ(page_home µÈ¼ÛÂß¼­, 0x21 ±»³£×¤½Ø»ñºóÓÉÕâÀïÍ³Ò»¹©Êı)
    -- 2026-09-10 ĞŞ: ²¹Æë voff/loufei/louzh(´ËÇ°×÷ÒµÖĞÂ©Ğ´ -> Ö÷Ò³ÁĞĞĞ³Ìºã0¡¢
    -- Â©ÖÖ/Â©Öê¼ÆÊı¶³½á); ÅÅºÅ¸ÄÏÔÊ¾ÅÅºÅ¿Ú¾¶(=Ò³Ãæ6/QT DisplayRowNum, rows-r),
    -- Í¼ÍâÖ¡(RowNum=-1/rows, ³öÍ¼µôÍ·)±£³Ö×î½üÍ¼ÄÚÖµ, ²»ÔÙÉÁ 65535
    if w16 then
        w16(LW.A.runstate, st.RunState)
        w16(LW.A.bdstate,  st.BdState)
        -- Õæ»úÓïÒå(QT :345-356): ÓĞABÏßÊ± VerticalOff ÏÔÊ¾Ç°·ûºÅ·­×ª
        --   pathType 0/1/2 ÇÒ ABÍ¬Ïò -> È¡·´; pathType 3/4/5 ÇÒ AB·´Ïò -> È¡·´
        --   ÎŞABÏß/ÎŞ×÷Òµ: Ô­Öµ(Á¬Ğø²¥ÖÖÒ³ÓëQT formcontinuoussowÍ¬¿Ú¾¶)
        local voff = st.VerticalOff
        if J and J.ab and J.ab.has and STORE and STORE.tasks[J.task] then
            local pt = STORE.tasks[J.task].path_type
            if pt <= 2 then
                if J.ab.dir then voff = -voff end
            else
                if not J.ab.dir then voff = -voff end
            end
        end
        if w32 then
            w32(LW.A.speed,  st.Speed)
            w32(LW.A.offlen, st.OffLen)
            w32(LW.A.voff,   voff)
        end
        local rn = st.RowNum
        if J and J.m and rn >= 0 and rn < J.m.rows then
            J.disp_row = J.m.rows - rn            -- Í¼ÄÚ: ÏÔÊ¾ÅÅºÅ(1»ù)
        end
        w16(LW.A.rownum, (J and J.disp_row) or rn)
        -- Â©·Ê/Â©Öê¼ÆÊı²»ÔÙĞ´AÇø(2026-09-24): ÏÔÊ¾Í³Ò»×ß²âÊÔÕï¶ÏÒ³
        -- td_loufei1-6/td_louzh1-6, AÇøÔ­µØÖ·(0x1009~0x100F)ÊÍ·Å
    end

    if not J then return end
    if st.RowNum <= -10000000 then return end        -- Î´¿ª²¥ÉÚ±ø(QT :399)
    if not J.sow_state then return end

    local t = STORE.tasks[J.task]
    local m = J.m
    local rows = m.rows
    local b = (t.sow_exceed == 1)
    local bet = PATHALGO.block_each_trip(m)

    if st.RowNum < 0 or st.RowNum >= rows then
        ---- Í¼Íâ: ±ß½çÅÅÍê³É(QT :403-409, ½ö setBlockState=2, ²»ÍÆ½ø²»ÏÂ·¢)
        if J.cur_read_row == 0 or J.cur_read_row == rows - 1 then
            STORE.task_mark_row_done(J.task, J.cur_read_row, J.cur_col, {}, now_s())
            -- 2026-09-11 ¶şĞŞ(ÓÃ»§Áªµ÷±©Â¶: sim ÖØÆôĞĞ³Ì¹éÁãºóÈÔÍÆµ½100%):
            --  ´ËÇ°´Ë´¦²¹ advance() ÏëÈÃ"ÌËÄ©³öÍ¼Ö¡¼´¹ÒÆğ", µ« QT Ã»ÓĞ ¡ª¡ª
            --  sim ÎŞ 0x20 Ê±°´Àï³Ì×Ô×ß, RowNum ÕÇ¹ı±ß½ç -> Í¼Íâ advance ->
            --  send_node ÖØ·¢ 0x20 ÖØĞÂÒıµ¼ sim, ĞĞ³Ì²»·ûÍÆ½øÁ´¸´»î;
            --  QT ½öÖÃ state=2 ¹Ò×¡¡£É¾ advance ¶ÔÆë(ÌËÍê³ÉÌáÊ¾¸ÄÓÉÍê³ÉÂÊ
            --  Í£ÖÍ±í´ï, Óë QT Ò»ÖÂ; Ğø×÷ÆğµãÈÔÓĞ stop »ØÍË+resume É¨ÃèË«±£ÏÕ)
            local d, tot = STORE.task_progress(J.task)
            if d >= tot then jobrun._complete() end
        end
        if b and st.RowNum ~= J.cur_read_row then
            send_node(st.RowNum, J.cur_col)          -- Í¼ÍâÖğÅÅÍÆ½ø
        end
    else
        ---- Í¼ÄÚ(QT :411-470)
        local pn = J.path[J.next_idx]
        if not pn then jobrun._complete(); return end

        -- QT :413-415: ¼ÇÂ¼×îĞÂÍê³ÉÅÅ, temp_idx=¸Ã½ÚµãÔÚpathÖĞµÄÏÂÒ»¸ö
        local ti = jobrun._index_of(st.RowNum, J.cur_col)
        if ti then
            J.temp_idx = ti % #J.path + 1
            t.last_r, t.last_c = st.RowNum, J.cur_col
        end

        local sow_flag = PATHALGO.is_sow(t, m, pn.row, J.cur_col, b)

        -- QT :446-458: ÕıÔÚ²¥ next_idx ÅÅ
        if st.RowNum == pn.row then
            if not J.enter_map then
                send_node(pn.row, J.cur_col)         -- ÈëÍ¼Ê×ÅÅ(½öÒ»´Î)
                J.enter_map = true
            end
            if sow_flag then STORE.task_mark_dispatched(J.task, pn.row, J.cur_col) end
        -- QT :459-470: ¸Õ×ßÍê next_idx ÅÅ ¡ú ¼Ç½á¹û + ÍÆ½ø
        elseif (function()
                    local blk = t.blocks[pn.row] and t.blocks[pn.row][J.cur_col]
                    return (blk and (blk.state == 1 or blk.state == 2)) or not sow_flag
                end)() then
            if sow_flag then
                -- QT :422-445: currentResult[i] Ñ¨Êı/·ÊÊıÈ¡×Ô LouZHCnt/LoufeiCnt
                local ents = {}
                for i = 0, bet - 1 do
                    local seed, fert = {}, {}
                    local base = i * (m.block_col or 1)
                    for k = 0, (m.block_col or 1) - 1 do
                        seed[k + 1] = st.LouZHCnt[base + k + 1] or 0
                        fert[k + 1] = st.LoufeiCnt[base + k + 1] or 0
                    end
                    ents[i + 1] = { state = 2, start_t = J.result_t0 or now_s(),
                                    end_t = now_s(), seed = seed, fert = fert }
                end
                STORE.task_mark_row_done(J.task, pn.row, J.cur_col, ents, now_s())
            end
            -- ÍÆ½ø(QT :469 + BµµĞŞÕı: Í¬²½ currentColumn; ¿çÌË¹ÒÆğ¼û advance)
            advance()
        end
    end
    J.cur_read_row = st.RowNum
    jobrun._refresh_ui()
end

-- QT :1106 getIndex: path ÖĞÕÒ {row,column} ½ÚµãĞòºÅ
function jobrun._index_of(row, column)
    for i, pn in ipairs(J.path) do
        if pn.row == row and pn.column == column then return i end
    end
    return nil
end

-- Â·¾¶È«³Ì×ßÍê(¶ÔÆë QT: ¼´Ê¹100%Ò²²»×Ô¶¯Í£»ú/²»Í£ÂÖÑ¯, ÍÏÀ­»úÈÔÔÚ
-- ĞĞÊ»Ğè³ÖĞøË¢ĞÂ×´Ì¬; ÓÉ²Ù×÷Ô±°´Ö÷Ò³"Í£Ö¹"°´Å¥ -> jobrun.stop() ÊÕÎ²¹éµµ)
function jobrun._complete()
    J.completed = true
    J.sow_state = false                            -- Í£ÍÆ½ø, ²»ÔÙÏÂ·¢ĞÂ½Úµã
    if STORE then STORE.task_save(J.task) end
    log("INF", "×÷ÒµÍê³É(´ıÊÖ¶¯Í£Ö¹) " .. J.task)
    jobrun._refresh_ui()
end

-- Ö÷Ò³½ø¶ÈÎÄ±¾ LW.A.taskinfo: "ÈÎÎñ1 12/24 50%"
function jobrun._refresh_ui()
    if not (wstr and J) then return end
    local d, tot, pct = STORE.task_progress(J.task)
    local s = ("%s %d/%d %d%%"):format(J.task, d, tot, pct)
    if J.completed then s = s .. " ÒÑÍê³É"
    elseif J.trip_wait then s = s .. " ±¾ÌËÍê³É" end
    wstr(LW.A.taskinfo, s)
end

return jobrun

]==]

_MODS["page_task.lua"] = [==[
--[[
page_task.lua ¡ª¡ª ÈÎÎñ×÷ÒµÒ³(»­Ãæ6, 2026-09-24ÖØ¹¹)
================================================================================
Ô­4²½Ïòµ¼ÒÑÉ¾³ı, ·ÂQTÊµÊ±ÈÎÎñÒ³½á¹¹:
  ÅäÖÃ(tstate=1): µØÍ¼ÁĞ±íÑ¡Ôñ + ÈÎÎñ²ÎÊıÇø(Â·¾¶·½Ê½/·½Ïò/ÆğÊ¼ÅÅ/ÆğÊ¼ÁĞ/Í¼Íâ²¥ÖÖ)
        -> [´´½¨ÈÎÎñ] Ö»´´½¨²»Æô¶¯(QT´´½¨ºóÓÉ¿ªÊ¼¼üÖ´ĞĞ)
  ¾ÍĞ÷(tstate=4): ÈÎÎñÒÑ´´½¨´ı¿ªÊ¼ -> [¿ªÊ¼×÷Òµ] JOBRUN.start
  ×÷Òµ(tstate=2): jobrun.snapshot ÇáË¢ĞÂ; [¿ªÊ¼]=ĞøÌËÂã·¢0x0A; [Í£Ö¹]=ÊÕÎ²
        (ÎŞABÏßµØÍ¼Í£Ö¹ºóµ¯AB±£´æ¶Ô»°¿ò, ¼û jobrun stop/LW.ABP)
  Íê³É(tstate=3): ´ıĞø½Ó/·µ»ØÅäÖÃ
AB²Ù×÷: ²é¿´/±£´æ=»­Ãæ¹¦ÄÜ°´Å¥(´ò¿ª¶Ô»°¿ò»­Ãæ22+Ö´ĞĞÍ¨ÖªLW.ABP.req, jobrun´¦Àí);
        µ¼Èë/Çå³ı=×ÖÉèÖÃ°´Å¥(±¾Ò³´¦Àí, ×÷ÓÃÓÚËùÑ¡/µ±Ç°µØÍ¼)¡£
UÅÌµ¼ÈëÒÑÒÆÖÁµØÍ¼µ¼ÈëÒ³(page_map.lua, »­Ãæ9)¡£
ÒÀÀµ×¢Èë: creator(ctx) Í¬ÏÖÓĞÒ³ÃæÄ£Ê½¡£
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, PATHALGO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.PATHALGO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6                  -- ÁĞ±í´°¿ÚĞĞÊı

    -- Ò³ÃæÏÖ³¡(·Ç³Ö¾Ã): ÅäÖÃÌ¬µÄÑ¡ÔñÓëÒÑ´´½¨ÈÎÎñÃû
    local W = { map = nil, task = nil, sel = 0, top = 0, items = {} }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function render_list()
        local lines = {}
        for i = W.top + 1, math.min(W.top + LIST_ROWS, #W.items) do
            local mark = (i == W.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. W.items[i]
        end
        while #lines < 1 do lines[1] = " " end
        wstr(LW.TW.list, table.concat(lines, "\r\n"))
        w16(LW.TW.count, #W.items)
        w16(LW.TW.selidx, W.sel)
    end

    -- ÅäÖÃÌ¬ÁĞ±í: µØÍ¼Çåµ¥
    local function cfg_items()
        W.items = {}
        if STORE then
            for _, n in ipairs(STORE.map_list()) do
                W.items[#W.items + 1] = n .. " " .. STORE.map_spec(n)
            end
        end
        if #W.items == 0 then W.items[1] = "(ÎŞµØÍ¼, Çëµ½µØÍ¼µ¼ÈëÒ³)" end
    end

    -- Ñ¡¶¨µØÍ¼: ÕªÒª + Ä¬ÈÏÆğÊ¼Ğ¡Çø(Â·¾¶Ëã·¨Ê×½Úµã)
    local function pick_map(name)
        local m = STORE and STORE.map_get(name)
        if not m then return end
        W.map = name
        wstr(LW.TW.mapinfo, name .. " " .. STORE.map_spec(name))
        if PATHALGO then
            local path = PATHALGO.create_path(m, r16(LW.TW.path_type) or 0,
                                              r16(LW.TW.positive) == 1)
            if path and path[1] then
                w16(LW.TW.start_row, m.rows - path[1].row)
                w16(LW.TW.start_col, path[1].column + 1)
            end
        end
        -- Â·¾¶·½Ê½/·½Ïò±ä»¯Ê±ÖØËãÄ¬ÈÏÆğµã
    end

    local function goto_state(n)
        w16(LW.TW.tstate, n)
        W.sel, W.top = 0, 0
        if n == 1 then
            cfg_items()
            wstr(LW.TW.detail, "Ñ¡µØÍ¼ Éè²ÎÊı ºó´´½¨ÈÎÎñ")
            if W.map then pick_map(W.map) end
        elseif n == 4 then
            wstr(LW.TW.detail, "ÈÎÎñÒÑ´´½¨ °´[¿ªÊ¼×÷Òµ]Ö´ĞĞ")
        elseif n == 2 then
            wstr(LW.TW.detail, "×÷ÒµÖĞ " .. tostring(W.task or ""))
        elseif n == 3 then
            wstr(LW.TW.detail, "ÒÑÍ£Ö¹ ¿ÉĞø½Ó»ò·µ»ØÅäÖÃ")
        end
        render_list()
    end

    ------------------------------------------------------------------ AB²Ù×÷
    -- ²é¿´/±£´æ: »­Ãæ¹¦ÄÜ°´Å¥´ò¿ª¶Ô»°¿ò(Ğ´LW.ABP.req), jobrunÓ°×ÓÒ³È«¾Ö´¦Àí;
    -- ±¾Ò³Ö»´¦Àí µ¼Èë/Çå³ı(×ÖÉèÖÃ°´Å¥), Ä¿±ê=ÅäÖÃÌ¬ËùÑ¡µØÍ¼ »ò ×÷ÒµÌ¬µ±Ç°µØÍ¼
    local function ab_target_map()
        if JOBRUN and JOBRUN.active() then
            local s = JOBRUN.snapshot()
            if s then return s.map end
        end
        return W.map
    end

    local function on_ab_btn(addr)
        if addr ~= LW.TW.ab_import and addr ~= LW.TW.ab_clear then return end
        local map_name = ab_target_map()
        if not map_name then
            wstr(LW.TW.detail, "ÇëÏÈÑ¡ÔñµØÍ¼")
            return
        end
        if addr == LW.TW.ab_import then
            if not JOBRUN.ab_cache then
                JOBRUN.ab_cache = JOBRUN.ab_rw_load()   -- RW»º´æ -> °ó¶¨µØÍ¼
            end
            local ok, err = JOBRUN.ab_bind_map(map_name)
            wstr(LW.TW.detail, ok and ("ABÏßÒÑ°ó¶¨ " .. map_name)
                                   or ("°ó¶¨Ê§°Ü " .. tostring(err):sub(1, 20)))
        else
            local ok, err = JOBRUN.ab_clear_map(map_name)
            wstr(LW.TW.detail, ok and ("ABÏßÒÑÇå³ı " .. map_name)
                                   or ("Çå³ıÊ§°Ü " .. tostring(err):sub(1, 20)))
        end
    end

    ------------------------------------------------------------------ °´Å¥
    local function on_btn(addr, val)
        if val ~= 1 then return end
        local ts = r16(LW.TW.tstate) or 1

        -- ÁĞ±í·­Ñ¡(ÅäÖÃÌ¬)
        if addr == LW.TW.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
        elseif addr == LW.TW.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()

        elseif addr == LW.TW.btn_sel then
            -- ÅäÖÃÌ¬: Ñ¡ÖĞÁĞ±íÏîÎªµ±Ç°µØÍ¼
            if ts == 1 and STORE then
                local names = STORE.map_list()
                local name = names[W.sel + 1]
                if name then pick_map(name) end
            end

        elseif addr == LW.TW.btn_ok then
            -- ´´½¨ÈÎÎñ(²»×Ô¶¯¿ªÊ¼, 2026-09-24ÓÃ»§¾ö²ß: ÉèÖÃÍê²ÎÊıµã¿ªÊ¼ÔÙÖ´ĞĞ)
            local m = STORE and STORE.map_get(W.map)
            if not m then
                goto_state(1)
                wstr(LW.TW.detail, "ÇëÏÈÑ¡ÔñµØÍ¼")
                return
            end
            local drow = math.max(0, math.min(m.rows - 1,
                m.rows - (r16(LW.TW.start_row) or m.rows)))
            local dcol = math.max(0, math.min(m.cols - 1,
                (r16(LW.TW.start_col) or 1) - 1))
            local seq = #STORE.task_list() + 1
            local name = "ÈÎÎñ" .. seq
            local ok, err = STORE.task_create(name, W.map,
                r16(LW.TW.path_type) or 0, r16(LW.TW.positive) or 0,
                r16(LW.TW.sow_exceed) or 0, drow, dcol, NOW())
            if not ok then
                log("ERR", "ÈÎÎñ´´½¨Ê§°Ü: " .. tostring(err))
                wstr(LW.TW.detail, "´´½¨Ê§°Ü " .. tostring(err):sub(1, 20))
                return
            end
            W.task = name
            log("CMD", ("´´½¨ÈÎÎñ %s µØÍ¼=%s"):format(name, W.map))
            goto_state(4)

        elseif addr == LW.TW.btn_start then
            if ts == 4 and W.task then
                local ok, err = JOBRUN.start(W.task)
                if ok then
                    goto_state(2)
                else
                    wstr(LW.TW.detail, "Æô¶¯Ê§°Ü " .. tostring(err):sub(1, 20))
                end
            elseif ts == 2 then
                -- ×÷ÒµÖĞ¿ªÊ¼¼ü: ÌË¼ä¹ÒÆğÌáÊ¾ÏÈÍ£Ö¹, ·ñÔòÂã·¢0x0AĞø²¥(QTÓïÒå)
                if JOBRUN.active() then
                    local s = JOBRUN.snapshot()
                    if s and s.trip_wait then
                        wstr(LW.TW.detail, "±¾ÌËÒÑÍê³É ÇëÏÈ°´Í£Ö¹")
                    else
                        ctx.PROTOCOL.send(ctx.PROTOCOL.FNC.CMD_START_BZ)
                    end
                end
            end

        elseif addr == LW.TW.btn_stop then
            if JOBRUN then
                JOBRUN.stop()
                goto_state(3)
            end

        elseif addr == LW.TW.btn_cancel then
            -- ·µ»ØÅäÖÃ(²»É¾³ıÒÑ½¨ÈÎÎñ)
            goto_state(1)

        elseif addr == LW.TW.btn_resume then
            -- Ğø½Ó×î½üµÄÎ´Íê³ÉÈÎÎñ
            for _, n in ipairs(STORE.task_list()) do
                local t = STORE.task_get(n)
                if t then
                    local d, tot = STORE.task_progress(n)
                    if d < tot then
                        W.task = n
                        local ok, err = JOBRUN.start(n, { resume = true })
                        if ok then goto_state(2)
                        else wstr(LW.TW.detail, tostring(err):sub(1, 20)) end
                        return
                    end
                end
            end
            wstr(LW.TW.detail, "ÎŞ¿ÉĞø½ÓÈÎÎñ")
        end
    end

    ------------------------------------------------------------------ Ò³Ãæ±í
    local page = {
        id = LW.SCREEN.TASK,
        poll_cmds = {},
        addrs = {
            LW.TW.btn_up, LW.TW.btn_down, LW.TW.btn_sel, LW.TW.btn_ok,
            LW.TW.btn_start, LW.TW.btn_stop, LW.TW.btn_cancel,
            LW.TW.btn_resume, LW.TW.ab_import, LW.TW.ab_clear,
        },
    }

    function page:on_enter()
        if JOBRUN.active() then
            local cs = JOBRUN.snapshot()
            if cs then W.task = cs.task end
            w16(LW.TW.tstate, (cs and cs.completed) and 3 or 2)
        else
            goto_state(1)
        end
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == ctx.PROTOCOL.FNC.GET_BZ_STATUS then
            job_view()
        end
    end

    function page:on_update(addr, val)           -- Ã°ºÅ¶¨Òå(app.lua Ã°ºÅµ÷ÓÃ)
        on_btn(addr, val)
        on_ab_btn(addr)
    end

    -- ×÷ÒµÊÓÍ¼Ë¢ĞÂ(0x21±»jobrun³£×¤½Ø»ñ, Ò³ÃæÓÃtick¼¶ÇáË¢ĞÂ)
    function job_view()
        if not JOBRUN.active() then
            if (r16(LW.TW.tstate) or 0) == 2 then w16(LW.TW.tstate, 3) end
            return
        end
        local s = JOBRUN.snapshot()
        if s then
            if s.completed then w16(LW.TW.tstate, 3) end
            w16(LW.TW.cur_row, s.rows and (s.rows - (s.cur_row or 0)) or 0)
            w16(LW.TW.cur_col, (s.cur_col or 0) + 1)
            w16(LW.TW.done_cnt, s.done or 0)
            w16(LW.TW.total_cnt, s.total or 0)
            w16(LW.TW.pct, s.pct or 0)
        end
    end

    page.on_tick = function()
        job_view()
    end

    return page
end

]==]

_MODS["page_history.lua"] = [==[
--[[
page_history.lua ¡ª¡ª ÀúÊ·¼ÇÂ¼Ò³(0x1900~, »­Ãæ7, Bµµ)
================================================================================
ÈÎÎñÁĞ±í(¶àĞĞ×Ö·û´®+ÉÏÏÂÒÆ) ¡ú ²é¿´Ã÷Ï¸(¸÷ÅÅ½á¹û) / µ¼³öUÅÌ / É¾³ı¡£
Ã÷Ï¸: ÈÎÎñ¹æ¸ñ + ÒÑÍê³ÉÅÅµÄ½á¹ûÕªÒª(ÆğÖ¹Ê±¼ä/Ñ¨·ÊºÏ¼Æ)¡£
--]]

return function(ctx)
    local LW = ctx.LW
    local STORE, LOGGER, FILEIO = ctx.STORE, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6
    local S = { sel = 0, top = 0, items = {} }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function task_names()
        return STORE and STORE.task_list() or {}   -- BµµÊı¾İ²ã½µ¼¶Èİ´í
    end

    local function refresh_list()
        S.items = {}
        for _, n in ipairs(task_names()) do
            local d, tot, pct = STORE.task_progress(n)
            S.items[#S.items + 1] = ("%s %d/%d"):format(n, d, tot)
        end
        local lines = {}
        for i = S.top + 1, math.min(S.top + LIST_ROWS, #S.items) do
            local mark = (i == S.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. S.items[i]
        end
        if #lines == 0 then lines[1] = " ÎŞ¼ÇÂ¼" end
        wstr(LW.HIST.list, table.concat(lines, "\r\n"))
        w16(LW.HIST.count, #S.items)
        -- 2026-09-10 ĞŞ: »ØĞ´Ñ¡ÖĞÏî/ÁĞ±íÊ×Ïî(´ËÇ°Ö»Ğ´ÁĞ±íÎÄ±¾, »­ÃæÊıÖµ¿Ø¼şºã0)
        w16(LW.HIST.selidx, S.sel)
        w16(LW.HIST.listtop, S.top)
    end

    local function selected_name()
        local names = task_names()
        return names[S.sel + 1]
    end

    local function render_detail()
        local n = selected_name()
        if not n then wstr(LW.HIST.detail, " "); return end
        local t = STORE.task_get(n)
        local lines = { ("%s µØÍ¼=%s"):format(n, t and t.map or "?") }
        if t then
            lines[#lines + 1] = ("Â·¾¶%d ·½Ïò%d Æğµã%d,%d"):format(
                t.path_type or 0, t.positive or 0,
                (t.outset and t.outset.r or 0) + 1,
                (t.outset and t.outset.c or 0) + 1)
            -- ½á¹ûÕªÒª: ×î½ü¼¸Ìõ(¾É->ĞÂÈ¡Î²²¿)
            local res = STORE.results[n] or {}
            local from = math.max(1, #res - 5)
            for i = from, #res do
                local e = res[i]
                local ss, fs = 0, 0
                for _, v in ipairs(e.seed or {}) do ss = ss + v end
                for _, v in ipairs(e.fert or {}) do fs = fs + v end
                lines[#lines + 1] = ("ÅÅ%s Ñ¨%d ·Ê%d %s"):format(
                    tostring(e.row), ss, fs,
                    (e.end_t or ""):sub(1, 10))
            end
            local d, tot, pct = STORE.task_progress(n)
            lines[#lines + 1] = ("Íê³É %d/%d %d%%"):format(d, tot, pct)
        end
        wstr(LW.HIST.detail, table.concat(lines, "\r\n"))
    end

    local function export_usb()
        local n = selected_name()
        if not n then return end
        if not FILEIO then log("ERR", "fileioÎ´×¢Èë"); return end
        local txt = STORE.export_task_text(n)
        -- UÅÌÎÄ¼şÃû±ØĞë´¿ASCII(ÆÁ¶ËÎÄ¼şÏµÍ³ÏŞÖÆ, Õæ»úÊµ²â), ÓÃ store.slug;
        -- µ¼³öµÄCSVÄÚÈİÀï #TASK ĞĞÈÔÊÇÖĞÎÄÏÔÊ¾Ãû
        local fname = "result_" .. (STORE.slug and STORE.slug(n) or n) .. ".csv"
        local ok, err = FILEIO.write_all("2:" .. fname, txt)
        log(ok and "INF" or "ERR",
            ok and ("µ¼³öÈÎÎñ " .. n .. " -> " .. fname)
               or ("µ¼³öÊ§°Ü " .. tostring(err)))
    end

    local page = {
        id = LW.SCREEN.HISTORY,                   -- »­ÃæºÅ(Êı×Ö, APP.set_screen Â·ÓÉ)
        on_enter = function()
            refresh_list()
            render_detail()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {                                 -- °´Å¥µØÖ·ÉùÃ÷(APP.by_addr Â·ÓÉ±ØĞè)
            LW.HIST.btn_up, LW.HIST.btn_down, LW.HIST.btn_view,
            LW.HIST.btn_exp, LW.HIST.btn_del,
        },
        on_update = function(self, addr, val)
            if val ~= 1 then return end
            if addr == LW.HIST.btn_up and S.sel > 0 then
                S.sel = S.sel - 1
                if S.sel < S.top then S.top = S.sel end
                refresh_list(); render_detail()
            elseif addr == LW.HIST.btn_down and S.sel < #S.items - 1 then
                S.sel = S.sel + 1
                if S.sel >= S.top + LIST_ROWS then S.top = S.sel - LIST_ROWS + 1 end
                refresh_list(); render_detail()
            elseif addr == LW.HIST.btn_view then
                render_detail()
            elseif addr == LW.HIST.btn_exp then
                export_usb()
            elseif addr == LW.HIST.btn_del then
                local n = selected_name()
                if n then
                    STORE.task_delete(n)
                    log("CMD", "É¾³ıÈÎÎñ " .. n)
                    if S.sel > 0 then S.sel = S.sel - 1 end
                    refresh_list(); render_detail()
                end
            end
        end,
    }
    return page
end

]==]

_MODS["page_logview.lua"] = [==[
--[[
page_logview.lua ¡ª¡ª ÈÕÖ¾²é¿´Ò³(0x1A00~, »­Ãæ8, Bµµ)
================================================================================
ÈÕÖ¾´°¿Ú¶àĞĞÏÔÊ¾(Î²²¿¶ÔÆë=×îĞÂÔÚÏÂ), ÉÏ/ÏÂ·­Ò³, Ìø×îĞÂ, Çå¿Õ, µ¼³öUÅÌ¡£
--]]

return function(ctx)
    local LW = ctx.LW
    local LOGGER, FILEIO = ctx.LOGGER, ctx.FILEIO
    local w16, wstr = ctx.w16, ctx.wstr

    local VIEW_ROWS = 8
    local top = 1                     -- ´°¿ÚÊ×Ìõ(1»ù, ¾É->ĞÂ)

    local function refresh()
        local cnt = LOGGER and LOGGER.count() or 0
        if cnt == 0 then
            top = 1
            wstr(LW.LOGV.view, " ÎŞÈÕÖ¾")
        else
            if top > cnt then top = math.max(1, cnt - VIEW_ROWS + 1) end
            if top < 1 then top = 1 end
            local lines = LOGGER.view(top, VIEW_ROWS)
            wstr(LW.LOGV.view, table.concat(lines, "\r\n"))
        end
        w16(LW.LOGV.count, cnt)
    end

    local page = {
        id = LW.SCREEN.LOGVIEW,                   -- »­ÃæºÅ(Êı×Ö, APP.set_screen Â·ÓÉ)
        on_enter = function()
            -- ½øÈëÊ±Ìøµ½×îĞÂ(Î²²¿)
            local cnt = LOGGER and LOGGER.count() or 0
            top = math.max(1, cnt - VIEW_ROWS + 1)
            refresh()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {                                 -- °´Å¥µØÖ·ÉùÃ÷(APP.by_addr Â·ÓÉ±ØĞè)
            LW.LOGV.btn_up, LW.LOGV.btn_down, LW.LOGV.btn_top,
            LW.LOGV.btn_clear, LW.LOGV.btn_exp,
        },
        on_update = function(self, addr, val)
            if val ~= 1 then return end
            local cnt = LOGGER and LOGGER.count() or 0
            if addr == LW.LOGV.btn_up then
                top = math.max(1, top - VIEW_ROWS)
                refresh()
            elseif addr == LW.LOGV.btn_down then
                top = math.min(math.max(1, cnt - VIEW_ROWS + 1), top + VIEW_ROWS)
                refresh()
            elseif addr == LW.LOGV.btn_top then
                top = math.max(1, cnt - VIEW_ROWS + 1)
                refresh()
            elseif addr == LW.LOGV.btn_clear then
                if LOGGER then
                    LOGGER.clear()
                    LOGGER.log("CMD", "ÈÕÖ¾Çå¿Õ")
                end
                top = 1
                refresh()
            elseif addr == LW.LOGV.btn_exp then
                if FILEIO and LOGGER then
                    local ok, err = FILEIO.copy("3:log.txt", "2:log_export.txt")
                    LOGGER.log(ok and "INF" or "ERR",
                        ok and "ÈÕÖ¾µ¼³ö" or ("µ¼³öÊ§°Ü " .. tostring(err)))
                    refresh()
                end
            end
        end,
    }

    return page
end

]==]

_MODS["page_map.lua"] = [==[
--[[
page_map.lua â€”â€” åœ°å›¾å¯¼å…¥é¡µ(ç”»é¢9, 2026-09-24æ–°å¢)
================================================================================
ä»¿QTåœ°å›¾ç®¡ç†é¡µçš„å±ç«¯å­é›†(åœ°å›¾åˆ›å»º/ç¼–è¾‘ç”±PCå¯¼å‡ºå·¥å…·è´Ÿè´£):
  åœ°å›¾åˆ—è¡¨(é€‰ä¸­) + è¯¦æƒ…æ‘˜è¦ + Uç›˜æ‰«æå¯¼å…¥(map_*.csv, æ–‡ä»¶åé¡»ASCII, æ˜¾ç¤ºåå–#MAP)
  + åˆ é™¤åœ°å›¾ + ABçº¿æ“ä½œ(æŸ¥çœ‹=å¯¹è¯æ¡†0x23å›æ˜¾ / å¯¼å…¥=RWç¼“å­˜ç»‘å®šæœ¬å›¾ / æ¸…é™¤=è§£ç»‘)
Uç›˜å¯¼å…¥é€»è¾‘è‡ªåŸä»»åŠ¡å‘å¯¼é¡µè¿ç§»(2026-09-24å‘å¯¼åˆ é™¤)ã€‚
LW: LW.MAP (0x1C00åŒº); ABæŸ¥çœ‹æŒ‰é’®=åŠŸèƒ½æŒ‰é’®(æ‰“å¼€å¯¹è¯æ¡†ç”»é¢22+é€šçŸ¥LW.ABP.req=2)ã€‚
ä¾èµ–æ³¨å…¥: creator(ctx) åŒç°æœ‰é¡µé¢æ¨¡å¼ã€‚
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, FILEIO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16

    local LIST_ROWS = 6
    local W = { sel = 0, top = 0, items = {} }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function render_list()
        local lines = {}
        for i = W.top + 1, math.min(W.top + LIST_ROWS, #W.items) do
            local mark = (i == W.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. W.items[i]
        end
        while #lines < 1 do lines[1] = " " end
        wstr(LW.MAP.list, table.concat(lines, "\r\n"))
        w16(LW.MAP.count, #W.items)
        w16(LW.MAP.selidx, W.sel)
        w16(LW.MAP.listtop, W.top)
    end

    local function selected_name()
        local names = STORE and STORE.map_list() or {}
        return names[W.sel + 1]
    end

    local function refresh()
        W.items = {}
        if STORE then
            for _, n in ipairs(STORE.map_list()) do
                W.items[#W.items + 1] = n .. " " .. STORE.map_spec(n)
            end
        end
        if #W.items == 0 then W.items[1] = "(æ— åœ°å›¾, è¯·æ‰«æUç›˜å¯¼å…¥)" end
        W.sel, W.top = 0, 0
        render_list()
        wstr(LW.MAP.detail, "")
    end

    local function show_detail()
        local n = selected_name()
        if not (n and STORE) then return end
        local m = STORE.map_get(n)
        if not m then return end
        JOBRUN.ab_hint_map = n                  -- ABå¯¹è¯æ¡†çš„é»˜è®¤ç›®æ ‡åœ°å›¾
        local ab = m.ab and ("å·²ç»‘AB " .. (m.ab.name or "?"))
                       or "æ— ABçº¿"
        wstr(LW.MAP.detail, ("%s %dæ’x%dåˆ— %s"):format(n, m.rows, m.cols, ab))
    end

    ------------------------------------------------------------------ Uç›˜å¯¼å…¥
    -- list_dir å›ºä»¶åŒæ—¶åº: å¼‚æ­¥ç» on_list_dir è·¯ç”± / åŒæ­¥è¿”å› table(è§ fileio.lua)
    local tick_n = 0
    local scan_deadline = nil
    local SCAN_TICKS = math.max(5, math.ceil(3000 / (ctx.poll_ms or 200)))

    local function usb_import()
        if not FILEIO then return end
        if not STORE then wstr(LW.MAP.detail, "æ•°æ®å±‚ä¸å¯ç”¨"); return end
        if scan_deadline then wstr(LW.MAP.detail, "æ‰«æä¸­,è¯·ç¨å€™"); return end
        wstr(LW.MAP.detail, "æ‰«æUç›˜ä¸­...")
        scan_deadline = tick_n + SCAN_TICKS
        local ok, err = FILEIO.list("2:", function(list, dir)
            scan_deadline = nil
            if not list then
                log("ERR", "åˆ—ç›®å½•å¤±è´¥ " .. tostring(dir))
                wstr(LW.MAP.detail, "æ‰«æå¤±è´¥(æœªæ’Uç›˜?)")
                return
            end
            if #list == 0 then                   -- è™šæ‹Ÿå±å›é€€: çº¦å®šæ¸…å• 2:maps.txt
                local lines = FILEIO.read_lines("2:maps.txt")
                if lines then
                    for i = 1, #lines do
                        if #lines[i] > 0 then list[#list + 1] = lines[i] end
                    end
                end
            end
            local imported, msgs = 0, {}
            for _, fnm in ipairs(list) do
                if type(fnm) == "string" and fnm:match("^map_.+%.csv$") then
                    local name = fnm:sub(5, -5)
                    local ok2, w2 = STORE.map_import_file("2:" .. fnm, name)
                    if ok2 then imported = imported + 1 else msgs[#msgs + 1] = w2 end
                end
            end
            log(imported > 0 and "INF" or "WRN",
                ("Uç›˜å¯¼å…¥ %d å¼ åœ°å›¾"):format(imported))
            if #msgs > 0 then log("ERR", msgs[1]) end
            wstr(LW.MAP.detail,
                imported > 0 and ("å¯¼å…¥%då¼ åœ°å›¾"):format(imported)
                or "æ— åœ°å›¾æ–‡ä»¶(æˆ–æœªæ’Uç›˜)")
            refresh()
        end)
        if not ok then
            scan_deadline = nil
            wstr(LW.MAP.detail, "Uç›˜ä¸å¯ç”¨")
            log("ERR", "Uç›˜æœªæ’å…¥æˆ–ä¸å¯è¯»")
        end
    end

    ------------------------------------------------------------------ æŒ‰é’®
    local function on_btn(addr, val)
        if val ~= 1 then return end
        if addr == LW.MAP.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
        elseif addr == LW.MAP.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()
        elseif addr == LW.MAP.btn_sel then
            show_detail()
        elseif addr == LW.MAP.btn_usb then
            usb_import()
        elseif addr == LW.MAP.btn_del then
            local n = selected_name()
            if n and STORE then
                STORE.map_delete(n)
                log("CMD", "åˆ é™¤åœ°å›¾ " .. n)
                wstr(LW.MAP.detail, "å·²åˆ é™¤ " .. n)
                refresh()
            end
        elseif addr == LW.MAP.ab_import then
            local n = selected_name()
            if not n then return end
            if JOBRUN then
                if not JOBRUN.ab_cache then
                    JOBRUN.ab_cache = JOBRUN.ab_rw_load()
                end
                local ok, err = JOBRUN.ab_bind_map(n)
                wstr(LW.MAP.detail, ok and ("ABçº¿å·²ç»‘å®š " .. n)
                                       or ("ç»‘å®šå¤±è´¥ " .. tostring(err):sub(1, 16)))
                show_detail()
            end
        elseif addr == LW.MAP.ab_clear then
            local n = selected_name()
            if n and JOBRUN then
                local ok, err = JOBRUN.ab_clear_map(n)
                wstr(LW.MAP.detail, ok and ("ABçº¿å·²æ¸…é™¤ " .. n)
                                       or ("æ¸…é™¤å¤±è´¥ " .. tostring(err):sub(1, 16)))
                show_detail()
            end
        end
    end

    local page = {
        id = LW.SCREEN.MAP,
        poll_cmds = {},
        addrs = {
            LW.MAP.btn_up, LW.MAP.btn_down, LW.MAP.btn_sel, LW.MAP.btn_del,
            LW.MAP.btn_usb, LW.MAP.ab_import, LW.MAP.ab_clear,
        },
    }

    function page:on_enter()
        refresh()
    end

    function page:on_leave() end

    function page:on_frame() end

    function page:on_update(addr, val)           -- å†’å·å®šä¹‰(app.lua å†’å·è°ƒç”¨)
        on_btn(addr, val)
    end

    page.on_tick = function()
        tick_n = tick_n + 1
        if scan_deadline and tick_n > scan_deadline then
            scan_deadline = nil
            wstr(LW.MAP.detail, "æ‰«ææ— å“åº”(æœªæ’Uç›˜?)")
            log("WRN", "list_dir å›è°ƒè¶…æ—¶(å¼‚æ­¥æ— æœ)")
        end
    end

    return page
end
]==]
-- END _MODS

--================ Ä£¿é¼ÓÔØ: dofile ÓÅÏÈ(¹Ù·½Ö§³Ö), load() ÄÚÇ¶¶µµ× =================
local function load_mod(name)
    local errs = {}
    if type(dofile) == "function" then
        local tries = { name, "/" .. name, "./" .. name }
        for i = 1, #tries do
            local ok, r = pcall(dofile, tries[i])
            if ok and (type(r) == "table" or type(r) == "function") then
                print("[HMI] " .. name .. " via dofile(" .. tries[i] .. ")")
                return r
            end
            errs[#errs + 1] = tries[i] .. "=>" .. tostring(r)
        end
    else
        errs[#errs + 1] = "dofile unavailable"
    end
    local src = _MODS[name]
    if src then
        local chunk, e = load(src, "@" .. name)
        if chunk then
            local ok2, r2 = pcall(chunk)
            -- page_*.lua ¶¥²ã return creator(ctx) º¯Êı¶ø·Ç table, Á½Õß¾ùÊÓÎª¼ÓÔØ³É¹¦
            if ok2 and (type(r2) == "table" or type(r2) == "function") then
                print("[HMI] " .. name .. " via EMBEDDED source")
                return r2
            end
            errs[#errs + 1] = "embed-run=>" .. tostring(r2)
        else
            errs[#errs + 1] = "embed-compile=>" .. tostring(e)
        end
    end
    print("[HMI] load " .. name .. " FAILED: " .. table.concat(errs, " | "))
    return nil, table.concat(errs, " | ")
end

--================ ×°Åä =================
local APP, PROTOCOL, CODEC, LWMAP
local FILEIO, CSV, STORE, PATHALGO, LOGGER, JOBRUN
local pages = {}

-- ÆÁ¶ËÊ±¼äÔ´(Bµµ): Æ½Ì¨Ê±¼ä API Î´ÑéÖ¤, ÍË»¯Îª¿ª»úÃë¼ÆÊı "T+<n>s"
-- (½ö½øÈÕÖ¾/½á¹ûÊ±¼ä×Ö¶Î, ²»²ÎÓëÒµÎñ¼ÆËã; ÊµÎïÑéÖ¤Ïî: Ìæ»»Îª¹Ù·½ RTC)
local tick_cnt = 0
local function now_s()
    return ("T+%ds"):format(tick_cnt // 2)   -- POLL_MS=500 -> 2´Î/Ãë
end

local function setup()
    LWMAP = load_mod("lwmap.lua")
    PROTOCOL = LWMAP and load_mod("protocol.lua")
    CODEC = PROTOCOL and load_mod("codec.lua")
    APP = CODEC and load_mod("app.lua")
    if not APP then return false end

    CODEC.init { rows = ROWS }
    APP.wire { PROTOCOL = PROTOCOL, CODEC = CODEC, LW = LWMAP }
    APP.init {
        w16 = w16, w32 = w32, wstr = wstr, r16 = r16, r32 = r32,
        tx = uart_tx, poll_ms = POLL_MS,
    }

    -- BµµÊı¾İ²ã(ÕûÌå pcall ¸ôÀë: 2026-09-08 ĞéÄâÆÁÊµ²â logger.init ¶Á 3:log.txt
    -- Ê± file_open ·µ»Ø boolean, ÀàĞÍ±È½ÏÒì³£ÔøÕ¨µôÕû¸ö on_init ÖÂ´®¿Ú¾²Ä¬;
    -- ÈÎÒ»»·½ÚÒì³£Ö»½µ¼¶ B µµ, ²»×è¶Ï A µµÒ³Ãæ×°Åä)
    FILEIO = load_mod("fileio.lua")
    if FILEIO then
        local okb, berr = pcall(function()
            FILEIO.wire()                          -- °ó¹Ù·½ file_*/list_dir/feed_dog È«¾Ö
            local apis, marks = FILEIO.apis(), {}  -- O-1 Ì½²â: ´òÓ¡Æ½Ì¨ÎÄ¼ş API ´æÔÚĞÔ
            for k, v in pairs(apis) do
                marks[#marks + 1] = (v and "+" or "-") .. k
            end
            table.sort(marks)
            print("[HMI] file api: " .. table.concat(marks, " "))
            CSV      = load_mod("csv.lua")
            STORE    = CSV and load_mod("store.lua") or nil
            if STORE then STORE.init(FILEIO, CSV, "3:") end
            PATHALGO = load_mod("pathalgo.lua")
            LOGGER   = load_mod("logger.lua")
            if LOGGER then
                LOGGER.init { fileio = FILEIO, path = "3:log.txt", cap = 500, now = now_s }
                LOGGER.log("SYS", "ÆÁ¶ËÆô¶¯")
            end
            JOBRUN   = STORE and load_mod("jobrun.lua") or nil
            if JOBRUN then
                JOBRUN.init {
                    APP = APP, PROTOCOL = PROTOCOL, CODEC = CODEC,
                    STORE = STORE, PATHALGO = PATHALGO, LOGGER = LOGGER,
                    LW = LWMAP, w16 = w16, w32 = w32, wstr = wstr, now = now_s,
                    rw16 = rw16, rw16w = rw16w,     -- ABÏßRW³Ö¾Ã»¯(2026-09-23×Ôpage_ablineÇ¨Èë)
                    rstr = rstr, r16 = r16,         -- AB¶Ô»°¿ò: ¶ÁÃû³Æ/ÇëÇóÖµ(2026-09-24)
                }
            end
            if STORE then STORE.boot() end         -- µôµç»Ö¸´(¿ÕÆ¬Ê×Æô²»±¨´í)
        end)
        if not okb then
            CSV, STORE, PATHALGO, LOGGER, JOBRUN = nil, nil, nil, nil, nil
            wstr(LWMAP.A.log, "Bµµ×°ÅäÒì³£ÒÑ½µ¼¶(ÏêÇé¼ûprint)")
            print("[HMI] B-tier setup FAILED(½µ¼¶Aµµ): " .. tostring(berr))
        end
    else
        wstr(LWMAP.A.log, "fileio load fail(Bµµ¹¦ÄÜ²»¿ÉÓÃ)")
    end

    -- ¼ÓÔØÒ³ÃæÄ£¿é(creator ÊÕ ctx ·µ»Ø page ±í)
    local ctx = {
        APP = APP, PROTOCOL = PROTOCOL, CODEC = CODEC, LW = LWMAP,
        w16 = w16, w32 = w32, wstr = wstr, r16 = r16, r32 = r32,
        rw16 = rw16, rw16w = rw16w,
        FILEIO = FILEIO, STORE = STORE, JOBRUN = JOBRUN,
        LOGGER = LOGGER, PATHALGO = PATHALGO, now = now_s,
    }
    for _, name in ipairs(MODULES) do
        if name:sub(1, 5) == "page_" then
            local creator = load_mod(name)
            if type(creator) == "function" then
                local okp, page = pcall(creator, ctx)   -- creator Òì³£Ö»Ìø¹ı¸ÃÒ³
                if okp and type(page) == "table" then
                    APP.register(page)
                else
                    wstr(LWMAP.A.log, "page init fail: " .. name)
                    print("[HMI] page creator FAILED " .. name .. ": " .. tostring(page))
                end
            else
                wstr(LWMAP.A.log, "page load fail: " .. name)
            end
        end
    end
    return true
end

--================ ÏµÍ³»Øµ÷ =================
function on_init()
    print("[HMI] on_init enter")
    print("[HMI] api: set_uint16=" .. type(set_uint16) .. " set_int32=" .. type(set_int32)
        .. " set_string=" .. type(set_string) .. " get_uint16=" .. type(get_uint16)
        .. " uart_send=" .. type(uart_send) .. " uart_send_data=" .. type(uart_send_data))

    uart_free_protocol = 1                 -- ¿ªÆô×ÔÓÉ´®¿ÚĞ­Òé(±»¶¯»Øµ÷Ä£Ê½)
    if uart_set_timeout then uart_set_timeout(UART_CH, 0) end

    -- ·¢ËÍº¯ÊıÌ½²â(Ä£¿é¼ÓÔØÇ°ÏÈÅÅ³ıÆ½Ì¨APIÎÊÌâ)
    local txfn_addr = 0x1018
    if type(uart_send) == "function" then w16(txfn_addr, 1)
    elseif type(uart_send_data) == "function" then w16(txfn_addr, 2) end

    w16(0x1017, 1)                         -- Õï¶ÏÂë1: on_init ÒÑÖ´ĞĞ
    if not setup() then
        w16(0x1017, 3)                     -- Õï¶ÏÂë3: Ä£¿é¼ÓÔØÊ§°Ü
        wstr(0x1060, "module load FAILED (see print)")
        print("[HMI] module load FAILED")
        return
    end
    w16(0x1017, 2)                         -- Õï¶ÏÂë2: Ä£¿éOK½øÈëÂÖÑ¯

    set_run_cycle(POLL_MS)                 -- on_run ÂÖÑ¯ÖÜÆÚ(½ö on_init ÉèÖÃ)
    APP.set_screen(LWMAP.SCREEN.HOME)      -- ³õÊ¼Ò³: ´¥·¢ on_enter(°æ±¾²éÑ¯=Á´Â·×Ô¼ì)

    print("[HMI] on_init done")
end

function on_run(screen)
    tick_cnt = tick_cnt + 1
    if APP then APP.tick() end             -- ĞÄÌø+µ±Ç°Ò³ÂÖÑ¯(½ÚÁ÷ÔÚ APP)
    if FILEIO then FILEIO.pump() end       -- list_dir ÌõÄ¿Á÷±Ã(¾²Ä¬³¬Ê±ÊÕ¸î)
end

-- ¹Ù·½ list_dir Òì²½»Øµ÷: Ã¿É¨Ãèµ½Ò»¸öÌõÄ¿µ÷ÓÃÒ»´Î(Ç©Ãû 2026-09-08 ºËÊµ):
--   path=Ä¿Â¼ / filename=ÌõÄ¿Ãû / type 0ÎÄ¼ş¼Ğ 1ÎÄ¼ş / fsize=×Ö½ÚÊı
local list_logged = false
function on_list_dir(path, filename, ftype, fsize)
    if not list_logged then
        list_logged = true
        print("[HMI] on_list_dir alive: " .. tostring(path) .. " "
            .. tostring(filename) .. " type=" .. tostring(ftype)
            .. " size=" .. tostring(fsize))
    end
    if FILEIO then FILEIO.on_list_dir(path, filename, ftype, fsize) end
end

-- UÅÌ²å°Î(¹Ù·½»Øµ÷): MÏµÁĞÅÌ·û "2"
function on_usb_inserted(driver)
    print("[HMI] usb inserted: " .. tostring(driver))
    if LOGGER then LOGGER.log("SYS", "UÅÌ²åÈë " .. tostring(driver)) end
end
function on_usb_removed()
    print("[HMI] usb removed")
    if LOGGER then LOGGER.log("SYS", "UÅÌ°Î³ö") end
end

-- ´®¿Ú½ÓÊÕ»Øµ÷: ¹Ù·½Ãû on_uart_recv(ch, data), data Îª×Ö·û´®
local uart_rx_logged = false
function on_uart_recv(ch, data)
    if ch ~= UART_CH then return end
    if APP then APP.diag(6) end            -- Õï¶ÏÂë6: ÊÕµ½´®¿Ú×Ö½Ú
    if not uart_rx_logged then
        uart_rx_logged = true
        print("[HMI] uart rx callback alive, ch=" .. tostring(ch))
    end
    if not PROTOCOL then return end
    PROTOCOL.feed_bytes(packet_to_str(data))
end
on_uart_recv_data = function(packet) on_uart_recv(UART_CH, packet) end

-- ¡¾¸ùÒò½ÌÑµ 2026-08-28¡¿¸´Î»Ö»¶ÔÒÑ×¢²á°´Å¥µØÖ·Ğ´0, ¾ø²»²¨¼°ÆäËû LW;
-- Î´×¢²áµØÖ·(ÊıÖµ¿Ø¼ş/Ğ­Òé×´Ì¬Ğ´Èë)Ò»ÂÉ·ÅĞĞ²»¸ÉÔ¤¡£
function on_update(slave, vtype, addr)
    if vtype ~= VT_LW then return end
    if not APP then return end
    local v = r16(addr)
    if v ~= 1 then return end              -- Ö»ÏìÓ¦Ğ´1
    APP.on_button(addr)                    -- Â·ÓÉµ½Ò³Ãæ(ÄÚ²¿¸´Î»°´Å¥)
end

function on_screen_change(screen)
    if APP then APP.set_screen(screen) end
end

function on_draw(screen_id, control_id)
end
