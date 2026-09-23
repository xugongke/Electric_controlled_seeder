_ENCRYPT_=0    --LUA脚本加密

--********************************************************************
-- 电控播种机 HMI 主程序(部署壳) —— 大彩 VisualHMI, 对接 hd3005a1 / sim_controller.py
--
-- 链路: 虚拟屏(串口0, 115200) <== 虚拟串口对 COM8<->COM9 ==>
--       python sim_controller.py --port COM9 --baud 115200
--
-- 【架构 2026-09-02】多文件模块化(dofile 官方支持, LUA API §9.1):
--   POC/lua/ 为唯一真源(protocol/codec/lwmap/app/page_*),
--   deploy_screen.py 同步文件到本目录 + 注入 _MODS 内嵌兜底区。
--   load_mod 优先 dofile 外部文件, 失败则 load() 内嵌源码。
--
-- 【联调诊断】画面上放数值控件绑 LW0x1017, 按其值定位故障环节:
--   0  = main.lua 完全没执行(工程未编译该脚本, 检查VisualHMI文件清单)
--   1  = on_init 已执行, 但模块加载失败 -> 看LW0x1060文本
--   2  = 模块加载成功, 进入正常轮询; 串口助手应周期收到查询帧
--   5  = 按钮已触发on_update   6  = 收到串口数据
-- LW0x1018 = 发送函数探测: 1=uart_send可用 2=uart_send_data可用 0=都没有(严重)
--********************************************************************

--数据类型定义
VT_LW = 1    --变量地址
VT_RW = 2    --FLASH存储

--================ 运行配置 =================
local UART_CH       = 0      -- 主串口（下位机接线口）
local POLL_MS       = 500    -- 状态轮询周期 ms
local ROWS          = 4      -- 下位机行数: 4=hd3005a1源码 / 6=平板版; 联调模拟器默认4
local TX_ONE_BASED  = true   -- 发送字节数组下标约定: true=从1起(大彩文档用法)

-- 模块清单(新页面在此追加, deploy_screen.py 同步扫描同列表)
local MODULES = {
    "lwmap.lua", "protocol.lua", "codec.lua", "app.lua",
    "page_home.lua", "page_params.lua", "page_cellpara.lua", "page_continuous.lua",
    "page_abline.lua", "page_testdiag.lua",
    -- B档新增: 文件IO/CSV/数据层/路径算法/作业调度/日志/3新页面
    "fileio.lua", "csv.lua", "store.lua", "pathalgo.lua", "logger.lua", "jobrun.lua",
    "page_task.lua", "page_history.lua", "page_logview.lua",
}

--================ 平台适配层 =================
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
local function r32(addr)
    if get_uint32 then return get_uint32(VT_LW, addr) end
    if get_uint16 then                            -- 降级: 拼两个 u16(小端)
        local lo = get_uint16(VT_LW, addr) or 0
        local hi = get_uint16(VT_LW, addr + 1) or 0
        return hi * 0x10000 + lo
    end
end

-- RW 掉电保持区读写(VT_RW=2); 虚拟屏支持存疑, 空片读回 nil
local function rw16(addr)
    if get_uint16 then return get_uint16(VT_RW, addr) end
end
local function rw16w(addr, v)
    if set_uint16 then set_uint16(VT_RW, addr, v & 0xFFFF) end
end

-- string -> 平台字节数组 -> 发送（兼容 uart_send / uart_send_data 两种平台函数名）
local function uart_tx(bytes)
    local fn = type(uart_send) == "function" and uart_send
            or type(uart_send_data) == "function" and uart_send_data
    if not fn then
        w16(0x1018, 0)                     -- 发送函数探测(=LW.A.txfn, 加载前硬编码)
        print("[HMI] uart_send/uart_send_data 均不存在")
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

-- 平台 packet 数组 -> string（自动兼容下标从0/从1两种约定）
local function packet_to_str(packet)
    if type(packet) ~= "table" then return tostring(packet) end
    local t, i = {}, 0
    while packet[i] ~= nil do             -- 0-based 遍历
        t[#t + 1] = string.char(packet[i] & 0xFF)
        i = i + 1
    end
    if #t == 0 then                       -- 回退 1-based
        for j = 1, #packet do t[j] = string.char(packet[j] & 0xFF) end
    end
    return table.concat(t)
end

--================ 内嵌模块区(由 deploy_screen.py 生成, 勿手改) =================
-- BEGIN _MODS (auto-generated, do not edit)
local _MODS = {}

_MODS["lwmap.lua"] = [==[
--[[
lwmap.lua —— LW/RW 变量地址规划单一来源（所有页面模块引用此处，禁止散落定义）
================================================================================
约定:
  1. LW 地址一律十六进制; 用户区 >= 0x1000, 系统区 (<0x1000) 禁写
  2. VisualHMI 控件属性里的变量地址按十六进制解释(填"1019"=绑定0x1019),
     故常量必须用 0x 字面量, 与控件绑定值严格一致
  3. 【实测禁用地址】0x1000/0x1001(页面号系统寄存器)与 0x1016 写入无效/被系统覆盖
  4. i32 变量占两个 LW(小端), 规划时预留连续两字
  5. 本文件是绑定表生成器数据源: 改地址必须同步改 VisualHMI 控件绑定
  6. 【LW 最小单元 16 位】一个 LW 地址 = 2 字节, 控件无 u8 类型, 最小 UINT16;
     注释中的 "u8" 指下位机协议字段宽度(1 字节), LW 侧以 16 位承载取值 0/1,
     控件数据类型一律配 UINT16, lua 读写一律 r16/w16

分区规划(用户区 0x1000~):
  0x1002~0x102F  全局状态区 A_*(跨页面可见: 状态/诊断/版本/提示)
  0x1030~0x10FF  预留(全局扩展)
  0x1100~0x11FF  全局按钮区 B_*(写1触发, 代码自动复位)
  0x1200~0x12FF  页面0 主页扩展(状态显示走全局区, 暂未占用)
  0x1300~0x13FF  页面1 小区参数 LW.CELL
  0x1400~0x14FF  页面2 连续播种 LW.CONT
  0x1500~0x15FF  页面3 AB线 LW.AB
  0x1600~0x16FF  页面4 参数页 LW.PF / LW.PU
  0x1700~0x17FF  页面5 测试诊断 LW.TD
  0x1800~0x18FF  页面6 任务向导 LW.TW (B档新增: U盘CSV地图导入+4步向导)
  0x1900~0x19FF  页面7 历史记录 LW.HIST (B档新增: 分页列表+明细+U盘导出)
  0x1A00~0x1AFF  页面8 日志查看 LW.LOGV (B档新增: 日志留痕查看/导出)
  0x1B00~0x1FFF  预留(页面扩展)
--]]

local LW = {}

--==================== 画面号(与 VisualHMI 画面配置一致) ====================
LW.SCREEN = {
    HOME       = 0,   -- 主页(作业监视+启停)
    CELLPARA   = 1,   -- 小区播种参数
    CONTINUOUS = 2,   -- 连续播种
    ABLINE     = 3,   -- AB线管理
    PARAMS     = 4,   -- 厂家/用户参数
    TESTDIAG   = 5,   -- 测试诊断
    TASK       = 6,   -- 任务向导(B档新增: 选地图/AB线/路径/起点, 含U盘导入)
    HISTORY    = 7,   -- 历史记录(B档新增)
    LOGVIEW    = 8,   -- 日志查看(B档新增)
}

--==================== 全局状态区(0x1002~0x102F) ====================
-- 与 POC 阶段 main.lua 实测可用地址保持一致(勿动已验证地址)
LW.A = {
    speed    = 0x1002, -- i32 速度 mm/s       (占 0x1002~0x1003) 画面配3位小数->m/s(QT同口径)
    rownum   = 0x1004, -- u16 当前排号(显示排号rows-r,作业中图外保持最近图内值)
    offlen   = 0x1005, -- i32 AB行程偏移cm    (占 0x1005~0x1006) 画面配2位小数->m(=QT排行程)
    voff     = 0x1007, -- i32 垂直偏移cm      (占 0x1007~0x1008) 画面配2位小数->m(=QT列行程)
    loufei   = 0x1009, -- u16 x4 漏种计数1~4行 (0x1009~0x100C)
    louzh    = 0x100D, -- u16 漏株计数(第1行)
    -- 0x100E~0x1013 预留(漏株2~4行扩展)
    tx_cnt   = 0x1014, -- u16 发帧计数(lua心跳, on_run活着就会动)
    rx_cnt   = 0x1015, -- u16 收帧计数
    link     = 0x1013, -- u16 链路状态 0=通信中断 1=在线(app.lua心跳判定,
                       --   掉线=连续3个1s探测周期无0x22应答; 画面绑指示灯控件)
    -- 0x1016 【实测禁用】写入无效
    diag     = 0x1017, -- u16 诊断码(见 app.lua APP.diag)
    txfn     = 0x1018, -- u16 发送函数探测 1=uart_send 2=uart_send_data 0=都没有
    runstate = 0x1019, -- u16 作业状态 RunState
    bdstate  = 0x101A, -- u16 北斗状态 BdState
    ack      = 0x101B, -- u16 最近命令应答(1成功/0失败)
    -- tip/ver 为字符串变量, set_string 按串长写入不清尾, 必须留足隔离区:
    -- "√ 下发小区参数"=15B 需 8 个 LW 字(0x101C~0x1023); 旧规划 tip 只有
    -- 4 字, 溢出踩 ver(0x1020) 造成两串互染(主页"√下发蠕OC-SIM"乱码实锤)
    tip      = 0x101C, -- 字符串 操作提示(ack 弹窗文本, 占0x101C~0x1023 共8字)
    ver      = 0x1024, -- 字符串 下位机版本号(0xA3, 占0x1024~0x102B 共8字;
                       --   原0x1020已废, 画面0版本文本控件绑定须改0x1024)
    log      = 0x1060, -- 字符串 调试信息(0x22)/模块加载错误详情
    taskinfo = 0x1030, -- 字符串 主页任务进度文本(B档: "任务1 12/24 50%", 占0x1030~0x104F)
}

--==================== 全局按钮区(0x1100~, 写1触发自动复位) ====================
LW.B = {
    start    = 0x1100, -- 启动小区播种  -> 0x0A
    stop     = 0x1101, -- 停止播种      -> 0x0B
    ver      = 0x1102, -- 查询版本      -> 0xA3
    debug    = 0x1103, -- 读调试信息    -> 0x22
    -- 0x1104+ 预留给全局导航按钮(各页面跳转由画面配置直接实现, 不占LW)
}

--==================== 页面1 小区播种参数(0x1300~, BZCellParaType 表单) ====================
-- i32 字段占2字(偶地址起); u8 标志用开关控件; 表单值由数值输入控件写入
LW.CELL = {
    txflag        = 0x1300, -- u8 开关  TXFlag 播种方向与AB线 0反向/1同向(TX=同向,非透传)
    finalflag     = 0x1301, -- u8 开关  FinalFlag 1=当前小区是本排最后一小区(过道停投种)
    nextfinalflag = 0x1302, -- u8 开关  NextFinalFlag 1=下一小区是下一排最后一小区
    afternextzone = 0x1303, -- u8 开关  isAfterNextZoneSow 1=当前排+2的排仍播种(提前启机构)
    rownum        = 0x1304, -- i32 当前排号 RowNum
    ins           = 0x1306, -- i32 InS
    density       = 0x1308, -- i32 x4 当前排密度[1..4] (0x1308~0x130F)
    celllen       = 0x1310, -- i32 小区长度 CellLen
    startpos      = 0x1312, -- i32 起始位置 StartPOS
    disprownum    = 0x1314, -- i32 显示排号 DisplayRowNum
    nextrownum    = 0x1316, -- i32 下一排号
    nextins       = 0x1318, -- i32 NextInS
    nextdensity   = 0x131A, -- i32 x4 下一排密度[1..4] (0x131A~0x1321)
    nextcelllen   = 0x1322, -- i32 下一排小区长度
    nextstartpos  = 0x1324, -- i32 NextCellStartPOS
    nextdisprow   = 0x1326, -- i32 下一排显示排号
    send          = 0x1330, -- 按钮 下发参数 -> 0x20 (读表单组包, 前端校验)
}

--==================== 页面2 连续播种(0x1400~, LXBZParaType 12B) ====================
LW.CONT = {
    density = 0x1400,     -- i32 密度 Density
    celllen = 0x1402,     -- i32 行长 CellLen
    hju     = 0x1404,     -- i32 行距 Hju(i16域, 下发截断)
    zhushu  = 0x1406,     -- u32 株数 ZhuShu(u16域, 下发截断)
    start   = 0x1410,     -- 按钮 启动连续播种 -> 0x11
    stop    = 0x1411,     -- 按钮 停止连续播种 -> 0x12
}

--==================== 页面3 AB线(0x1500~, BDParaType 56B) ====================
-- double/float 屏端无原生控件: lua 读值后 string.format 写字符串控件显示
LW.AB = {
    startn      = 0x1500, -- 字符串 StartN 起点纬度
    starte      = 0x1502, -- 字符串 StartE 起点经度
    endbn       = 0x1504, -- 字符串 EndBN 终点纬度
    endbe       = 0x1506, -- 字符串 EndBE 终点经度
    startdir    = 0x1508, -- 字符串 StartDir 起始方向角
    calcdir     = 0x150A, -- 字符串 CalcDir 计算方向角
    startstate  = 0x150C, -- u16 StartState
    calcdirflag = 0x150D, -- u16 CalcDirFlag
    offlen      = 0x150E, -- u16 OffLen 偏移量
    bdofftime   = 0x150F, -- u16 BDOffTime
    capture     = 0x1520, -- 按钮 触发采集 -> 0x23 (下位机回当前AB线)
    send        = 0x1521, -- 按钮 下发AB线 -> 0x24 (组包56B)
    save        = 0x1522, -- 按钮 保存到RW(掉电持久化)
    load        = 0x1523, -- 按钮 从RW读回(验证持久化, 测试用)
    rw_magic    = 0x0000, -- RW区 AB线有效标志 0x55AA(见 LW.RW)
}

--==================== 页面4 参数页(0x1600~, TerParaType 40B + UserParaType 16B) ====================
-- 范围/默认值列由 params 任务从 hd3005a1/Src/para.c ParaLegalCheck 核对后固化
LW.PF = {                  -- 厂家参数(只读展示+授权后可写)
    a           = 0x1600,  -- i16 A
    b           = 0x1601,  -- i16 B
    encodenum   = 0x1602,  -- u16 EncodeNum 编码器脉冲
    encoderdir  = 0x1603,  -- u8 开关 EncoderDir
    holenum     = 0x1604,  -- u8 HoleNum 排种盘孔数
    gearratio   = 0x1605,  -- u16 GearRatio 传动比
    microstep   = 0x1606,  -- i16 MicroStepValue 细分
    x1          = 0x1607,  -- i16 X1
    bdiroff     = 0x1608,  -- i16 BDiroff 北斗偏移
    tapptrigoff = 0x1609,  -- i16 TappTrigOff
    tappertime  = 0x160A,  -- u16 TapperTime
    zeroposen   = 0x160B,  -- u8 开关 ZeroPosEn
    gzen        = 0x160C,  -- u8 开关 GZEn
    prepercent  = 0x160D,  -- u8 PrePercent 预压比
    read        = 0x1640,  -- 按钮 读厂家参数 -> 0x26
    write       = 0x1641,  -- 按钮 写厂家参数 -> 0x25 (读表单+范围校验)
    pass        = 0x1650,  -- u32 密码输入(数值输入, 占2字; Qt端密码同源)
    unlock      = 0x1652,  -- 按钮 解锁厂家参数(校验密码, 通过后放行写)
                           -- 【勿放0x1651】pass占0x1650~51, 0x1651是其高字, 写密码会误触发
}
LW.PU = {                  -- 用户参数
    dztime       = 0x1620, -- u16 DZTime 点滞时间
    hj           = 0x1621, -- i16 HJ
    rmp          = 0x1622, -- u32 RMP (占2字)
    antennatype  = 0x1624, -- u8 AntennaType 天线类型
    antennadist  = 0x1625, -- i16 AntennaDistance 天线距离
    read         = 0x1642, -- 按钮 读用户参数 -> 0x28
    write        = 0x1643, -- 按钮 写用户参数 -> 0x27
}

--==================== 页面5 测试诊断(0x1700~, TestModeStateType 4行52B) ====================
LW.TD = {
    encodercnt = 0x1700,   -- u32 编码器计数(占2字)
    bdcnt      = 0x1702,   -- u32 北斗计数(占2字)
    loufei     = 0x1704,   -- u32 x4 漏种计数[1..4] (0x1704~0x170B)
    louzh      = 0x170C,   -- u32 x4 漏株计数[1..4] (0x170C~0x1713)
    input      = 0x1714,   -- u32 IO输入位图(位指示灯 x32)
    warning    = 0x1716,   -- u32 报警位图(位指示灯 x32)
    ctrl       = 0x1718,   -- u32 输出位图(位指示灯 x32)
    -- 调试信息字符串复用全局 LW.A.log(0x1060)
    enter      = 0x1740,   -- 按钮 进入测试模式 -> 0x0E
    exit       = 0x1741,   -- 按钮 退出测试模式 -> 0x0F
    jogno      = 0x1742,   -- u16 点动通道号 CtrlNo(数值输入, 0~31 位)
    jogon      = 0x1743,   -- u16 点动 State 原值透传(下位机主循环消费, 屏端不解释)
    jogtrig    = 0x1744,   -- 按钮 触发点动 -> 0x09 (组包 TestCMDType)
    debug      = 0x1745,   -- 按钮 读调试信息 -> 0x22
}

--==================== 页面6 任务向导(0x1800~0x18FF, B档新增) ====================
-- 4步状态机: 1选地图 2选AB线 3选路径方式 4选起始小区
-- 列表交互: 多行字符串控件(选中行前缀">")+上下移按钮, 不依赖触摸列表
-- 字符串占用说明: 占用字数=控件"最大字符数"配置, GB2312下1汉字=2字节=1LW,
--   表内注释跨度为规划上限, 控件配置不得超过
LW.TW = {
    step       = 0x1800, -- u16 向导步骤 1~4
    tstate     = 0x1801, -- u16 任务状态 0=无 1=向导中 2=作业中 3=已完成
    count      = 0x1802, -- u16 当前列表可选项数
    selidx     = 0x1803, -- u16 列表选中项(0基)
    listtop    = 0x1804, -- u16 列表窗口首项(0基, 滚动)
    path_type  = 0x1805, -- u16 路径方式0~5(步骤3数值输入: 0梭形/1同向/2中间左/3右梭/4右同/5中间右)
    positive   = 0x1806, -- u16 行进方向 0=正向 1=反向(步骤3开关)
    start_row  = 0x1807, -- u16 起始小区排(1基显示号, 步骤4数值输入, 默认=算法起点)
    start_col  = 0x1808, -- u16 起始小区列(1基, 步骤4数值输入)
    cur_row    = 0x1809, -- u16 作业中: 当前排(显示号)
    cur_col    = 0x180A, -- u16 作业中: 当前列(1基)
    done_cnt   = 0x180B, -- u16 已完成小区数
    total_cnt  = 0x180C, -- u16 总小区数
    pct        = 0x180D, -- u16 完成率%
    sow_exceed = 0x180E, -- u16 图外播种开关 0=关 1=开(对齐QT checkBoxSowExceedMap, startNode density()的b参数)
    mapinfo    = 0x1810, -- 字符串 地图规格摘要(规划占0x1810~0x181F, 16字)
    detail     = 0x1820, -- 字符串 选中项详情(规划占0x1820~0x183F, 32字)
    list       = 0x1840, -- 字符串 列表多行文本(规划占0x1840~0x187F, 64字≈6行)
    btn_up     = 0x1880, -- 按钮 选项上移
    btn_down   = 0x1881, -- 按钮 选项下移
    btn_sel    = 0x1882, -- 按钮 选中/进入下一步
    btn_prev   = 0x1883, -- 按钮 上一步
    btn_ok     = 0x1884, -- 按钮 创建任务(步骤4)
    btn_cancel = 0x1885, -- 按钮 取消向导
    btn_resume = 0x1886, -- 按钮 续接未完成任务
    btn_import = 0x1887, -- 按钮 扫描U盘导入地图(步骤1)
}

--==================== 页面7 历史记录(0x1900~0x19FF, B档新增) ====================
LW.HIST = {
    count    = 0x1900, -- u16 任务总数
    selidx   = 0x1901, -- u16 选中任务(0基)
    listtop  = 0x1902, -- u16 列表窗口首项(0基)
    list     = 0x1910, -- 字符串 任务列表(规划占0x1910~0x194F, 64字≈6行)
    detail   = 0x1950, -- 字符串 任务明细多行(规划占0x1950~0x19BF, 112字≈8行: 各排穴数/肥数)
    btn_up   = 0x19C0, -- 按钮 上移
    btn_down = 0x19C1, -- 按钮 下移
    btn_view = 0x19C2, -- 按钮 查看明细
    btn_exp  = 0x19C3, -- 按钮 导出CSV到U盘
    btn_del  = 0x19C4, -- 按钮 删除任务
}

--==================== 页面8 日志查看(0x1A00~0x1AFF, B档新增) ====================
LW.LOGV = {
    count     = 0x1A00, -- u16 日志总条数
    view      = 0x1A10, -- 字符串 日志窗口多行(规划占0x1A10~0x1A9F, 144字≈8行)
    btn_up    = 0x1AB0, -- 按钮 上翻页
    btn_down  = 0x1AB1, -- 按钮 下翻页
    btn_top   = 0x1AB2, -- 按钮 跳到最新
    btn_clear = 0x1AB3, -- 按钮 清空日志
    btn_exp   = 0x1AB4, -- 按钮 导出日志到U盘
}

--==================== RW 掉电保持区(0x0000~0x7FFF, 64KB 按扇区) ====================
-- 注意: 标志位与数据须同 4KB 扇区; 上电读 0xFFFF 须恢复默认; 严禁高频写
-- AB线 BDParaType 56B=28字: magic(0x55AA) + 完整 pack 镜像(CrcCheck置0)
LW.RW = {
    ab_magic = 0x0000, -- u16 AB线有效标志 0x55AA
    ab_data  = 0x0001, -- 28字 BDParaType 完整镜像(page_abline pack, CrcCheck=0)
}

return LW

]==]

_MODS["protocol.lua"] = [==[
--[[
protocol.lua —— 电控播种机 0x68 协议帧引擎（纯逻辑，无平台依赖）
=================================================================
移植自两侧源码（已字节级核对，2026-08-27）：
  下位机: hd3005a1/Src/protocol.c   (FrameConstruct / FrameAnalysis / CRC16_MODBUS)
  上位机: SowSystem/tool/communication.cpp (addCrc / checkCrc / FrameAnalysis)

帧格式（总长 = DataLen + 7）:
  +------+-----+-------------+------+---------------+------+
  | 0x68 | FNC | Len (u16LE) | Data | CRC16 (u16LE) | 0x0D |
  +------+-----+-------------+------+---------------+------+
  CRC: CRC-16/CCITT 反射式（KERMIT 变体，初值 0x0000，无异或输出）
       计算范围: 从帧头 0x68 到 Data 末尾（不含 CRC 与 0x0D）
       标准校验值: CRC16("123456789") == 0x2189   (0x31C3 是XMODEM的值, 勿混淆)

用法（大彩 VisualHMI 屏端，副串口 ch1）:
    -- main.lua:
    --   require("protocol")
    --   PROTOCOL.io.tx = function(bytes) uart_send(1, str_to_bytes(bytes)) end
    --   function on_uart_recv(ch, packet)
    --       if ch == 1 then PROTOCOL.feed_bytes(bytes_to_str(packet)) end
    --   end
    -- （str<->byte数组 转换函数见文件尾部 PROTOCOL.util）

用法（PC 标准 Lua 5.3+ 自测）:
    --   直接 require 后调 PROTOCOL.feed_bytes(string)，见 test_protocol.lua
--]]

local string = string
local table  = table

local PROTOCOL = {}

-- 协议常量（与 hd3005a1/Inc/protocol.h 同步）
PROTOCOL.FRAME_START     = 0x68
PROTOCOL.FRAME_END       = 0x0D
PROTOCOL.MAX_DATA_LEN    = 1400        -- FRAME_MAX_DATA_LEN

-- 功能码（两侧 protocol.h 并集，以注释标注来源）
PROTOCOL.FNC = {
    GET_RTC          = 0x04,   -- 下位机: 回 u32 时间
    SET_RTC          = 0x05,   -- 下位机: 收 u32 时间, 回 ack
    GET_TEST_STATUS  = 0x08,   -- 回 TestModeStateType
    CMD_SVCTRL       = 0x09,   -- 收 TestCMDType, 回 ack
    CMD_START_BZ     = 0x0A,   -- 启动小区播种, 空域, 回 ack
    CMD_STOP_BZ      = 0x0B,   -- 停止播种, 空域, 回 ack
    RESTART_TER      = 0x10,   -- 重启设备, 回 ack（仅下位机协议表有）
    CMD_START_TEST   = 0x0E,   -- 进入测试模式, 空域, 回 ack
    CMD_STOP_TEST    = 0x0F,   -- 退出测试模式, 空域, 回 ack
    CMD_START_LXBZ   = 0x11,   -- 连续播种, 收 LXBZParaType, 回 ack
    CMD_STOP_LXBZ    = 0x12,   -- 停止连续播种, 空域, 回 ack
    SET_BZ_PARA      = 0x20,   -- 收 BZCellParaType, 回 ack(1/0)
    GET_BZ_STATUS    = 0x21,   -- 回 BZStatusType
    RD_DEBUG_INFO    = 0x22,   -- 回调试字符串(GB2312, 不含NUL; D5决策后固件改UTF-8)
    STORE_AB         = 0x23,   -- 空域, 回 BDParaType(当前AB线)
    SET_AB           = 0x24,   -- 收 BDParaType, 回 ack
    SET_TER_PARA     = 0x25,   -- 收 TerParaType, 回 ack
    GET_TER_PARA     = 0x26,   -- 空域, 回 TerParaType
    SET_USER_PARA    = 0x27,   -- 收 UserParaType, 回 ack
    GET_USER_PARA    = 0x28,   -- 空域, 回 UserParaType
    QZDD_ENABLE      = 0x29,   -- 收1字节(0/1), 回 ack
    GET_QZDD_STATE   = 0x30,   -- 空域, 回1字节（仅下位机协议表有）
    GDDD_ENABLE      = 0x31,   -- 收1字节(0/1), 回 ack
    GET_GDDD_STATE   = 0x32,   -- 空域, 回1字节（仅下位机协议表有）
    UPDATE_START     = 0xA0,   -- IAP 升级（屏端不实现，仅识别）
    UPDATE_BIN       = 0xA1,
    UPDATE_END       = 0xA2,
    GET_SOFT_VER     = 0xA3,   -- 回 "xxx,vol:n.n" + NUL (strlen+1)
}

--------------------------------------------------------------------
-- CRC-16/CCITT 反射式（KERMIT 变体, poly 0x8408, init 0x0000, xorout 0x0000）
-- 与下位机 CRC16_MODBUS() / 上位机 CRC16_CCITTCalc() 的查表完全等价
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
-- 组帧: build_frame(fnc, data) -> 完整帧二进制字符串
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
-- 发送接口: send(fnc, data)
-- io.tx 注入实际传输层；未注入时缓存到 io.pending（PC 自测可断言）
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
-- 收包状态机: feed_bytes(bytes) -> 解出的帧列表 {{fnc=..,data=..},...]
-- 语义复刻下位机 FrameAnalysis（do-while 逐帧提取 + 丢帧头重同步）：
--   1. 找不到 0x68         -> 丢弃全部（纯噪声）
--   2. 累计不足 7 字节      -> 等待更多数据
--   3. Len > 1400          -> 丢弃该 0x68 重找（防长度域损坏）
--   4. 累计不足整帧         -> 等待更多数据
--   5. CRC 不符 或 帧尾错   -> 丢弃该 0x68 重找（比上位机多验帧尾）
--   6. 校验通过            -> 派发回调, 继续处理剩余（粘包）
--------------------------------------------------------------------
PROTOCOL.rxbuf = ""
PROTOCOL.on_frame = nil          -- function(frame_table) 由上层注册

function PROTOCOL.feed_bytes(bytes)
    local rx = PROTOCOL.rxbuf .. bytes
    local frames = {}
    while true do
        -- 1) 找帧头
        local head = string.find(rx, string.char(PROTOCOL.FRAME_START), 1, true)
        if not head then rx = ""; break end
        if head > 1 then rx = string.sub(rx, head) end
        -- 2) 最小帧长 7 字节
        if #rx < 7 then break end
        -- 3) 长度域合法性
        local dlen = string.unpack("<I2", rx, 3)
        if dlen > PROTOCOL.MAX_DATA_LEN then
            rx = string.sub(rx, 2)          -- 丢掉伪帧头，重找
        else
            local total = dlen + 7
            -- 4) 等待整帧
            if #rx < total then break end
            -- 5) CRC + 帧尾校验
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
                rx = string.sub(rx, total + 1)                -- 处理粘包：继续
            else
                rx = string.sub(rx, 2)      -- 丢帧头重同步（复刻 buf.remove(0,1)）
            end
        end
    end
    PROTOCOL.rxbuf = rx
    return frames
end

--------------------------------------------------------------------
-- 工具: 字符串 <-> 大彩 packet 字节数组（屏端适配用）
-- 注意: 大彩文档标注 packet 下标从 1 起，与 string.byte 一致；POC 实测确认
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
codec.lua —— 协议结构体 <-> Lua table 编解码（string.pack 实现）
================================================================================
字节布局以 hd3005a2 固件(Inc/protocol.h, LINE_NUM=6 编译)为准, 2026-09-23 真机
联调修正: 三个行数相关结构体恒为 [6] 数组版本, **与4行机/6行机运行模式无关**:
  BZCellParaType 92B / BZStatusType 84B(Resv2[4]) / TestModeStateType 68B
  4行机只是 U8Resv2=4 的运行参数(上位机 protocol.h 同口径), 数组第5/6路恒0。
  (旧版按 hd3005a1 固件[4]布局在4行模式发76B包, hd3005a2/模拟器按92B校验
   直接 ACK=0, 播种空跑"播种结束[0]" —— 真机实测复现)
其余结构体: LXBZ 12 / TestCmd 4 / TerPara 40 / UserPara 16 / BDPara 56 B。
C 结构体自然对齐无填充, string.pack 紧凑排列与其内存镜像一致。

用法:
    local codec = require("codec")
    codec.init{ rows = 4 }                  -- rows 只作业务语义(有效路数), 默认4
    local s  = codec.bzcell.pack{ RowNum = 1, Density = {4000,4000,4000,4000} }
    local t  = codec.bzcell.unpack(s)       -- Density 恒为6元素(4行机末2路为0)
--]]

local string = string
local codec = {}

local ROWS = 4   -- 业务有效行数(4/6), 不影响结构体布局

-- 平台兼容: string.rep 屏端不可用(文档LUA/000_Lua_Api), 手写等价实现
-- (定义须在 codec.init 之前, init 的函数体词法引用本局部)
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
    -- 布局恒为[6]数组版本(hd3005a2 编译期 LINE_NUM=6), rows 只影响业务语义
    codec.bzcell.size  = 92
    codec.bzcell.fmt   = "<BBBB" .. "ii" .. reps("i", 6) .. "iii"
                               .. "ii" .. reps("i", 6) .. "iii"
    -- BZStatus: Resv2[4] 恒 84B (hd3005a2 para.h: Resv2[8-(LINE_NUM-4)*2], LINE_NUM=6)
    codec.bzstatus.size  = 84
    codec.bzstatus.resv2 = 4
    codec.bzstatus.fmt   = "<BBBBiiii" .. reps("I", 12) .. reps("i", 4)
    codec.teststate.size = 68
    codec.teststate.fmt  = "<II" .. reps("I", 12) .. "III"
end
codec.ROWS = ROWS

--------------------------------------------------------------------
-- 通用: 按字段表 + 格式串生成 pack/unpack
--   fields: 有序字段名; fmt: string.pack 格式串; size: 字节数
--------------------------------------------------------------------
-- 等价于 s:gsub("%d+$", ""): 去掉字符串尾部连续数字 (string.gsub 屏端不可用)
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
        vals[#vals] = nil                       -- 去掉 string.unpack 尾部游标
        local t = {}
        for i = 1, #fields do t[fields[i]] = vals[i] end
        return t
    end
    return S
end

--------------------------------------------------------------------
-- LXBZParaType 连续播种参数（12B，两侧一致）
-- hd3005a1/Inc/protocol.h:108
--------------------------------------------------------------------
codec.lxbz = make_struct(
    { "Density", "CellLen", "Hju", "ZhuShu" },
    "<iihH", 12)

--------------------------------------------------------------------
-- TerParaType 厂家参数（40B，两侧一致）
-- hd3005a1/Inc/para.h:147 / common/protocol.h
--------------------------------------------------------------------
codec.terpara = make_struct(
    { "A", "B", "EncodeNum", "EncoderDir", "HoleNum",
      "GearRatio", "MicroStepValue", "X1", "BDiroff", "TappTrigOff",
      "TapperTime", "ZeroPosEn", "GZEn", "PrePercent", "Resv1",
      "Resv0", "Resv1_", "Resv2", "CrcCheck" },
    "<hhHBBHHhhhHBBBBiiiI", 40)
-- 注: Resv[3] 拆为 Resv0/Resv1_/Resv2（避免与 u8 Resv1 重名）

--------------------------------------------------------------------
-- UserParaType 用户参数（16B，两侧一致）
-- hd3005a1/Inc/para.h:172
--------------------------------------------------------------------
codec.userpara = make_struct(
    { "DZTime", "HJ", "RMP", "AntennaType", "U8Resv", "AntennaDistance", "CrcCheck" },
    "<HhIBBhI", 16)

--------------------------------------------------------------------
-- BDParaType AB线参数（56B，两侧一致）
-- hd3005a1/Inc/para.h:183
--------------------------------------------------------------------
codec.bdpara = make_struct(
    { "StartN", "StartE", "EndBN", "EndBE",        -- double x4
      "StartDir", "CalcDir",                        -- float  x2
      "StartState", "CalcDirFlag", "OffLen", "BDOffTime",  -- u16 x4
      "Resv", "CrcCheck" },                         -- u32 x2
    "<ddddffHHHHII", 56)

--------------------------------------------------------------------
-- TestCMDType 测试控制命令（4B，两侧一致）
--------------------------------------------------------------------
codec.testcmd = make_struct({ "CtrlNo", "State" }, "<HH", 4)

--------------------------------------------------------------------
-- BZCellParaType 小区播种参数（4行76B / 6行92B）
-- hd3005a1/Inc/protocol.h:73  Density[4] vs 平板 Density[6]
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
    seg("")           -- 当前排
    seg("Next")       -- 下一排
    return f
end

codec.bzcell = {
    fields_of = bzcell_fields,
    pack = function(t)
        -- 把 Density/NextDensity 数组摊平进有序参数(恒6元素, 不足补0)
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
-- BZStatusType 播种状态（4行84B / 6行100B）
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
            for i = 1, 6 do flat[#flat+1] = a[i] or 0 end   -- 恒6路, 不足补0
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
-- TestModeStateType 测试模式状态（4行52B / 6行68B）
-- hd3005a1/Inc/protocol.h:118
--------------------------------------------------------------------
codec.teststate = {
    pack = function(t)
        local flat = { t.EncoderCnt, t.BdCnt }
        for _, key in ipairs({ "LoufeiCnt", "LouZHCnt" }) do
            local a = t[key]
            assert(type(a) == "table" and #a >= 1 and #a <= 6,
                   key .. " must be array of 1..6")
            for i = 1, 6 do flat[#flat+1] = a[i] or 0 end   -- 恒6路, 不足补0
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
-- 调试字符串(0x22): 固件现状 GB2312；D5 决策后改 UTF-8
-- Lua/LUA 屏端字符串即字节流，直接透传；显示中文需编码转换（见评估报告 C4）
--------------------------------------------------------------------
function codec.debug_str(data)
    return data
end

-- 初始化默认变体（4行，对手头下位机源码）
codec.init{ rows = 4 }

return codec

]==]

_MODS["app.lua"] = [==[
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

]==]

_MODS["page_home.lua"] = [==[
--[[
page_home.lua —— 主页: 作业状态监视 + 启停控制
================================================================================
自 POC 阶段 main.lua 迁移(行为/LW地址不变, 供 e2e 回归对照):
  轮询  0x21 BZStatusType -> 状态区刷新
  按钮  B_START 0x1100 -> 0x0A 启动小区播种
        B_STOP  0x1101 -> 0x0B 停止播种
        B_VER   0x1102 -> 0xA3 查询版本
        B_DEBUG 0x1103 -> 0x22 读调试信息
  应答  0xA3 -> 版本串; 0x22 -> 调试串(D5决策: 暂显ASCII, 过滤>=0x80字节)
返回 creator(ctx) -> page 表(ctx 见 app.lua 头注释)
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local JOBRUN, STORE = ctx.JOBRUN, ctx.STORE
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr = ctx.w16, ctx.w32, ctx.wstr

    local page = {
        id        = LW.SCREEN.HOME,
        -- 2026-09-23: 主页不再自轮询0x21 —— 作业期间由 jobrun 的常驻轮询驱动
        -- (其 _feed 已写 LW.A.runstate/speed/offlen/voff, 主页显示不受影响),
        -- 空闲期零轮询(用户决策); 链路活性由 app.lua 全局0x22心跳负责
        poll_cmds = {},
        addrs     = { LW.B.start, LW.B.stop, LW.B.ver, LW.B.debug },
    }

    -- 进入主页: 查一次版本(链路自检)
    function page:on_enter()
        PROTOCOL.send(FNC.GET_SOFT_VER)
    end

    function page:on_frame(f)
        local d = f.data
        if f.fnc == FNC.GET_BZ_STATUS then           -- 0x21 作业状态
            local ok, st = pcall(CODEC.bzstatus.unpack, d)
            if ok then
                w16(LW.A.runstate, st.RunState)
                w16(LW.A.bdstate,  st.BdState)
                w32(LW.A.speed,    st.Speed)
                w16(LW.A.rownum,   st.RowNum)
                w32(LW.A.offlen,   st.OffLen)
                w32(LW.A.voff,     st.VerticalOff)
                for i = 1, CODEC.ROWS do w16(LW.A.loufei + i - 1, st.LoufeiCnt[i]) end
                w16(LW.A.louzh, st.LouZHCnt[1])
            else
                wstr(LW.A.log, "bzstatus unpack err: len=" .. #d)
            end
        elseif f.fnc == FNC.GET_SOFT_VER then        -- 0xA3 版本串
            wstr(LW.A.ver, d)
        elseif f.fnc == FNC.RD_DEBUG_INFO then       -- 0x22 调试串(D5: ASCII过滤)
            local t = {}
            for i = 1, #d do
                local b = string.byte(d, i)
                if b < 0x80 then t[#t + 1] = string.char(b) end
            end
            wstr(LW.A.log, table.concat(t))
        elseif f.fnc == FNC.STORE_AB then            -- 0x23 停止时AB线采集应答
            if JOBRUN and JOBRUN.save_ab then
                if JOBRUN.save_ab(d) then
                    wstr(LW.A.tip, "√ AB线已保存")
                end
            end
        end
    end

    function page:on_update(addr)
        -- 开始键(QT pushButtonStart 语义三分支):
        --   作业中           -> 裸发 0x0A(下位机级续播, 任务参数已在线)
        --   趟间等待(跨趟挂起) -> 提示先停止(实操流程: 停止->掉头->开始)
        --   无作业有断点     -> 断点续作 resume(下发新趟 0x20 参数+0x0A,
        --                        等价 QT signalStartSow :276/:299)
        --   无任务           -> 裸发 0x0A(非任务手动播种场景)
        if     addr == LW.B.start then
            if JOBRUN and JOBRUN.active() then
                local s = JOBRUN.snapshot()
                if s and s.trip_wait then
                    wstr(LW.A.log, "本趟已完成 请先按停止")
                else
                    PROTOCOL.send(FNC.CMD_START_BZ)
                end
            else
                local name
                if JOBRUN and STORE and STORE.task_list then
                    for _, n in ipairs(STORE.task_list()) do
                        local d, tot = STORE.task_progress(n)
                        if d < tot then name = n break end
                    end
                end
                if name then
                    local ok, err = JOBRUN.start(name, { resume = true })
                    if not ok then wstr(LW.A.log, "续作失败: " .. tostring(err)) end
                else
                    PROTOCOL.send(FNC.CMD_START_BZ)
                end
            end
        -- 停止经作业调度层: 有任务时归档断点/清现场(100%完成待停也在此收尾),
        -- 无任务(B档降级)时裸发急停; 两条路径内部均发 0x0B
        elseif addr == LW.B.stop  then
            if JOBRUN then JOBRUN.stop() else PROTOCOL.send(FNC.CMD_STOP_BZ) end
        elseif addr == LW.B.ver   then PROTOCOL.send(FNC.GET_SOFT_VER)
        elseif addr == LW.B.debug then PROTOCOL.send(FNC.RD_DEBUG_INFO)
        end
    end

    return page
end

]==]

_MODS["page_params.lua"] = [==[
--[[
page_params.lua —— 厂家/用户参数页: 0x26/0x28 读快照, 0x25/0x27 写入+前端校验
================================================================================
范围表来源(下位机强制, hd3005a1/Src/para.c ParaLegalCheck, 2026-09 核对):
  GearRatio      <2  回落10   => [2, 65535]        para.c:168
  HoleNum        ==0 回落9    => [1, 255]          para.c:171
  HJ             10~5000 回落60                   para.c:174
  DZTime         100~10000 回落1500                para.c:177
  RMP            5~70 回落20                        para.c:180
  TapperTime     >1000 回落60 => [0, 1000]          para.c:183
  MicroStepValue >6400 回落800 => [0, 6400]          para.c:187
  EncodeNum      ==0 回落700  => [1, 65535]         para.c:191
  PrePercent     无校验, 按注释 [0,100]              para.h:165
  其余字段无下位机校验, 放行(负值经 LW i16 控件语义)
密码锁: 厂家参数写入前须解锁, 密码与 Qt 端一致 formconfig.cpp:172 ("515516")
CrcCheck: 传 0 占位, 下位机写 EEPROM 前重算(Qt 同此行为)
返回 creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16, r32 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16, ctx.r32

    local PASSWORD = 515516
    local unlocked = false

    -- 最近一次 0x26 快照: 写回时保留固件侧维护的字段。
    -- Resv1 即行数字段U8Resv2(4/6), 曾被硬编码0下发, 真机实测会把行数冲掉
    -- (模拟器状态文件被写成 U8Resv2=0 复现), 必须从快照原样带回。
    local last_ter = nil

    -- 范围表: { 字段, 下限, 上限, 中文名 }  nil 下限/上限 = 不检
    local RANGE_T = {
        { "GearRatio",      2,     65535, "传动比" },
        { "HoleNum",        1,     255,   "排种盘孔数" },
        { "EncodeNum",      1,     65535, "编码器脉冲" },
        { "MicroStepValue", 0,     6400,  "细分值" },
        { "TapperTime",     0,     1000,  "打点时间" },
        { "PrePercent",     0,     100,   "预压比" },
    }
    local RANGE_U = {
        { "HJ",     10, 5000,  "行间距HJ" },
        { "DZTime", 100, 10000, "点滞时间" },
        { "RMP",    5,  70,    "播种盘转速RMP" },
    }

    local function s16(v)                       -- u16 -> i16 符号扩展
        v = v & 0xFFFF
        if v >= 0x8000 then v = v - 0x10000 end
        return v
    end

    local function check(t, ranges)
        for _, r in ipairs(ranges) do
            local name, lo, hi, cn = r[1], r[2], r[3], r[4]
            local v = t[name]
            if lo and v < lo then return name, ("参数%s=%d 低于下限%d"):format(cn, v, lo) end
            if hi and v > hi then return name, ("参数%s=%d 超过上限%d"):format(cn, v, hi) end
        end
        return nil
    end

    -- 读表单(LW) -> terpara 表(i16 字段符号扩展, Crc 占位0)
    local function read_ter_form()
        local P = LW.PF
        local rows = last_ter and last_ter.Resv1
        if rows ~= 4 and rows ~= 6 then rows = 6 end   -- 无快照时兜底6行
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

    -- 读表单 -> userpara 表
    local function read_user_form()
        local U = LW.PU
        return {
            DZTime = r16(U.dztime), HJ = s16(r16(U.hj)), RMP = r32(U.rmp),
            AntennaType = r16(U.antennatype), U8Resv = 0,
            AntennaDistance = s16(r16(U.antennadist)), CrcCheck = 0,
        }
    end

    -- 0x26/0x28 应答 -> LW 表单回显
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
        poll_cmds = {},                          -- 快照式: 进页/手动读, 不轮询
        addrs     = {
            LW.PF.read, LW.PF.write, LW.PF.pass, LW.PF.unlock,
            LW.PU.read, LW.PU.write,
        },
    }

    function page:on_enter()                     -- 进页读双份快照
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
                wstr(LW.A.tip, "√ 厂家参数已解锁")
            else
                unlocked = false
                wstr(LW.A.tip, "× 密码错误")
            end
        elseif addr == P.write then
            if not unlocked then
                wstr(LW.A.tip, "× 请先输入密码解锁")
                return
            end
            local t = read_ter_form()
            local bad, msg = check(t, RANGE_T)
            if bad then wstr(LW.A.tip, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_TER_PARA, CODEC.terpara.pack(t))
        elseif addr == U.write then
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.tip, "× " .. msg) return end
            PROTOCOL.send(FNC.SET_USER_PARA, CODEC.userpara.pack(t))
        end
    end

    return page
end

]==]

_MODS["page_cellpara.lua"] = [==[
--[[
page_cellpara.lua —— 小区播种参数页: 手动表单 -> 0x20 成对下发(BZCellParaType)
================================================================================
表单 = 当前排 + 下一排 成对参数(密度x4/小区长/起始位/排号/InS/显示排号 + 4个u8标志)
校验策略: 下位机 ParaLegalCheck 不覆盖小区参数(2026-09 核对), 无权威范围源;
         本页仅做结构完整性, 不臆造业务范围(表单默认0即为合法下发值)
注: 正式的 startNode/createPath 自动算参依赖地图/任务数据源, 留待后续迭代(本轮 D2)
返回 creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, r16, r32 = ctx.w16, ctx.r16, ctx.r32

    local function s32(v)                       -- u32 -> i32 符号扩展
        v = v & 0xFFFFFFFF
        if v >= 0x80000000 then v = v - 0x100000000 end
        return v
    end

    local page = {
        id        = LW.SCREEN.CELLPARA,
        poll_cmds = {},
        addrs     = { LW.CELL.send },
    }

    -- 读表单(LW.CELL) -> BZCellParaType 表
    local function read_form()
        local C = LW.CELL
        local t = {
            TXFlag = r16(C.txflag), FinalFlag = r16(C.finalflag),
            NextFinalFlag = r16(C.nextfinalflag),
            isAfterNextZoneSow = r16(C.afternextzone),
            RowNum = s32(r32(C.rownum)), InS = s32(r32(C.ins)),
            Density = {}, CellLen = s32(r32(C.celllen)),
            StartPOS = s32(r32(C.startpos)),
            DisplayRowNum = s32(r32(C.disprownum)),
            NextRowNum = s32(r32(C.nextrownum)), NextInS = s32(r32(C.nextins)),
            NextDensity = {}, NextCellLen = s32(r32(C.nextcelllen)),
            NextCellStartPOS = s32(r32(C.nextstartpos)),
            NextDisplayRowNum = s32(r32(C.nextdisprow)),
        }
        for i = 1, CODEC.ROWS do
            t.Density[i] = s32(r32(C.density + (i - 1) * 2))
            t.NextDensity[i] = s32(r32(C.nextdensity + (i - 1) * 2))
        end
        return t
    end

    function page:on_update(addr)
        if addr == LW.CELL.send then
            local ok, t = pcall(read_form)
            if not ok then
                ctx.wstr(LW.A.tip, "× 表单读取失败")
                ctx.wstr(LW.A.log, "cellpara form err: " .. tostring(t))
                return
            end
            PROTOCOL.send(FNC.SET_BZ_PARA, CODEC.bzcell.pack(t))
            -- 启动按钮在主页: 下发成功后由人工切回主页按"启动"
        end
    end

    return page
end

]==]

_MODS["page_continuous.lua"] = [==[
--[[
page_continuous.lua —— 连续播种页: LXBZParaType 表单 -> 0x11 启动 / 0x12 停止
================================================================================
表单: 密度(i32) 行长(i32) 行距(Hju i16域) 株数(ZhuShu u16域)
LW 表单控件为 32 位, 下发时按协议域截断(Hju s16 / ZhuShu u16)
返回 creator(ctx) -> page
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
            Hju     = s16(r32(C.hju)),        -- 协议域 h(s16)
            ZhuShu  = r32(C.zhushu) & 0xFFFF, -- 协议域 H(u16)
        }
    end

    function page:on_update(addr)
        if addr == LW.CONT.start then
            PROTOCOL.send(FNC.CMD_START_LXBZ, CODEC.lxbz.pack(read_form()))
        elseif addr == LW.CONT.stop then
            PROTOCOL.send(FNC.CMD_STOP_LXBZ)  -- 空域
        end
    end

    return page
end

]==]

_MODS["page_abline.lua"] = [==[
--[[
page_abline.lua —— AB线管理: 0x23 采集 / 0x24 下发 / RW 掉电持久化
================================================================================
作业流: 触发采集(0x23, 下位机回当前AB线) -> 字符串只读显示 -> 保存RW / 下发0x24
设计决策:
  - 坐标显示用字符串控件("%.7f"), 但 cache 保留原始 double —— 避免字符串
    往返解析的精度丢失, 下发/存RW 均走 cache 原值
  - 本轮不做屏端手动编辑坐标(Qt 端也以采集为主), 手编留待后续迭代
RW 布局(同扇区合规, 见 lwmap.lua LW.RW):
  0x0000 = magic 0x55AA; 0x0001~0x001C = BDParaType 完整 pack 56B(CrcCheck=0)
  上电 magic != 0x55AA(含空片0xFFFF) -> cache=nil(恢复"未保存"默认态)
  仅"保存"按钮触发写入(低频合规), 严禁高频写
虚拟屏 RW 支持存疑 -> 本页逻辑单测先行, 实物回归清单验证
返回 creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, wstr = ctx.w16, ctx.wstr
    local rw16, rw16w = ctx.rw16, ctx.rw16w

    local ab_cache = nil                  -- BDParaType 表(最近一次采集/RW恢复)

    -- cache -> LW 显示(double 用 %.7f; u16 直接写)
    local function show(p)
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

    local function pack_cache()
        local t = {}
        for k, v in pairs(ab_cache) do t[k] = v end
        t.Resv = 0; t.CrcCheck = 0        -- 占位, 下位机自行处理
        return CODEC.bdpara.pack(t)
    end

    -- ---- RW 持久化: 28字 = 56B pack 的小端 u16 序列 ----
    local function rw_save()
        local data = pack_cache()
        for i = 0, 27 do                   -- 先写数据后写标志: 数据写一半掉电时
            local b1 = string.byte(data, i * 2 + 1)     -- magic 未置位, 读回判无效(安全侧)
            local b2 = string.byte(data, i * 2 + 2)
            rw16w(LW.RW.ab_data + i, b1 | (b2 << 8))
        end
        rw16w(LW.RW.ab_magic, 0x55AA)
    end

    local function rw_load()
        if rw16(LW.RW.ab_magic) ~= 0x55AA then return nil end
        local bytes = {}
        for i = 0, 27 do
            local v = rw16(LW.RW.ab_data + i)
            bytes[#bytes + 1] = string.pack("<H", v & 0xFFFF)
        end
        local ok, p = pcall(CODEC.bdpara.unpack, table.concat(bytes))
        if not ok then return nil end
        return p
    end

    -- creator 执行即恢复(模拟屏重启后 cache 从 RW 重建)
    ab_cache = rw_load()
    if ab_cache then show(ab_cache) end

    local page = {
        id        = LW.SCREEN.ABLINE,
        poll_cmds = {},
        addrs     = { LW.AB.capture, LW.AB.send, LW.AB.save, LW.AB.load },
    }

    function page:on_enter()
        if ab_cache then show(ab_cache) end
    end

    function page:on_frame(f)
        if f.fnc == FNC.STORE_AB then      -- 采集应答: BDParaType
            local ok, p = pcall(CODEC.bdpara.unpack, f.data)
            if ok then
                ab_cache = p
                show(p)
                wstr(LW.A.tip, "√ AB线已采集")
            else
                wstr(LW.A.log, "bdpara unpack err: len=" .. #f.data)
            end
        end
    end

    function page:on_update(addr)
        if addr == LW.AB.capture then
            PROTOCOL.send(FNC.STORE_AB)    -- 空域
        elseif addr == LW.AB.send then
            if not ab_cache then
                wstr(LW.A.tip, "× 无AB线, 请先采集或读回")
                return
            end
            PROTOCOL.send(FNC.SET_AB, pack_cache())
        elseif addr == LW.AB.save then
            if not ab_cache then
                wstr(LW.A.tip, "× 无AB线, 请先采集")
                return
            end
            rw_save()
            wstr(LW.A.tip, "√ AB线已保存(掉电保持)")
        elseif addr == LW.AB.load then
            local p = rw_load()
            if p then
                ab_cache = p
                show(p)
                wstr(LW.A.tip, "√ 已从RW读回")
            else
                wstr(LW.A.tip, "× RW无有效数据")
            end
        end
    end

    return page
end

]==]

_MODS["page_testdiag.lua"] = [==[
--[[
page_testdiag.lua —— 测试诊断页: 测试模式切换 / 0x08 位图轮询 / 0x09 点动 / 0x22 调试串
================================================================================
  轮询  0x08 TestModeStateType -> 编码器/北斗计数, 漏种漏株x行, IO/报警/输出位图
        (poll_cmds 机制: 仅本页可见时轮询, 离开自动停 —— app.lua 框架保证)
  按钮  TD.enter 0x1740 -> 0x0E 进入测试模式(空域)
        TD.exit  0x1741 -> 0x0F 退出(空域)
        TD.jogtrig 0x1744 -> 0x09 TestCMDType{CtrlNo, State}(4B)
        TD.debug 0x1745 -> 0x22 读调试信息(空域)
  应答  0x08 -> LW.TD 区刷新; 0x22 -> ASCII 过滤写 LW.A.log(D5 决策)
        注: 主页也有 0x22 按钮; 帧按当前页路由, 两页各自处理自己发出的 0x22
  State 语义: 下位机仅存 TestCMD 由主循环消费(protocool.c:385), 屏端透传不解释
返回 creator(ctx) -> page
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16

    local page = {
        id        = LW.SCREEN.TESTDIAG,
        poll_cmds = { FNC.GET_TEST_STATUS },         -- 0x08 仅本页可见时轮询
        addrs     = { LW.TD.enter, LW.TD.exit, LW.TD.jogtrig, LW.TD.debug },
    }

    function page:on_frame(f)
        local d = f.data
        if f.fnc == FNC.GET_TEST_STATUS then        -- 0x08 测试状态
            local ok, st = pcall(CODEC.teststate.unpack, d)
            if ok then
                w32(LW.TD.encodercnt, st.EncoderCnt)
                w32(LW.TD.bdcnt,      st.BdCnt)
                for i = 1, CODEC.ROWS do
                    w32(LW.TD.loufei + (i - 1) * 2, st.LoufeiCnt[i])
                    w32(LW.TD.louzh  + (i - 1) * 2, st.LouZHCnt[i])
                end
                w32(LW.TD.input,   st.InputState)   -- 位指示灯 x32 绑定
                w32(LW.TD.warning, st.WarningState)
                w32(LW.TD.ctrl,    st.CtrlState)
            else
                wstr(LW.A.log, "teststate unpack err: len=" .. #d)
            end
        elseif f.fnc == FNC.RD_DEBUG_INFO then      -- 0x22 (D5: ASCII 过滤)
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
            PROTOCOL.send(FNC.CMD_START_TEST)       -- 空域
        elseif addr == LW.TD.exit then
            PROTOCOL.send(FNC.CMD_STOP_TEST)        -- 空域
        elseif addr == LW.TD.jogtrig then
            local cmd = CODEC.testcmd.pack{
                CtrlNo = r16(LW.TD.jogno),
                State  = r16(LW.TD.jogon),
            }
            PROTOCOL.send(FNC.CMD_SVCTRL, cmd)
        elseif addr == LW.TD.debug then
            PROTOCOL.send(FNC.RD_DEBUG_INFO)        -- 空域
        end
    end

    return page
end

]==]

_MODS["fileio.lua"] = [==[
--[[
fileio.lua —— 大彩文件/USB API 封装（B档数据层底座）
================================================================================
依据: 官方 LUA API 文档(hmi-doc.gz-dc.com/LUA) + 2026-09-08 虚拟屏实测纠错:
  【单文件会话模型】file_open 只返回布尔(成功 true/失败 false); 打开成功即
  选中"当前文件", 后续 file_read/write/seek/size/close 均不带句柄参数,
  作用于当前文件。同一时刻只有一个"当前文件", 不支持并发打开两个文件。
  (旧预研误记为"数字句柄"语义, 曾把 open 的 true 当句柄传入 file_read(fd,n)
   多参调用, boolean 进 C 层段错误直接崩掉虚拟屏——画面8导出按钮实测)
语义契约(平台注入 io 表, 屏端 wire() 绑全局, PC 单测注入 mock):
  io.open(path, mode)  mode:0读/1覆盖/2追加 -> true|false   前缀 1:SD 2:U盘 3:内部Flash
  io.read(n<=2048)     -> 字节数组table|nil   (1基为主, 0基兼容; nil=EOF或失败)
  io.write(t<=2048)    -> bool
  io.seek(off)         -> bool   io.size() -> n|nil   io.close() -> bool
  io.delete(path)
  io.list(path)        发起异步目录扫描, 平台每发现一个条目回调一次
                       on_list_dir(path, filename, type, fsize) —— 逐条目流式,
                       流结束无显式信号, 由 pump() 静默超时判定收割
  io.dog()             喂狗
返回: 所有操作统一 (nil, "错误消息") 或 (值/true)
--]]

local FILEIO = {}

FILEIO.P_SD, FILEIO.P_USB, FILEIO.P_FLASH = "1:", "2:", "3:"
FILEIO.CHUNK    = 2048          -- 单次读写上限(官方)
FILEIO.MAX_FILE = 512 * 1024    -- 读入总量护栏(防异常文件拖死屏)

-- 平台 io 注入点(默认 nil; 屏端 FILEIO.wire() / 测试 FILEIO.bind())
FILEIO.io = nil

-------------------------------------------------------------------- 字节适配
local zero_based = nil           -- nil=未探测; true=平台返回0基数组

local function bytes_to_str(t)
    if t == nil then return "" end
    if type(t) ~= "table" then return tostring(t) end
    if zero_based == nil then                     -- 探测基准(仅提示一次)
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

-------------------------------------------------------------------- 内部封装
local function dog()
    if FILEIO.io and FILEIO.io.dog then pcall(FILEIO.io.dog) end
end

local function fopen(path, mode)
    if not FILEIO.io or not FILEIO.io.open then
        return nil, ("open失败 %s: 平台无file_open"):format(path)
    end
    local ok, r = pcall(FILEIO.io.open, path, mode)
    -- 官方语义(2026-09-08 文档核实+虚拟屏实测): file_open 返回布尔值;
    -- true=打开成功并选中"当前文件", false=失败。
    -- 注意绝不能把返回值当句柄传给 read/write 等(单会话模型无句柄参数)。
    if ok and r == true then return true end
    return nil, ("open失败 %s mode=%d ret=%s"):format(path, mode, tostring(r))
end

-------------------------------------------------------------------- 公开 API
function FILEIO.read_all(path)
    local ok0, err = fopen(path, 0)
    if not ok0 then return nil, err end
    local parts, total, first = {}, 0, true
    while true do
        local ok, t = pcall(FILEIO.io.read, FILEIO.CHUNK)
        if not ok then break end                 -- 平台异常按EOF收尾
        if t == nil then                         -- nil=EOF/失败(官方)
            if first then                        -- 首轮即EOF: 空/不可读文件
                pcall(FILEIO.io.close)
                return nil, ("read空 %s"):format(path)
            end
            break
        end
        local s = bytes_to_str(t)
        if #s == 0 then break end                -- 空表=EOF(防御)
        first = false
        total = total + #s
        if total > FILEIO.MAX_FILE then
            pcall(FILEIO.io.close)
            return nil, ("文件超限 %s >%d"):format(path, FILEIO.MAX_FILE)
        end
        parts[#parts + 1] = s
        dog()
        if #s < FILEIO.CHUNK then break end      -- 短读=EOF
    end
    pcall(FILEIO.io.close)
    return table.concat(parts)
end

-- 逐行读文本: 兼容 \r\n 与 \n; 尾行无换行也收; 空文件返回 {}
-- 注: read_all 对空文件返回 nil(EOF契约), 故用 size 预判存在性;
--     string.gmatch 平台禁用, 手写 find 循环
function FILEIO.read_lines(path)
    local sz = FILEIO.size(path)
    if sz == nil then return nil, ("read_lines: 无法打开 %s"):format(path) end
    if sz == 0 then return {} end
    local s = FILEIO.read_all(path)
    if s == nil then return {} end               -- 防御: size>0 但读空
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
    if #data == 0 then                           -- 空串: 建空文件即返回
        pcall(FILEIO.io.close)
        return true
    end
    local off = 1
    while off <= #data do
        local seg = data:sub(off, off + FILEIO.CHUNK - 1)
        local ok, r = pcall(FILEIO.io.write, str_to_bytes(seg))
        if not ok or not r then
            pcall(FILEIO.io.close)
            return nil, ("write失败 %s@%d"):format(path, off)
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
    -- 保守双保险: 官方 mode=2 即末尾追加, 但历史预研提示写指针不确定,
    -- 显式 seek 到 size 再写(即使已指末尾也无害)
    local ok, n = pcall(FILEIO.io.size)
    if ok and type(n) == "number" and n > 0 then pcall(FILEIO.io.seek, n) end
    local off = 1
    while off <= #data do
        local seg = data:sub(off, off + FILEIO.CHUNK - 1)
        local wok, r = pcall(FILEIO.io.write, str_to_bytes(seg))
        if not wok or not r then
            pcall(FILEIO.io.close)
            return nil, ("append失败 %s@%d"):format(path, off)
        end
        off = off + #seg
        dog()
    end
    pcall(FILEIO.io.close)
    return true
end

-- 存在性: size>0 才算存在(open 成功不代表有数据, 官方 mode=0 可能建空文件)
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

-- 拷贝: 单会话模型不能同时开两文件 -> 两段式(读全量->写全量)。
-- 日志/地图均为小文件(<<MAX_FILE), 内存中转无压力; 大文件流式留实物优化
-- (官方另有 file_copy(src,dst) 带 on_copy_file_process 进度回调, 可后续切换)。
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

-------------------------------------------------------------------- 目录(条目流)
-- 官方 list_dir(path) 异步扫描, 平台每发现一个条目回调一次
--   on_list_dir(path, filename, type, fsize): type 0=文件夹 1=普通文件
-- 流结束无显式信号 -> pump() 按"静默期+总兜底"收割(单挂起请求模型)
local pend = nil                     -- { dir, cb, items, quiet, total }
FILEIO.LIST_IDLE_TICKS = 6           -- 连续N次pump无新条目 => 扫描完成
FILEIO.LIST_MAX_TICKS  = 12          -- 发起后N次pump强制收割(空介质/无U盘)

function FILEIO.list_async(dir, cb)
    if not FILEIO.io or not FILEIO.io.list then return nil, "平台无list_dir" end
    pend = { dir = dir, cb = cb, items = {}, quiet = 0, total = 0 }
    local ok, err = pcall(FILEIO.io.list, dir)
    if not ok then
        pend = nil
        return nil, ("list_dir失败 %s: %s"):format(dir, tostring(err))
    end
    return true
end

-- main.lua 全局 on_list_dir(path, filename, type, fsize) 逐条目转发到此
function FILEIO.on_list_dir(path, filename, ftype, fsize)
    if not pend then return end
    if ftype == 1 and type(filename) == "string" then   -- 只收普通文件
        pend.items[#pend.items + 1] = filename
        pend.quiet = 0
    end
end

-- 泵: main.lua on_run 每 tick 调用一次; 静默期满/总兜底 => 收割挂起请求
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

-- 语义别名(屏端与页面统一入口)
function FILEIO.list(dir, cb)
    return FILEIO.list_async(dir, cb)
end

-------------------------------------------------------------------- 平台绑定
-- 平台文件 API 存在性探测(main 装配时打印, 核销规格 O-1 观测点)
function FILEIO.apis()
    local t = {}
    for _, n in ipairs { "file_open", "file_read", "file_write", "file_seek",
                         "file_size", "file_close", "file_delete", "list_dir", "feed_dog" } do
        t[n] = (type(_G[n]) == "function")
    end
    return t
end

-- 屏端装配(main.lua): FILEIO.wire() —— 从全局函数绑官方 API
-- 按存在性绑定: 虚拟屏可能缺整个文件 API 族, 缺失项保持 nil,
-- 后续操作经 fopen/read/write 统一防御返回 (nil, err) 而非抛异常
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

-- 测试装配: FILEIO.bind(io_table) -> FILEIO(可链式)
function FILEIO.bind(io_table)
    zero_based = nil                              -- 重置基准探测
    pend = nil                                    -- 重置挂起扫描
    FILEIO.io = io_table
    return FILEIO
end

return FILEIO

]==]

_MODS["csv.lua"] = [==[
--[[
csv.lua —— CSV/行文本 解析与序列化（B档数据层, 纯函数无副作用）
================================================================================
依据: POC/docs/移植规格-B档冻结.md §3.2 格式冻结
约定: 编码GB2312(本模块只处理字节流, 不做转码); 换行\r\n或\n; 分隔逗号;
      字段禁逗号/换行(名字类校验 check_name); 无引号转义。
地图格式: #MAP/#DIM/#ROWLEN/#AISLE/#AB/#BLOCKS   (BLOCKS 内 1 基, 存储 0 基)
任务格式: #TASK/#MAP/#PATH/#EXCEED/#OUTSET/#LAST/#STATE/#TIME/#BLOCKS/#RESULTS (0 基)
返回: parse_xxx(text) -> obj|nil, msgs(数组, 前缀"E:"致命/"W:"警告)
--]]

local csv = {}

-------------------------------------------------------------------- 基础
-- 平台兼容: string.gsub / string.gmatch / string.rep 屏端不可用(文档LUA/000_Lua_Api),
-- 以下均手写等价实现, 行为与PC Lua原版逐一验证一致(hmi_port/tests/test_him_equivalence.py)

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

-- 行迭代: 剥BOM/统一\r\n; 返回迭代器 (等价原 gmatch("([^\n]*)\n?") 语义)
function csv.iter_lines(text)
    if text:sub(1, 3) == "\xEF\xBB\xBF" then text = text:sub(4) end
    if string.find(text, CR, 1, true) then        -- 含\r才做归一化(快路径跳过)
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
            return ""                             -- 原语义: 空文本产一次空行
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
        if #t > 32 then break end                 -- 字段数护栏
    end
    return t
end

local function num(s)
    if s == nil then return nil end
    return tonumber(s)
end

-- 名字校验: 非空/无逗号换行/<=31字节(GB2312汉字≈15个)
function csv.check_name(s)
    if type(s) ~= "string" or #s == 0 then return false, "空名字" end
    if #s > 31 then return false, "名字超31字节" end
    if s:find("[,\r\n]") then return false, "名字含逗号或换行" end
    return true
end

-- 等价于原 s:gsub("%.?0+$", ""): 去尾部连续'0', 再去残留的'.'
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
    return trim_zeros(string.format("%.8f", v))  -- 8位小数=GPS毫米级, 去尾零
end

-------------------------------------------------------------------- 地图解析
-- #DIM 校验界限
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
                    msgs[#msgs + 1] = ("E:BLOCKS行非法: %s"):format(line)
                elseif not m.rows then
                    msgs[#msgs + 1] = "E:#DIM缺失(在BLOCKS前)"
                elseif r < 1 or r > m.rows or c < 1 or c > m.cols then
                    msgs[#msgs + 1] = ("E:BLOCKS越界 r=%s c=%s"):format(tostring(f[1]), tostring(f[2]))
                else
                    local rr, cc = r - 1, c - 1                -- 转0基
                    if m.blocks[rr] and m.blocks[rr][cc] then
                        msgs[#msgs + 1] = ("W:重复块(%d,%d)覆盖"):format(r, c)
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
                    msgs[#msgs + 1] = "E:#MAP名字非法"
                end
            elseif tag == "#DIM" then
                m.rows, m.cols, m.machine_cols, m.col_gap =
                    num(f[2]), num(f[3]), num(f[4]), num(f[5])
                m.block_col = num(f[6]) or 1       -- 可选: BlockColumn(小区行数), 默认1
                if not (m.rows and m.cols and m.machine_cols and m.col_gap) then
                    msgs[#msgs + 1] = "E:#DIM需4个数值(rows,cols,machine_cols,col_gap)"
                elseif m.rows < 1 or m.rows > ROWS_MAX
                    or m.cols < 1 or m.cols > COLS_MAX
                    or m.machine_cols < 1 or m.machine_cols > MC_MAX
                    or m.block_col < 1 or m.block_col > 8
                    or m.machine_cols % m.block_col ~= 0 then
                    msgs[#msgs + 1] = ("E:#DIM越界 %s"):format(line)
                end
                seen.DIM = true
            elseif tag == "#ROWLEN" or tag == "#AISLE" then
                local arr = (tag == "#ROWLEN") and m.rowlen or m.aisle
                for i = 2, #f do
                    local v = num(f[i])
                    if v == nil or v < 0 then
                        msgs[#msgs + 1] = ("E:%s数值非法: %s"):format(tag, tostring(f[i]))
                    else
                        arr[#arr + 1] = v
                    end
                end
            elseif tag == "#AB" then
                if #f >= 8 then
                    -- 第9字段: AB参考排(QT Map.ARow 0基), 缺省0
                    -- 第10字段: AB方向bool(QT Map.ABLineDirection, 1=同向/A在排上沿)
                    --   旧文件缺省由 a_row 反推(formmap.cpp:353 aRow=dir?0:rows-1)
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
                        msgs[#msgs + 1] = "E:#AB字段数值非法"
                    end
                else
                    msgs[#msgs + 1] = "W:#AB字段不足已忽略"
                end
            elseif tag:sub(1, 1) == "#" then
                -- 未知标签: 容错跳过(前向兼容)
            else
                msgs[#msgs + 1] = ("W:无法识别行已忽略: %s"):format(line:sub(1, 24))
            end
        end
    end

    -- 结构校验
    if not seen.DIM then msgs[#msgs + 1] = "E:缺#DIM" end
    if m.name == nil then msgs[#msgs + 1] = "E:缺#MAP" end
    if m.rows then
        if #m.rowlen ~= m.rows then
            msgs[#msgs + 1] = ("E:#ROWLEN需%d条实有%d"):format(m.rows, #m.rowlen)
        end
        if #m.aisle ~= m.rows + 1 then
            msgs[#msgs + 1] = ("E:#AISLE需%d条实有%d"):format(m.rows + 1, #m.aisle)
        end
        local want = m.rows * m.cols
        if m.block_cnt < want then
            msgs[#msgs + 1] = ("W:BLOCKS缺%d/%d块,按默认补(密度0不播)"):format(want - m.block_cnt, want)
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

-------------------------------------------------------------------- 地图序列化
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

-------------------------------------------------------------------- 任务解析
-- 结果行: r,c,state,start,end,seed[1..n],fert[1..n] (n=seed列数, 自适应4/6)
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
                    msgs[#msgs + 1] = ("E:BLOCKS行非法: %s"):format(line)
                else
                    if not t.blocks[r] then t.blocks[r] = {} end
                    t.blocks[r][c] = { state = st, sow = (sow or 1) ~= 0 and 1 or 0 }
                end
            elseif section == "#RESULTS" then
                local e = parse_result_line(f)
                if e then
                    t.results[#t.results + 1] = e
                else
                    msgs[#msgs + 1] = ("W:RESULTS行非法已忽略: %s"):format(line:sub(1, 24))
                end
            elseif tag == "#TASK" then
                t.name = f[2]
                if not csv.check_name(f[2] or "") then msgs[#msgs + 1] = "E:#TASK名字非法" end
            elseif tag == "#MAP" then
                t.map = f[2]
                if not csv.check_name(f[2] or "") then msgs[#msgs + 1] = "E:#MAP名字非法" end
            elseif tag == "#PATH" then
                local pt, po = num(f[2]), num(f[3])
                if pt == nil or pt < 0 or pt > 5 then
                    msgs[#msgs + 1] = ("E:#PATH非法: %s"):format(line)
                else
                    t.path_type = pt
                    t.positive = (po and po ~= 0) and 1 or 0
                end
            elseif tag == "#EXCEED" then
                t.sow_exceed = (num(f[2]) or 0) ~= 0 and 1 or 0
            elseif tag == "#OUTSET" then
                local r, c = num(f[2]), num(f[3])
                if r == nil or c == nil then
                    msgs[#msgs + 1] = ("E:#OUTSET非法: %s"):format(line)
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
                -- 未知标签容错
            else
                msgs[#msgs + 1] = ("W:节外行已忽略: %s"):format(line:sub(1, 24))
            end
        end
    end

    if t.name == nil then msgs[#msgs + 1] = "E:缺#TASK" end
    if t.map == nil then msgs[#msgs + 1] = "E:缺#MAP" end
    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return t, msgs
end

-------------------------------------------------------------------- 任务序列化
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
store.lua —— 数据层: 9表驻留模型 + 行文本持久化 + 启动恢复（B档）
================================================================================
依据: POC/docs/移植规格-B档冻结.md §3
内存模型: store.maps / store.tasks / store.results / store.cfg (坐标全 0 基)
持久化(内部Flash "3:", prefix 可注入):
  map_<名>.csv    地图(原样转存U盘导入内容)
  task_<名>.csv   任务定义+块状态(不含结果, 排级重写)
  result_<名>.csv 结果记录(追加式)
  index.txt       "M,<名>"/"T,<名>" 清单(启动免扫目录)
块状态: 0待播 1已下发 2完成 3中断(boot时1→3, 对齐QT task.cpp:44 且修正isSow含3)
依赖注入: store.init(fileio模块, csv模块, prefix) —— 屏端 main.lua / PC 测试均如此装配
--]]

local store = {}

store.maps    = {}      -- [name] = map(csv.parse_map 产物, 另含 block_col)
store.tasks   = {}      -- [name] = task(csv.parse_task 产物)
store.results = {}      -- [name] = { {r,c,state,start_t,end_t,seed={},fert={}} }
store.cfg     = { fine_tune = {} }   -- {{origin,specified,enabled}}

local F, C, PREFIX = nil, nil, "3:"

-------------------------------------------------------------------- 文件名ASCII化
-- 真机实测(2026-09): 屏端文件系统对含中文(GB2312多字节)的文件名 open 直接失败,
-- 纯ASCII长文件名正常。因此: 中文名仅作显示名/索引键(index.txt内容可中文),
-- 落盘文件名一律用 slug = 名字中ASCII字母数字段(截前16) + "_" + FNV-1a哈希8位hex。
-- 同名必得同slug(boot恢复依赖确定性), 不同名哈希不同(防ASCII段碰撞)。
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

-- 旧命名兼容: 早期版本曾用原名直拼文件名(仅ASCII名能落盘成功)。
-- boot 读取时 slug 路径不存在则回退旧路径, 避免升级后旧数据失联。
local function read_legacy(p_slug, p_old)
    local t = F.read_all(p_slug)
    if not t and p_old ~= p_slug then t = F.read_all(p_old) end
    return t
end

-------------------------------------------------------------------- 装配
function store.init(fileio_mod, csv_mod, prefix)
    F, C, PREFIX = fileio_mod, csv_mod, prefix or "3:"
    return store
end

local function bet(map)   -- 一趟覆盖的列数 = MachineColumn/BlockColumn (QT blockEachTrip)
    return math.max(1, math.floor((map.machine_cols or 1) / (map.block_col or 1)))
end
store.block_each_trip = function(map) return bet(map) end

-- 实际组宽: 末趟剩余列可能小于 bet (QT 奇数剩余趟语义)
local function grp(map, c0)
    local n = bet(map)
    if map.cols and c0 + n > map.cols then n = map.cols - c0 end
    return math.max(1, n)
end

-------------------------------------------------------------------- index 维护
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

-------------------------------------------------------------------- 地图
-- 导入(文本): 解析校验 → 驻留 → 原样字节转存内部Flash → 更新index
function store.map_import_text(name, text)
    if not select(1, C.check_name(name)) then
        return nil, "地图名非法"
    end
    local m, msgs = C.parse_map(text)
    if not m then
        return nil, "地图解析失败: " .. (msgs[1] or "?")
    end
    if m.name ~= name then
        return nil, ("文件名与内容名不符(%s≠%s)"):format(name, tostring(m.name))
    end
    local ok, err = F.write_all(p_map(name), text)      -- 原样转存
    if not ok then return nil, "地图落盘失败: " .. tostring(err) end
    store.maps[name] = m
    index_write()
    return m, (#msgs > 0) and table.concat(msgs, "; ") or nil
end

-- 导入(U盘文件): 读全量→导入
-- U盘文件名必须纯ASCII(固件文件系统限制, 真机实测); 地图显示名取自 #MAP 行,
-- 可为中文(文件内容不受文件名限制)。
function store.map_import_file(path, name)
    local text, err = F.read_all(path)
    if not text then
        for i = 1, #name do
            if string.byte(name, i) > 126 then
                return nil, "文件名含中文,请改纯英文数字名后重试"
            end
        end
        return nil, "读取失败: " .. tostring(err)
    end
    -- 显示名以内容 #MAP 为准(U盘文件名只作载体, 不必与显示名一致)
    local m0 = C.parse_map(text)
    if not m0 then return nil, "地图解析失败" end
    if m0.name and select(1, C.check_name(m0.name)) then
        name = m0.name
    end
    return store.map_import_text(name, text)
end

-- 地图重渲染落盘(驻留对象已改, 如停止时保存AB线 -> #AB 段写回)
function store.map_save(name)
    local m = store.maps[name]
    if not m then return nil, "地图不存在" end
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

-- 向导列表摘要: "演示田 4排×6列"
function store.map_spec(name)
    local m = store.maps[name]
    if not m then return "?" end
    return ("%d排×%d列"):format(m.rows, m.cols)
end

-------------------------------------------------------------------- 任务
-- 创建: 克隆地图块状态(sow) → 全0待播; last=-1; 落盘
function store.task_create(name, map_name, path_type, positive, sow_exceed,
                           outset_r, outset_c, now)
    if not select(1, C.check_name(name)) then return nil, "任务名非法" end
    if store.tasks[name] then return nil, "任务已存在" end
    local m = store.maps[map_name]
    if not m then return nil, "地图不存在" end
    if not (outset_r >= 0 and outset_r < m.rows and outset_c >= 0 and outset_c < m.cols) then
        return nil, "起始小区越界"
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
        return nil, "任务落盘失败: " .. tostring(err)
    end
    index_write()
    return t
end

-- 定义+块状态落盘(不含结果; 结果走追加文件)
function store.task_save(name)
    local t = store.tasks[name]
    if not t then return nil, "任务不存在" end
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

-- startNode 下发后标记: 组内 c0..c0+bet-1 置1 (对齐 QT setBlockState(row,col,1))
-- 并落盘: 下发即掉电 → 重启识别为中断(3), 支持断点续作 (QT task.cpp:44)
function store.task_mark_dispatched(name, r, c0)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "块不存在" end
    local m = store.maps[t.map]
    local n = m and grp(m, c0) or 1
    for c = c0, c0 + n - 1 do
        if t.blocks[r][c] then t.blocks[r][c].state = 1 end
    end
    return store.task_save(name)
end

-- 排完成: 组内置2 + 追加结果行 + 更新断点 + 整任务落盘(排级频度)
function store.task_mark_row_done(name, r, c0, entries, now)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "块不存在" end
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
        if not ok then return nil, "结果落盘失败: " .. tostring(err) end
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

-- 完成度: 分子=state2块数, 分母=总块数(对齐QT completionDegree口径)
-- 完成度: 分母=作业路径覆盖的小区数 (QT dialogrealtimetask.cpp:916
-- trip=cols/blockEachTrip 整除, 余数列不进路径不作业), 与 mark 口径一致;
-- 分母错大会导致任务完成后完成率封顶 <100% 且已完成任务仍被判定可续作。
function store.task_progress(name)
    local t = store.tasks[name]
    if not t then return 0, 0, 0 end
    local m = store.maps[t.map]
    local rows = (m and m.rows) or 0
    local cols = (m and m.cols) or 0
    local n = m and bet(m) or 1
    local cov = math.floor(cols / n) * n          -- 作业覆盖列数(整除, 丢余数列)
    if cov <= 0 then cov = cols end               -- 退化: 覆盖空时按全列兜底
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

-- USB 导出文本: 任务定义 + 全部结果(合并渲染)
function store.export_task_text(name)
    local t = store.tasks[name]
    if not t then return nil, "任务不存在" end
    t.results = store.results[name] or {}
    local s = C.render_task(t)
    t.results = {}
    return s
end

-------------------------------------------------------------------- 结果/密度微调
function store.result_add(name, entry)
    local list = store.results[name]
    if not list then return nil, "任务不存在" end
    list[#list + 1] = entry
    return F.append(p_result(name), C.render_result_line(entry) .. "\r\n")
end

-- 密度微调映射(QT global.cpp densityIsSpecified/specifiedDensity; 首轮空表=恒等)
function store.apply_density(v)
    for _, ft in ipairs(store.cfg.fine_tune) do
        if ft.enabled and ft.origin == v then return ft.specified end
    end
    return v
end

-------------------------------------------------------------------- 启动恢复
-- 读 index → 装载全部地图/任务/结果; 空片无index返回零; 失败项跳过并计数
function store.boot()
    local warns = {}
    store.maps, store.tasks, store.results = {}, {}, {}

    local text = F.read_all(p_index())
    if not text or #text == 0 then
        return { maps = 0, tasks = 0, warns = { "空片或无index" } }
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
            warns[#warns + 1] = ("地图%s装载失败已跳过"):format(n)
        end
    end

    for _, n in ipairs(tnames) do
        local raw = read_legacy(p_task(n), PREFIX .. "task_" .. n .. ".csv")
        local t
        if raw then t = C.parse_task(raw) end
        if t then
            -- 中断转换: 1→3 (QT task.cpp:44); 屏端isSow含3, 修正断电恢复密度误0
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
            warns[#warns + 1] = ("任务%s装载失败已跳过"):format(n)
        end
    end

    -- index 与内存对齐(失败项剔除)
    index_write()
    return { maps = #store.map_list(), tasks = #store.task_list(), warns = warns }
end

return store

]==]

_MODS["pathalgo.lua"] = [==[
--[[
pathalgo.lua —— 路径算法层: createPath 六种 + startNode 逐排预置参数（B档）
================================================================================
逐函数对齐 QT 源码:
  create_path      <- dialogrealtimetask.cpp:913 createPath(pathType 0~5)
  column_direction <- dialogrealtimetask.cpp:1180 (作业中从 path 序列查列方向)
  is_sow           <- task.cpp:344 Task::isSow (组内任一块 sow 且 state∈{0,1})
  density          <- task.cpp:373 Task::density (图外/不播/微调三态)
  start_node       <- dialogrealtimetask.cpp:701 startNode (当前排+下一排参数组)
  fwd_start/bwd_start/start_pos <- map.cpp:733/747/755
坐标全 0 基。纯函数无副作用, 依赖全部经参数注入。
--]]

local pathalgo = {}

local function bet(m)   -- 一趟组宽 = MachineColumn/BlockColumn
    return math.max(1, math.floor((m.machine_cols or 1) / (m.block_col or 1)))
end
pathalgo.block_each_trip = bet

-------------------------------------------------------------------- createPath
-- 生成有序作业序列 { {row=, column=组起点列, positive=行进方向bool} ... }
-- positive=true: row 0→rows-1 递增; false: rows-1→0 递减
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
    local trip = math.floor(m.cols / b)      -- QT: trip=cols/blockEachTrip 整除
    local cols = {}
    local dirs = {}

    if path_type == 0 then
        -- 梭形交替(左起): 0正,1反,2正...
        local i = 0
        while i < trip do
            cols[#cols + 1] = b * i;  i = i + 1;  dirs[#dirs + 1] = positive
            if i == trip then break end
            cols[#cols + 1] = b * i;  i = i + 1;  dirs[#dirs + 1] = not positive
        end
    elseif path_type == 1 then
        -- 全同向(左起)
        for i = 0, trip - 1 do
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 2 then
        -- 中间分两侧, 左半先(左端进出): 0正,trip-1反,1正,trip-2反...
        local i = 0
        while i < trip / 2 do
            cols[#cols + 1] = b * i;            dirs[#dirs + 1] = positive
            cols[#cols + 1] = b * (trip - 1 - i); dirs[#dirs + 1] = not positive
            i = i + 1
        end
        if trip % b == 1 then                   -- QT 奇数剩余趟判断(照抄)
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 3 then
        -- 梭形交替(右起): trip-1正,trip-2反...
        local i = trip - 1
        while i >= 0 do
            cols[#cols + 1] = b * i;  i = i - 1;  dirs[#dirs + 1] = positive
            if i < 0 then break end
            cols[#cols + 1] = b * i;  i = i - 1;  dirs[#dirs + 1] = not positive
        end
    elseif path_type == 4 then
        -- 全同向(右起)
        for i = trip - 1, 0, -1 do
            cols[#cols + 1] = b * i;  dirs[#dirs + 1] = positive
        end
    elseif path_type == 5 then
        -- 中间分两侧, 右半先(右端进出): trip-1正,0反,trip-2正,1反...
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
        return nil, "路径类型非法"
    end

    for k = 1, #cols do emit(path, rows, cols[k], dirs[k]) end
    return path
end

-- 作业中查列方向 (dialogrealtimetask.cpp:1180)
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
            -- 组内任一未完成且需播种 → 该组需播 (QT task.cpp:354)
            if blk and blk.sow == 1 and (blk.state == 0 or blk.state == 1) then
                return true
            end
        end
        return false
    end
    return b          -- 图外: 由"出图播种"开关决定
end

-- fine_tune: {{origin,specified,enabled}...} 密度微调映射(可为nil)
function pathalgo.density(task, m, row, column, b, fine_tune)
    local d
    if b then
        if row < 0 then
            d = m.blocks[0][column].density          -- 图外上侧: 首排密度
        elseif row < m.rows then
            d = pathalgo.is_sow(task, m, row, column, b)
                and m.blocks[row][column].density or 0
        else
            d = m.blocks[m.rows - 1][column].density  -- 图外下侧: 末排密度
        end
    else
        if row >= 0 and row < m.rows then
            d = pathalgo.is_sow(task, m, row, column, b)
                and m.blocks[row][column].density or 0
        else
            d = -1                                    -- 图外不播
        end
    end
    if fine_tune then
        for _, ft in ipairs(fine_tune) do
            if ft.enabled and ft.origin == d then return ft.specified end
        end
    end
    return d
end

-------------------------------------------------------------------- 起始位置
-- 正向累计: row<0 图外按首排+首过道倒推; row>=0 图内 sum(rowlen[i]+aisle[i+1])
function pathalgo.fwd_start(m, row)
    local d = 0
    if row < 0 then
        for _ = row + 1, -1 do                -- QT: i++<0 → row=-1 计0次, row=-2 计1次
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

-- 反向起点 = 正向累计 + 本排排长 (图外负排用首排长)
function pathalgo.bwd_start(m, row)
    if row < 0 then
        return pathalgo.fwd_start(m, row) + m.rowlen[1]
    end
    local ri = (row < m.rows) and row or (m.rows - 1)
    return pathalgo.fwd_start(m, row) + m.rowlen[ri + 1]
end

-- AB 参考: ab = { has=bool, dir=bool, a_row=int } (无AB时 a_row=outset排)
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
-- 逐排预置参数组 (dialogrealtimetask.cpp:701 BZCellParaType_st 语义字段)
-- 返回 table 供 codec.pack_bzcell 打包 0x20 下发
-- task: store 任务(含 blocks/sow_exceed); m: 地图; path: create_path 产物
-- row/column: 当前节点 0 基; ab: AB 参考; fine_tune: 密度微调
function pathalgo.start_node(task, m, path, row, column, ab, fine_tune)
    local b = (task.sow_exceed == 1)          -- 出图播种开关
    local d = pathalgo.column_direction(path, column)
    local rows = m.rows
    local bc = m.block_col or 1
    local ncol = m.machine_cols               -- maxSowColumn 播种行数

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
        -- 当前排在图内
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
        -- 当前排在图外
        p.FinalFlag = b and 0 or 1
        if d then
            p.InS = m.aisle[rows + 1]
            p.Density = dens_vec(rows)        -- 图外: 末排密度(t.density row>=rows 分支)
            p.CellLen = m.rowlen[rows]
        else
            p.InS = m.aisle[1]
            p.Density = dens_vec(0)           -- 图外: 首排密度(反向 row<=-1? 主段用0行)
            p.CellLen = m.rowlen[1]
        end
    end
    p.StartPOS = pathalgo.start_pos(m, p.RowNum, d, ab)

    p.NextRowNum = d and (row + 1) or (row - 1)
    p.NextDisplayRowNum = rows - p.NextRowNum
    local nr = p.NextRowNum
    if nr >= 0 and nr < rows then
        -- 下一排在图内
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
        -- 下一排在图外
        p.NextFinalFlag = b and 0 or 1
        if d then
            p.NextInS = m.aisle[rows + 1]
            p.NextDensity = dens_vec(rows)
            p.NextCellLen = m.rowlen[rows]
        else
            p.NextInS = m.aisle[1]
            p.NextDensity = dens_vec(-1)      -- QT: 反向图外 Next 用 density(-1) → b?0:-1
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
logger.lua —— 操作/告警日志留痕(B档)
================================================================================
- 内存环形缓冲 cap 条 + 单行追加文件(低频写, 对齐官方 RW/Flash 写约束)
- init 时从文件恢复最近条目(掉电不丢已落盘日志)
- 行格式: "<time> <tag> <msg>" CRLF; tag: INF/CMD/ERR/WRN
- 依赖注入: init{ now=时钟函数, fileio=F, path="3:log.txt", cap=120 }
  (屏端 now 由装配层提供: 优先下位机 0x04 时间缓存; 单测注入假时钟)
--]]

local logger = {}

local F, PATH, CAP, NOW
local buf = {}          -- 环形缓冲(1基数组, #buf 为当前条数, 上限 CAP)
local drop_cnt = 0      -- 溢出丢弃数(文件仍在)

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
    -- 掉电恢复: 读回最近条目 (手写行切分: string.gmatch 屏端不可用)
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

-- 追加一条: 内存环形 + 文件单行追加(官方陷阱已由 fileio.append 封装: seek到size)
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

-- 查看窗口: top=1基起始条, n=条数; 返回数组(旧->新)
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

-- 导出到U盘: 全量重写(读取屏内文件原文, 不经过内存重组, 防大文件溢出)
function logger.export(udisk_path)
    if not F then return nil, "fileio未注入" end
    local ok, err = F.copy(PATH, udisk_path)
    if not ok then return nil, err end
    return true
end

return logger

]==]

_MODS["jobrun.lua"] = [==[
--[[
jobrun.lua —— 作业调度状态机(B档核心): 逐排预置下发 + 排完成落库 + 断点续作
================================================================================
逐分支对齐 QT dialogrealtimetask.cpp:
  start()      <- :269 signalStartSow(图外起播 :285-300 / AB参考无AB线时更新 :278-284)
  on_status()  <- :330 signalGetSowStatus 200ms 状态机 (:399-473)
  stop()       <- :305 signalStopSow(当前块完成则回退 nextPathIndex=tempIndex :306-307)
  _complete()  <- QT语义: path走完不自动停机, 等操作员手动停止(主页停止按钮->stop收尾)
  start_node() <- pathalgo.start_node + codec.bzcell.pack -> 0x20

QT 瑕疵修正(有意为之, 与C++差异点):
  排推进到新列组时同步 currentColumn = path[nextPathIndex].column
  (QT :469 只更新 row, 列切换瞬间 startNode 仍用旧列密度, 属上游隐患;
   B档统一 0 基坐标系时一并修正, 见 移植规格-B档冻结.md)

依赖注入 jobrun.init{ APP, PROTOCOL, CODEC, STORE, PATHALGO, LOGGER, LW,
                      w16, w32, wstr, now }
  now() -> "yyyy-MM-dd hh:mm:ss" 字符串(屏端由装配层提供, 单测注入假时钟)
--]]

local jobrun = {}

local APP, PROTOCOL, CODEC, STORE, PATHALGO, LOGGER, LW
local w16, w32, wstr, NOW

-- 作业现场(单个活动任务)
local J = nil
-- J = { task=名, m=地图, path, ab, next_idx, cur_col, cur_read_row,
--       enter_map, sow_state, temp_idx, result_t0, fine, disp_row }
--       disp_row = 最近图内排的显示排号(rows-r), 图外帧主页排号保持该值

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
    -- 常驻订阅: 0x21 帧无论当前页都进状态机(作业中切页不丢)
    APP.sub_always(PROTOCOL.FNC.GET_BZ_STATUS, function(f) jobrun._feed(f) end)
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

-------------------------------------------------------------------- 下发封装
local function send_node(row, column)
    local p = PATHALGO.start_node(STORE.tasks[J.task], J.m, J.path, row, column, J.ab, J.fine)
    local ok, bin = pcall(CODEC.bzcell.pack, p)
    if not ok then
        log("ERR", "startNode组包失败 r=" .. row)
        return false
    end
    PROTOCOL.send(PROTOCOL.FNC.SET_BZ_PARA, bin)
    -- QT :318 signalSetSowParameters: 记录当前组起始时间(结果表 startTime)
    J.result_t0 = now_s()
    return true
end

-------------------------------------------------------------------- 推进(共用)
-- 图内(:264 刚走完 next_idx 排)与图外(边界排落库后)两处殊途同归:
--   同趟下一排 -> 自动预置(QT :469); 跨列组 -> trip_wait 挂起(对齐 QT 现场
--   实操: 播完一趟手动按停止, 掉头后再按开始续播); path 走完 -> 完成态收口
local function advance()
    if J.next_idx < #J.path then
        J.next_idx = J.next_idx + 1
        local np = J.path[J.next_idx]
        if np.column ~= J.cur_col then
            -- 跨趟(列组切换): 断点推进到下一趟首节点后挂起, 不自动下发,
            -- 0x21 只刷显示, 等待主页 停止->开始 (续播参数等价 QT :276/:299
            -- 由 start(resume) 重新下发, 而非复用 QT :469 的旧列自动 startNode)
            J.cur_col = np.column
            J.enter_map = false
            J.trip_wait = true
            J.sow_state = false               -- 停推进(等手动), 保留 J
            local _, _, pct = STORE.task_progress(J.task)
            log("INF", ("本趟完成 下一趟列组=%d 进度%d%% 请停止后掉头再开始")
                :format(np.column + 1, pct or 0))
            jobrun._refresh_ui()
        else
            send_node(np.row, J.cur_col)      -- 同趟下一排: QT :469 自动
            -- QT 语义: startNode 只下发参数不置 state=1(state 仅由在播帧
            -- RowNum==path[next].row 建立, :456) -> 行程不符(未走到预期排)
            -- 时 :459 推进条件永不满足, 完成率挂住; 屏端此前在此预置
            -- mark_dispatched(state=1)打穿该保护, 乱序排帧也会推进落库
            -- 一路到100%. 2026-09-11 对齐 QT 删预置(用户联调暴露)
        end
    else
        jobrun._complete()                    -- path 走完: 完成态待手动停止
    end
end

-------------------------------------------------------------------- 启动(QT :269)
-- opts: { resume=bool } 续接时 path 进度由 store 断点推
function jobrun.start(task_name, opts)
    opts = opts or {}
    if J then return nil, "已有作业进行中" end
    local t = STORE.tasks[task_name]
    if not t then return nil, "任务不存在" end
    local m = STORE.maps[t.map]
    if not m then return nil, "地图缺失" end

    local path, err = PATHALGO.create_path(m, t.path_type, t.positive == 1)
    if not path then return nil, err end

    -- 断点续作: 找到第一个未完成组的节点作为起点
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

    -- AB 参考(QT :278-284: 无AB线时每次启动用起点更新 aRow/方向)
    -- 真机化(2026-09-10): 方向改用 #AB.abdir(QT ABLineDirection bool);
    -- 此前误用 sdir(StartDir 航向角)==1 恒false, 且 has 未置位,
    -- 屏端一直按"无AB线"调度(TXFlag/start_pos/翻转全错), sim 不校验故未暴露
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

    -- 状态展示: 主页 taskinfo / TW 页
    if APP then APP.set_always_poll(PROTOCOL.FNC.GET_BZ_STATUS) end
    log("INF", ("作业启动 %s 地图=%s 路径=%d 起点组=%d"):format(
        task_name, m.name, t.path_type, start_idx))

    -- QT :275-300: 启动时先下发首个节点参数(图外播种=从图外排开始, 否则首排)
    local pn = path[J.next_idx]
    if (t.sow_exceed == 1) then
        J.cur_read_row = pn.positive and -1 or m.rows   -- 图外虚拟排
        J.enter_map = false
        send_node(J.cur_read_row, J.cur_col)
    else
        J.enter_map = true
        send_node(pn.row, J.cur_col)
    end
    -- 不预置 mark_dispatched(QT state=1 仅由在播帧建立: 行程不符保护,
    -- 见 advance() 内注释; resume 扫描按 state~=2 判未完成, 不受影响)
    PROTOCOL.send(PROTOCOL.FNC.CMD_START_BZ)       -- 0x0A
    J.sow_state = true
    return true
end

-------------------------------------------------------------------- 停止(QT :305)
-- 主页停止按钮唯一收尾入口; 0x0B 无条件急停(含无任务时裸发),
-- 有作业时回退断点(QT :306-307)+归档+清现场(允许后续新任务/续作)
-- QT :310-311: 地图无AB线时停止弹"是否保存AB线?" -> Yes 则 0x23 采集
-- 存图; 组态屏无 Yes/No 弹窗 -> 简化为自动采集保存(应答由 page_home
-- 收帧后调 save_ab 落盘, 见下)
local pending_ab = nil            -- { map=地图名, a_row=启动A排, dir=AB方向 }

function jobrun.stop()
    PROTOCOL.send(PROTOCOL.FNC.CMD_STOP_BZ)        -- 0x0B
    if not J then return true end
    -- AB线采集(QT signalStopSow :310-311 + 无AB线时启动即更新参考 :278-284:
    -- a_row/dir 取 J.ab —— 无AB线任务启动时已按起点节点填好)
    if not (J.m.ab and J.m.ab.has) then
        pending_ab = { map = J.m.name, a_row = J.ab and J.ab.a_row or 0,
                       dir = J.ab and J.ab.dir or false }
        PROTOCOL.send(PROTOCOL.FNC.STORE_AB)       -- 0x23 采集请求
        log("INF", "地图无AB线, 停止时采集(0x23): " .. J.m.name)
    end
    if not J.completed then
        -- QT :306-307: 停止时当前块已完成则 next_idx 回退到 temp_idx(下次续作起点)
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
    log("INF", "作业停止 " .. J.task)
    jobrun.detach()
    J = nil
    return true
end

-- 保留现场仅停轮询(掉电恢复/页面展示用)
function jobrun.detach()
    if APP then APP.set_always_poll(nil) end
end

-- 0x23 采集应答 -> 写地图 #AB 段并落盘(page_home 收帧后调用)
-- 等价 QT: signalGetABLine :504 + m.saveABLine; 名称用地图名(QT 弹框输入,
-- 组态屏无文本输入, 简化); A排/ABDir 用 stop 时快照(启动参考值)
function jobrun.save_ab(data)
    if not pending_ab then return nil end
    local pa = pending_ab
    pending_ab = nil
    local ok, p = pcall(CODEC.bdpara.unpack, data)
    if not ok then log("WRN", "AB线采集应答解析失败") return nil end
    local m = STORE.maps[pa.map]
    if not m then log("WRN", "AB线保存失败: 地图缺失 " .. pa.map) return nil end
    m.ab = { name = m.name,
             sn = p.StartN, se = p.StartE, en = p.EndBN, ee = p.EndBE,
             sdir = p.StartDir, cdir = p.CalcDir,
             a_row = pa.a_row or 0,
             abdir = pa.dir and 1 or 0, has = true }
    if STORE.map_save and not STORE.map_save(pa.map) then
        log("WRN", "AB线落盘失败: " .. pa.map)
        return nil
    end
    log("INF", ("AB线已保存至地图 %s (A排%d %s)"):format(
        pa.map, pa.a_row or 0, pa.dir and "同向" or "反向"))
    return true
end

-------------------------------------------------------------------- 200ms 状态机
-- QT :330-473 signalGetSowStatus 核心分支(去除拖拉机图标/表格可视化)
function jobrun._feed(f)
    local ok, st = pcall(CODEC.bzstatus.unpack, f.data)
    if not ok then return end

    -- 全局状态区刷新(page_home 等价逻辑, 0x21 被常驻截获后由这里统一供数)
    -- 2026-09-10 修: 补齐 voff/loufei/louzh(此前作业中漏写 -> 主页列行程恒0、
    -- 漏种/漏株计数冻结); 排号改显示排号口径(=页面6/QT DisplayRowNum, rows-r),
    -- 图外帧(RowNum=-1/rows, 出图掉头)保持最近图内值, 不再闪 65535
    if w16 then
        w16(LW.A.runstate, st.RunState)
        w16(LW.A.bdstate,  st.BdState)
        -- 真机语义(QT :345-356): 有AB线时 VerticalOff 显示前符号翻转
        --   pathType 0/1/2 且 AB同向 -> 取反; pathType 3/4/5 且 AB反向 -> 取反
        --   无AB线/无作业: 原值(连续播种页与QT formcontinuoussow同口径)
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
            J.disp_row = J.m.rows - rn            -- 图内: 显示排号(1基)
        end
        w16(LW.A.rownum, (J and J.disp_row) or rn)
        for i = 1, CODEC.ROWS do w16(LW.A.loufei + i - 1, st.LoufeiCnt[i]) end
        w16(LW.A.louzh, st.LouZHCnt[1])
    end

    if not J then return end
    if st.RowNum <= -10000000 then return end        -- 未开播哨兵(QT :399)
    if not J.sow_state then return end

    local t = STORE.tasks[J.task]
    local m = J.m
    local rows = m.rows
    local b = (t.sow_exceed == 1)
    local bet = PATHALGO.block_each_trip(m)

    if st.RowNum < 0 or st.RowNum >= rows then
        ---- 图外: 边界排完成(QT :403-409, 仅 setBlockState=2, 不推进不下发)
        if J.cur_read_row == 0 or J.cur_read_row == rows - 1 then
            STORE.task_mark_row_done(J.task, J.cur_read_row, J.cur_col, {}, now_s())
            -- 2026-09-11 二修(用户联调暴露: sim 重启行程归零后仍推到100%):
            --  此前此处补 advance() 想让"趟末出图帧即挂起", 但 QT 没有 ——
            --  sim 无 0x20 时按里程自走, RowNum 涨过边界 -> 图外 advance ->
            --  send_node 重发 0x20 重新引导 sim, 行程不符推进链复活;
            --  QT 仅置 state=2 挂住。删 advance 对齐(趟完成提示改由完成率
            --  停滞表达, 与 QT 一致; 续作起点仍有 stop 回退+resume 扫描双保险)
            local d, tot = STORE.task_progress(J.task)
            if d >= tot then jobrun._complete() end
        end
        if b and st.RowNum ~= J.cur_read_row then
            send_node(st.RowNum, J.cur_col)          -- 图外逐排推进
        end
    else
        ---- 图内(QT :411-470)
        local pn = J.path[J.next_idx]
        if not pn then jobrun._complete(); return end

        -- QT :413-415: 记录最新完成排, temp_idx=该节点在path中的下一个
        local ti = jobrun._index_of(st.RowNum, J.cur_col)
        if ti then
            J.temp_idx = ti % #J.path + 1
            t.last_r, t.last_c = st.RowNum, J.cur_col
        end

        local sow_flag = PATHALGO.is_sow(t, m, pn.row, J.cur_col, b)

        -- QT :446-458: 正在播 next_idx 排
        if st.RowNum == pn.row then
            if not J.enter_map then
                send_node(pn.row, J.cur_col)         -- 入图首排(仅一次)
                J.enter_map = true
            end
            if sow_flag then STORE.task_mark_dispatched(J.task, pn.row, J.cur_col) end
        -- QT :459-470: 刚走完 next_idx 排 → 记结果 + 推进
        elseif (function()
                    local blk = t.blocks[pn.row] and t.blocks[pn.row][J.cur_col]
                    return (blk and (blk.state == 1 or blk.state == 2)) or not sow_flag
                end)() then
            if sow_flag then
                -- QT :422-445: currentResult[i] 穴数/肥数取自 LouZHCnt/LoufeiCnt
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
            -- 推进(QT :469 + B档修正: 同步 currentColumn; 跨趟挂起见 advance)
            advance()
        end
    end
    J.cur_read_row = st.RowNum
    jobrun._refresh_ui()
end

-- QT :1106 getIndex: path 中找 {row,column} 节点序号
function jobrun._index_of(row, column)
    for i, pn in ipairs(J.path) do
        if pn.row == row and pn.column == column then return i end
    end
    return nil
end

-- 路径全程走完(对齐 QT: 即使100%也不自动停机/不停轮询, 拖拉机仍在
-- 行驶需持续刷新状态; 由操作员按主页"停止"按钮 -> jobrun.stop() 收尾归档)
function jobrun._complete()
    J.completed = true
    J.sow_state = false                            -- 停推进, 不再下发新节点
    if STORE then STORE.task_save(J.task) end
    log("INF", "作业完成(待手动停止) " .. J.task)
    jobrun._refresh_ui()
end

-- 主页进度文本 LW.A.taskinfo: "任务1 12/24 50%"
function jobrun._refresh_ui()
    if not (wstr and J) then return end
    local d, tot, pct = STORE.task_progress(J.task)
    local s = ("%s %d/%d %d%%"):format(J.task, d, tot, pct)
    if J.completed then s = s .. " 已完成"
    elseif J.trip_wait then s = s .. " 本趟完成" end
    wstr(LW.A.taskinfo, s)
end

return jobrun

]==]

_MODS["page_task.lua"] = [==[
--[[
page_task.lua —— 任务向导页(0x1800~, 画面6, B档)
================================================================================
4步状态机(LW.TW.step):
  1 选地图(列表+U盘导入) → 2 选AB线 → 3 路径方式/方向/图外播种 → 4 起始小区+创建
作业视图(tstate=2): jobrun.snapshot 写 LW 进度区。
列表交互: 多行字符串(选中行">"前缀) + 上/下移按钮; btn_sel 选中进入下一步。
依赖注入: creator(ctx) 同现有页面模式; ctx 增 STORE/JOBRUN/LOGGER/FILEIO。
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, FILEIO, PATHALGO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.FILEIO, ctx.PATHALGO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6                  -- 列表窗口行数(与 LW.TW.list 控件规划一致)

    -- 向导现场(非持久, 离开页面丢弃; 已创建任务落 store)
    local W = { map = nil, use_ab = false, sel = 0, top = 0, items = {} }

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
        -- 2026-09-10 修: 回写选中项/列表首项(此前只写列表文本, 画面数值控件恒0)
        w16(LW.TW.selidx, W.sel)
        w16(LW.TW.listtop, W.top)
    end

    local function step1_items()
        W.items = { "扫描U盘导入地图" }
        if not STORE then                       -- B档数据层降级(如虚拟屏无文件API)
            W.items[#W.items + 1] = "(数据层不可用)"
            return
        end
        for _, n in ipairs(STORE.map_list()) do
            W.items[#W.items + 1] = n .. " " .. STORE.map_spec(n)
        end
    end

    local function step2_items()
        local m = STORE.map_get(W.map)
        W.items = { "无AB线(按起点直线作业)" }
        if m and m.ab then
            W.items[#W.items + 1] = ("使用地图AB线 %s"):format(m.ab.name or "")
        end
    end

    local function step4_default_start()
        -- 默认起始小区 = 路径算法首节点(显示排=rows-row, 显示列=column+1)
        local m = STORE.map_get(W.map)
        if not (m and PATHALGO) then return end
        local path = PATHALGO.create_path(m, r16(LW.TW.path_type) or 0,
                                          r16(LW.TW.positive) == 1)
        if path and path[1] then
            w16(LW.TW.start_row, m.rows - path[1].row)
            w16(LW.TW.start_col, path[1].column + 1)
        end
    end

    local function goto_step(n)
        w16(LW.TW.step, n)
        W.sel, W.top = 0, 0
        if n == 1 then
            w16(LW.TW.tstate, 1)
            wstr(LW.TW.mapinfo, "选择地图")
            step1_items()
        elseif n == 2 then
            step2_items()
            local m = STORE.map_get(W.map)
            wstr(LW.TW.mapinfo, m and STORE.map_spec(W.map) or "")
        elseif n == 3 then
            wstr(LW.TW.detail, "0梭形 1同向 2中左 3右梭 4右同 5中右")
        elseif n == 4 then
            step4_default_start()
        end
        render_list()
    end

    ------------------------------------------------------------------ U盘导入
    -- list_dir 固件双时序: 异步经 on_list_dir 路由 / 同步返回 table(见 fileio.lua);
    -- 画面即时反馈: 扫描中... -> 回调刷新 / 回调超时(约3s, on_tick 判定)提示
    local tick_n = 0
    local scan_deadline = nil                 -- 非 nil = 扫描挂起中
    local SCAN_TICKS = math.max(5, math.ceil(3000 / (ctx.poll_ms or 200)))

    local function usb_import()
        if not FILEIO then return end
        if not STORE then wstr(LW.TW.detail, "数据层不可用"); return end
        if scan_deadline then wstr(LW.TW.detail, "扫描中,请稍候"); return end
        wstr(LW.TW.detail, "扫描U盘中...")
        local names = {}
        scan_deadline = tick_n + SCAN_TICKS
        -- list_dir 异步: 发起列举, 回调在 on_list_dir 路由(见 fileio.lua)
        local ok, err = FILEIO.list("2:", function(list, dir)
            scan_deadline = nil
            if not list then
                log("ERR", "列目录失败 " .. tostring(dir))
                wstr(LW.TW.detail, "扫描失败(未插U盘?)")
                return
            end
            -- 虚拟屏平台 list_dir 不回调, pump 收割空表:
            -- 回退约定清单 2:maps.txt(每行一个 map 文件名, 与 csv 同 GB2312)
            -- 实物屏 list_dir 正常枚举, 清单非必需, 二者无害共存
            if #list == 0 then
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
                ("U盘导入 %d 张地图"):format(imported))
            if #msgs > 0 then log("ERR", msgs[1]) end
            wstr(LW.TW.detail,
                imported > 0 and ("导入%d张地图"):format(imported)
                or "无地图文件(或未插U盘)")
            -- 刷新步骤1列表
            if r16(LW.TW.step) == 1 then
                W.sel, W.top = 0, 0
                step1_items()
                render_list()
            end
        end)
        if not ok then
            scan_deadline = nil
            wstr(LW.TW.detail, "U盘不可用")
            log("ERR", "U盘未插入或不可读")
        end
    end

    ------------------------------------------------------------------ 按钮处理
    local function on_btn(addr, val)
        if val ~= 1 then return end
        if addr == LW.TW.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            render_list()
        elseif addr == LW.TW.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            render_list()
        elseif addr == LW.TW.btn_cancel then
            W.map = nil
            goto_step(1)
        elseif addr == LW.TW.btn_sel then
            local step = r16(LW.TW.step) or 1
            if step == 1 then
                if W.sel == 0 then
                    usb_import()
                else
                    local names = STORE and STORE.map_list() or {}
                    W.map = names[W.sel]
                    if W.map then goto_step(2) end
                end
            elseif step == 2 then
                W.use_ab = (W.sel == 1)
                goto_step(3)
            else
                goto_step(math.min(step + 1, 4))
            end
        elseif addr == LW.TW.btn_prev then
            local step = r16(LW.TW.step) or 1
            if step > 1 then goto_step(step - 1) end
        elseif addr == LW.TW.btn_import then
            usb_import()
        elseif addr == LW.TW.btn_ok then
            -- 步骤4: 创建任务并启动
            local m = STORE.map_get(W.map)
            if not m then goto_step(1); return end
            local drow = math.max(0, math.min(m.rows - 1,
                m.rows - (r16(LW.TW.start_row) or m.rows)))
            local dcol = math.max(0, math.min(m.cols - 1,
                (r16(LW.TW.start_col) or 1) - 1))
            local seq = #STORE.task_list() + 1
            local name = "任务" .. seq
            local ok, err = STORE.task_create(name, W.map,
                r16(LW.TW.path_type) or 0, r16(LW.TW.positive) or 0,
                r16(LW.TW.sow_exceed) or 0, drow, dcol, NOW())
            if not ok then
                log("ERR", "任务创建失败: " .. tostring(err))
                wstr(LW.TW.detail, "创建失败 " .. tostring(err):sub(1, 24))
                return
            end
            log("CMD", ("创建任务 %s 地图=%s"):format(name, W.map))
            local ok2, err2 = JOBRUN.start(name)
            if not ok2 then
                log("ERR", "作业启动失败: " .. tostring(err2))
                wstr(LW.TW.detail, "启动失败 " .. tostring(err2):sub(1, 24))
                return
            end
            w16(LW.TW.tstate, 2)
            wstr(LW.TW.detail, "作业中 " .. name)
        elseif addr == LW.TW.btn_resume then
            -- 续接: 找最近的未完成任务
            for _, n in ipairs(STORE.task_list()) do
                local t = STORE.task_get(n)
                if t then
                    local d, tot = STORE.task_progress(n)
                    if d < tot then
                        local ok, err = JOBRUN.start(n, { resume = true })
                        if ok then
                            w16(LW.TW.tstate, 2)
                            wstr(LW.TW.detail, "续作 " .. n)
                        else
                            wstr(LW.TW.detail, tostring(err):sub(1, 24))
                        end
                        return
                    end
                end
            end
            wstr(LW.TW.detail, "无可续接任务")
        end
    end

    ------------------------------------------------------------------ 页面表
    local page = {
        id = LW.SCREEN.TASK,                     -- 画面号(数字, APP.set_screen 按 pages[6] 路由)
        on_enter = function()
            if JOBRUN.active() then
                local cs = JOBRUN.snapshot()
                w16(LW.TW.tstate, (cs and cs.completed) and 3 or 2)
            elseif W.map then
                goto_step(r16(LW.TW.step) or 1)
            else
                goto_step(1)
            end
        end,
        on_leave = function() end,
        poll_cmds = {},
        addrs = {                                -- 按钮地址声明(APP.by_addr 路由必需)
            LW.TW.btn_up, LW.TW.btn_down, LW.TW.btn_sel, LW.TW.btn_prev,
            LW.TW.btn_ok, LW.TW.btn_cancel, LW.TW.btn_resume, LW.TW.btn_import,
        },
        on_frame = function(f)
            if f.fnc == ctx.PROTOCOL.FNC.GET_BZ_STATUS then
                job_view()
            end
        end,
    }

    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用, 点定义会错位收 self)
        on_btn(addr, val)
    end

    -- 作业视图刷新(0x21 被 jobrun 常驻截获, 页面用 tick 级轻刷新)
    function job_view()
        if not JOBRUN.active() then
            if (r16(LW.TW.tstate) or 0) == 2 then
                w16(LW.TW.tstate, 3)
            end
            return
        end
        local s = JOBRUN.snapshot()
        if s then
            if s.completed then w16(LW.TW.tstate, 3) end   -- 完成待手动停止
            -- 显示排=rows-r(0基->1基显示口径, 对齐向导页与冻结规格); cur_col+1
            w16(LW.TW.cur_row, s.rows and (s.rows - (s.cur_row or 0)) or (s.cur_row or 0))
            w16(LW.TW.cur_col, (s.cur_col or 0) + 1)
            w16(LW.TW.done_cnt, s.done or 0)
            w16(LW.TW.total_cnt, s.total or 0)
            w16(LW.TW.pct, s.pct or 0)
        end
    end

    -- 页面 tick 钩子: 扫描回调超时判定 + 作业进度轻刷新(APP.tick 末尾调用, 若存在)
    page.on_tick = function()
        tick_n = tick_n + 1
        if scan_deadline and tick_n > scan_deadline then
            scan_deadline = nil
            wstr(LW.TW.detail, "扫描无响应(未插U盘?)")
            log("WRN", "list_dir 回调超时(异步无果)")
        end
        job_view()
    end

    return page
end

]==]

_MODS["page_history.lua"] = [==[
--[[
page_history.lua —— 历史记录页(0x1900~, 画面7, B档)
================================================================================
任务列表(多行字符串+上下移) → 查看明细(各排结果) / 导出U盘 / 删除。
明细: 任务规格 + 已完成排的结果摘要(起止时间/穴肥合计)。
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
        return STORE and STORE.task_list() or {}   -- B档数据层降级容错
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
        if #lines == 0 then lines[1] = " 无记录" end
        wstr(LW.HIST.list, table.concat(lines, "\r\n"))
        w16(LW.HIST.count, #S.items)
        -- 2026-09-10 修: 回写选中项/列表首项(此前只写列表文本, 画面数值控件恒0)
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
        local lines = { ("%s 地图=%s"):format(n, t and t.map or "?") }
        if t then
            lines[#lines + 1] = ("路径%d 方向%d 起点%d,%d"):format(
                t.path_type or 0, t.positive or 0,
                (t.outset and t.outset.r or 0) + 1,
                (t.outset and t.outset.c or 0) + 1)
            -- 结果摘要: 最近几条(旧->新取尾部)
            local res = STORE.results[n] or {}
            local from = math.max(1, #res - 5)
            for i = from, #res do
                local e = res[i]
                local ss, fs = 0, 0
                for _, v in ipairs(e.seed or {}) do ss = ss + v end
                for _, v in ipairs(e.fert or {}) do fs = fs + v end
                lines[#lines + 1] = ("排%s 穴%d 肥%d %s"):format(
                    tostring(e.row), ss, fs,
                    (e.end_t or ""):sub(1, 10))
            end
            local d, tot, pct = STORE.task_progress(n)
            lines[#lines + 1] = ("完成 %d/%d %d%%"):format(d, tot, pct)
        end
        wstr(LW.HIST.detail, table.concat(lines, "\r\n"))
    end

    local function export_usb()
        local n = selected_name()
        if not n then return end
        if not FILEIO then log("ERR", "fileio未注入"); return end
        local txt = STORE.export_task_text(n)
        -- U盘文件名必须纯ASCII(屏端文件系统限制, 真机实测), 用 store.slug;
        -- 导出的CSV内容里 #TASK 行仍是中文显示名
        local fname = "result_" .. (STORE.slug and STORE.slug(n) or n) .. ".csv"
        local ok, err = FILEIO.write_all("2:" .. fname, txt)
        log(ok and "INF" or "ERR",
            ok and ("导出任务 " .. n .. " -> " .. fname)
               or ("导出失败 " .. tostring(err)))
    end

    local page = {
        id = LW.SCREEN.HISTORY,                   -- 画面号(数字, APP.set_screen 路由)
        on_enter = function()
            refresh_list()
            render_detail()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {                                 -- 按钮地址声明(APP.by_addr 路由必需)
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
                    log("CMD", "删除任务 " .. n)
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
page_logview.lua —— 日志查看页(0x1A00~, 画面8, B档)
================================================================================
日志窗口多行显示(尾部对齐=最新在下), 上/下翻页, 跳最新, 清空, 导出U盘。
--]]

return function(ctx)
    local LW = ctx.LW
    local LOGGER, FILEIO = ctx.LOGGER, ctx.FILEIO
    local w16, wstr = ctx.w16, ctx.wstr

    local VIEW_ROWS = 8
    local top = 1                     -- 窗口首条(1基, 旧->新)

    local function refresh()
        local cnt = LOGGER and LOGGER.count() or 0
        if cnt == 0 then
            top = 1
            wstr(LW.LOGV.view, " 无日志")
        else
            if top > cnt then top = math.max(1, cnt - VIEW_ROWS + 1) end
            if top < 1 then top = 1 end
            local lines = LOGGER.view(top, VIEW_ROWS)
            wstr(LW.LOGV.view, table.concat(lines, "\r\n"))
        end
        w16(LW.LOGV.count, cnt)
    end

    local page = {
        id = LW.SCREEN.LOGVIEW,                   -- 画面号(数字, APP.set_screen 路由)
        on_enter = function()
            -- 进入时跳到最新(尾部)
            local cnt = LOGGER and LOGGER.count() or 0
            top = math.max(1, cnt - VIEW_ROWS + 1)
            refresh()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {                                 -- 按钮地址声明(APP.by_addr 路由必需)
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
                    LOGGER.log("CMD", "日志清空")
                end
                top = 1
                refresh()
            elseif addr == LW.LOGV.btn_exp then
                if FILEIO and LOGGER then
                    local ok, err = FILEIO.copy("3:log.txt", "2:log_export.txt")
                    LOGGER.log(ok and "INF" or "ERR",
                        ok and "日志导出" or ("导出失败 " .. tostring(err)))
                    refresh()
                end
            end
        end,
    }

    return page
end

]==]
-- END _MODS

--================ 模块加载: dofile 优先(官方支持), load() 内嵌兜底 =================
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
            -- page_*.lua 顶层 return creator(ctx) 函数而非 table, 两者均视为加载成功
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

--================ 装配 =================
local APP, PROTOCOL, CODEC, LWMAP
local FILEIO, CSV, STORE, PATHALGO, LOGGER, JOBRUN
local pages = {}

-- 屏端时间源(B档): 平台时间 API 未验证, 退化为开机秒计数 "T+<n>s"
-- (仅进日志/结果时间字段, 不参与业务计算; 实物验证项: 替换为官方 RTC)
local tick_cnt = 0
local function now_s()
    return ("T+%ds"):format(tick_cnt // 2)   -- POLL_MS=500 -> 2次/秒
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

    -- B档数据层(整体 pcall 隔离: 2026-09-08 虚拟屏实测 logger.init 读 3:log.txt
    -- 时 file_open 返回 boolean, 类型比较异常曾炸掉整个 on_init 致串口静默;
    -- 任一环节异常只降级 B 档, 不阻断 A 档页面装配)
    FILEIO = load_mod("fileio.lua")
    if FILEIO then
        local okb, berr = pcall(function()
            FILEIO.wire()                          -- 绑官方 file_*/list_dir/feed_dog 全局
            local apis, marks = FILEIO.apis(), {}  -- O-1 探测: 打印平台文件 API 存在性
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
                LOGGER.log("SYS", "屏端启动")
            end
            JOBRUN   = STORE and load_mod("jobrun.lua") or nil
            if JOBRUN then
                JOBRUN.init {
                    APP = APP, PROTOCOL = PROTOCOL, CODEC = CODEC,
                    STORE = STORE, PATHALGO = PATHALGO, LOGGER = LOGGER,
                    LW = LWMAP, w16 = w16, w32 = w32, wstr = wstr, now = now_s,
                }
            end
            if STORE then STORE.boot() end         -- 掉电恢复(空片首启不报错)
        end)
        if not okb then
            CSV, STORE, PATHALGO, LOGGER, JOBRUN = nil, nil, nil, nil, nil
            wstr(LWMAP.A.log, "B档装配异常已降级(详情见print)")
            print("[HMI] B-tier setup FAILED(降级A档): " .. tostring(berr))
        end
    else
        wstr(LWMAP.A.log, "fileio load fail(B档功能不可用)")
    end

    -- 加载页面模块(creator 收 ctx 返回 page 表)
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
                local okp, page = pcall(creator, ctx)   -- creator 异常只跳过该页
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

--================ 系统回调 =================
function on_init()
    print("[HMI] on_init enter")
    print("[HMI] api: set_uint16=" .. type(set_uint16) .. " set_int32=" .. type(set_int32)
        .. " set_string=" .. type(set_string) .. " get_uint16=" .. type(get_uint16)
        .. " uart_send=" .. type(uart_send) .. " uart_send_data=" .. type(uart_send_data))

    uart_free_protocol = 1                 -- 开启自由串口协议(被动回调模式)
    if uart_set_timeout then uart_set_timeout(UART_CH, 0) end

    -- 发送函数探测(模块加载前先排除平台API问题)
    local txfn_addr = 0x1018
    if type(uart_send) == "function" then w16(txfn_addr, 1)
    elseif type(uart_send_data) == "function" then w16(txfn_addr, 2) end

    w16(0x1017, 1)                         -- 诊断码1: on_init 已执行
    if not setup() then
        w16(0x1017, 3)                     -- 诊断码3: 模块加载失败
        wstr(0x1060, "module load FAILED (see print)")
        print("[HMI] module load FAILED")
        return
    end
    w16(0x1017, 2)                         -- 诊断码2: 模块OK进入轮询

    set_run_cycle(POLL_MS)                 -- on_run 轮询周期(仅 on_init 设置)
    APP.set_screen(LWMAP.SCREEN.HOME)      -- 初始页: 触发 on_enter(版本查询=链路自检)

    print("[HMI] on_init done")
end

function on_run(screen)
    tick_cnt = tick_cnt + 1
    if APP then APP.tick() end             -- 心跳+当前页轮询(节流在 APP)
    if FILEIO then FILEIO.pump() end       -- list_dir 条目流泵(静默超时收割)
end

-- 官方 list_dir 异步回调: 每扫描到一个条目调用一次(签名 2026-09-08 核实):
--   path=目录 / filename=条目名 / type 0文件夹 1文件 / fsize=字节数
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

-- U盘插拔(官方回调): M系列盘符 "2"
function on_usb_inserted(driver)
    print("[HMI] usb inserted: " .. tostring(driver))
    if LOGGER then LOGGER.log("SYS", "U盘插入 " .. tostring(driver)) end
end
function on_usb_removed()
    print("[HMI] usb removed")
    if LOGGER then LOGGER.log("SYS", "U盘拔出") end
end

-- 串口接收回调: 官方名 on_uart_recv(ch, data), data 为字符串
local uart_rx_logged = false
function on_uart_recv(ch, data)
    if ch ~= UART_CH then return end
    if APP then APP.diag(6) end            -- 诊断码6: 收到串口字节
    if not uart_rx_logged then
        uart_rx_logged = true
        print("[HMI] uart rx callback alive, ch=" .. tostring(ch))
    end
    if not PROTOCOL then return end
    PROTOCOL.feed_bytes(packet_to_str(data))
end
on_uart_recv_data = function(packet) on_uart_recv(UART_CH, packet) end

-- 【根因教训 2026-08-28】复位只对已注册按钮地址写0, 绝不波及其他 LW;
-- 未注册地址(数值控件/协议状态写入)一律放行不干预。
function on_update(slave, vtype, addr)
    if vtype ~= VT_LW then return end
    if not APP then return end
    local v = r16(addr)
    if v ~= 1 then return end              -- 只响应写1
    APP.on_button(addr)                    -- 路由到页面(内部复位按钮)
end

function on_screen_change(screen)
    if APP then APP.set_screen(screen) end
end

function on_draw(screen_id, control_id)
end
