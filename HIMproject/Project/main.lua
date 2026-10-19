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
local UART_CH       = 2      -- 副RS232(2026-10-19二十一修: HMI80480KM070通道表
                               --   0=主RS485 1=UART2 TTL未初始化 2=副RS232;
                               --   UartSetup=0须Lua显式uart_setup, 否则崩屏)
local POLL_MS       = 200    -- 状态轮询周期 ms(2026-10-15: 500->200对齐QT STATUSINTERVAL, 修末拍计数少1)
local ROWS          = 4      -- 下位机行数: 4=hd3005a1源码 / 6=平板版; 联调模拟器默认4
local TX_ONE_BASED  = true   -- 发送字节数组下标约定: true=从1起(大彩文档用法)

-- 模块清单(新页面在此追加, deploy_screen.py 同步扫描同列表)
local MODULES = {
    "lwmap.lua", "protocol.lua", "codec.lua", "app.lua",
    "page_userparam.lua", "page_manuparam.lua", "page_continuous.lua",
    "page_testdiag.lua",
    -- B档新增: 文件IO/CSV/数据层/路径算法/作业调度/日志/3新页面
    "fileio.lua", "csv.lua", "store.lua", "pathalgo.lua", "logger.lua", "parastore.lua", "jobrun.lua",
    "page_taskmgr.lua", "page_sowrt.lua",   -- 2026-10-13拆页: 任务管理(画面9+新建25弹窗)/实时播种(画面24); page_task退役
    "page_history.lua", "page_logview.lua",
    "page_map.lua", "mapdraw.lua",                            -- 地图导入页(2026-09-24新增, 画面9)
}

--================ 平台适配层 =================
local function w16(addr, v)
    -- addr/v双守卫(nil地址曾以set_uint16 arg2=nil炸穿回调, 2026-10-08)
    if set_uint16 and v and addr then set_uint16(VT_LW, addr, v & 0xFFFF) end
end
local function w32(addr, v)
    if set_int32 and v and addr then set_int32(VT_LW, addr, v) end
end
local function wstr(addr, s)
    if set_string and s then pcall(set_string, VT_LW, addr, s) end
end
local function r16(addr)
    if get_uint16 then return get_uint16(VT_LW, addr) end
end
local function rstr(addr, len)                   -- 读字符串变量(2026-10-14
    -- 五修·布局实测: 用户dump "C8CE CEF1 3100"="任务1" -> 每LW字打包
    -- 2字节且高字节在前(首字符在hi); 半字NUL即终止
    len = len or 32
    local t = {}
    for i = 0, len - 1 do
        local v = get_uint16
                      and get_uint16(VT_LW, addr + i)
        if not v or v == 0 then break end
        local hi = (v >> 8) & 0xFF
        local lo = v & 0xFF
        if hi == 0 then break end
        t[#t + 1] = string.char(hi)
        if lo == 0 then break end
        t[#t + 1] = string.char(lo)
    end
    return table.concat(t)
end
local function r32(addr)
    if get_uint32 then return get_uint32(VT_LW, addr) end
    if get_uint16 then                            -- 降级: 拼两个 u16(小端)
        local lo = get_uint16(VT_LW, addr) or 0
        local hi = get_uint16(VT_LW, addr + 1) or 0
        return hi * 0x10000 + lo
    end
end

-- RW 掉电保持区读写(VT_RW=2); 虚拟屏对VT_RW可能抛错或空片读回nil
-- (2026-09-30用户实测虚拟屏进测试无任何下发, 根因即rw16抛错炸穿on_update
--  回调链 -> parastore.begin中断; pcall防护后异常等价于无副本, 链仍发帧)
local function rw16(addr)
    if get_uint16 then
        local ok, v = pcall(get_uint16, VT_RW, addr)
        if ok then return v end
    end
end
local function rw16w(addr, v)
    if set_uint16 then
        pcall(set_uint16, VT_RW, addr, v & 0xFFFF)
    end
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
    -- 画面1(原小区参数)/画面3(原AB线管理)已删除(2026-09-23: 前者为早期手动
    -- 下发参数测试页; 后者并入任务页AB操作, 见 LW.TW.ab_*), 画面号不复用
    MAP        = 1,   -- 地图导入页(2026-09-24新增, 原画面1小区参数已删, 复用编号:
                      --   U盘导入/列表/删除/AB绑定)
    CONTINUOUS = 2,   -- 连续播种
    USERPARAM  = 3,   -- 用户参数页(2026-09-28自原参数页拆分; 含[厂家参数]入口)
    MANUPARAM  = 4,   -- 厂家参数页(经用户参数页密码弹窗进入)
    PWDLG      = 23,  -- 密码输入对话框画面(仅作功能按钮弹出内容)
    TESTDIAG   = 5,   -- 测试诊断
    -- 画面6任务作业页已退役(2026-10-13拆页重构: 任务管理=画面9 +
    --   实时播种=画面24 + 新建任务弹窗=画面25, 对齐QT FormTask/
    --   DialogRealtimeTask/DialogNewTask; LW.TW地址区随page_task退役,
    --   0x1800~0x18FF空闲可复用)
    HISTORY    = 7,   -- 历史记录(B档新增)
    LOGVIEW    = 8,   -- 日志查看(B档新增)
    -- 画面9空闲(地图导入页曾用, 2026-09-24改放画面1)
    ABDLG      = 22,  -- AB线对话框画面(仅作功能按钮"打开对话框"的弹出内容)
    TASKMGR    = 9,   -- 任务管理页(2026-10-13拆页: 列表/详情/地图画布/
                      --   新建删除导入导出重置/开始任务; 画面6退役)
    SOWRT      = 24,  -- 实时播种页(拆页: 左信息栏+右地图画布+启停;
                      --   自任务管理页[开始任务]进入)
    NEWTASK    = 25,  -- 新建任务对话框(名称+地图选择, 对齐QT DialogNewTask)
}

--==================== 全局状态区(0x1002~0x102F) ====================
-- 与 POC 阶段 main.lua 实测可用地址保持一致(勿动已验证地址)
LW.A = {
    offlen  = 0x1005, -- i32 排列行程cm(0x21, jobrun常驻写入; 连播页/任务页共用,
                       --   2026-09-29自QT语义恢复: 两页显示同一数据源)
    voff    = 0x1007, -- i32 列行程(垂直偏移)cm(0x21; 有AB线时按QT :345-356符号翻转)
    -- 0x1009~0x100F 原主页漏肥/漏株显示区已删除(2026-09-24: 主页纯导航,
    -- 计数显示统一走测试诊断页 td_loufei1-6/td_louzh1-6), 地址释放可复用
    tx_cnt   = 0x1014, -- u16 发帧计数(lua心跳, on_run活着就会动)
    rx_cnt   = 0x1015, -- u16 收帧计数
    runstate = 0x1019, -- u16 运行状态RunState(0停止/1准备/0x81播种; 2026-09-29
                       --   恢复: 连播页/任务页运行灯共用)
    link     = 0x1013, -- u16 链路状态 0=通信中断 1=在线(app.lua心跳判定,
                       --   掉线=连续3个1s探测周期无0x22应答; 画面绑指示灯控件)
    -- 注: LW>=0x1000 的存储器地址均可正常读写(早期"0x1016禁写"为误判, 2026-09-23更正)
    diag     = 0x1017, -- u16 诊断码(见 app.lua APP.diag)
    txfn     = 0x1018, -- u16 发送函数探测 1=uart_send 2=uart_send_data 0=都没有
    -- 字数口径(2026-09-30真机标定): 文本控件1字=1个ASCII字符
    -- (24字配额只显示23字符证实), set_string按串长写入不清尾, 串间留隔离
    ver      = 0x1024, -- 字符串 下位机版本号(0xA3); 实际串37字符
                       --   "hd3005a2_sim v1.7 20260820_2,vol:12.1",
                       --   占0x1024~0x1049 共40字(8/24字两版皆截断, 画面配40)
    appver   = 0x104A, -- 字符串 屏端程序版本"0.5.0(2026.9.30)"=15字符,
                       --   占0x104A~0x1059 共16字(QT formconfig:31-33风格,
                       --   main启动写一次; 与log留6字隔离, 画面配16)
    log      = 0x1060, -- 字符串 调试串(0x22心跳全局刷新, GB2312直通;
                       --   占0x1060~0x109F 共64字, 文本控件字数配64)
    -- 0x10A0~0x10FF空闲(绘图试验页画面26已删除, 2026-10-16)
}

-- 全局按钮区 LW.B(0x1100~0x1103)已删除(2026-09-24): 主页改为纯导航,
-- 启停/版本/调试按钮职能分别移至任务作业页与全局心跳(app.lua),
-- 0x1100区地址空闲可复用(画面跳转用功能按钮直配, 不占LW)。

-- 0x1300~0x13FF 原页面1(小区参数手动下发测试页)地址区随页面一并删除(2026-09-23)

--==================== 页面2 连续播种(0x1400~, LXBZParaType 12B) ====================
LW.CONT = {
    -- 2026-09-29农艺语义修正(用户): 行长×行距=1亩(666.67m²) -> 行长非人工
    -- 输入, 由用户参数HJ(行距,pu_hj)折算: 行长cm=6666700/行距cm; 株数数值
    -- =密度(ZhuShu=0固件按1亩面积GetZhuShu恰得密度); 株距=行长*10/(密度-1)
    -- 四舍五入只读显示。仅密度人工输入(原hju/celllen输入已删; 漏肥/漏株计数与测试诊断页共用
    --   td_loufei1-6/td_louzh1-6, 2026-09-29 cont_loufei*/cont_louzh*已删)。
    density = 0x1400,     -- i32 输入 密度(株/亩)
    zhuju   = 0x1404,     -- i32 只读 株距cm(计算显示)
    speed   = 0x1408,     -- i32 只读 速度mm/s(0x21)
    start   = 0x1430,     -- 按钮 启动连续播种 -> 0x11
    stop    = 0x1431,     -- 按钮 停止连续播种 -> 0x12
}

--==================== AB线显示区(0x1500~, BDParaType 56B) ====================
-- 原页面3(AB线管理)已删除(2026-09-23): 显示区保留, 由任务页承载;
-- 操作按钮在 LW.TW.ab_*(查看/导入/清除/保存), 采集应答经 jobrun 全局0x23路由。
-- double/float 屏端无原生控件: lua 读值后 string.format 写字符串控件显示
LW.AB = {
    -- 字符串区按 %.7f 最长11字符=6字/串 重排(2026-09-24; 旧版每串2字会互相
    -- 覆盖截断); 方向角 %.3f=6字符=3字, 配4字余量
    startn      = 0x1500, -- 字符串 A点纬度  (占0x1500~0x1505 共6字)
    starte      = 0x1506, -- 字符串 A点经度  (占0x1506~0x150B 共6字)
    endbn       = 0x150C, -- 字符串 B点纬度  (占0x150C~0x1511 共6字)
    endbe       = 0x1512, -- 字符串 B点经度  (占0x1512~0x1517 共6字)
    startdir    = 0x1518, -- 字符串 起始方向角(占0x1518~0x151B 共4字)
    calcdir     = 0x151C, -- 字符串 计算方向角(占0x151C~0x151F 共4字)
    startstate  = 0x1520, -- u16 StartState
    calcdirflag = 0x1521, -- u16 CalcDirFlag
    offlen      = 0x1522, -- u16 OffLen 偏移量
    bdofftime   = 0x1523, -- u16 BDOffTime
    arow        = 0x1524, -- u16 A点排(0基, 地图本地属性; 0x23应答无此字段,
                          --   保存模式显示0, 查看模式显示地图绑定值)
    abdir       = 0x1525, -- u16 方向 0=反向/1=同向(查看模式填地图绑定值)
    -- 原操作按钮(0x1520~0x1523)已随页面3删除, 区址让位给数值字段
}

--==================== 页面4 参数页(0x1600~, TerParaType 40B + UserParaType 16B) ====================
-- 范围/默认值列由 params 任务从 hd3005a1/Src/para.c ParaLegalCheck 核对后固化
LW.PF = {                  -- 厂家参数(2026-09-16对齐QT formconfig.cpp:77~91厂家参数组)
    a           = 0x1600,  -- i16 A 下种口距离(LW/协议均cm, 控件2位小数显m)
    b           = 0x1601,  -- i16 B 种子落地距离(cm, 控件2位小数显m)
    encodenum   = 0x1602,  -- u16 EncodeNum 编码器变送比(QT叫TransmissionRatio)
    encoderdir  = 0x1603,  -- u16 EncoderDir 编码器方向 0=正 1=反(QT下拉框)
    holenum     = 0x1604,  -- u8 HoleNum 播种盘孔数
    gearratio   = 0x1605,  -- u16 GearRatio 电机减速比
    microstep   = 0x1606,  -- i16 MicroStepValue 步进电机细分值
    x1          = 0x1607,  -- i16 X1 天线距离(cm, 2位小数显m; 与PU.antennadist两个字段)
    bdiroff     = 0x1608,  -- i16 BDiroff 反向距离修订(cm, 2位小数显m)
    tapptrigoff = 0x1609,  -- i16 TappTrigOff 打点器到行程开关距离(cm, 2位小数显m)
    tappertime  = 0x160A,  -- u16 TapperTime 打点时间(LW存0.01s单位, 控件2位小数显s,
                           --   pack*10->ms / show四舍五入//10; 协议与QT存储均ms)
    zeroposen   = 0x160B,  -- u8 开关 ZeroPosEn 零位开关(QT复选框)
    gzen        = 0x160C,  -- u8 开关 GZEn 刮种(QT复选框ScrapeSeed, global.cpp:72)
    prepercent  = 0x160D,  -- u8 PrePercent 预充种百分比%
    devtype     = 0x160E,  -- u8 设备类型(=0x25行数字段U8Resv2): 4=4行机 6=6行机;
                           --   0x26回显固件当前值, 可改, 保存时随0x25下发
                           --   (QT global.cpp:78 DeviceType首字符; 下位机暂未用)
    write       = 0x1641,  -- 按钮 保存 -> 0x25(读表单+范围校验, Resv1取devtype;
                           --   0x1640原读按钮已删, 进页自动0x26快照)
    reset       = 0x1644,  -- 按钮 重置 -> 表单恢复QT默认值(formconfig.cpp:204~221,
                           --   不下发, 需再点保存; 0x1642/43是PU读写)
    pass        = 0x1650,  -- u32 密码输入(数值输入, 占2字; Qt端密码同源)
                           -- 【勿放0x1651】pass占0x1650~51, 0x1651是其高字, 写密码会误触发
}
LW.PU = {                  -- 用户参数
    dztime       = 0x1620, -- u16 DZTime 点滞时间
    hj           = 0x1621, -- i16 HJ
    rmp          = 0x1622, -- u32 RMP (占2字)
    antennatype  = 0x1624, -- u8 AntennaType 天线类型
    antennadist  = 0x1625, -- i16 AntennaDistance 天线距离
    gappoint     = 0x1626, -- u16 过道打点 三态: 0=关 1=开 2=间隔(隔趟打点,
    -- 株距微调表5档(2026-10-08, QT SeedGapFineTuning; 原密度固定4000~6000
    -- 画面静态文本显示, 不占地址; d=微调后密度输入, e=启用开关)
    ft_d1       = 0x1627, -- u16 档1(4000) SpecifiedDensity
    ft_d2       = 0x1628, -- u16 档2(4500)
    ft_d3       = 0x1629, -- u16 档3(5000)
    ft_d4       = 0x162A, -- u16 档4(5500)
    ft_d5       = 0x162B, -- u16 档5(6000)
    ft_e1       = 0x162C, -- u16 开关 档1启用 0/1
    ft_e2       = 0x162D, -- u16 开关 档2
    ft_e3       = 0x162E, -- u16 开关 档3
    ft_e4       = 0x162F, -- u16 开关 档4
    ft_e5       = 0x1630, -- u16 开关 档5
                           --   奇数趟不打偶数趟打, QT:255 outsetColumn/bet%2==0;
                           --   QT原设计在用户参数页(config.ini GapPoint),
                           --   任务启动发0x31; 点[下发参数]持久化RW)
    write        = 0x1643, -- 按钮 保存 -> 0x27(读表单+范围校验+gappoint持久化RW;
                           --   0x1642原读按钮已删(2026-09-30), 进页自动0x28)
    reset        = 0x1645, -- 按钮 重置 -> 表单恢复QT默认值(formconfig.cpp:187~199,
    cfgexp       = 0x1646, -- 按钮 导出配置 -> 3:config.txt 拷贝到 2:U盘
                           --   (QT config.ini兼容格式, UTF-8)
                           --   不下发, 需再点保存)
}

--==================== 页面5 测试诊断(0x1700~, TestModeStateType 4行52B) ====================
LW.TD = {
    encodercnt = 0x1700,   -- u32 编码器计数(占2字)
    bdcnt      = 0x1702,   -- u32 北斗计数(占2字)
    -- 漏肥/漏种各6路(独立地址, 兼容6行机); loufei1/louzh1 为基址代码按 +(i-1)*2 访问
    loufei1    = 0x1704,   -- u32 漏肥计数第1路
    loufei2    = 0x1706,   -- u32 漏肥计数第2路
    loufei3    = 0x1708,   -- u32 漏肥计数第3路
    loufei4    = 0x170A,   -- u32 漏肥计数第4路
    loufei5    = 0x170C,   -- u32 漏肥计数第5路(6行机)
    loufei6    = 0x170E,   -- u32 漏肥计数第6路(6行机)
    louzh1     = 0x1710,   -- u32 漏株计数第1路
    louzh2     = 0x1712,   -- u32 漏株计数第2路
    louzh3     = 0x1714,   -- u32 漏株计数第3路
    louzh4     = 0x1716,   -- u32 漏株计数第4路
    louzh5     = 0x1718,   -- u32 漏株计数第5路(6行机)
    louzh6     = 0x171A,   -- u32 漏株计数第6路(6行机)
    input      = 0x171C,   -- u32 IO输入位图(具名位灯绑位0~14, 见画面配置清单)
    warning    = 0x171E,   -- u32 报警位图(同上, 报警红字)
    ctrl       = 0x1720,   -- u32 输出位图(阀位0~9, 电机位16~22)
    -- 输出一键翻转按钮(2026-09-28对齐QT测试页: 点按=取反当前位再0x09下发;
    -- 原jogno/jogon/jogtrig三件套已删)
    sw0        = 0x1728,   -- 按钮 预落种阀(CtrlNo0)
    sw1        = 0x1729,   -- 按钮 倒种阀(CtrlNo1)
    sw2        = 0x172A,   -- 按钮 清种阀(CtrlNo2)
    sw3        = 0x172B,   -- 按钮 刮种阀(CtrlNo3)
    sw4        = 0x172C,   -- 按钮 阀5(CtrlNo4)
    sw5        = 0x172D,   -- 按钮 阀6(CtrlNo5)
    sw6        = 0x172E,   -- 按钮 阀7(CtrlNo6)
    sw7        = 0x172F,   -- 按钮 阀8(CtrlNo7)
    sw8        = 0x1730,   -- 按钮 阀9(CtrlNo8)
    m1         = 0x1731,   -- 按钮 播种盘1电机(CtrlNo16)
    m2         = 0x1732,   -- 按钮 播种盘2电机(CtrlNo17)
    m3         = 0x1733,   -- 按钮 播种盘3电机(CtrlNo18)
    m4         = 0x1734,   -- 按钮 播种盘4电机(CtrlNo19)
    m5         = 0x1735,   -- 按钮 自动供种电机(CtrlNo20)
    m6         = 0x1736,   -- 按钮 播种盘5电机(CtrlNo21)
    m7         = 0x1737,   -- 按钮 播种盘6电机(CtrlNo22)
    enter      = 0x1740,   -- 按钮 进入测试模式 -> 0x0E
    exit       = 0x1741,   -- 按钮 退出测试模式 -> 0x0F
}

--==================== 页面6 任务向导(0x1800~0x18FF, B档新增) ====================
-- 4步状态机: 1选地图 2选AB线 3选路径方式 4选起始小区
-- 列表交互: 多行字符串控件(选中行前缀">")+上下移按钮, 不依赖触摸列表
-- 字符串占用说明: 占用字数=控件"最大字符数"配置, GB2312下1汉字=2字节=1LW,
--   表内注释跨度为规划上限, 控件配置不得超过
LW.TW = {
    tstate     = 0x1801, -- u16 任务状态 0=无 1=向导中 2=作业中 3=已完成
    count      = 0x1802, -- u16 当前列表可选项数
    selidx     = 0x1803, -- u16 列表选中项(0基)
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
    btn_sel    = 0x1882, -- 按钮 选中/进入下一步
    btn_ok     = 0x1884, -- 按钮 创建任务(步骤4)
    btn_cancel = 0x1885, -- 按钮 取消向导
    btn_resume = 0x1886, -- 按钮 续接未完成任务
    -- AB线操作(2026-09-23自page_abline迁移; 配置期作用于所选地图, 作业期作用于当前地图;
    -- 绑定信息显示复用 LW.AB 地址区, 查看/保存走AB对话框画面22)
    ab_import  = 0x1889, -- 按钮 AB线导入: RW缓存绑定到地图(#AB段落盘)
    ab_clear   = 0x188A, -- 按钮 AB线清除: 解除地图绑定
    btn_start  = 0x188C, -- 按钮 开始作业(任务就绪后启动; 作业中=续趟裸发0x0A)
    btn_stop   = 0x188D, -- 按钮 停止作业(收尾断点+无AB线时弹保存对话框)
}

--==================== 页面9 地图导入(0x1C00~, 2026-09-24新增) ====================
LW.MAP = {
    count      = 0x1C00, -- u16 地图数
    selidx     = 0x1C01, -- u16 列表选中项(0基)
    list       = 0x1C04, -- 字符串 列表多行文本(占0x1C04~0x1C43, 64字)
    detail     = 0x1C44, -- 字符串 选中地图详情(占0x1C44~0x1C63, 32字)
    btn_up     = 0x1C70, -- 按钮 选项上移
    btn_down   = 0x1C71, -- 按钮 选项下移
    btn_sel    = 0x1C72, -- 按钮 查看详情
    btn_del    = 0x1C73, -- 按钮 删除地图
    btn_usb    = 0x1C74, -- 按钮 扫描U盘导入
    view       = 0x1C78, -- u16 地图预览视图 0排列/1编号/2密度(下拉,
                       --   2026-10-13画布预览用)
    ab_import  = 0x1C76, -- 按钮 AB线导入(RW缓存绑定本图)
    ab_clear   = 0x1C77, -- 按钮 AB线清除(解绑本图)
}

--==================== AB线对话框交互区(0x1D00~, 画面22承载) ====================
-- 弹窗由画面侧功能按钮("打开对话框"目标=画面22)打开; 对话框内确认按钮为
-- "关闭对话框"+执行通知(写LW=1), 经 on_update 路由到 jobrun 注册的AB对话框页
LW.ABP = {
    mode     = 0x1D00, -- u16 对话框模式 0=保存命名(需输入名称) 1=查看(只读)
    auto_req = 0x1D01, -- u16 停止后自动弹窗请求(条件触发功能按钮的条件地址)
    name     = 0x1D02, -- 字符串 AB线名称(保存=输入框, 查看=绑定的AB名; 占8字)
    req      = 0x1D10, -- 通知 打开请求(画面按钮执行通知: 1=保存 2=查看)
    confirm  = 0x1D11, -- 通知 确认(关闭对话框按钮执行通知写1)
    cancel   = 0x1D12, -- 通知 取消(关闭对话框按钮执行通知写1)
}

--==================== 密码对话框交互区(0x1D20~, 画面23承载) ====================
-- 2026-09-29补: 此前与SCREEN三键同批丢失(拆页编辑未落盘), 导致page_userparam
-- 创建即抛错(LW.PWD为nil), 页面未注册 -> 用户参数读写按钮无响应的根因
LW.PWD = {
    confirm  = 0x1D20, -- 通知 密码正确确认(关闭对话框按钮执行通知写1 -> 校验进厂家页)
    cancel   = 0x1D21, -- 通知 取消(关闭对话框)
    ok       = 0x1D22, -- u16 解锁标志 1=已解锁(厂家参数页进入校验)
}

--==================== 页面7 历史记录(0x1900~0x19FF, B档新增) ====================
LW.HIST = {
    count    = 0x1900, -- u16 任务总数
    selidx   = 0x1901, -- u16 选中任务(0基)
    list     = 0x2C00, -- 字符串 任务列表(2026-10-19二十修: 移大字符串区
                       --   0x2C00~0x2CFF共512字=1024字节, 原0x1910区64字
                       --   配MaxLen64字节仅容~5行, 9行列表字节级腰斩;
                       --   0x1910~0x194F释放空闲)
    detail   = 0x2000, -- 字符串 结果表(2026-10-16十九修移大字符串区:
                       --   规划0x2000~0x2BFF共3072字; 原0x1950区112字
                       --   装不下14列x多行, 0x1950~0x19BF释放空闲)
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

--==================== 任务管理页(0x1E00~, 画面9承载; 2026-10-13拆页) ====================
LW.TM = {
    list      = 0x2D00, -- 字符串 任务列表多行(2026-10-19二十修: 移
                       --   0x2D00~0x2DFF共256字=512字节; 原0x1E00区48字
                       --   释放给详情字段)
    count     = 0x1E30, -- u16 任务数
    selidx    = 0x1E31, -- u16 列表选中项(0基)
    tname     = 0x1E32, -- 字符串 详情:任务名(占0x1E32~0x1E41, 16字)
    tmap      = 0x1E42, -- 字符串 详情:地图名(16字)
    tcreate   = 0x1E52, -- 字符串 详情:创建时间(16字)
    tlast     = 0x1E62, -- 字符串 详情:上次工作时间(16字)
    tpct      = 0x1E72, -- u16 详情:完成率%
    tremark   = 0x1E74, -- 字符串 详情:备注(占0x1E74~0x1E93, 32字)
    view      = 0x1E94, -- u16 地图画布视图 0排列/1编号/2密度(下拉)
    btn_new   = 0x1E96, -- 按钮 新建任务(开画面25)
    btn_del   = 0x1E97, -- 按钮 删除任务
    btn_imp   = 0x1E98, -- 按钮 从U盘导入任务
    btn_exp   = 0x1E99, -- 按钮 导出任务到U盘
    btn_reset = 0x1E9A, -- 按钮 重置任务(块状态清0)
    btn_up    = 0x1E9B, -- 按钮 列表上移
    btn_down  = 0x1E9C, -- 按钮 列表下移
    btn_sel   = 0x1E9D, -- 按钮 选中查看
    btn_start = 0x1E9E, -- 按钮 开始任务(进画面24)
}

--==================== 新建任务对话框(0x1EA0~, 画面25承载) ====================
LW.NT = {
    name      = 0x1EB0, -- 字符串 任务名输入(占0x1EB0~0x1EBF, 16字)
    mapsel    = 0x1EC0, -- 字符串 当前候选地图名(16字)
    count     = 0x1ED0, -- u16 地图数
    selidx    = 0x1ED1, -- u16 地图选中项(0基)
    btn_ok    = 0x1ED2, -- 按钮 确定创建
    btn_cancel= 0x1ED3, -- 按钮 取消
    btn_up    = 0x1ED4, -- 按钮 地图上移
    btn_down  = 0x1ED5, -- 按钮 地图下移
}

--==================== 实时播种页(0x1F00~, 画面24承载; 排列行程/运行状态复用LW.A) ====================
LW.RT = {
    path_type = 0x1F00, -- u16 路线 0梭形..5(6态, 与画面6同口径)
    positive  = 0x1F01, -- u16 行进方向 0反向/1正向
    sow_exceed= 0x1F02, -- u16 地图外播种 0/1(有AB线才可开)
    gapdot    = 0x1F03, -- u16 清种时打点 0关/1开(bool, 0x29独立下发;
                       --   2026-10-14与过道打点0x31分离, 后者走
                       --   config三态 pu_gappoint)
    sp_enable = 0x1F04, -- u16 更改起点使能
    sp_row    = 0x1F05, -- u16 起始排(显示号1基)
    sp_col    = 0x1F06, -- u16 起始列(显示号1基)
    speed     = 0x1F07, -- i32 速度mm/s(0x21, jobrun常驻写入; 占2字)
    view      = 0x1F09, -- u16 地图画布视图 0排列/1编号/2密度(下拉)
    cur_zh    = 0x1F10, -- u16[6] 当前漏种(0x21 LouZHCnt, 占6字)
    cur_fe    = 0x1F16, -- u16[6] 当前漏肥(LoufeiCnt)
    last_zh   = 0x1F1C, -- u16[6] 最近完成排漏种(快照)
    last_fe   = 0x1F22, -- u16[6] 最近完成排漏肥(快照)
    tname     = 0x1F38, -- 字符串 当前任务名显示(占0x1F38~0x1F47, 16字)
    pct       = 0x1F58, -- u16 完成率%(页面on_tick刷新)
    done      = 0x1F59, -- u16 已完成块数
    tot       = 0x1F5A, -- u16 总块数
    running   = 0x1F5C, -- u16 作业进行中0/1(jobrun启停写; 合并开始/
                       --   停止按钮显示+返回等控件权限条件地址)
    btn_start = 0x1F60, -- 按钮 开始(下发作业链)
    btn_stop  = 0x1F61, -- 按钮 停止
    btn_result= 0x1F62, -- 按钮 任务结果(跳画面7并预选)
    btn_exp   = 0x1F63, -- 按钮 导出结果到U盘
    btn_abclr = 0x1F64, -- 按钮 清除AB线(当前任务地图)
    btn_spply = 0x1F65, -- 按钮 应用新起点(重建任务路径)
}

--==================== RW 掉电保持区(0x0000~0x7FFF, 64KB 按扇区) ====================
-- 注意: 标志位与数据须同 4KB 扇区; 上电读 0xFFFF 须恢复默认; 严禁高频写
-- AB线 BDParaType 56B=28字: magic(0x55AA) + 完整 pack 镜像(CrcCheck置0)
LW.RW = {
    ab_magic = 0x0000, -- u16 AB线有效标志 0x55AA
    ab_data  = 0x0001, -- 28字 BDParaType 完整镜像(page_abline pack, CrcCheck=0)
    -- 参数配置已迁3:config.txt单轨(2026-09-30, QT模式); gap_point随迁,
    -- 参数副本区(0x0020起)整体撤销, RW仅存AB线
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
    QZDD_ENABLE      = 0x29,   -- 清种时打点开关, 收1字节(0/1), 回 ack
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
        for i = 1, #page.addrs do
            local a = page.addrs[i]
            if type(a) == "number" then APP.by_addr[a] = page end
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
    APP.cur = APP.pages[sid]
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
    local page = APP.by_addr[addr]
    if not page then return false end
    APP.diag(5)
    -- v默认1(按钮写1); ABP.req等功能通知可携带模式值(2=查看),
    -- 页面on_update按需读r16获取(2026-10-08: 查看AB线曾被v~=1过滤丢弃)
    v = v or 1
    if page.on_update then safe_call("on_update", page.on_update, page, addr, v) end
    ENV.w16(addr, 0)                    -- 复位按钮
    return true
end

return APP

]==]




_MODS["page_continuous.lua"] = [==[
--[[
page_continuous.lua -- 连续播种页(画面2, 2026-09-28重设对齐QT formcontinuoussow)
================================================================================
QT口径: 用户只须输入密度即可开始; 行距/行长默认60/500可调(屏端无config.ini,
以输入控件默认值承载); 株距=行长*10/(密度-1)四舍五入只读显示(QT :116);
ZhuShu=0自动。运行显示: 排列行程/速度/漏肥漏株各6路(0x21轮询经jobrun常驻
截获存 last_status, 本页 on_tick 取快照刷新显示)。
LW: LW.CONT (0x1400区)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local JOBRUN = ctx.JOBRUN
    local FNC = PROTOCOL.FNC
    local r16, r32, w16, w32, wstr = ctx.r16, ctx.r32, ctx.w16, ctx.w32, ctx.wstr

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

    -- 行长折算(2026-09-29用户农艺语义): 行长×行距=1亩(666.67m²)
    -- -> 行长cm = 6666700cm² / 行距cm
    local function row_len_cm(hju)
        if not hju or hju < 1 then hju = 60 end
        return 6666700 // hju
    end

    local page = {
        id = LW.SCREEN.CONTINUOUS,
        -- 0x21: 应答被 jobrun 常驻订阅截获(更新 jobrun.last_status),
        -- 连续模式无作业不设 always_poll, 由本页 poll 触发请求
        poll_cmds = { FNC.GET_BZ_STATUS },
        addrs = { LW.CONT.start, LW.CONT.stop },
    }

    function page:on_enter()
        w16(LW.CONT.start, 0)
        w16(LW.CONT.stop, 0)
        -- 密度持久化(2026-09-30): 从config.txt预填, 启动时写回(QT同款)
        if ctx.PARASTORE then
            local d = ctx.PARASTORE.load_density()
            if d and d >= 2 then w32(LW.CONT.density, d) end
        end
    end

    function page:on_leave() end

    function page:on_frame() end

    function page:on_update(addr)
        if addr == LW.CONT.start then
            local density = s32(r32(LW.CONT.density))
            local hju     = s16(r16(LW.PU.hj) or 60)   -- 行距取用户参数HJ表单
            local celllen = row_len_cm(hju)
            if density < 2 then
                wstr(LW.A.log, ("× 连续播种启动失败: 密度=%d无效(画面输入控件须绑定"
                                .. "cont_density并启用输入, 设初值如4000)"):format(density))
                return
            end
            if hju < 1 then
                wstr(LW.A.log, "× 连续播种启动失败: 用户参数HJ行距无效(先在用户参数页设置)")
                return
            end
            if ctx.PARASTORE then ctx.PARASTORE.save_density(density) end
            local start_lxbz = function()
                PROTOCOL.send(FNC.CMD_START_LXBZ, CODEC.lxbz.pack {
                    Density = density, CellLen = celllen, Hju = hju, ZhuShu = 0,
                })  -- ZhuShu=0: 固件GetZhuShu按1亩面积(行长×行距)算出株数恰=密度
            end
            -- 2026-09-30对齐QT(formcontinuoussow.cpp:31-38): 先参数链
            -- 0x27成功->0x25->成功->再0x11; 中止则不启动
            if ctx.PARASTORE then
                ctx.PARASTORE.begin("LXBZ", nil, start_lxbz)
            else
                start_lxbz()
            end
        elseif addr == LW.CONT.stop then
            PROTOCOL.send(FNC.CMD_STOP_LXBZ)    -- 空域
        end
    end

    -- 运行显示: 株距计算 + jobrun.last_status 刷新行程/速度/计数
    page.on_tick = function()
        local density = s32(r32(LW.CONT.density))
        local celllen = row_len_cm(s16(r16(LW.PU.hj) or 60))
        if density > 1 and celllen > 0 then
            -- QT formcontinuoussow.cpp:116 株距四舍五入(行长由1亩面积折算)
            w32(LW.CONT.zhuju, (celllen * 10 // (density - 1) + 5) // 10)
        end
        local st = JOBRUN and JOBRUN.last_status
        if st then
            -- 排/列行程由jobrun常驻写入全局a_offlen/a_voff(两页共用), 此处只刷速度;
            -- 漏肥/漏株与测试诊断页共用TD区地址(画面绑同一组标签, cont_*已删)
            w32(LW.CONT.speed,  st.Speed or 0)
            for i = 1, CODEC.ROWS do
                w32(LW.TD.loufei1 + (i - 1) * 2, st.LoufeiCnt[i] or 0)
                w32(LW.TD.louzh1 + (i - 1) * 2, st.LouZHCnt[i] or 0)
            end
        end
    end

    return page
end

]==]


_MODS["page_testdiag.lua"] = [==[
--[[
page_testdiag.lua -- 测试诊断页(画面5, 2026-09-28重设对齐QT formtest)
================================================================================
输入状态: 15盏具名位灯(画面绑 td_input 位0~14, 报警红字绑 td_warning 同位):
  bit0~3 零位1~4 | bit4 自动供种 | bit5 预留 | bit6/7 钢索1/2 | bit8 压力
  bit9 风机 | bit10 脚踏板 | bit11 初始化 | bit12 北斗 | bit13/14 零位5/6
输出控制: 16个一键翻转按钮(阀CtrlNo0~8 + 电机CtrlNo16~22), 点按=读当前
  CtrlState位取反后0x09下发(QT setValveState(ch,!bit)同款);
  电机位在0x08应答的CtrlState里位于bit16~22(固件 DJCtrlState<<16 上报)。
计数: 编码器/北斗 + 漏肥/漏株各6路(随 codec.ROWS 由 0x26 动态切换, 4行残留已修)。
原 jogno/jogon/jogtrig 点动三件套已删(一键翻转取代)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr = ctx.w16, ctx.w32, ctx.wstr

    local last_ctrl = 0                        -- 最近一帧0x08的CtrlState

    -- 输出按钮地址 -> CtrlNo(一键翻转)
    local SW = {
        [LW.TD.sw0] = 0,  [LW.TD.sw1] = 1,  [LW.TD.sw2] = 2,  [LW.TD.sw3] = 3,
        [LW.TD.sw4] = 4,  [LW.TD.sw5] = 5,  [LW.TD.sw6] = 6,  [LW.TD.sw7] = 7,
        [LW.TD.sw8] = 8,
        [LW.TD.m1] = 16, [LW.TD.m2] = 17, [LW.TD.m3] = 18, [LW.TD.m4] = 19,
        [LW.TD.m5] = 20, [LW.TD.m6] = 21, [LW.TD.m7] = 22,
    }

    local page = {
        id = LW.SCREEN.TESTDIAG,
        poll_cmds = { FNC.GET_TEST_STATUS },         -- 0x08 仅本页可见时轮询
        addrs = { LW.TD.enter, LW.TD.exit },
    }
    for a in pairs(SW) do page.addrs[#page.addrs + 1] = a end

    function page:on_frame(f)
        if f.fnc ~= FNC.GET_TEST_STATUS then return end
        local ok, st = pcall(CODEC.teststate.unpack, f.data)
        if not ok then
            wstr(LW.A.log, "teststate unpack err: len=" .. #f.data)
            return
        end
        last_ctrl = st.CtrlState or 0
        w32(LW.TD.encodercnt, st.EncoderCnt)
        w32(LW.TD.bdcnt,      st.BdCnt)
        for i = 1, CODEC.ROWS do
            w32(LW.TD.loufei1 + (i - 1) * 2, st.LoufeiCnt[i])
            w32(LW.TD.louzh1 + (i - 1) * 2, st.LouZHCnt[i])
        end
        w32(LW.TD.input,   st.InputState)
        w32(LW.TD.warning, st.WarningState)
        w32(LW.TD.ctrl,    st.CtrlState)
    end

    function page:on_update(addr)
        if addr == LW.TD.enter then
            -- 2026-09-30对齐QT(formtest.cpp:43-49): 进测试前先参数链
            -- 0x27成功->0x25->成功->0x0E; 中止则不进测试
            local enter_test = function()
                PROTOCOL.send(FNC.CMD_START_TEST)   -- 空域
            end
            if ctx.PARASTORE then
                ctx.PARASTORE.begin("TEST", nil, enter_test)
            else
                enter_test()
            end
        elseif addr == LW.TD.exit then
            PROTOCOL.send(FNC.CMD_STOP_TEST)
        else
            local no = SW[addr]
            if no then
                -- QT语义: 取反当前位再下发
                local state = 0
                if (last_ctrl >> no) & 1 == 0 then state = 1 end
                PROTOCOL.send(FNC.CMD_SVCTRL,
                              CODEC.testcmd.pack { CtrlNo = no, State = state })
            end
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
    -- 写指针归零(2026-10-19二十一修: 覆写模式打开指针不归零,
    -- 单会话残留偏移致已写盘回读不一致, 用户实测)
    if FILEIO.io.seek then pcall(FILEIO.io.seek, 0) end
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
    -- 2026-10-16十四修: 十三修的read_all验证有洞——fopen失败(单会话
    -- 被占/宿主占用)也返回nil, 被误判"已删"(用户实测文件还在但日志
    -- 干净). 改直接fopen探测并立即关闭: 打不开=已删(或本不存在);
        -- 打得开=文件在, 清空兜底并如实标注
    if FILEIO.io and FILEIO.io.delete then
        pcall(FILEIO.io.delete, path)
    end
    local ok0 = fopen(path, 0)
    if ok0 then
        pcall(FILEIO.io.close)
        local okw = FILEIO.write_all and FILEIO.write_all(path, "")
        if okw then
            return true, "已清空(delete未生效): " .. path
        end
        return nil, "删除失败: " .. path
    end
    return true                            -- fopen失败=已删/不存在
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
    -- 手写字节扫描(二十一修: 字符类find屏端不可靠)
    for i = 1, #s do
        local b = string.byte(s, i)
        if b == 44 or b == 13 or b == 10 then
            return false, "名字含逗号或换行"
        end
    end
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

-- "N排"标签手写解析(2026-10-19二十一修: ^(%d+)排$复杂match屏端不可靠)
local function row_label_num(a1)
    local bl, bh = string.byte("排", 1, 2)
    local n = #a1
    if n < 3 then return nil end
    if string.byte(a1, n - 1) ~= bl or string.byte(a1, n) ~= bh then
        return nil
    end
    local digits = string.sub(a1, 1, n - 2)
    for i = 1, #digits do
        local b = string.byte(digits, i)
        if b < 48 or b > 57 then return nil end
    end
    return tonumber(digits)
end

-------------------------------------------------------------------- 区块式解析(2026-10-08)
-- 布局=QT上位机xlsx导出同款(用户样例), 单文件五区块:
--   信息(键值+排长/过道序列藏C/D列) / AB线(BDPara全字段+A点排/A点列/
--   方向/名称) / 编号 / 密度 / 是否播种(矩阵, 行倒序N排在上, 列从B列1基)
-- "; "注释行忽略; 编号区允许空(顺位补), 密度/播种区必须完整
function csv.parse_map_grid(text)
    local msgs = {}
    local m = { name = nil, rows = nil, cols = nil, machine_cols = nil,
                col_gap = nil, rowlen = {}, aisle = {}, block_col = 1,
                blocks = {}, ab = nil, block_cnt = 0 }
    local section = nil
    local rowlen_seq, aisle_seq = {}, {}
    local abf = {}
    local head_pending = {}

    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= ";" then
            local f = csv.split(line)
            local a1 = f[1] or ""
            if a1 == "信息" or a1 == "AB线" or a1 == "编号"
               or a1 == "密度" or a1 == "是否播种" then
                section = a1
                head_pending[section] = true
            elseif section == "信息" then
                if a1 ~= "类型" then              -- 表头行(排长cm/过道长cm)
                    if a1 == "名称" then m.name = (f[2] ~= "" and f[2]) or nil
                        -- 地图显示名(hmi_export; 空串归nil)
                    elseif a1 == "排" then m.rows = num(f[2])
                    elseif a1 == "列" then m.cols = num(f[2])
                    elseif a1 == "小区行数" then m.block_col = num(f[2]) or 1
                    elseif a1 == "机器行数" then m.machine_cols = num(f[2])
                    elseif a1 == "行间距(cm)" then m.col_gap = num(f[2])
                    end
                    local cl, ai = num(f[3]), num(f[4])
                    if cl then rowlen_seq[#rowlen_seq + 1] = cl end
                    if ai then aisle_seq[#aisle_seq + 1] = ai end
                end
            elseif section == "AB线" then
                if a1 ~= "" then abf[a1] = f[2] end
            elseif section == "编号" or section == "密度"
                or section == "是否播种" then
                if head_pending[section] and a1 == "" then
                    head_pending[section] = false  -- ",1列,2列"表头行
                else
                    local rr = row_label_num(a1)            -- 二十一修手写
                    local r = rr and tonumber(rr)
                    if r and m.rows and r >= 1 and r <= m.rows then
                        -- 2026-10-16十七修: N排->内部rows-N(QT :55-83内部0
                        -- 在顶部表头'排N'; 旧N-1映射致文件1排=屏上N排翻转)
                        local r0 = m.rows - r
                        if not m.blocks[r0] then m.blocks[r0] = {} end
                        for c = 2, #f do
                            local c0 = c - 2
                            if m.cols and c0 >= 0 and c0 < m.cols then
                                local cur = m.blocks[r0][c0]
                                           or { num = r0 * m.cols + c0 + 1,
                                                density = 0, sow = 1 }
                                local v = num(f[c])
                                if section == "编号" then
                                    if v ~= nil then cur.num = v end
                                elseif section == "密度" then
                                    cur.density = v or 0
                                else
                                    if v ~= nil then
                                        cur.sow = (v ~= 0) and 1 or 0
                                    end
                                end
                                m.blocks[r0][c0] = cur
                            end
                        end
                    end
                end
            end
        end
    end

    -- 校验与组装(对齐 legacy 口径)
    if not (m.rows and m.cols and m.machine_cols and m.col_gap) then
        msgs[#msgs + 1] = "E:信息区缺排/列/机器行数/行间距"
        return m, msgs
    end
    if #rowlen_seq ~= m.rows then
        msgs[#msgs + 1] = ("E:排长需%d条实有%d"):format(m.rows, #rowlen_seq)
    else
        m.rowlen = rowlen_seq
    end
    -- 旧版render补0自愈(2026-10-13): D列曾在rows+1之后补0, rows<7的
    -- 地图过道超期且尾部全0 -> 截断告警, 已损坏的落盘文件重启可恢复开播
    if m.rows and #aisle_seq > m.rows + 1 then
        local want = m.rows + 1
        local pad = true
        for i = want + 1, #aisle_seq do
            if aisle_seq[i] ~= 0 then
                pad = false
                break
            end
        end
        if pad then
            local extra = #aisle_seq - want
            for _ = 1, extra do aisle_seq[#aisle_seq] = nil end
            msgs[#msgs + 1] = ("W:过道尾部%d条补0已截断(旧版渲染兼容)")
                :format(extra)
        end
    end
    if #aisle_seq ~= m.rows + 1 then
        msgs[#msgs + 1] = ("E:过道需%d条实有%d"):format(m.rows + 1, #aisle_seq)
    else
        m.aisle = aisle_seq
    end
    local want = m.rows * m.cols
    local got = 0
    for r = 0, m.rows - 1 do
        for c = 0, m.cols - 1 do
            if m.blocks[r] and m.blocks[r][c] then got = got + 1 end
        end
    end
    if got ~= want then
        msgs[#msgs + 1] = ("E:密度矩阵需%d块实有%d"):format(want, got)
    end
    m.block_cnt = got
    -- 地图名: 信息区"名称"行(hmi_export生成); 缺省由store用导入文件名兜底

    if abf["StartN"] ~= nil then
        m.ab = { name = abf["名称"] or "ab",
                 sn = tonumber(abf["StartN"]), se = tonumber(abf["StartE"]),
                 en = tonumber(abf["EndBN"]), ee = tonumber(abf["EndBE"]),
                 sdir = tonumber(abf["StartDir"]),
                 cdir = tonumber(abf["CalcDir"]),
                 a_row = tonumber(abf["A点排"]) or 0,
                 a_col = tonumber(abf["A点列"]) or 0,
                 abdir = (abf["方向"] == "TRUE"
                          or abf["方向"] == "1") and 1 or 0,
                 startstate = tonumber(abf["StartState"]) or 1,
                 calcdirflag = tonumber(abf["CalcDirFlag"]) or 1,
                 offlen = tonumber(abf["OffLen"]) or 0,
                 bdofftime = tonumber(abf["BDOffTime"]) or 100,
                 has = true }
        if m.ab.sn == nil or m.ab.se == nil or m.ab.en == nil
            or m.ab.ee == nil or m.ab.sdir == nil or m.ab.cdir == nil then
            m.ab = nil
            msgs[#msgs + 1] = "E:AB线字段数值非法"
        end
    end
    return m, msgs
end

-- 双格式分派: 首个有效行首字段="信息" -> 区块式; 否则旧#段式
function csv.parse_map(text)
    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= ";" then
            local f = csv.split(line)
            if (f[1] or "") == "信息" then
                local m1, m2 = csv.parse_map_grid(text)
                return m1, m2
            end
            break
        end
    end
    -- (局部中转: 避免出现模块尾return字面, 兼容测试的patch注入点)
    local m1, m2 = csv.parse_map_legacy(text)
    return m1, m2
end

-------------------------------------------------------------------- 地图解析
-- #DIM 校验界限
local ROWS_MAX, COLS_MAX, MC_MAX = 200, 200, 16

function csv.parse_map_legacy(text)  -- 旧#段式(2026-10-08前)
    local msgs = {}
    local m = { name = nil, rows = nil, cols = nil, machine_cols = nil,
                col_gap = nil, rowlen = {}, aisle = {},
                blocks = {}, ab = nil, block_cnt = 0 }
    local in_blocks = false
    local seen = {}

    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= ";" then   -- ";"=中文注解行(hmi_export)
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
                    -- 第11~14字段(2026-10-08, QT ABLine表): 起始状态/方向标志/
                    --   偏移长度cm/偏移时间ms; 旧文件缺省=屏端下发语义(1/1/0/100)
                    m.ab = { name = f[2],
                             sn = num(f[3]), se = num(f[4]),
                             en = num(f[5]), ee = num(f[6]),
                             sdir = num(f[7]), cdir = num(f[8]),
                             a_row = num(f[9]) or 0,
                             abdir = num(f[10])
                                 or ((num(f[9]) or 0) == 0 and 1 or 0),
                             startstate = num(f[11]) or 1,
                             calcdirflag = num(f[12]) or 1,
                             offlen = num(f[13]) or 0,
                             bdofftime = num(f[14]) or 100,
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
    -- 区块式(2026-10-08, QT xlsx导出同款布局); 旧#段式文件保存后自动升级
    local L = {}
    local function row(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
        L[#L + 1] = table.concat(t, ",")
    end
    row("信息", "", "", "")
    -- 名称行(2026-10-13补, 对齐hmi_export.render_map_csv): 旧版不写,
    -- 地图经map_save重渲染后名称丢失, 重启boot重载m.name=nil
    if m.name and m.name ~= "" then row("名称", m.name) end
    row("类型", "播种", "排长(cm)", "过道长(cm)")
    -- 信息区: C列=排长(rows条), D列=过道(rows+1条), 标签行固定8个不够留空
    local labels = { "创建时间", "修改时间", "备注", "排", "列",
                     "小区行数", "机器行数", "行间距(cm)" }
    local meta_rows = math.max(8, (m.rows or 0) + 1)
    for i = 1, meta_rows do
        local lab = labels[i] or ""
        local b = ""
        if lab == "排" then b = m.rows or 0
        elseif lab == "列" then b = m.cols or 0
        elseif lab == "小区行数" then b = m.block_col or 1
        elseif lab == "机器行数" then b = m.machine_cols or 6
        elseif lab == "行间距(cm)" then b = fmt_num(m.col_gap or 60) end
        local c = ""
        if i <= (m.rows or 0) then c = fmt_num(m.rowlen[i] or 0) end
        -- D列仅rows+1行(2026-10-13, 对齐hmi_export): 此前行行写值,
        -- rows<7地图回写后过道多出补0条目 -> 重启重载E: -> m.aisle空
        -- -> start_node对nil算术炸断启动链(0x24后0x20/0x31/0x0A全不发)
        local d = ""
        if i <= (m.rows or 0) + 1 then d = fmt_num(m.aisle[i] or 0) end
        row(lab, b, c, d)
    end
    row("", "", "", "")
    if m.ab then
        row("AB线", "", "", "")
        row("StartN", fmt_num(m.ab.sn or 0))
        row("StartE", fmt_num(m.ab.se or 0))
        row("EndBN", fmt_num(m.ab.en or 0))
        row("EndBE", fmt_num(m.ab.ee or 0))
        row("StartDir", fmt_num(m.ab.sdir or 0))
        row("CalcDir", fmt_num(m.ab.cdir or 0))
        row("StartState", m.ab.startstate or 1)
        row("CalcDirFlag", m.ab.calcdirflag or 1)
        row("OffLen", m.ab.offlen or 0)
        row("BDOffTime", m.ab.bdofftime or 100)
        row("Resv", 0)
        row("CrcCheck", 0)
        row("A点排", m.ab.a_row or 0)
        row("A点列", m.ab.a_col or 0)
        row("方向", (m.ab.abdir or 0) == 1 and "TRUE" or "FALSE")
        row("名称", m.ab.name or "")
        row("", "", "", "")
    end
    local function matrix(title, get)
        row(title, "", "", "")
        local hd = { "" }
        for c = 1, m.cols do hd[c + 1] = c .. "列" end
        L[#L + 1] = table.concat(hd, ",")
        for r = m.rows, 1, -1 do
            local vals = { r .. "排" }
            for c = 1, m.cols do
                local b = (m.blocks[m.rows - r] or {})[c - 1]  -- 十七修: 标签N排<-内部rows-N
                           or { num = 0, density = 0, sow = 1 }
                vals[c + 1] = get(b)
            end
            L[#L + 1] = table.concat(vals, ",")
        end
        row("", "", "", "")
    end
    matrix("编号", function(b) return b.num end)
    matrix("密度", function(b) return b.density end)
    matrix("是否播种", function(b) return b.sow end)
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

-- 双格式分派(2026-10-13): 首个有效行首字段="信息" -> Excel式(任务.csv
-- 导出布局); 否则旧#段式(内部3:盘存储格式)
function csv.parse_task(text)
    for line in csv.iter_lines(text) do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local f0 = csv.split(line)
            if (f0[1] or "") == "信息" then
                return csv.parse_task_xlsx(text)
            end
            break
        end
    end
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


-------------------------------------------------------------------- 任务Excel格式(2026-10-13)
-- 仿QT"任务.csv"导出布局(用户样例): 信息键值区 + 状态矩阵 + 是否播种矩阵
-- + 结果表; U盘导出供Excel直接查看(GB2312)。parse_task双格式分派,
-- 导出的文件可再导入(内部3:盘存储仍用#段式, 互不影响)。
local function task_dims(t)
    local rows, cols = 0, 0
    for r, rowb in pairs(t.blocks) do
        if r + 1 > rows then rows = r + 1 end
        for c in pairs(rowb) do
            if c + 1 > cols then cols = c + 1 end
        end
    end
    return rows, cols
end

function csv.render_task_xlsx(t)
    local L = {}
    local function row(...)
        local s = {}
        for i = 1, select("#", ...) do s[i] = tostring(select(i, ...)) end
        L[#L + 1] = table.concat(s, ",")
    end
    local rows, cols = task_dims(t)
    row("信息")
    row("名称", t.name or "")
    row("地图", t.map or "")
    row("创建时间", t.create_time or "")
    row("最后工作时间", t.last_work_time or "")
    row("备注", t.remark or "")
    row("排", rows)
    row("列", cols)
    row("路线类型", t.path_type or 0)
    row("路线方向", (t.positive == 1) and "反" or "正")  -- 十八修: 值1=反(QT语义)
    row("起点排列", (t.outset and t.outset.r) or 0,
        (t.outset and t.outset.c) or 0)
    row("最近完成排列", (t.last and t.last.r) or -1,
        (t.last and t.last.c) or -1)
    row("")
    local function matrix(title, get)
        row(title)
        local hd = { "" }
        for c = 1, cols do hd[c + 1] = c .. "列" end
        L[#L + 1] = table.concat(hd, ",")
        for r = rows, 1, -1 do
            local vals = { r .. "排" }
            for c = 1, cols do
                local b = (t.blocks[rows - r] or {})[c - 1]  -- 十七修
                vals[c + 1] = get(b)
            end
            L[#L + 1] = table.concat(vals, ",")
        end
        row("")
    end
    matrix("状态", function(b) return b and b.state or 0 end)
    matrix("是否播种", function(b)
        return (b and b.sow == 1) and "√" or ""
    end)
    row("结果")
    local hd = { "排", "列", "开始时间", "完成时间", "状态" }
    for i = 1, 6 do hd[#hd + 1] = i .. "行播种" end
    for i = 1, 6 do hd[#hd + 1] = i .. "行漏肥" end
    L[#L + 1] = table.concat(hd, ",")
    -- 排=显示排号(rows-内部行, 对齐QT :324 blockVector.size()-row;
    --   2026-10-14修正: 原r+1与QT口径相反); 列=1基
    for _, e in ipairs(t.results or {}) do
        local vals = { rows - e.r, e.c + 1, e.start_t or "", e.end_t or "",
                       e.state or 0 }
        for i = 1, 6 do vals[#vals + 1] = (e.seed or {})[i] or 0 end
        for i = 1, 6 do vals[#vals + 1] = (e.fert or {})[i] or 0 end
        L[#L + 1] = table.concat(vals, ",")
    end
    return table.concat(L, "\r\n") .. "\r\n"
end

function csv.parse_task_xlsx(text)
    local msgs = {}
    local t = { name = nil, map = nil, path_type = 0, positive = 0,
                sow_exceed = 0, outset = { r = 0, c = 0 },
                last = { r = -1, c = -1 }, state = 0,
                create_time = "", last_work_time = "",
                blocks = {}, results = {} }
    local section = nil
    for line in csv.iter_lines(text) do
        if line ~= "" then
            local f = csv.split(line)
            local a1 = f[1] or ""
            if a1 == "信息" or a1 == "状态" or a1 == "是否播种"
               or a1 == "结果" then
                section = a1
            elseif section == "信息" then
                if a1 == "名称" then t.name = f[2]
                elseif a1 == "地图" then t.map = f[2]
                elseif a1 == "创建时间" then t.create_time = f[2] or ""
                elseif a1 == "最后工作时间" then t.last_work_time = f[2] or ""
                elseif a1 == "备注" then t.remark = f[2] or ""
                elseif a1 == "路线类型" then
                    local v = num(f[2])
                    if v and v >= 0 and v <= 5 then t.path_type = v end
                elseif a1 == "路线方向" then
                    t.positive = (f[2] == "反") and 1 or 0  -- 十八修
                elseif a1 == "起点排列" then
                    t.outset = { r = num(f[2]) or 0, c = num(f[3]) or 0 }
                elseif a1 == "最近完成排列" then
                    t.last = { r = num(f[2]) or -1, c = num(f[3]) or -1 }
                end
            elseif (section == "状态" or section == "是否播种") then
                local rr = row_label_num(a1)            -- 二十一修手写
                if rr then
                    -- 十七修: N排->内部nrows-N(与地图/QT口径一致)
                    local r0 = nrows and (nrows - tonumber(rr))
                                or (tonumber(rr) - 1)
                    if r0 and r0 >= 0 then
                        if not t.blocks[r0] then t.blocks[r0] = {} end
                        for c = 2, #f do
                            local c0 = c - 2
                            local cur = t.blocks[r0][c0]
                                       or { state = 0, sow = 1 }
                            if section == "状态" then
                                cur.state = num(f[c]) or 0
                            else
                                cur.sow = (f[c] ~= "" and f[c] ~= nil) and 1 or 0
                            end
                            t.blocks[r0][c0] = cur
                        end
                    end
                end
            elseif section == "结果" then
                local e = parse_result_line(f)
                if e then
                    -- 十七修: 排=显示号(1基)->内部nrows-显示; 列1基->0基
                    e.c = e.c - 1
                    e.r = nrows and (nrows - e.r) or (e.r - 1)
                    if e.r >= 0 and e.c >= 0 then
                        t.results[#t.results + 1] = e
                    end
                end
            end
        end
    end
    if t.name == nil then msgs[#msgs + 1] = "E:信息区缺名称" end
    if t.map == nil then msgs[#msgs + 1] = "E:信息区缺地图" end
    for _, s in ipairs(msgs) do
        if s:sub(1, 2) == "E:" then return nil, msgs end
    end
    return t, msgs
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
local PENDING = {}   -- [任务名]={结果行...}; 停止时统一落盘
                    -- (2026-10-15: 逐排写3:太频繁, 用户要求改)
local function pend_add(name, line)
    local pd = PENDING[name]
    if not pd then pd = {}; PENDING[name] = pd end
    pd[#pd + 1] = line
end

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

-- 任务名ASCII段(导出文件名可读片, 2026-10-15)
function store.slug_head(name)
    local ascii = {}
    for i = 1, #name do
        local c = string.byte(name, i)
        if (c >= 48 and c <= 57) or (c >= 65 and c <= 90)
           or (c >= 97 and c <= 122) then
            if #ascii < 16 then ascii[#ascii + 1] = string.char(c) end
        end
    end
    if #ascii == 0 then return "n" end
    return table.concat(ascii)
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

-- 自然排序(2026-10-16十九修): 字典序会把"任务10"排在"任务2"之后(用户实测
-- 任务10插到任务1下面); 同前缀+尾数字按数值比, 其余字典序
local function digit_tail(s)
    -- 尾部连续数字手写提取(二十一修: (.-)(%d+)$复杂match屏端不可靠)
    local e = #s
    while e >= 1 do
        local b = string.byte(s, e)
        if b < 48 or b > 57 then break end
        e = e - 1
    end
    if e == #s then return nil end
    return string.sub(s, 1, e), tonumber(string.sub(s, e + 1))
end

local function nat_less(a, b)
    local pa, na = digit_tail(a)
    local pb, nb = digit_tail(b)
    if pa and pb and pa == pb then
        return tonumber(na) < tonumber(nb)
    end
    return a < b
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
    table.sort(names, nat_less)
    for _, n in ipairs(names) do L[#L + 1] = "M," .. n end
    names = {}
    for n in pairs(store.tasks) do names[#names + 1] = n end
    table.sort(names, nat_less)
    for _, n in ipairs(names) do L[#L + 1] = "T," .. n end
    local s = table.concat(L, "\r\n")
    if #L > 0 then s = s .. "\r\n" end
    -- 2026-10-16: index重写结果上报(删除后index.txt仍含旧名时可见)
    local ok = F.write_all(p_index(), s)
    store.last_index_ok = ok
    return ok
end

-------------------------------------------------------------------- 地图
-- 导入(文本): 解析校验 → 驻留 → 原样字节转存内部Flash → 更新index
function store.map_import_text(name, text)
    if not select(1, C.check_name(name)) then
        return nil, "地图名非法"
    end
    local m, msgs = C.parse_map(text)
    if not m.name then m.name = name end   -- 区块式无"名称"行: 用导入名(2026-10-08)
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
    local ok, err = F.remove(p_map(name))
    local oki = index_write()
    -- 2026-10-15: remove如实返回(旧恒true), 供页面记日志;
    --   index重写失败并入err(2026-10-16)
    if not oki then
        err = (err and (err .. "; ") or "") .. "index重写失败"
    end
    return ok, err
end

function store.map_get(name) return store.maps[name] end

function store.map_list()
    local t = {}
    for n in pairs(store.maps) do t[#t + 1] = n end
    table.sort(t, nat_less)
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
    table.sort(t, nat_less)
    return t
end

-- 重置: 全部块状态清0+结果清空(QT formtask.cpp:164-181 重置语义)
function store.task_reset(name)
    local t = store.tasks[name]
    if not t then return nil, "任务不存在" end
    local m = store.maps[t.map]
    for r = 0, (m and m.rows or 0) - 1 do
        local row = t.blocks[r]
        if row then
            for c in pairs(row) do row[c].state = 0 end
        end
    end
    t.last = { r = -1, c = -1 }
    t.state = 0
    store.results[name] = {}
    PENDING[name] = nil
    F.remove(p_result(name))
    return store.task_save(name)
end

-- 导入(U盘文本, 2026-10-13 M3任务管理页): 解析->校验地图存在->驻留+index
-- 中断转换(1->3)与boot口径一致
function store.task_import_text(text)
    local t = C.parse_task(text)
    if not t then return nil, "任务解析失败" end
    if not t.name then return nil, "任务缺名称" end
    if not store.maps[t.map] then
        return nil, "地图不存在: " .. tostring(t.map)
    end
    for _, row in pairs(t.blocks) do
        for _, b in pairs(row) do
            if b.state == 1 then b.state = 3 end
        end
    end
    store.tasks[t.name] = t
    store.results[t.name] = {}
    index_write()
    return t
end

function store.task_delete(name)
    store.tasks[name], store.results[name] = nil, nil
    PENDING[name] = nil
    local ok1 = F.remove(p_task(name))
    local ok2, err2 = F.remove(p_result(name))
    local oki = index_write()
    if not oki then
        err2 = (err2 and (err2 .. "; ") or "") .. "index重写失败"
    end
    return ok1 and ok2, err2
end

-- startNode 下发后标记: 组内 c0..c0+bet-1 置1 (对齐 QT setBlockState(row,col,1))
-- 并落盘: 下发即掉电 → 重启识别为中断(3), 支持断点续作 (QT task.cpp:44)
function store.task_mark_dispatched(name, r, c0)
    local t = store.tasks[name]
    if not t or not t.blocks[r] then return nil, "块不存在" end
    local m = store.maps[t.map]
    local n = m and grp(m, c0) or 1
    -- 2026-10-15: state=1为过渡态不再逐次落盘(停止时flush统一写)
    for c = c0, c0 + n - 1 do
        if t.blocks[r][c] then t.blocks[r][c].state = 1 end
    end
    return true
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
    -- 2026-10-15: 结果行暂存PENDING, 任务与结果均停止时统一落盘
    for _, ln in ipairs(lines) do pend_add(name, ln) end
    t.last = { r = r, c = c0 + n - 1 }
    if now then t.last_work_time = now end
    return true
end

-- 停止时统一落盘: 暂存结果行追加3:结果文件 + 任务定义落盘
function store.task_flush(name)
    local pd = PENDING[name]
    if pd and #pd > 0 then
        local ok, err = F.append(p_result(name),
                                 table.concat(pd) .. "\r\n")
        if not ok then return nil, "结果落盘失败: " .. tostring(err) end
    end
    PENDING[name] = nil
    return store.task_save(name)
end

-- 导出清档(2026-10-15用户要求): 结果已并入U盘task文件后, 清3:结果
-- 文件与内存结果, 下次导出只含新完成的部分
function store.task_export_clear(name)
    PENDING[name] = nil
    store.results[name] = {}
    return F.remove(p_result(name))
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

-- USB 导出文本: Excel友好格式(2026-10-13仿QT任务.csv: 信息+状态矩阵+
-- 是否播种矩阵+结果表; Excel直开; parse_task双格式可再导回)
function store.export_task_text(name)
    local t = store.tasks[name]
    if not t then return nil, "任务不存在" end
    t.results = store.results[name] or {}
    local s = C.render_task_xlsx(t)
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
            -- 旧版渲染文件无名称行(2026-10-13): 回填索引名, 与导入口径一致
            if m.name == nil or m.name == "" then m.name = n end
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

local APP, PROTOCOL, CODEC, STORE, PATHALGO, LOGGER, LW, MAPDRAW
local w16, w32, wstr, NOW, rw16, rw16w, RSTR, r16
local PSTORE                    -- parastore(启动参数链, 可缺省)

-- 路径缓存(跨启停, 对齐QT对话框级path成员; 屏重启后重建)
local PCACHE = { task = nil, path_type = nil, path = nil }
-- 作业现场(单个活动任务)
local J = nil
-- 停止流程挂起的AB采集请求 { map, a_row, dir } (声明在前供 init 闭包引用)
local pending_ab = nil
-- AB对话框状态(画面22): mode 0=无 1=保存命名 2=查看; map=保存目标地图
local ab_dlg_mode = 0
local ab_dlg_map = nil
-- J = { task=名, m=地图, path, ab, next_idx, cur_col, cur_read_row,

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
    MAPDRAW = deps.mapdraw                -- 地图绘制纯函数(可缺省: 无则不更新农机定位)
    w16, w32, wstr, NOW = deps.w16, deps.w32, deps.wstr, deps.now
    rw16, rw16w = deps.rw16, deps.rw16w
    PSTORE = deps.parastore
    RSTR, r16 = deps.rstr, deps.r16
    -- 常驻订阅: 0x21 帧无论当前页都进状态机(作业中切页不丢)
    APP.sub_always(PROTOCOL.FNC.GET_BZ_STATUS, function(f) jobrun._feed(f) end)
    -- 0x26 全局路由(2026-09-28修4行残留): 按厂家参数行数字段(Resv1=U8Resv2)
    -- 动态重置 codec 行数变体——此前 codec.init{rows=4} 后无人更新, 测试页
    -- 计数/密度数组永远按4行解析(用户实测暴露); 处理后转发当前页(参数页回显)
    APP.sub_always(PROTOCOL.FNC.GET_TER_PARA, function(f)
        local ok, p = pcall(CODEC.terpara.unpack, f.data)
        if ok and (p.Resv1 == 4 or p.Resv1 == 6) and p.Resv1 ~= CODEC.ROWS then
            CODEC.init { rows = p.Resv1 }
            log("INF", ("行数切换 codec.ROWS=%d"):format(p.Resv1))
        end
        if APP.cur and APP.cur.on_frame then APP.cur:on_frame(f) end
    end)
    -- 0x23 采集应答全局处理: 填 ab_cache 与 LW.AB 显示区(对话框画面22的显示控件
    -- 绑同一地址区)。2026-09-24 起停止不再自动落图, 改由对话框确认保存
    APP.sub_always(PROTOCOL.FNC.STORE_AB, function(f)
        local ok, p = pcall(CODEC.bdpara.unpack, f.data)
        if not ok then
            wstr(LW.A.log, "bdpara unpack err: len=" .. #f.data)
            return
        end
        jobrun.ab_cache = p
        jobrun.ab_show(p)
    end)
    -- AB对话框通知地址(画面22的功能按钮执行通知写LW=1) -> 影子页全局路由
    APP.register({
        id = -900,                              -- 非真实画面号, 永不成为当前页
        addrs = { LW.ABP.req, LW.ABP.confirm, LW.ABP.cancel },
        on_update = function(_, addr) jobrun._ab_dlg_on_update(addr) end,
    })
    -- creator 时机恢复 RW 缓存(掉电保持)
    jobrun.ab_cache = jobrun.ab_rw_load()
    return jobrun
end

function jobrun.active() return J ~= nil end

-- 画布脏计数(2026-10-13 M2): 页面on_tick比对jobrun.draw_ver变化->redraw
jobrun.draw_ver = 0
-- 方向/路线切换后由页面调用: 清路径缓存, 下次start按新参数重建
function jobrun.reset_path()
    PCACHE.task, PCACHE.path_type, PCACHE.path = nil, nil, nil
end

function jobrun.bump_draw()
    jobrun.draw_ver = jobrun.draw_ver + 1
end

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
    -- start_node纳入pcall(2026-10-13): 地图数据缺陷(如重载后aisle缺失)
    -- 在组参期对nil算术抛错, 此前未捕获直接炸断调用链
    local ok, p = pcall(PATHALGO.start_node, STORE.tasks[J.task], J.m,
                        J.path, row, column, J.ab, J.fine)
    if not ok then
        log("ERR", "startNode组参失败 r=" .. tostring(row)
            .. ": " .. tostring(p))
        return false
    end
    local ok2, bin = pcall(CODEC.bzcell.pack, p)
    if not ok2 then
        log("ERR", "startNode组包失败 r=" .. tostring(row)
            .. ": " .. tostring(bin))
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

-------------------------------------------------------------------- AB线子系统
-- 2026-09-23 自 page_abline(已删除)迁移: 查看采集(0x23)/RW掉电保存/
-- 地图绑定与清除/下发(0x24)。显示复用 LW.AB 地址区(任务页承载)。
-- 显示区由任务页承载, 无页面时仅更新 cache 不写屏。

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
    t.Resv, t.CrcCheck = 0, 0                 -- 占位, 下位机自行处理
    return CODEC.bdpara.pack(t)
end

-- RW 持久化(28字=56B小端u16序列; 先写数据后写magic, 掉电安全侧判无效)
function jobrun.ab_rw_save()
    if not jobrun.ab_cache then return nil, "无AB线, 请先采集" end
    if not (rw16w and LW.RW) then return nil, "RW不可用" end
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

-- 把 cache 绑定到地图(QT FormMap 导入语义: 写 #AB 段并落盘)
-- name: AB线显示名(对话框输入); pa: 停止快照{a_row,dir}(优先于作业参考)
function jobrun.ab_bind_map(map_name, name, pa)
    local p = jobrun.ab_cache
    if not p then return nil, "无AB线, 请先采集或从RW读回" end
    local m = STORE.maps[map_name]
    if not m then return nil, "地图不存在" end
    local a_row, abdir = 0, 1
    if pa then
        a_row, abdir = pa.a_row or 0, (pa.dir and 1 or 0)
    elseif J and J.m and J.m.name == map_name and J.ab then
        a_row, abdir = J.ab.a_row or 0, (J.ab.dir and 1 or 0)
    end
    m.ab = { name = (name and name ~= "") and name or map_name,
             sn = p.StartN, se = p.StartE,
             en = p.EndBN, ee = p.EndBE, sdir = p.StartDir, cdir = p.CalcDir,
             a_row = a_row, abdir = abdir, has = true,
             -- BDPara下发参数随线保存(2026-10-08, 0x24/查看用存储真值)
             startstate = p.StartState or 1, calcdirflag = p.CalcDirFlag or 1,
             offlen = p.OffLen or 0, bdofftime = p.BDOffTime or 100,
             -- A点列(QT aColumn: 农机图标列定位输入, 2026-10-08随格式补)
             a_col = (J and J.cur_col) or 0 }
    if STORE.map_save and not STORE.map_save(map_name) then
        return nil, "地图落盘失败"
    end
    return true
end

-- 清除地图AB绑定
function jobrun.ab_clear_map(map_name)
    local m = STORE.maps[map_name]
    if not m then return nil, "地图不存在" end
    m.ab = nil
    if STORE.map_save and not STORE.map_save(map_name) then
        return nil, "地图落盘失败"
    end
    return true
end

-- 下发地图AB(0x24); 无绑定时下发全零(StartState=0, 固件清空并等待行程开关设A)
function jobrun.ab_send_map(m)
    local t
    if m and m.ab and m.ab.has then
        t = { StartN = m.ab.sn, StartE = m.ab.se, EndBN = m.ab.en, EndBE = m.ab.ee,
              StartDir = m.ab.sdir, CalcDir = m.ab.cdir,
              StartState = m.ab.startstate or 1,
              CalcDirFlag = m.ab.calcdirflag or 1,
              OffLen = m.ab.offlen or 0,
              BDOffTime = m.ab.bdofftime or 100 }
    else
        -- QT communication.cpp:591 setEmptyABLine: 全零, StartState=0
        -- -> 固件 protocol.c:284 清空BDParam, 地头行程开关触发后才设A点开播
        t = { StartN = 0, StartE = 0, EndBN = 0, EndBE = 0,
              StartDir = 0, CalcDir = 0, StartState = 0, CalcDirFlag = 0,
              OffLen = 0, BDOffTime = 0 }
    end
    PROTOCOL.send(PROTOCOL.FNC.SET_AB, ab_pack(t))
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

    -- 路径缓存(2026-10-14六修, 对齐QT :209/:811-897/:234): 路径仅在任务
    -- 或路线类型变化时重建; 正反向开关不重建(仅随下次重建生效)——此前
    -- 每次start重建, 中途改方向会让整条路径翻转, 续作走错(用户实测)
    local path
    if PCACHE.path and PCACHE.task == task_name
       and PCACHE.path_type == t.path_type then
        path = PCACHE.path
    else
        local err
        path, err = PATHALGO.create_path(m, t.path_type, t.positive == 1)
        if not path then return nil, err end
        PCACHE.task, PCACHE.path_type, PCACHE.path =
            task_name, t.path_type, path
    end

    -- 起点定位扫描(2026-10-16十六修, 对齐QT showOutset->nextPathIndex=
    -- getIndex(outsetRow,outsetColumn) :653): 从任务的播种起点节点起,
    -- 向后跳过已完成节点——起点之前的小区永不下发不计数(不漏种漏肥,
    -- 用户要求); 续作时自然落在首个未完成处(等价QT指针延续)
    local osr = (t.outset and t.outset.r) or 0
    local osc = (t.outset and t.outset.c) or 0
    local start_idx = nil
    for i, pn in ipairs(path) do
        if pn.row == osr and pn.column == osc then
            start_idx = i
            break
        end
    end
    if not start_idx then start_idx = 1 end      -- 起点不在路径内: 从头
    while start_idx <= #path do
        local pn = path[start_idx]
        local blk = t.blocks[pn.row] and t.blocks[pn.row][pn.column]
        if not blk or (blk.sow == 1 and blk.state ~= 2) then
            break
        end
        start_idx = start_idx + 1
    end
    if start_idx > #path then
        return nil, "任务已完成"                  -- QT :217 path走尽开始键无效
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
        temp_idx = start_idx,
        -- 株距微调从config.txt实时读(2026-10-08; 恒五档表,
        -- pathalgo.density按enabled过滤, 全不启用=恒等, 同QT)
        fine = PSTORE and PSTORE.load_fine()
               or (STORE.cfg and STORE.cfg.fine_tune) or nil,
    }

    -- 状态展示: 主页 taskinfo / TW 页
    if APP then APP.set_always_poll(PROTOCOL.FNC.GET_BZ_STATUS) end
    log("INF", ("作业启动 %s 地图=%s 路径=%d 起点组=%d"):format(
        task_name, m.name, t.path_type, start_idx))

    -- 2026-09-30对齐QT启动参数链(dialogrealtimetask.cpp:569/227-230):
    -- 先0x27(HJ用地图行距col_gap, 即Map::getUserParameter) -> ACK ->
    -- 0x25 -> ACK -> 再0x24/首节点/0x31/0x0A。链期间用户点停止则J失效,
    -- 回调直接放弃; parastore缺省(A档降级)时退化为直发(旧版行为)。
    local function launch_tail()
        if not J or J.task ~= task_name then return end
        -- 2026-09-23 对齐QT(dialogrealtimetask.cpp:559-568): 启动先下发AB线——
        -- 有绑定->存储值(StartState=1); 无绑定->全零(StartState=0, 固件清空BDParam,
        -- 地头等待行程开关触发设A点后才开播)。此前屏端从不发0x24, 下位机沿用上次
        -- 持久化的StartState=1, 无AB线任务跳过触发直接开播(用户联调暴露)。
        jobrun.ab_send_map(m)

        -- QT :275-300: 启动时先下发首个节点参数(图外播种=从图外排开始, 否则首排)
        local pn = path[J.next_idx]
        local sent
        if (t.sow_exceed == 1) then
            J.cur_read_row = pn.positive and -1 or m.rows   -- 图外虚拟排
            J.enter_map = false
            sent = send_node(J.cur_read_row, J.cur_col)
        else
            J.enter_map = true
            sent = send_node(pn.row, J.cur_col)
        end
        if not sent then
            -- 首节点未下发(地图数据缺陷等): 安全停机+清现场, 页面回就绪
            -- 可重试, 不残留假"作业中"(2026-10-13: 用户实测重启后
            -- 0x20/0x31/0x0A全未发而任务状态显示作业中)
            PROTOCOL.send(PROTOCOL.FNC.CMD_STOP_BZ)
            if LW and LW.RT and w16 then w16(LW.RT.running, 0) end
            jobrun.detach()
            J = nil
            log("ERR", "作业启动失败: 首节点未下发, 已回滚现场")
            return
        end
        -- 不预置 mark_dispatched(QT state=1 仅由在播帧建立: 行程不符保护,
        -- 见 advance() 内注释; resume 扫描按 state~=2 判未完成, 不受影响)
        -- 过道打点使能(2026-09-30三态, 对齐QT:251-259 在0x0A前下发0x31):
        --   0=关(恒0) 1=开(恒1) 2=间隔(隔趟: 本趟列组序号%2==0才打点,
        --   outsetColumn/bet%2==0 与QT:255同式; 存config.txt经用户参数页配置)
        -- 过道打点三态从config.txt读(2026-09-30, RW副本已撤)
        local gp = 0
        if opts.gap ~= nil then
            gp = opts.gap                   -- 实时播种页下拉直读(2026-10-13)
        elseif PSTORE then
            gp = PSTORE.load_gap()
        end
        if gp ~= 0 and gp ~= 1 and gp ~= 2 then gp = 0 end
        local gp_on = 0
        if gp == 1 then
            gp_on = 1
        elseif gp == 2 then
            local bet = m and PATHALGO.block_each_trip(m) or 1
            if (path[start_idx].column // bet) % 2 == 0 then gp_on = 1 end
        end
        PROTOCOL.send(PROTOCOL.FNC.GDDD_ENABLE, string.char(gp_on))
        PROTOCOL.send(PROTOCOL.FNC.CMD_START_BZ)       -- 0x0A
        J.sow_state = true
        if LW and LW.RT and w16 then w16(LW.RT.running, 1) end
        jobrun.bump_draw()
    end
    if PSTORE then
        PSTORE.begin("SOW", { HJ = m.col_gap }, launch_tail)
    else
        launch_tail()
    end
    return true
end

-------------------------------------------------------------------- 停止(QT :305)
-- 主页停止按钮唯一收尾入口; 0x0B 无条件急停(含无任务时裸发),
-- 有作业时回退断点(QT :306-307)+归档+清现场(允许后续新任务/续作)
-- QT :310-311: 地图无AB线时停止弹"是否保存AB线?" -> 2026-09-24 对齐:
-- 停止时写 LW.ABP.auto_req=1, 画面侧"打开AB对话框"功能按钮以条件触发联动弹出
-- (蒙版半透明模态), 用户命名后确认才保存(等价QT的Yes+名称输入), 取消则不存。

function jobrun.stop()
    PROTOCOL.send(PROTOCOL.FNC.CMD_STOP_BZ)        -- 0x0B
    if not J then return true end
    -- AB线保存建议(QT signalStopSow :310-311): 无绑定地图 -> 采集填显示 + 请求弹窗
    if not (J.m.ab and J.m.ab.has) then
        pending_ab = { map = J.m.name, a_row = J.ab and J.ab.a_row or 0,
                       dir = J.ab and J.ab.dir or false }
        ab_dlg_mode = 1                            -- 预置保存模式(弹窗已带目的)
        ab_dlg_map = J.m.name
        w16(LW.ABP.mode, 0)
        wstr(LW.ABP.name, "")
        PROTOCOL.send(PROTOCOL.FNC.STORE_AB)       -- 0x23 采集填显示
        w16(LW.ABP.auto_req, 1)                    -- 画面功能按钮条件触发弹窗
        log("INF", "地图无AB线, 停止后建议保存: " .. J.m.name)
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
    if LW and LW.RT and w16 then w16(LW.RT.running, 0) end
    -- 停止时统一落盘(2026-10-15: 暂存结果+任务定义一次写入3:)
    if STORE.task_flush then
        local okf, errf = STORE.task_flush(J.task)
        if not okf then log("ERR", "落盘失败: " .. tostring(errf)) end
    end
    log("INF", "作业停止 " .. J.task)
    jobrun.bump_draw()
    jobrun.detach()
    J = nil
    return true
end

-- 保留现场仅停轮询(掉电恢复/页面展示用)
function jobrun.detach()
    if APP then APP.set_always_poll(nil) end
end

-------------------------------------------------------------------- AB线对话框(LW.ABP)
-- 画面22承载(功能按钮"打开对话框"弹出, 蒙版半透明模态); 字段显示控件绑 LW.AB 区,
-- 0x23 应答经全局路由自动填充。名称输入为文本控件(虚拟键盘)读写 LW.ABP.name。
-- 交互: 画面按钮执行通知写 LW.ABP.req(1保存/2查看) -> 采集+开窗;
--       确认(关闭对话框+通知confirm) -> 命名保存到地图+RW; 取消 -> 丢弃。
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
    end
end

-- 打开请求(mode 1=保存命名 2=查看): 填模式/名称, 发0x23采集
-- 目标地图优先级: 作业中=当前任务地图 > 停止快照 > 页面提示(jobrun.ab_hint_map,
-- 地图导入页选中行设置) > 保持上次
function jobrun.ab_dlg_open(mode)
    ab_dlg_mode = mode
    if J and J.m then ab_dlg_map = J.m.name
    elseif pending_ab then ab_dlg_map = pending_ab.map
    elseif jobrun.ab_hint_map then ab_dlg_map = jobrun.ab_hint_map end
    w16(LW.ABP.mode, mode == 2 and 1 or 0)      -- LW口径: 0保存 1查看
    if mode == 2 then
        -- QT语义(DialogABLine:517+): 查看=显示地图绑定的AB线, 不读下位机
        -- (2026-10-08修复: 原实现发0x23读下位机实时值, 屏/固件重启后显示全0;
        --  地图AB段落盘在3:, 重启屏后仍完整)
        local m = ab_dlg_map and STORE.maps[ab_dlg_map]
        if m and m.ab and m.ab.has then
            wstr(LW.ABP.name, m.ab.name or "")
            jobrun.ab_show({ StartN = m.ab.sn, StartE = m.ab.se,
                             EndBN = m.ab.en, EndBE = m.ab.ee,
                             StartDir = m.ab.sdir, CalcDir = m.ab.cdir,
                             StartState = m.ab.startstate or 1,
                             CalcDirFlag = m.ab.calcdirflag or 1,
                             OffLen = m.ab.offlen or 0,
                             BDOffTime = m.ab.bdofftime or 100 })
            -- A点排/方向为地图本地属性(0x23应答无), 查看时显示绑定值
            w16(LW.AB.arow, m.ab.a_row or 0)
            w16(LW.AB.abdir, m.ab.abdir or 0)
        else
            -- 地图未绑定: 回退显示RW镜像(最近一次保存), 再无则提示
            local p = jobrun.ab_rw_load()
            if p then
                wstr(LW.ABP.name, "(RW缓存)")
                jobrun.ab_show(p)
            else
                wstr(LW.ABP.name, "(无AB线)")
                jobrun.ab_show({ StartN = 0, StartE = 0, EndBN = 0, EndBE = 0,
                                 StartDir = 0, CalcDir = 0, StartState = 0,
                                 CalcDirFlag = 0, OffLen = 0, BDOffTime = 0 })
            end
        end
    else
        wstr(LW.ABP.name, "")
        PROTOCOL.send(PROTOCOL.FNC.STORE_AB)   -- 保存前0x23采集当前B点
    end
end

-- 确认保存: 以对话框输入名称绑定地图(#AB段落盘) + 存RW; A排/方向用停止快照
-- (严格要求本次开窗后已有0x23应答, 不回退RW旧缓存——避免保存过期数据)
function jobrun.ab_dlg_confirm()
    if ab_dlg_mode ~= 1 then
        ab_dlg_mode = 0
        w16(LW.ABP.auto_req, 0)
        return
    end
    ab_dlg_mode = 0
    w16(LW.ABP.auto_req, 0)
    if not (ab_dlg_map and STORE.maps[ab_dlg_map]) then
        return
    end
    jobrun.ab_cache = jobrun.ab_cache
    if not jobrun.ab_cache then
        return
    end
    local name = rstr_safe(LW.ABP.name)
    if name == "" then name = ab_dlg_map end
    local pa = pending_ab
    local ok, err = jobrun.ab_bind_map(ab_dlg_map, name, pa)
    if ok then
        jobrun.ab_rw_save()
        log("INF", ("AB线保存 %s -> 地图%s"):format(name, ab_dlg_map))
    else
    end
    pending_ab = nil
end

-------------------------------------------------------------------- 200ms 状态机
-- QT :330-473 signalGetSowStatus 核心分支(去除拖拉机图标/表格可视化)
function jobrun._feed(f)
    local ok, st = pcall(CODEC.bzstatus.unpack, f.data)
    if not ok then return end
    jobrun.last_status = st      -- 最近一帧0x21快照(连续播种页显示用)

    -- 排/列行程(2026-09-29恢复): 连播页/任务页共用全局地址, jobrun常驻统一写入;
    -- QT :345-356 有AB线时 VerticalOff 显示前符号翻转
    --   (pathType 0/1/2且AB同向取反; 3/4/5且AB反向取反), 无AB线/无作业原值
    if w16 then
        -- RunState字节=状态位|电机位(固件口径): 播种中随电机组合变(如
        -- 1|0x14=21), QT :332-344仅认0/1/0x81且其余保持上一态——此前
        -- 直写致3态灯ValueMap无匹配而空白(2026-10-15十二修)
        local rs = st.RunState or 0
        if rs == 0 or rs == 1 or rs == 0x81 then
            w16(LW.A.runstate, rs)
        end
        if w32 then
            local voff = st.VerticalOff
            if J and J.ab and J.ab.has and STORE and STORE.tasks[J.task] then
                local pt = STORE.tasks[J.task].path_type
                if pt <= 2 then
                    if J.ab.dir then voff = -voff end
                else
                    if not J.ab.dir then voff = -voff end
                end
            end
            w32(LW.A.offlen, st.OffLen)
            w32(LW.A.voff, voff)
        end
    end

    -- 实时播种页数据(2026-10-13 M2): 速度/当前漏种漏肥(无作业也刷新,
    -- 与offlen/voff/runstate同口径; 4行机末2路恒0同模拟器)
    if LW and LW.RT then
        if w32 then w32(LW.RT.speed, st.Speed or 0) end
        if w16 then
            for i = 1, 6 do
                w16(LW.RT.cur_zh + i - 1, st.LouZHCnt[i] or 0)
                w16(LW.RT.cur_fe + i - 1, st.LoufeiCnt[i] or 0)
            end
        end
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
            -- 边界排完成(2026-10-14十修: 原空ents致每趟末排结果行缺失,
            -- e2e导出10行仅8; 与图内分支同式快照计数落库)
            local zh, fe = J.row_zh or st.LouZHCnt, J.row_fe or st.LoufeiCnt
            local ents = {}
            for i = 0, bet - 1 do
                local seed, fert = {}, {}
                local base = i * (m.block_col or 1)
                for k = 0, (m.block_col or 1) - 1 do
                    seed[k + 1] = zh[base + k + 1] or 0
                    fert[k + 1] = fe[base + k + 1] or 0
                end
                ents[i + 1] = { state = 2,
                                start_t = J.result_t0 or now_s(),
                                end_t = now_s(), seed = seed, fert = fert }
            end
            if LW and LW.RT and w16 then
                for i = 1, 6 do
                    w16(LW.RT.last_zh + i - 1, zh[i] or 0)
                    w16(LW.RT.last_fe + i - 1, fe[i] or 0)
                end
            end
            STORE.task_mark_row_done(J.task, J.cur_read_row, J.cur_col, ents, now_s())
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
            -- 逐拍缓存当前排计数(2026-10-15十一修, QT :421-424同坑:
            -- 换排过渡帧计数已被新排清零覆盖, 完成落库须用换排前
            -- 最后一拍的值——此前读过渡帧致非末排计数恒~1)
            J.row_zh, J.row_fe = st.LouZHCnt, st.LoufeiCnt
            if not J.enter_map then
                send_node(pn.row, J.cur_col)         -- 入图首排(仅一次)
                J.enter_map = true
            end
            if sow_flag then
                STORE.task_mark_dispatched(J.task, pn.row, J.cur_col)
                jobrun.bump_draw()
            end
        -- QT :459-470: 刚走完 next_idx 排 → 记结果 + 推进
        elseif (function()
                    local blk = t.blocks[pn.row] and t.blocks[pn.row][J.cur_col]
                    return (blk and (blk.state == 1 or blk.state == 2)) or not sow_flag
                end)() then
            if sow_flag then
                -- QT :422-445: currentResult[i] 穴数/肥数取自 LouZHCnt/LoufeiCnt
                -- (2026-10-15十一修: 用逐拍缓存J.row_zh/fe, 过渡帧已清零)
                local zh, fe = J.row_zh or st.LouZHCnt, J.row_fe or st.LoufeiCnt
                local ents = {}
                for i = 0, bet - 1 do
                    local seed, fert = {}, {}
                    local base = i * (m.block_col or 1)
                    for k = 0, (m.block_col or 1) - 1 do
                        seed[k + 1] = zh[base + k + 1] or 0
                        fert[k + 1] = fe[base + k + 1] or 0
                    end
                    ents[i + 1] = { state = 2, start_t = J.result_t0 or now_s(),
                                    end_t = now_s(), seed = seed, fert = fert }
                end
                STORE.task_mark_row_done(J.task, pn.row, J.cur_col, ents, now_s())
                -- 最近完成排漏种漏肥快照(2026-10-13 M2, QT showLastBlock:
                -- 本排最终计数, 下次0x20下发后固件清零)
                if LW and LW.RT and w16 then
                    local zh, fe = J.row_zh or st.LouZHCnt,
                                  J.row_fe or st.LoufeiCnt
                    for i = 1, 6 do
                        w16(LW.RT.last_zh + i - 1, zh[i] or 0)
                        w16(LW.RT.last_fe + i - 1, fe[i] or 0)
                    end
                end
            end
            jobrun.bump_draw()
            -- 推进(QT :469 + B档修正: 同步 currentColumn; 跨趟挂起见 advance)
            advance()
        end
    end
    J.cur_read_row = st.RowNum
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
    jobrun.bump_draw()
    if STORE then STORE.task_save(J.task) end
    log("INF", "作业完成(待手动停止) " .. J.task)
end


return jobrun

]==]


_MODS["page_history.lua"] = [==[
--[[
page_history.lua —— 历史记录页(0x1900~, 画面7; 2026-10-16十八修重设计)
================================================================================
对齐QT FormHistory样式(裁剪到800x480):
  顶行: 任务总数/选中项 + [导出U盘][删除]
  左栏: 任务列表(名+完成度) + 上移/下移 + 刷新
  右区: 结果表(等宽字体对齐, wqyMicroHeiMono):
        排|列|状|播1-6|肥1-6 逐行 + 表头 + 任务摘要(地图/路径/方向/完成率)
        + 起止时间行(选中行), 上下翻页浏览全部结果。
数据记录组件评估(2026-10-16): 其数据源=资料取样(Flash采样)/配方数据,
官方对动态数据的推荐方案即"字符串表格+Lua拼接"——本页采用后者,
虚拟屏也可联调(资料取样走Flash存储虚拟屏不支持)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP = ctx.APP
    local STORE, LOGGER, FILEIO = ctx.STORE, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    -- 列表行数保守取9(330px高/约35px行; 十九修: 用户反馈10行时末行
    -- 可能被截且窗口不跟随, 取小确保可视+滚动跟随生效)
    local LIST_ROWS = 9
    local TBL_ROWS = 16                -- 结果表可见行数(detail加宽后)
    local S = { sel = 0, top = 0, items = {}, ttop = 1 }

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function task_names()
        return STORE and STORE.task_list() or {}
    end

    -- 等宽填充: 数字右对齐定宽(n字符), 中文按2宽
    local function pad_n(v, w)
        local s = tostring(v or 0)
        while #s < w do s = " " .. s end
        return s
    end

    local function refresh_list()
        S.items = {}
        for _, n in ipairs(task_names()) do
            local d, tot, pct = STORE.task_progress(n)
            S.items[#S.items + 1] = ("%s %d%%"):format(n, pct or 0)
        end
        local lines = {}
        for i = S.top + 1, math.min(S.top + LIST_ROWS, #S.items) do
            local mark = (i == S.sel + 1) and ">" or " "
            lines[#lines + 1] = mark .. S.items[i]
        end
        if #lines == 0 then lines[1] = " 无记录" end
        wstr(LW.HIST.list, table.concat(lines, "\r\n"))
        w16(LW.HIST.count, #S.items)
        w16(LW.HIST.selidx, S.sel)
    end

    local function selected_name()
        local names = task_names()
        return names[S.sel + 1]
    end

    local function render_detail()
        local n = selected_name()
        if not n then
            wstr(LW.HIST.detail, " 无任务")
            return
        end
        local t = STORE.task_get(n)
        local m = t and STORE.maps[t.map]
        local lines = {}
        -- 摘要行
        local dir = (t and t.positive == 1) and "反" or "正"
        lines[#lines + 1] = ("%s %d排x%d列 路%d %s"):format(
            (t and t.map or "?"), m and m.rows or 0, m and m.cols or 0,
            t and t.path_type or 0, dir)
        local d, tot, pct = STORE.task_progress(n)
        lines[#lines + 1] = ("完成 %d/%d %d%% 共%d条"):format(
            d or 0, tot or 0, pct or 0,
            #(STORE.results[n] or {}))
        -- 表头: 排 列 状 播1..6 肥1..6
        local hd = { "排", "列", "状" }
        for i = 1, 6 do hd[#hd + 1] = "播" .. i end
        for i = 1, 6 do hd[#hd + 1] = "肥" .. i end
        lines[#lines + 1] = table.concat(hd, " ")
        -- 结果行(等宽对齐; 排/列显示号口径)
        local res = STORE.results[n] or {}
        local rows = m and m.rows or 5
        local from = S.ttop
        local to = math.min(S.ttop + TBL_ROWS - 1, #res)
        for i = from, to do
            local e = res[i]
            local ss, fs = 0, 0
            for _, v in ipairs(e.seed or {}) do ss = ss + v end
            for _, v in ipairs(e.fert or {}) do fs = fs + v end
            local f = {
                pad_n(rows - (e.r or 0), 2),
                pad_n((e.c or 0) + 1, 2),
                pad_n(e.state or 0, 1),
            }
            for k = 1, 6 do f[#f + 1] = pad_n((e.seed or {})[k], 3) end
            for k = 1, 6 do f[#f + 1] = pad_n((e.fert or {})[k], 3) end
            lines[#lines + 1] = table.concat(f, " ")
        end
        if #res == 0 then
            lines[#lines + 1] = " (暂无结果记录)"
        elseif to < #res then
            lines[#lines + 1] = (" ...还有%d条 [刷新]翻页"):format(#res - to)
        end
        wstr(LW.HIST.detail, table.concat(lines, "\r\n"))
    end

    local function export_usb()
        local n = selected_name()
        if not n then return end
        if not FILEIO then log("ERR", "fileio未注入"); return end
        local txt = STORE.export_task_text(n)
        local nm = STORE.slug_head and STORE.slug_head(n)
                  or (STORE.slug and STORE.slug(n) or n)
        local ts = NOW()
        local stamp = {}
        for i = 1, #ts do
            local c = string.sub(ts, i, i)
            local b = string.byte(c)
            if (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
               or (b >= 97 and b <= 122) then
                stamp[#stamp + 1] = c
            else
                stamp[#stamp + 1] = "_"
            end
        end
        local fname = "task_" .. nm .. "_" .. table.concat(stamp) .. ".csv"
        local ok, err = FILEIO.write_all("2:" .. fname, txt)
        if ok and STORE.task_flush then STORE.task_flush(n) end
        if ok and STORE.task_export_clear then
            STORE.task_export_clear(n)
        end
        log(ok and "INF" or "ERR",
            ok and ("导出任务 " .. n .. " -> " .. fname .. "(3:结果已清)")
               or ("导出失败 " .. tostring(err)))
    end

    local page = {
        id = LW.SCREEN.HISTORY,
        on_enter = function()
            if APP and APP.preset_hist_task then
                local want = APP.preset_hist_task
                APP.preset_hist_task = nil
                local lst = task_names()
                for i, n in ipairs(lst) do
                    if n == want and i - 1 ~= S.sel then
                        S.sel = i - 1
                        S.top = math.max(0, i - 1 - 2)
                    end
                end
            end
            S.ttop = 1
            refresh_list()
            render_detail()
        end,
        on_leave = function() end,
        poll_cmds = {},
        on_frame = function() end,
        addrs = {
            LW.HIST.btn_up, LW.HIST.btn_down, LW.HIST.btn_view,
            LW.HIST.btn_exp, LW.HIST.btn_del,
        },
        on_update = function(self, addr, val)
            if val ~= 1 then return end
            if addr == LW.HIST.btn_up then
                if S.sel > 0 then
                    S.sel = S.sel - 1
                    if S.sel < S.top then S.top = S.sel end
                    S.ttop = 1
                    refresh_list(); render_detail()
                end
            elseif addr == LW.HIST.btn_down then
                if S.sel < #S.items - 1 then
                    S.sel = S.sel + 1
                    if S.sel >= S.top + LIST_ROWS then
                        S.top = S.sel - LIST_ROWS + 1
                    end
                    S.ttop = 1
                    refresh_list(); render_detail()
                end
            elseif addr == LW.HIST.btn_view then
                -- 刷新=结果表翻页(到底回卷)
                local n = selected_name()
                local res = n and (STORE.results[n] or {}) or {}
                S.ttop = S.ttop + TBL_ROWS - 1
                if S.ttop > #res then S.ttop = 1 end
                render_detail()
            elseif addr == LW.HIST.btn_exp then
                export_usb()
            elseif addr == LW.HIST.btn_del then
                local n = selected_name()
                if n then
                    local okd, errd = STORE.task_delete(n)
                    log(okd and "CMD" or "ERR",
                        "删除任务 " .. n
                        .. (okd and "(已验证)"
                            or (": " .. tostring(errd))))
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

_MODS["page_map.lua"] = [==[
--[[
page_map.lua -- 地图导入页(画面9, 2026-09-24新增)
================================================================================
仿QT地图管理页的屏端子集(地图创建/编辑由PC导出工具负责):
  地图列表(选中) + 详情摘要 + U盘扫描导入(map_*.csv, 文件名须ASCII, 显示名取#MAP)
  + 删除地图 + AB线操作(查看=对话框0x23回显 / 导入=RW缓存绑定本图 / 清除=解绑)
U盘导入逻辑自原任务向导页迁移(2026-09-24向导删除)。
LW: LW.MAP (0x1C00区); AB查看按钮=功能按钮(打开对话框画面22+通知LW.ABP.req=2)。
依赖注入: creator(ctx) 同现有页面模式。
--]]

return function(ctx)
    local APP, LW = ctx.APP, ctx.LW
    local STORE, JOBRUN, LOGGER, FILEIO = ctx.STORE, ctx.JOBRUN, ctx.LOGGER, ctx.FILEIO
    local MAPDRAW = ctx.MAPDRAW             -- 地图画布预览(2026-10-13)
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16

    local LIST_ROWS = 6
    local W = { sel = 0, top = 0, items = {} }
    local canvas_dirty = true               -- 画布置脏(选中/导入变化)

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
        if #W.items == 0 then W.items[1] = "(无地图, 请扫描U盘导入)" end
        W.sel, W.top = 0, 0
        render_list()
        wstr(LW.MAP.detail, "")
    end

    local function show_detail()
        canvas_dirty = true                 -- 选中变化即重绘画布
        local n = selected_name()
        if not (n and STORE) then return end
        local m = STORE.map_get(n)
        if not m then return end
        JOBRUN.ab_hint_map = n                  -- AB对话框的默认目标地图
        local ab = m.ab and ("已绑AB " .. (m.ab.name or "?"))
                       or "无AB线"
        wstr(LW.MAP.detail, ("%s %d排x%d列 %s"):format(n, m.rows, m.cols, ab))
    end

    ------------------------------------------------------------------ U盘导入
    -- list_dir 固件双时序: 异步经 on_list_dir 路由 / 同步返回 table(见 fileio.lua)
    local tick_n = 0
    local scan_deadline = nil
    local SCAN_TICKS = math.max(5, math.ceil(3000 / (ctx.poll_ms or 200)))

    local function usb_import()
        if not FILEIO then return end
        if not STORE then wstr(LW.MAP.detail, "数据层不可用"); return end
        if scan_deadline then wstr(LW.MAP.detail, "扫描中,请稍候"); return end
        wstr(LW.MAP.detail, "扫描U盘中...")
        scan_deadline = tick_n + SCAN_TICKS
        local ok, err = FILEIO.list("2:", function(list, dir)
            scan_deadline = nil
            if not list then
                log("ERR", "列目录失败 " .. tostring(dir))
                wstr(LW.MAP.detail, "扫描失败(未插U盘?)")
                return
            end
            if #list == 0 then                   -- 虚拟屏回退: 约定清单 2:maps.txt
                local lines = FILEIO.read_lines("2:maps.txt")
                if lines then
                    for i = 1, #lines do
                        if #lines[i] > 0 then list[#list + 1] = lines[i] end
                    end
                end
            end
            local imported, msgs = 0, {}
            for _, fnm in ipairs(list) do
                -- 文件名过滤手写(二十一修: 复杂match屏端不可靠)
                if type(fnm) == "string"
                   and string.sub(fnm, 1, 4) == "map_"
                   and string.sub(fnm, #fnm - 3) == ".csv" then
                    local name = fnm:sub(5, -5)
                    local ok2, w2 = STORE.map_import_file("2:" .. fnm, name)
                    if ok2 then imported = imported + 1 else msgs[#msgs + 1] = w2 end
                end
            end
            log(imported > 0 and "INF" or "WRN",
                ("U盘导入 %d 张地图"):format(imported))
            if #msgs > 0 then log("ERR", msgs[1]) end
            wstr(LW.MAP.detail,
                imported > 0 and ("导入%d张地图"):format(imported)
                or "无地图文件(或未插U盘)")
            refresh()
        end)
        if not ok then
            scan_deadline = nil
            wstr(LW.MAP.detail, "U盘不可用")
            log("ERR", "U盘未插入或不可读")
        end
    end

    ------------------------------------------------------------------ 按钮
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
                local okm, errm = STORE.map_delete(n)
                log("CMD", "删除地图 " .. n .. (okm and "(已验证)"
                    or ("失败: " .. tostring(errm))))
                wstr(LW.MAP.detail, "已删除 " .. n)
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
                wstr(LW.MAP.detail, ok and ("AB线已绑定 " .. n)
                                       or ("绑定失败 " .. tostring(err):sub(1, 16)))
                show_detail()
            end
        elseif addr == LW.MAP.ab_clear then
            local n = selected_name()
            if n and JOBRUN then
                local ok, err = JOBRUN.ab_clear_map(n)
                wstr(LW.MAP.detail, ok and ("AB线已清除 " .. n)
                                       or ("清除失败 " .. tostring(err):sub(1, 16)))
                show_detail()
            end
        end
    end

    ---------------------------------------------------------------- 画布预览
    -- (2026-10-13, 用户提议: 动态绘图验证可行后地图页同样上画布,
    --  对齐QT FormMap选中即出图; 视图下拉 map_view 排列/编号/密度)
    local CANVAS_W, CANVAS_H = 384, 396         -- 2026-10-14画面1重布局大画布

    local function paint_canvas()
        if not MAPDRAW then return end
        local n = selected_name()
        if not n then return end
        local m = STORE and STORE.map_get(n)
        if not m then return end
        local v = r16 and r16(LW.MAP.view) or 0
        MAPDRAW.render(MAPDRAW.cmds(m, nil, {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density")
                   or "arrange",
        }), 412, 30)                  -- 画布原点(画面坐标系, 2026-10-14重布局)
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
        canvas_dirty = true
    end

    function page:on_leave() end

    function page:on_frame() end

    function page:on_drawctrl(cid)
        if cid == 1 then paint_canvas() end
    end

    function page:on_update(addr, val)           -- 冒号定义(app.lua 冒号调用)
        on_btn(addr, val)
    end

    page.on_tick = function()
        tick_n = tick_n + 1
        if canvas_dirty then
            canvas_dirty = false
            if redraw then redraw() end
        end
        if scan_deadline and tick_n > scan_deadline then
            scan_deadline = nil
            wstr(LW.MAP.detail, "扫描无响应(未插U盘?)")
            log("WRN", "list_dir 回调超时(异步无果)")
        end
    end

    return page
end
]==]

_MODS["page_userparam.lua"] = [==[
--[[
page_userparam.lua -- 用户参数页(画面3, 2026-09-28自原参数页拆分)
================================================================================
用户参数: QT模式(2026-09-30) —— 表单从3:config.txt读(不从下位机回显,
QT同款: formconfig.cpp只读ini, getUserParameter()声明未用), [保存]只写
config.txt+RW过道打点(启动任务/测试/连播时由参数链统一下发0x27/0x25)。
[厂家参数]按钮 = 画面侧功能按钮(打开对话框画面23, 密码数值输入绑 pf_pass,
确认=关闭对话框+执行通知写 LW.PWD.confirm=1) -> 本页校验密码(515516, 与
QT formconfig.cpp:172 同源), 正确则置 PWD.ok 并切换到画面4厂家参数页。
[重置]仅把表单恢复QT默认值(formconfig.cpp:187~199, 不下发, 需再点保存)。
范围表(下位机强制, hd3005a1/Src/para.c ParaLegalCheck):
  HJ 10~5000 回落60; DZTime 100~10000 回落1500; RMP 5~70 回落20
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, w32, wstr, r16, r32 = ctx.w16, ctx.w32, ctx.wstr, ctx.r16, ctx.r32

    local PASSWORD = 515516

    local RANGE_U = {
        { "HJ",     10, 5000,  "行间距HJ" },
        { "DZTime", 100, 10000, "点滞时间" },
        { "RMP",    5,  70,    "播种盘转速RMP" },
    }

    -- QT重置默认值(formconfig.cpp:187~199): 1.5s/0.6m/36r/单天线/0m/过道开
    local DEFAULTS_U = {
        dztime = 1500, hj = 60, rmp = 36,
        antennatype = 0, antennadist = 0, gappoint = 1,
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

    -- 读表单 -> userpara 表
    local function read_user_form()
        local U = LW.PU
        return {
            DZTime = r16(U.dztime), HJ = s16(r16(U.hj)), RMP = r32(U.rmp),
            AntennaType = r16(U.antennatype), U8Resv = 0,
            AntennaDistance = s16(r16(U.antennadist)), CrcCheck = 0,
        }
    end

    -- 0x28 应答 -> LW 表单回显
    local function show_user(p)
        local U = LW.PU
        w16(U.dztime, p.DZTime)
        w16(U.hj, p.HJ & 0xFFFF)
        w32(U.rmp, p.RMP)
        w16(U.antennatype, p.AntennaType)
        w16(U.antennadist, p.AntennaDistance & 0xFFFF)
    end

    local page = {
        id = LW.SCREEN.USERPARAM,
        poll_cmds = {},
        addrs = { LW.PU.write, LW.PU.reset, LW.PU.cfgexp,
                 LW.PWD.confirm, LW.PWD.cancel },
    }

    local function gappoint_load()
        -- 过道打点三态: 0=关 1=开 2=间隔(存config.txt [Application]GapPoint)
        local v = ctx.PARASTORE and ctx.PARASTORE.load_gap() or 0
        if v ~= 0 and v ~= 1 and v ~= 2 then v = 0 end
        w16(LW.PU.gappoint, v)
    end

    -- 株距微调表5档(QT SeedGapFineTuning; 原密度固定, 只收specified/enabled)
    local FT_D = { LW.PU.ft_d1, LW.PU.ft_d2, LW.PU.ft_d3,
                   LW.PU.ft_d4, LW.PU.ft_d5 }
    local FT_E = { LW.PU.ft_e1, LW.PU.ft_e2, LW.PU.ft_e3,
                   LW.PU.ft_e4, LW.PU.ft_e5 }

    local function fine_show()
        local t = ctx.PARASTORE and ctx.PARASTORE.load_fine()
        if not t then return end
        for i = 1, 5 do
            w16(FT_D[i], t[i].specified)
            w16(FT_E[i], t[i].enabled)
        end
    end

    local function fine_read()
        local t = {}
        for i = 1, 5 do
            t[i] = { specified = r16(FT_D[i]), enabled = r16(FT_E[i]) }
        end
        return t
    end

    function page:on_enter()                     -- 进页读用户参数快照
        -- 副本预填(2026-09-30): 下位机离线/屏重启后表单不显示0;
        -- 在线时随后被0x28应答覆盖为固件当前值
        if ctx.PARASTORE then
            local sv = ctx.PARASTORE.load_user()
            if sv then
                local U0 = LW.PU
                w16(U0.dztime, sv.DZTime)
                w16(U0.hj, sv.HJ & 0xFFFF)
                w32(U0.rmp, sv.RMP)
                w16(U0.antennatype, sv.AntennaType)
                w16(U0.antennadist, sv.AntennaDistance & 0xFFFF)
            end
        end
        -- QT模式: 不向下位机读取(0x28能力保留在协议层但页面不使用)
        gappoint_load()
        fine_show()
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == FNC.GET_USER_PARA then
            local ok2, u = pcall(CODEC.userpara.unpack, f.data)
            if ok2 then show_user(u); gappoint_load()
            else wstr(LW.A.log, "userpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        if addr == LW.PU.write then
            local t = read_user_form()
            local bad, msg = check(t, RANGE_U)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            -- QT模式: [保存]只写config.txt(启动任务/测试/连播时参数链统一下发)
            local gp = r16(LW.PU.gappoint) or 0
            if gp ~= 0 and gp ~= 1 and gp ~= 2 then gp = 0 end
            local okc = ctx.PARASTORE
                and ctx.PARASTORE.save_user(t, gp)
                and ctx.PARASTORE.save_fine(fine_read())
            if okc then
                wstr(LW.A.log, "√ 已保存(作业/测试启动时下发)")
            elseif ctx.PARASTORE then
                wstr(LW.A.log, "× 配置写入失败")
            end
        elseif addr == LW.PU.reset then
            -- 重置: 仅恢复表单QT默认值, 不下发(需再点保存; gappoint随下次保存持久化RW)
            local U = LW.PU
            -- rmp是u32占两字(LW0x1622~23), w16只写低字会残留高字
            -- (2026-10-08实测重置后显示2359326=高36低30), 必须w32整写
            for k, v in pairs(DEFAULTS_U) do
                if k == 'rmp' then w32(U.rmp, v) else w16(U[k], v) end
            end
            for i = 1, 5 do               -- 微调全不启用, 指定密度=原密度
                w16(FT_D[i], ({ 4000, 4500, 5000, 5500, 6000 })[i])
                w16(FT_E[i], 0)
            end
            wstr(LW.A.log, "√ 已恢复默认值, 保存后生效")
        elseif addr == LW.PU.cfgexp then
            -- 导出配置到U盘(3:config.txt -> 2:config.txt)
            if ctx.PARASTORE then
                local ok = ctx.PARASTORE.export_usb()
                if not ok then wstr(LW.A.log, "× 导出失败(插U盘?已保存?)") end
            else
                wstr(LW.A.log, "× 导出不可用")
            end
        elseif addr == LW.PWD.confirm then
            -- 密码对话框确认(关闭对话框按钮执行通知)
            local pw = r32(LW.PF.pass) or 0
            if pw == PASSWORD then
                w16(LW.PWD.ok, 1)
                wstr(LW.A.log, "√ 密码正确")
                APP.goto_screen(LW.SCREEN.MANUPARAM)   -- 物理切画面4
            else
                w16(LW.PWD.ok, 0)
                wstr(LW.A.log, "× 密码错误")
            end
        elseif addr == LW.PWD.cancel then
            w16(LW.PWD.ok, 0)
        end
    end

    return page
end
]==]

_MODS["page_manuparam.lua"] = [==[
--[[
page_manuparam.lua -- 厂家参数页(画面4, 2026-09-28自原参数页拆分;
2026-09-16对齐QT formconfig.cpp厂家参数组布局/控件/默认值)
================================================================================
进入条件: 用户参数页密码弹窗校验通过(LW.PWD.ok=1), 未解锁进入则踢回画面3。
厂家参数(TerParaType 40B): 进页自动0x26读快照(QT无读按钮, 对齐), 0x25 保存。
行数字段Resv1(=U8Resv2 4/6)由[设备类型]pf_devtype下拉设置(2026-09-30用户要求:
结构体字段应可设置; QT global.cpp:78同款下发); 0x26回显固件当前值作初始值,
控件值非4/6时兜底快照值/6(2026-09-23曾硬编码0下发把行数冲掉, 用户实测暴露)。
[重置]仅把表单恢复QT默认值(formconfig.cpp:204~221, 不下发, 需再点保存)。
范围表(hd3005a1/Src/para.c ParaLegalCheck, 2026-09核对):
  GearRatio<2回落10 | HoleNum==0回落9 | EncodeNum==0回落700
  MicroStepValue>6400回落800 | TapperTime>1000回落60 | PrePercent按[0,100]
LW单位约定: 距离存cm(控件2位小数显m); TapperTime存0.01s(控件2位小数显s),
pack时*10->ms, show时四舍五入//10(QT formconfig.cpp:88 以s显示/155以ms存储)。
--]]

return function(ctx)
    local APP, PROTOCOL, CODEC, LW = ctx.APP, ctx.PROTOCOL, ctx.CODEC, ctx.LW
    local FNC = PROTOCOL.FNC
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16

    local last_ter = nil       -- 最近一次0x26快照(写回保留固件侧字段: 行数Resv1)

    -- QT重置默认值(formconfig.cpp:204~221; tappertime为LW单位0.01s)
    local DEFAULTS = {
        a = 60, b = 90, encodenum = 2000, encoderdir = 0,
        holenum = 9, gearratio = 5, microstep = 800,
        x1 = 150, bdiroff = 0, tapptrigoff = 20, tappertime = 10,
        zeroposen = 1, gzen = 1, prepercent = 70, devtype = 4,
    }

    local RANGE_T = {
        { "GearRatio",      2,     65535, "传动比" },
        { "HoleNum",        1,     255,   "排种盘孔数" },
        { "EncodeNum",      1,     65535, "编码器脉冲" },
        { "MicroStepValue", 0,     6400,  "细分值" },
        { "TapperTime",     0,     1000,  "打点时间" },
        { "PrePercent",     0,     100,   "预压比" },
    }

    local function s16(v)
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

    -- 读表单(LW) -> terpara 表(i16符号扩展, 行数字段保留快照值)
    local function read_ter_form()
        local P = LW.PF
        local rows = r16(P.devtype)                    -- 设备类型下拉(0x26回显初值)
        if rows ~= 4 and rows ~= 6 then                -- 非法值兜底快照/6
            rows = last_ter and last_ter.Resv1
            if rows ~= 4 and rows ~= 6 then rows = 6 end
        end
        return {
            A = s16(r16(P.a)), B = s16(r16(P.b)),
            EncodeNum = r16(P.encodenum), EncoderDir = r16(P.encoderdir),
            HoleNum = r16(P.holenum), GearRatio = r16(P.gearratio),
            MicroStepValue = s16(r16(P.microstep)),
            X1 = s16(r16(P.x1)), BDiroff = s16(r16(P.bdiroff)),
            TappTrigOff = s16(r16(P.tapptrigoff)),
            TapperTime = r16(P.tappertime) * 10,       -- 0.01s单位 -> ms
            ZeroPosEn = r16(P.zeroposen), GZEn = r16(P.gzen),
            PrePercent = r16(P.prepercent),
            Resv1 = rows, Resv0 = 0, Resv1_ = 0, Resv2 = 0, CrcCheck = 0,
        }
    end

    -- 0x26 应答 -> LW 表单回显
    local function show_ter(p)
        local P = LW.PF
        w16(P.a, p.A & 0xFFFF);          w16(P.b, p.B & 0xFFFF)
        w16(P.encodenum, p.EncodeNum);   w16(P.encoderdir, p.EncoderDir)
        w16(P.holenum, p.HoleNum);       w16(P.gearratio, p.GearRatio)
        w16(P.microstep, p.MicroStepValue & 0xFFFF)
        w16(P.x1, p.X1 & 0xFFFF);        w16(P.bdiroff, p.BDiroff & 0xFFFF)
        w16(P.tapptrigoff, p.TappTrigOff & 0xFFFF)
        w16(P.tappertime, (p.TapperTime + 5) // 10)    -- ms -> 0.01s单位
        w16(P.zeroposen, p.ZeroPosEn)
        w16(P.gzen, p.GZEn);             w16(P.prepercent, p.PrePercent)
        w16(P.devtype, p.Resv1)                        -- 行数回显到设备类型下拉
    end

    local page = {
        id = LW.SCREEN.MANUPARAM,
        poll_cmds = {},
        addrs = { LW.PF.write, LW.PF.reset },
    }

    function page:on_enter()
        if (r16(LW.PWD.ok) or 0) ~= 1 then
            APP.goto_screen(LW.SCREEN.USERPARAM)  -- 物理踢回画面3          -- 未解锁踢回
            return
        end
        -- 副本预填(2026-09-30): 下位机离线/屏重启后表单不显示0;
        -- 在线时随后被0x26应答覆盖; tappertime按LW单位0.01s换算
        if ctx.PARASTORE then
            local sv = ctx.PARASTORE.load_ter()
            if sv then
                local P0 = LW.PF
                w16(P0.a, sv.A & 0xFFFF);         w16(P0.b, sv.B & 0xFFFF)
                w16(P0.encodenum, sv.EncodeNum);  w16(P0.encoderdir, sv.EncoderDir)
                w16(P0.holenum, sv.HoleNum);      w16(P0.gearratio, sv.GearRatio)
                w16(P0.microstep, sv.MicroStepValue & 0xFFFF)
                w16(P0.x1, sv.X1 & 0xFFFF);       w16(P0.bdiroff, sv.BDiroff & 0xFFFF)
                w16(P0.tapptrigoff, sv.TappTrigOff & 0xFFFF)
                w16(P0.tappertime, ((sv.TapperTime or 0) + 5) // 10)
                w16(P0.zeroposen, sv.ZeroPosEn);  w16(P0.gzen, sv.GZEn)
                w16(P0.prepercent, sv.PrePercent)
                w16(P0.devtype, sv.Resv1)
            end
        end
        -- QT模式: 不向下位机读取(0x26能力保留在协议层但页面不使用)
    end

    function page:on_leave() end

    function page:on_frame(f)
        if f.fnc == FNC.GET_TER_PARA then
            local ok, p = pcall(CODEC.terpara.unpack, f.data)
            if ok then show_ter(p); last_ter = p
            else wstr(LW.A.log, "terpara unpack err: len=" .. #f.data) end
        end
    end

    function page:on_update(addr)
        if addr == LW.PF.write then
            local t = read_ter_form()
            local bad, msg = check(t, RANGE_T)
            if bad then wstr(LW.A.log, "× " .. msg) return end
            -- QT模式: [保存]只写config.txt(启动任务/测试/连播时参数链统一下发)
            if ctx.PARASTORE and ctx.PARASTORE.save_ter(t) then
                wstr(LW.A.log, "× 已保存(作业/测试启动时下发)")
            elseif ctx.PARASTORE then
                wstr(LW.A.log, "× 配置写入失败")
            end
        elseif addr == LW.PF.reset then
            -- 重置: 仅恢复表单QT默认值, 不下发(需再点保存)
            local P = LW.PF
            for k, v in pairs(DEFAULTS) do w16(P[k], v) end
            wstr(LW.A.log, "√ 已恢复默认值, 保存后生效")
        end
    end

    return page
end
]==]

_MODS["parastore.lua"] = [==[
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
    - SeedGapFineTuning数组 株距微调(QSettings数组键\N\子键)
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
-- 株距微调五档(global.cpp:13 SeedGapFineTuningDensityList, 固定不可改)
local FINE_ORIGINS = { 4000, 4500, 5000, 5500, 6000 }

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

-- 组头/键值手写解析(2026-10-19二十一修: 屏端match复杂模式不可靠
-- ——%[(%w+)]捕获在真机失败致cur恒nil, 全部键回默认, 6行机变
-- 4行机+"配置文件缺失"假象, 用户实测; 官方仅保证%d+级简单模式)
local function head_group(ln)
    if #ln < 3 then return nil end
    if string.byte(ln, 1) ~= 91 or string.byte(ln, #ln) ~= 93 then
        return nil                          -- 非[...]形
    end
    local inner = string.sub(ln, 2, #ln - 1)
    for i = 1, #inner do
        local b = string.byte(inner, i)
        if b == 91 or b == 93 or b == 61 then return nil end
    end
    return inner
end

local function split_kv(ln)
    local eq = string.find(ln, "=", 1, true)   -- plain查找
    if not eq or eq <= 1 then return nil end
    local k = string.sub(ln, 1, eq - 1)
    for i = 1, #k do
        local b = string.byte(k, i)
        local okc = (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
                  or (b >= 97 and b <= 122) or b == 95 or b == 92
        if not okc then return nil end
    end
    local v = string.sub(ln, eq + 1)
    while #v > 0 and (string.byte(v, #v) == 32
                      or string.byte(v, #v) == 9) do
        v = string.sub(v, 1, #v - 1)
    end
    return k, v
end

-- 组内键值替换(保留其他组与键): 键序由keys给定, kv={键=值串}
local function edit_group(ls, group, kv, keys)
    local gstart = nil
    for i, ln in ipairs(ls) do
        -- 组头比较手写化(二十一修, 同val_of根因)
        if head_group(ln) == group then gstart = i break end
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
                if ls[i]:sub(1, #key + 1) == key .. "=" then hit = i break end
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
        local g = head_group(ln)
        if g then cur = g end
        local k, v = split_kv(ln)
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

---------------------------------------------------------------- 株距微调表
-- config.txt格式(与QT QSettings数组一致):
--   SeedGapFineTuning\\1\\OriginDensity=4000 (反斜杠子键路径)
-- 五档原密度固定, 用户只改 SpecifiedDensity/Enabled
-- -> { {origin,specified,enabled}, ... } 恒五元素(pathalgo.density直接用)
function parastore.load_fine()
    local ls = read_lines()
    local out = {}
    for i, org in ipairs(FINE_ORIGINS) do
        local spec, en = org, 0
        if ls then
            local p = "SeedGapFineTuning" .. "\\" .. i .. "\\"
            local v1 = tonumber(val_of(ls, "Application", p .. "SpecifiedDensity") or "")
            local v2 = tonumber(val_of(ls, "Application", p .. "Enabled") or "")
            if v1 and v1 > 0 and v1 <= 65535 then spec = v1 end
            if v2 == 1 then en = 1 end
        end
        out[i] = { origin = org, specified = spec, enabled = en }
    end
    return out
end

function parastore.save_fine(t)
    local ls = ensure_lines()
    for i, org in ipairs(FINE_ORIGINS) do
        local ft = t and t[i] or nil
        local spec = ft and tonumber(ft.specified) or org
        if not spec or spec < 0 or spec > 65535 then spec = org end
        local en = (ft and ft.enabled == 1) and 1 or 0
        local ka = "SeedGapFineTuning" .. "\\" .. i .. "\\"
        edit_group(ls, "Application", {
            [ka .. "OriginDensity"] = tostring(org),
            [ka .. "SpecifiedDensity"] = tostring(spec),
            [ka .. "Enabled"] = tostring(en),
        }, { ka .. "OriginDensity", ka .. "SpecifiedDensity",
            ka .. "Enabled" })
    end
    return write_lines(ls)
end

---------------------------------------------------------------- 株距微调表
-- config.txt格式(与QT QSettings数组一致):
--   SeedGapFineTuning\\1\\OriginDensity=4000 (反斜杠子键路径)
-- 五档原密度固定, 用户只改 SpecifiedDensity/Enabled
-- -> { {origin,specified,enabled}, ... } 恒五元素(pathalgo.density直接用)
function parastore.load_fine()
    local ls = read_lines()
    local out = {}
    for i, org in ipairs(FINE_ORIGINS) do
        local spec, en = org, 0
        if ls then
            local p = "SeedGapFineTuning" .. "\\" .. i .. "\\"
            local v1 = tonumber(val_of(ls, "Application", p .. "SpecifiedDensity") or "")
            local v2 = tonumber(val_of(ls, "Application", p .. "Enabled") or "")
            if v1 and v1 > 0 and v1 <= 65535 then spec = v1 end
            if v2 == 1 then en = 1 end
        end
        out[i] = { origin = org, specified = spec, enabled = en }
    end
    return out
end

function parastore.save_fine(t)
    local ls = ensure_lines()
    for i, org in ipairs(FINE_ORIGINS) do
        local ft = t and t[i] or nil
        local spec = ft and tonumber(ft.specified) or org
        if not spec or spec < 0 or spec > 65535 then spec = org end
        local en = (ft and ft.enabled == 1) and 1 or 0
        local ka = "SeedGapFineTuning" .. "\\" .. i .. "\\"
        edit_group(ls, "Application", {
            [ka .. "OriginDensity"] = tostring(org),
            [ka .. "SpecifiedDensity"] = tostring(spec),
            [ka .. "Enabled"] = tostring(en),
        }, { ka .. "OriginDensity", ka .. "SpecifiedDensity",
            ka .. "Enabled" })
    end
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
]==]


_MODS["mapdraw.lua"] = [==[
--[[
mapdraw.lua —— 地图绘制纯函数模块(2026-10-13 M2, 任务向导拆页重构)
================================================================================
职责: (地图, 任务块状态, 视图选项) -> 平台无关绘制指令数组; 屏端由
page_taskmgr/page_sowrt 的 on_drawctrl 薄壳逐指令翻译为 draw_* 调用
(隔离平台API签名风险, PC/lupa可完整单测)。

指令集(op):
  rect  x0 y0 x1 y1 fill(0边框/1填充) color(rgb565)
  arect x0 y0 x1 y1 alpha(0~255)              半透明叠加(轨迹)
  line  x0 y0 x1 y1 w color
  text  s x y w h size color align(0左/1中/2右)  (字符串为GB2312字节)

QT对照(dialogrealtimetask.cpp:55-135 QTableView网格):
  状态色: 0待播灰 / 1已下发蓝 / 2完成绿 / 3中断橙红; 不播小区深灰
  排标签 = "排"+(rows-r) 倒序; 列标签 = "列"+(c+1)
  视图: 排列"排-列" / 编号 / 密度(QT comboBoxView 三态)
布局: 均匀网格 + 排间过道灰带(比例带), 排/列标签沿边, fit-scale居中。
纯函数零平台依赖: 不用 string.rep/gsub/gmatch(屏端裁剪), 不触碰LW。
--]]

local mapdraw = {}

-- 状态色(RGB888 -> 由适配层rgb565转换; 此处直接给rgb565换算用888分量)
mapdraw.COLORS = {
    pending = { 192, 192, 192 },   -- 0 待播 灰
    running = { 0, 112, 192 },     -- 1 已下发 蓝
    done    = { 34, 139, 34 },     -- 2 完成 绿
    broken  = { 237, 108, 36 },    -- 3 中断 橙红
    nosow   = { 64, 64, 64 },      -- 不播 深灰
    aisle   = { 228, 228, 228 },   -- 过道带 更浅灰(与待播灰拉开)
    grid    = { 0, 0, 0 },         -- 网格线/文字 黑
    label   = { 0, 0, 0 },
    outset  = { 255, 200, 0 },     -- 起点标记 黄
    machine = { 255, 0, 0 },       -- 农机标记 红
    trail   = { 34, 139, 34 },     -- 轨迹叠加 绿
}

function mapdraw.rgb565(r, g, b)
    return ((r // 8) << 11) | ((g // 4) << 5) | (b // 8)
end

-------------------------------------------------------------------- 偏移->行
-- 累计偏移(排起点坐标系)处的排号; 落在过道/越界返回 nil
-- (QT map.cpp offsetToRow: -999999哨兵语义此处用nil表达)
function mapdraw.row_at(m, off)
    if not m or not m.rows or off == nil or off < 0 then return nil end
    local pos = 0
    for r = 0, m.rows - 1 do
        local rl = m.rowlen[r + 1] or 0
        -- 下界off>=pos不可省: 否则排后过道区间会误命中下一排
        if off >= pos and off < pos + rl then return r end
        pos = pos + rl + (m.aisle[r + 2] or 0)
    end
    return nil
end

-- 图外感知版(QT :374-382: 过道=-999999隐藏, 图外夹取-1/rows仍显示):
-- off<0 -> -1(图前); 越过末排终点 -> rows(图后); 排间过道 -> nil
function mapdraw.row_at_edge(m, off)
    if not m or not m.rows or off == nil then return nil end
    if off < 0 then return -1 end
    local pos = 0
    for r = 0, m.rows - 1 do
        local rl = m.rowlen[r + 1] or 0
        if off < pos + rl then return r end
        pos = pos + rl
        local gap = m.aisle[r + 2] or 0
        if r < m.rows - 1 and off < pos + gap then
            return nil                        -- 排间过道(隐藏)
        end
        pos = pos + gap
    end
    return m.rows                             -- 末排之后(图后夹取)
end

-------------------------------------------------------------------- 布局
-- fit-scale: 均匀网格 + 排间过道带(AISLE_FRAC*ch, 至少4px), 排/列标签边距
local AISLE_FRAC = 0.22                          -- 过道带比例(收窄,
                                                 --   2026-10-14样式重设计)
local LABEL_W, LABEL_H = 22, 18
local PAD = 4                                    -- 画布内边距(防控件
                                                 --   边框裁剪最外圈)

function mapdraw.layout(m, w, h)
    local rows, cols = m.rows or 1, m.cols or 1
    local iw, ih = w - LABEL_W - 2 * PAD, h - LABEL_H - 2 * PAD
    if iw < 20 or ih < 20 then return nil end
    local ch = ih // (rows + math.floor(AISLE_FRAC * (rows + 1)) + 1)
    if ch < 6 then ch = 6 end
    local aisle = math.max(4, math.floor(ch * AISLE_FRAC))
    local total_h = rows * ch + (rows + 1) * aisle
    if total_h > ih then                     -- 极端多排: 压缩过道
        aisle = math.max(2, (ih - rows * ch) // (rows + 1))
        total_h = rows * ch + (rows + 1) * aisle
    end
    local cw = iw // cols
    if cw < 6 then cw = 6 end
    return {
        x0 = LABEL_W + PAD + (iw - cw * cols) // 2,
        y0 = LABEL_H + PAD + (ih - total_h) // 2,
        cw = cw, ch = ch, aisle = aisle,
        rows = rows, cols = cols,
    }
end

local function cell_rect(g, r, c)
    local x = g.x0 + c * g.cw
    local y = g.y0 + (r + 1) * g.aisle + r * (g.ch + g.aisle)
    return x, y, x + g.cw - 1, y + g.ch - 1
end
mapdraw.cell_rect = cell_rect

-------------------------------------------------------------------- 指令生成
-- m: store地图; t: store任务(可nil=无任务纯地图); opts:
--   view     'arrange'|'num'|'density'
--   machine  {row=,col=}(可nil)
--   trail    {{row=,col=},...}(可nil)
--   outset   {r=,c=}(可nil, 缺省取t.outset)
local function state_color(m, t, r, c)
    local b = m.blocks and m.blocks[r] and m.blocks[r][c]
    if not b or b.sow == 0 then return mapdraw.COLORS.nosow end
    if not t or not t.blocks or not t.blocks[r] then
        return mapdraw.COLORS.pending
    end
    local tb = t.blocks[r][c]
    local st = tb and tb.state or 0
    if st == 2 then return mapdraw.COLORS.done end
    if st == 3 then return mapdraw.COLORS.broken end
    if st == 1 then return mapdraw.COLORS.running end
    return mapdraw.COLORS.pending
end

function mapdraw.cmds(m, t, opts)
    opts = opts or {}
    local out = {}
    local g = mapdraw.layout(m, opts.w or 500, opts.h or 380)
    if not g then return out, nil end

    -- 底白 + 过道带(整幅横条, 含首尾)
    out[#out + 1] = { op = 'rect', x0 = 0, y0 = 0,
                      x1 = (opts.w or 500) - 1, y1 = (opts.h or 380) - 1,
                      fill = 1, color = mapdraw.rgb565(255, 255, 255) }
    local ac = mapdraw.rgb565(mapdraw.COLORS.aisle[1],
                              mapdraw.COLORS.aisle[2], mapdraw.COLORS.aisle[3])
    local gx1 = g.x0 + g.cols * g.cw - 1
    for i = 0, g.rows do
        local y = g.y0 + i * (g.ch + g.aisle)
        out[#out + 1] = { op = 'rect', x0 = g.x0, y0 = y,
                          x1 = gx1, y1 = y + g.aisle - 1, fill = 1, color = ac }
    end

    -- 小区色块
    for r = 0, g.rows - 1 do
        for c = 0, g.cols - 1 do
            local col = state_color(m, t, r, c)
            local x0, y0, x1, y1 = cell_rect(g, r, c)
            -- 满格填充(2026-10-14: 原内缩1px+贯穿线在视觉上产生错位感;
            --   改QT式满格无缝, 格界靠颜色差与过道带表达)
            out[#out + 1] = { op = 'rect', x0 = x0, y0 = y0,
                              x1 = x1, y1 = y1, fill = 1,
                              color = mapdraw.rgb565(col[1], col[2], col[3]) }
        end
    end

    -- 每格细边框(2026-10-14: 满格填充后的格子感; 中大图省略保指令量:
    --   <=200格画边框, 更大只靠色块)
    local kc = mapdraw.rgb565(mapdraw.COLORS.grid[1],
                              mapdraw.COLORS.grid[2], mapdraw.COLORS.grid[3])
    if g.rows * g.cols <= 200 and g.cw >= 8 and g.ch >= 8 then
        for r = 0, g.rows - 1 do
            for c = 0, g.cols - 1 do
                local x0, y0, x1, y1 = cell_rect(g, r, c)
                out[#out + 1] = { op = 'rect', x0 = x0, y0 = y0,
                                  x1 = x1, y1 = y1, fill = 0, color = kc }
            end
        end
    end

    -- 排/列标签(排显示号=rows-r, 与QT表头一致)
    local lc = mapdraw.rgb565(mapdraw.COLORS.label[1],
                              mapdraw.COLORS.label[2], mapdraw.COLORS.label[3])
    if g.ch >= 14 then
        for r = 0, g.rows - 1 do
            local _, y0, _, y1 = cell_rect(g, r, 0)
            out[#out + 1] = { op = 'text', s = tostring(g.rows - r),
                              x = 0, y = y0, w = LABEL_W - 2,
                              h = g.ch, size = math.min(16, g.ch),
                              color = lc, align = 1 }
        end
    end
    if g.cw >= 18 then
        for c = 0, g.cols - 1 do
            local x0 = g.x0 + c * g.cw
            out[#out + 1] = { op = 'text', s = tostring(c + 1),
                              x = x0, y = 0, w = g.cw, h = LABEL_H - 2,
                              size = 14, color = lc, align = 1 }
        end
    end

    -- 格内视图文字(格子足够大才画)
    local view = opts.view or 'arrange'
    if g.cw >= 44 and g.ch >= 22 then
        for r = 0, g.rows - 1 do
            for c = 0, g.cols - 1 do
                local b = m.blocks and m.blocks[r] and m.blocks[r][c]
                if b and b.sow ~= 0 then
                    local s
                    if view == 'num' then
                        s = tostring(b.num or 0)
                    elseif view == 'density' then
                        s = tostring(b.density or 0)
                    else
                        s = tostring(g.rows - r) .. "-" .. tostring(c + 1)
                    end
                    local x0, y0, x1, y1 = cell_rect(g, r, c)
                    out[#out + 1] = { op = 'text', s = s, x = x0, y = y0,
                                      w = g.cw, h = g.ch,
                                      size = math.min(16, g.ch - 4),
                                      color = mapdraw.rgb565(255, 255, 255),
                                      align = 1 }
                end
            end
        end
    end

    -- 起点标记(2026-10-16十六修: 粗框4线w=3 + V形指示行进方向,
    -- outset_dir=true行号增=V尖朝下; 小格退化为粗框无V)
    local os_ = opts.outset or (t and t.outset or nil)
    if os_ and os_.r >= 0 and os_.r < g.rows and os_.c >= 0
       and os_.c < g.cols then
        local x0, y0, x1, y1 = cell_rect(g, os_.r, os_.c)
        local oc = mapdraw.rgb565(mapdraw.COLORS.outset[1],
                                  mapdraw.COLORS.outset[2],
                                  mapdraw.COLORS.outset[3])
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y0,
                          x1 = x1, y1 = y0, w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y1,
                          x1 = x1, y1 = y1, w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x0, y0 = y0,
                          x1 = x0, y1 = y1, w = 3, color = oc }
        out[#out + 1] = { op = 'line', x0 = x1, y0 = y0,
                          x1 = x1, y1 = y1, w = 3, color = oc }
        if g.cw >= 16 and g.ch >= 12 then
            local cx = (x0 + x1) // 2
            local sg = opts.outset_dir and 1 or -1
            local cy = (y0 + y1) // 2
            local h = g.ch // 4
            out[#out + 1] = { op = 'line', x0 = cx - h,
                              y0 = cy - sg * h, x1 = cx, y1 = cy + sg * h,
                              w = 3, color = oc }
            out[#out + 1] = { op = 'line', x0 = cx + h,
                              y0 = cy - sg * h, x1 = cx, y1 = cy + sg * h,
                              w = 3, color = oc }
        end
    end

    -- 轨迹显示已移除(2026-10-14用户要求: 只显示小车位置, 经过小区不变色)

    -- 农机标记与四周图外显示已删除(2026-10-15用户要求)

    return out, g
end


-------------------------------------------------------------------- 平台适配
-- cmds -> draw_* 翻译(on_draw回调内调用; PC/lupa无绘图API时整段跳过)。
-- draw_text charcode=1: 指令字符串为GB2312字节(lua源文件即GB18030)
function mapdraw.render(cmds, ox, oy)
    -- ox/oy: 画布控件在画面中的原点(2026-10-13用户实测: draw_*为整画面
    -- 坐标系, 画布控件不提供平移, 不加偏移会画到画面左上角)
    ox, oy = ox or 0, oy or 0
    if set_pen_color == nil then return end
    for i = 1, #cmds do
        local c = cmds[i]
        if c.op == "rect" then
            set_pen_color(c.color or 0)
            draw_rect(c.x0 + ox, c.y0 + oy, c.x1 + ox, c.y1 + oy,
                      c.fill == 1 and 1 or 0)
        elseif c.op == "arect" then
            draw_rect_alpha(c.x0 + ox, c.y0 + oy, c.x1 + ox, c.y1 + oy,
                           c.alpha or 128)
        elseif c.op == "line" then
            set_pen_color(c.color or 0)
            draw_line(c.x0 + ox, c.y0 + oy, c.x1 + ox, c.y1 + oy,
                      c.w or 1)
        elseif c.op == "text" then
            draw_text(c.s, c.x + ox, c.y + oy, c.w, c.h, 0,
                      c.size or 16, c.color or 0, c.align or 1, 1)
        end
    end
end

return mapdraw
]==]

_MODS["page_taskmgr.lua"] = [==[
--[[
page_taskmgr.lua —— 任务管理页(0x1E00~, 画面9) + 新建任务对话框(画面25)
================================================================================
还原 QT FormTask 三栏设计(2026-10-13 M3 任务向导拆页重构):
  左栏: 任务列表(多行字符串+上/下/选中) + 新建(开画面25)/删除/导入/导出/重置
  中栏: 任务详情(名/地图/创建/上次工作/完成率/摘要) + [开始任务]进画面24
  右栏: 地图画布(WidgetBasicGraph ID=1) 小区完成状态 + 视图下拉(排列/编号/密度)
画面25(新建任务对话框, 对齐 QT DialogNewTask): 任务名(全键盘) + 地图选择
  (上/下移) + 确定(关闭+通知nt_btn_ok)/取消(关闭+通知nt_btn_cancel)。
  创建只收名称+地图(路径/方向/起点/图外/打点在实时播种页配置, 与QT一致)。
任务导入导出: U盘 task_<slug>.csv(csv.render_task/parse_task往返); 导出复用
  store.export_task_text(任务定义+全部结果); U盘列目录走fileio回调(同page_map,
  虚拟屏空目录回退读 2:tasks.txt 清单)。
地图绘制: MAPDRAW.cmds(map, task, opts) -> MAPDRAW.render(平台适配); 重绘时机
  = 进入画面/选中变化/块状态变化(jobrun.draw_ver)/作业启停(同draw_ver)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP, STORE, JOBRUN = ctx.APP, ctx.STORE, ctx.JOBRUN
    local MAPDRAW, LOGGER, FILEIO = ctx.MAPDRAW, ctx.LOGGER, ctx.FILEIO
    local w16, wstr, r16, rstr = ctx.w16, ctx.wstr, ctx.r16, ctx.rstr
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local LIST_ROWS = 6
    local W = { sel = 0, top = 0, items = {}, ver = -1 }
    -- 前置声明: 画面25小节函数被画面9按钮处理器先行引用(定义在后)
    local dlg_init, dlg_refresh

    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function fname_stamp(s)
        -- "2026-10-15 12:00:00" -> "2026_10_15_12_00_00"(屏端无gsub手写)
        local out = {}
        for i = 1, #s do
            local c = string.sub(s, i, i)
            local b = string.byte(c)
            if (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
               or (b >= 97 and b <= 122) then
                out[#out + 1] = c
            else
                out[#out + 1] = "_"
            end
        end
        return table.concat(out)
    end

    local function trim16(s)
        return string.sub(tostring(s or ""), 1, 16)
    end

    ---------------------------------------------------------------- 列表/详情
    local function refresh()
        W.items = STORE and STORE.task_list() or {}
        if W.sel >= #W.items then W.sel = math.max(0, #W.items - 1) end
        if W.sel < W.top then W.top = W.sel end
        if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
        local lines = {}
        for i = W.top + 1, math.min(#W.items, W.top + LIST_ROWS) do
            local _, _, pct = STORE.task_progress(W.items[i])
            local ln = (i == W.sel + 1 and ">" or " ")
                .. W.items[i] .. " " .. tostring(pct or 0) .. "%"
            lines[#lines + 1] = string.sub(ln, 1, 15)
        end
        wstr(LW.TM.list, table.concat(lines, "\r\n"))
        w16(LW.TM.count, #W.items)
        w16(LW.TM.selidx, W.sel)
    end

    local function cur_task()
        local n = W.items[W.sel + 1]
        return n, n and STORE.tasks[n] or nil
    end

    local function render_detail()
        local n, t = cur_task()
        if not t then
            wstr(LW.TM.tname, "(无任务)")
            wstr(LW.TM.tmap, "")
            wstr(LW.TM.tcreate, "")
            wstr(LW.TM.tlast, "")
            w16(LW.TM.tpct, 0)
            wstr(LW.TM.tremark, "")
            return
        end
        local m = STORE.maps[t.map]
        wstr(LW.TM.tname, trim16(n))
        wstr(LW.TM.tmap, trim16(t.map))
        wstr(LW.TM.tcreate, trim16(t.create_time))
        wstr(LW.TM.tlast, trim16(t.last_work_time))
        local _, _, pct = STORE.task_progress(n)
        w16(LW.TM.tpct, pct or 0)
        local ab = m and m.ab and m.ab.has
        wstr(LW.TM.tremark, m and (string.format("%d排x%d列 AB:%s",
            m.rows or 0, m.cols or 0, ab and "有" or "无")) or "地图缺失")
    end

    ---------------------------------------------------------------- 画布
    local CANVAS_W, CANVAS_H = 322, 360

    local function paint()
        if not MAPDRAW then return end
        local n, t = cur_task()
        if not t then return end
        local m = STORE.maps[t.map]
        if not m then return end
        local v = r16 and r16(LW.TM.view) or 0
        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
        }
        -- 农机标记已删除(2026-10-15用户要求, 不再传machine)
        if ctx.PATHALGO and t.outset then
            local pp = ctx.PATHALGO.create_path(m, t.path_type,
                                              t.positive == 1)
            if pp then
                opts.outset_dir = ctx.PATHALGO.column_direction(
                    pp, t.outset.c)
            end
        end
        MAPDRAW.render(MAPDRAW.cmds(m, t, opts), 474, 60)
    end

    local function mark_dirty()
        W.ver = -1                             -- 强制on_tick比对失效->redraw
    end
    local canvas_dirty_from_dlg = false       -- 弹窗创建后画布置脏(声明
                                            --   在前供dlg闭包引用)

    ---------------------------------------------------------------- U盘导入(fileio回调式, 同page_map)
    local function start_scan()
        if not FILEIO then log("ERR", "fileio未注入"); return end
        if not STORE then log("ERR", "数据层不可用"); return end
        FILEIO.list("2:", function(list, dir)
            if not list then
                log("ERR", "列目录失败 " .. tostring(dir))
                return
            end
            if #list == 0 then                 -- 虚拟屏回退: 清单 2:tasks.txt
                local lines = FILEIO.read_lines
                    and FILEIO.read_lines("2:tasks.txt") or nil
                if lines then
                    for i = 1, #lines do
                        if #lines[i] > 0 then list[#list + 1] = lines[i] end
                    end
                end
            end
            local cnt = 0
            for _, fn in ipairs(list) do
                -- 文件名过滤手写(二十一修: 复杂match屏端不可靠)
                if type(fn) == "string"
                   and string.sub(fn, 1, 5) == "task_"
                   and string.sub(fn, #fn - 3) == ".csv" then
                    local txt = FILEIO.read_all("2:" .. fn)
                    if txt then
                        local t, err = STORE.task_import_text(txt)
                        if t then
                            cnt = cnt + 1
                        else
                            log("ERR", "任务导入失败 " .. fn .. ": "
                                .. tostring(err))
                        end
                    end
                end
            end
            log(cnt > 0 and "INF" or "WRN",
                ("U盘任务导入 %d 个"):format(cnt))
            W.sel, W.top = 0, 0
            refresh()
            render_detail()
            mark_dirty()
        end)
    end

    ---------------------------------------------------------------- 画面9页表
    local page = {
        id = LW.SCREEN.TASKMGR,
        poll_cmds = {},
        addrs = {
            LW.TM.btn_new,
            LW.TM.btn_del, LW.TM.btn_imp, LW.TM.btn_exp, LW.TM.btn_reset,
            LW.TM.btn_up, LW.TM.btn_down, LW.TM.btn_sel, LW.TM.btn_start,
        },
    }

    function page:on_enter()
        W.sel, W.top = 0, 0
        refresh()
        render_detail()
        mark_dirty()
    end

    function page:on_tick()
        local n = W.items[W.sel + 1]
        if n then
            local _, _, pct = STORE.task_progress(n)
            w16(LW.TM.tpct, pct or 0)
        end
        if canvas_dirty_from_dlg then
            canvas_dirty_from_dlg = false
            W.ver = -1
        end
        local ver = JOBRUN and JOBRUN.draw_ver or 0
        if ver ~= W.ver then
            W.ver = ver
            if redraw then redraw() end
        end
    end

    function page:on_drawctrl(cid)
        if cid == 1 then paint() end
    end

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if addr == LW.TM.btn_up and W.sel > 0 then
            W.sel = W.sel - 1
            if W.sel < W.top then W.top = W.sel end
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_down and W.sel < #W.items - 1 then
            W.sel = W.sel + 1
            if W.sel >= W.top + LIST_ROWS then W.top = W.sel - LIST_ROWS + 1 end
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_sel then
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_new then
            dlg_init()                    -- 弹窗即将打开: 预填地图/默认名
        elseif addr == LW.TM.btn_del then
            local n = W.items[W.sel + 1]
            if not n then return end
            if JOBRUN and JOBRUN.active() then
                local s = JOBRUN.snapshot()
                if s and s.task == n then
                    log("ERR", "作业中任务不可删除: " .. n)
                    return
                end
            end
            local okd, errd = STORE.task_delete(n)
            log(okd and "INF" or "ERR",
                okd and ("删除任务 " .. n .. (errd and ("(" .. errd .. ")")
                                                  or "(已验证)"))
                   or ("删除任务失败 " .. n .. ": " .. tostring(errd)))
            log("INF", "删除任务 " .. n)
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_imp then
            start_scan()
        elseif addr == LW.TM.btn_exp then
            local n = W.items[W.sel + 1]
            if not n or not FILEIO then return end
            -- 2026-10-15: 文件名带时间戳(同任务可多次导出不覆盖)
            local nm = STORE.slug_head and STORE.slug_head(n)
                      or STORE.slug(n)
            local fname = "task_" .. nm .. "_"
                .. fname_stamp(NOW()) .. ".csv"
            local ok = FILEIO.write_all("2:" .. fname,
                                         STORE.export_task_text(n))
            if ok and STORE.task_flush then STORE.task_flush(n) end
            if ok and STORE.task_export_clear then
                STORE.task_export_clear(n)      -- 3:结果清档(已并入U盘task)
            end
            log(ok and "INF" or "ERR",
                ok and ("导出任务 " .. n .. " -> " .. fname .. "(3:结果已清)")
                   or "任务导出失败")
        elseif addr == LW.TM.btn_reset then
            local n = W.items[W.sel + 1]
            if not n then return end
            if JOBRUN and JOBRUN.active() then
                local s = JOBRUN.snapshot()
                if s and s.task == n then
                    log("ERR", "作业中任务不可重置: " .. n)
                    return
                end
            end
            local ok, err = STORE.task_reset(n)
            log(ok and "INF" or "ERR",
                ok and ("重置任务 " .. n) or ("重置失败 " .. tostring(err)))
            refresh(); render_detail(); mark_dirty()
        elseif addr == LW.TM.btn_start then
            local n, t = cur_task()
            if not n then log("ERR", "无任务可开始"); return end
            if not STORE.maps[t.map] then
                log("ERR", "任务地图缺失: " .. tostring(t.map))
                return
            end
            APP.preset_sowrt_task = n
            APP.goto_screen(LW.SCREEN.SOWRT)
        end
    end

    ---------------------------------------------------------------- 画面25 新建任务
    local D = { sel = 0, items = {} }

    dlg_init = function()
        -- 弹窗打开路径: ButtonUsage=1弹窗不触发on_screen_change,
        -- dlg.on_enter不可靠(2026-10-13用户实测地图数0), 由画面9侧
        -- [新建任务]按钮执行通知(tm_btn_new)在此初始化弹窗数据
        D.sel = 0
        dlg_refresh()
        local n = "任务"
            .. tostring(#(STORE and STORE.task_list() or {}) + 1)
        wstr(LW.NT.name, n)
    end

    dlg_refresh = function()
        D.items = STORE and STORE.map_list() or {}
        if D.sel >= #D.items then D.sel = math.max(0, #D.items - 1) end
        wstr(LW.NT.mapsel,
             string.sub(D.items[D.sel + 1] or "(无地图)", 1, 15))
        w16(LW.NT.count, #D.items)
        w16(LW.NT.selidx, D.sel)
    end

    local dlg = {
        id = LW.SCREEN.NEWTASK,
        poll_cmds = {},
        addrs = {
            LW.NT.btn_ok, LW.NT.btn_cancel, LW.NT.btn_up, LW.NT.btn_down,
        },
    }

    function dlg:on_enter()
        dlg_init()                       -- 弹窗若触发on_enter同样初始化
    end

    function dlg:on_update(addr, val)
        if val ~= 1 then return end
        if addr == LW.NT.btn_up and D.sel > 0 then
            D.sel = D.sel - 1
            dlg_refresh()
        elseif addr == LW.NT.btn_down and D.sel < #D.items - 1 then
            D.sel = D.sel + 1
            dlg_refresh()
        elseif addr == LW.NT.btn_ok then
            local name = ""
            if rstr then
                local ok, s = pcall(rstr, LW.NT.name, 16)
                if ok and type(s) == "string" then name = s end
            end
            if name == "" then
                -- 附地址区hex转储(如再空, 一次定位输入落址/布局)
                local hex = ""
                for i = 0, 7 do
                    local v = r16 and r16(LW.NT.name + i) or -1
                    hex = hex .. string.format("%04X ", v)
                end
                log("ERR", "任务名不能为空 NT.name区: " .. hex)
                wstr(LW.NT.mapsel, "失败:任务名不能为空")
                return
            end
            local mapn = D.items[D.sel + 1]
            if not mapn then
                log("ERR", "无地图可选")
                return
            end
            local t, err = STORE.task_create(name, mapn, 0, 0, 0, 0, 0, NOW())  -- 十七修: 默认正(QT新任务positive=false)
            if not t then
                log("ERR", "创建失败: " .. tostring(err))
                wstr(LW.NT.mapsel, "失败:" .. tostring(err))
                wstr(LW.TM.tremark, "创建失败: " .. tostring(err))
                return
            end
            log("INF", "任务已创建 " .. name .. " 地图=" .. mapn)
            wstr(LW.NT.mapsel, "已创建 " .. name)
            wstr(LW.TM.tremark, "已创建 " .. name)
            -- 弹窗关闭不触发画面9 on_enter(同打开), 就地刷新列表/详情
            W.sel = math.max(0, #STORE.task_list() - 1)
            refresh()
            render_detail()
            canvas_dirty_from_dlg = true
        end
        -- btn_cancel: 仅关闭(按钮行为), 无动作
    end

    if APP and APP.register then
        APP.register(dlg)                     -- 弹窗页单独注册(id=25)
    end

    return page
end
]==]

_MODS["page_sowrt.lua"] = [==[
--[[
page_sowrt.lua —— 实时播种页(0x1F00~, 画面24; 2026-10-13 M3任务向导拆页重构)
================================================================================
还原 QT DialogRealtimeTask 左右两栏(800×480全屏, 拆页重构用户决策):
  左栏: 调试信息(a_log) / 排列·列行程(a_offlen/a_voff, cm缩放0.01显示m) /
        速度(rt_speed mm/s缩放0.001显示m/s) / 行进方向开关(rt_positive) /
        路线6态图(rt_path_type) / 清种打点三态(rt_gapdot) / 图外播种
        (rt_sow_exceed, 无AB线强制0) / AB线查看·保存(功能按钮开画面22, 复用
        jobrun ABP影子页)·清除(rt_abclr) / 当前+最近完成 漏种漏肥各6路
        (rt_cur_zh/fe, rt_last_zh/fe, jobrun 0x21常驻写入)
  右栏: 地图画布(WidgetBasicGraph ID=1, 544×360: 块状态色+轨迹+农机标记) /
        视图下拉(rt_view) / 更改起点(开关+排/列输入+应用, 仅记录/标记,
        与原画面6口径一致——路径几何不变) / 开始·停止 / 运行状态灯
        (a_runstate) / 完成率·进度(rt_pct/done/tot) / 任务结果(跳画面7并
        预选APP.preset_hist_task) / 导出U盘
开始: 收集左栏参数写入任务(path_type/positive/sow_exceed/outset)后
  JOBRUN.start(task, {gap=rt_gapdot直读}); 停止: JOBRUN.stop()(含无AB线
  停止保存建议弹窗, 复用既有机制)。
--]]

return function(ctx)
    local LW = ctx.LW
    local APP, STORE, JOBRUN = ctx.APP, ctx.STORE, ctx.JOBRUN
    local MAPDRAW, LOGGER, FILEIO = ctx.MAPDRAW, ctx.LOGGER, ctx.FILEIO
    local PROTOCOL = ctx.PROTOCOL
    local w16, wstr, r16 = ctx.w16, ctx.wstr, ctx.r16
    local NOW = ctx.now or function() return "1970-01-01 00:00:00" end

    local W = { task = nil, ver = -1, qzdd = -1,
                last_pt = -1, last_pos = -1 }

    local function fname_stamp(s)
        -- "2026-10-15 12:00:00" -> "2026_10_15_12_00_00"(屏端无gsub手写)
        local out = {}
        for i = 1, #s do
            local c = string.sub(s, i, i)
            local b = string.byte(c)
            if (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
               or (b >= 97 and b <= 122) then
                out[#out + 1] = c
            else
                out[#out + 1] = "_"
            end
        end
        return table.concat(out)
    end


    local function log(tag, msg)
        if LOGGER then LOGGER.log(tag, msg) end
    end

    local function task_map(t)
        return t and STORE.maps[t.map] or nil
    end

    ---------------------------------------------------------------- 参数收发
    local function load_params()
        -- 任务/配置参数 -> 左栏控件(进入画面/新建后)
        local t = W.task and STORE.tasks[W.task] or nil
        if not t then return end
        w16(LW.RT.path_type, t.path_type or 0)
        w16(LW.RT.positive, t.positive or 0)
        -- 图外播种恒默认关(2026-10-15用户要求: 此前还原任务存值,
        -- 上次开过则本次进来是1; QT每次开窗checkbox默认不勾)
        w16(LW.RT.sow_exceed, 0)
        -- 清种时打点(bool, 会话内保持; 不再装载过道打点config 2026-10-14)
        w16(LW.RT.gapdot, W.qzdd == 1 and 1 or 0)
        w16(LW.RT.sp_enable, 0)
        local m2 = task_map(t)
        if m2 and t.outset then
            -- 0基->显示号(排显示=总排-内部行, 与原画面6一致)
            w16(LW.RT.sp_row, math.max(1, (m2.rows or 1) - (t.outset.r or 0)))
            w16(LW.RT.sp_col, (t.outset.c or 0) + 1)
        else
            w16(LW.RT.sp_row, 1)
            w16(LW.RT.sp_col, 1)
        end
    end

    local function harvest(outset_only)
        -- 左栏控件 -> 任务字段(开始前/应用起点时)
        local t = W.task and STORE.tasks[W.task]
        if not t then return false end
        local m = task_map(t)
        if not outset_only then
            t.path_type = r16(LW.RT.path_type) or 0
            if t.path_type < 0 or t.path_type > 5 then t.path_type = 0 end
            t.positive = (r16(LW.RT.positive) or 0) ~= 0 and 1 or 0
            local has_ab = m and m.ab and m.ab.has
            t.sow_exceed = (r16(LW.RT.sow_exceed) == 1 and has_ab) and 1 or 0
            if r16(LW.RT.sow_exceed) == 1 and not has_ab then
                w16(LW.RT.sow_exceed, 0)      -- 无AB线: 图外播种强制关
                log("WRN", "无AB线, 图外播种不可用已自动关闭")
            end
        end
        if r16(LW.RT.sp_enable) == 1 then
            local r = (r16(LW.RT.sp_row) or 1) - 1
            local c = (r16(LW.RT.sp_col) or 1) - 1
            local rows = m and m.rows or 1
            -- 显示号->0基: 排内部行 = 总排-显示排
            t.outset = { r = math.min(math.max(rows - 1 - r, 0), rows - 1),
                         c = math.min(math.max(c, 0),
                                      (m and m.cols or 1) - 1) }
            w16(LW.RT.sp_enable, 0)          -- 应用后复位开关
        end
        STORE.task_save(W.task)
        return true
    end

    ---------------------------------------------------------------- 画布/刷新
    local CANVAS_W, CANVAS_H = 544, 360

    local function paint()
        if not MAPDRAW then return end
        local t = W.task and STORE.tasks[W.task] or nil
        if not t then return end
        local m = task_map(t)
        if not m then return end
        local v = r16(LW.RT.view) or 0
        local opts = {
            w = CANVAS_W, h = CANVAS_H,
            view = (v == 1 and "num") or (v == 2 and "density") or "arrange",
        }
        -- 农机标记已删除(2026-10-15用户要求, 不再传machine)
        -- 起点V方向: 起点列的行进方向(路径首到达该列的节点positive)
        if ctx.PATHALGO and t.outset then
            local pp = ctx.PATHALGO.create_path(m, t.path_type,
                                              t.positive == 1)
            if pp then
                opts.outset_dir = ctx.PATHALGO.column_direction(
                    pp, t.outset.c)
            end
        end
        MAPDRAW.render(MAPDRAW.cmds(m, t, opts), 252, 32)
    end

    local function pick_task()
        -- 预选(任务管理页[开始任务]) > 作业中任务 > 最近未完成 > 最新任务
        if APP.preset_sowrt_task then
            local n = APP.preset_sowrt_task
            APP.preset_sowrt_task = nil
            if STORE.tasks[n] then return n end
        end
        if JOBRUN and JOBRUN.active() then
            local s = JOBRUN.snapshot()
            if s and STORE.tasks[s.task] then return s.task end
        end
        local lst = STORE.task_list()
        for i = #lst, 1, -1 do
            local _, tot, pct = STORE.task_progress(lst[i])
            if tot == 0 or pct < 100 then return lst[i] end
        end
        return lst[#lst]
    end

    -- 方向/路线切换联动(2026-10-16十六修, 对齐QT :150-183方向单选触发
    -- 当前路线handler + :806-821 clearOutset+createPath+outset=path[0]):
    -- 重建路径, 播种起点重置为新路径首节点(手动改的起点随之失效)
    local function relink_outset(pt, pos)
        local t = W.task and STORE.tasks[W.task]
        if not t then return end
        local m = task_map(t)
        if not m then return end
        t.path_type = pt
        t.positive = pos
        if JOBRUN and JOBRUN.reset_path then JOBRUN.reset_path() end
        local path = ctx.PATHALGO and ctx.PATHALGO.create_path
                    and ctx.PATHALGO.create_path(m, pt, pos == 1)
        if path and path[1] then
            t.outset = { r = path[1].row, c = path[1].column }
        end
        STORE.task_save(W.task)
        if m and t.outset then
            w16(LW.RT.sp_row, math.max(1, m.rows - t.outset.r))
            w16(LW.RT.sp_col, t.outset.c + 1)
        end
        w16(LW.RT.path_type, pt)
        w16(LW.RT.positive, pos)
        W.ver = -1
        log("INF", ("路线/方向联动: 起点=%d,%d"):format(
            t.outset and (m.rows - t.outset.r) or 0,
            t.outset and (t.outset.c + 1) or 0))
    end

    local page = {
        id = LW.SCREEN.SOWRT,
        poll_cmds = { PROTOCOL and PROTOCOL.FNC.GET_BZ_STATUS or nil },
        addrs = {
            LW.RT.btn_start, LW.RT.btn_stop, LW.RT.btn_result,
            LW.RT.btn_exp, LW.RT.btn_abclr, LW.RT.btn_spply,
        },
    }

    function page:on_enter()
        W.task = pick_task()
        if W.task then
            wstr(LW.RT.tname, string.sub(W.task, 1, 15))
            load_params()
            local m = task_map(STORE.tasks[W.task])
            if JOBRUN then JOBRUN.ab_hint_map = m and m.name or nil end
        else
            wstr(LW.RT.tname, "(无任务)")
        end
        W.last_pt = r16(LW.RT.path_type) or 0
        W.last_pos = (r16(LW.RT.positive) == 1) and 1 or 0
        W.ver = -1
    end

    function page:on_tick()
        -- 方向/路线切换联动起点(仅空闲; 作业中控件已被权限禁触,
        -- 双保险仍判active)
        local pt = r16(LW.RT.path_type) or 0
        local pos = (r16(LW.RT.positive) == 1) and 1 or 0
        if W.last_pt >= 0 and (pt ~= W.last_pt or pos ~= W.last_pos)
           and not (JOBRUN and JOBRUN.active()) then
            relink_outset(pt, pos)
        end
        W.last_pt, W.last_pos = pt, pos
        -- 清种时打点开关变更即下发(0x29, bool)
        local qz = (r16(LW.RT.gapdot) == 1) and 1 or 0
        if qz ~= W.qzdd then
            W.qzdd = qz
            PROTOCOL.send(PROTOCOL.FNC.QZDD_ENABLE, string.char(qz))
        end
        if not W.task then return end
        local d, tot, pct = STORE.task_progress(W.task)
        w16(LW.RT.pct, pct or 0)
        w16(LW.RT.done, d or 0)
        w16(LW.RT.tot, tot or 0)
        local ver = JOBRUN and JOBRUN.draw_ver or 0
        if ver ~= W.ver then
            W.ver = ver
            if redraw then redraw() end
        end
    end

    function page:on_drawctrl(cid)
        if cid == 1 then paint() end
    end

    local function on_start()
        -- 开始按钮(2026-10-15回撤合并: 恢复独立开始/停止, 双按钮均带
        -- 控件权限变灰——开始仅空闲可用/停止仅作业中可用)
        if JOBRUN and JOBRUN.active() then
            log("WRN", "作业进行中, 请先停止")
            return
        end
        if not W.task then log("ERR", "无任务"); return end
        if not harvest(false) then return end
        -- 清种时打点(0x29): 独立命令随开始一并重发(对齐QT :499-501
        -- setDotWhenClearSeed为bool独立下发; 过道打点0x31回归config)
        local qz = (r16(LW.RT.gapdot) == 1) and 1 or 0
        PROTOCOL.send(PROTOCOL.FNC.QZDD_ENABLE, string.char(qz))
        W.qzdd = qz
        local ok, err = JOBRUN.start(W.task)
        log(ok and "INF" or "ERR",
            ok and ("作业启动 " .. W.task)
               or ("启动失败: " .. tostring(err)))
    end

    function page:on_update(addr, val)
        if val ~= 1 then return end
        if addr == LW.RT.btn_start then
            on_start()
        elseif addr == LW.RT.btn_stop then
            if JOBRUN then JOBRUN.stop() end
        elseif addr == LW.RT.btn_abclr then
            local t = W.task and STORE.tasks[W.task] or nil
            local m = task_map(t)
            if m then
                local ok, err = JOBRUN.ab_clear_map(m.name)
                log(ok and "INF" or "ERR",
                    ok and ("清除AB线 " .. m.name)
                       or ("清除失败: " .. tostring(err)))
            end
        elseif addr == LW.RT.btn_spply then
            if harvest(true) then
                log("INF", "起点已更新(记录/标记; 路径几何不变)")
                W.ver = -1
                if redraw then redraw() end
            end
        elseif addr == LW.RT.btn_result then
            APP.preset_hist_task = W.task
            APP.goto_screen(LW.SCREEN.HISTORY)
        elseif addr == LW.RT.btn_exp then
            if W.task and FILEIO then
                -- 2026-10-15: 导出即任务文件task_*.csv(信息+状态+是否播种+
                -- 结果一体, 只含实际存在的排列表行, 不复刻QT的脏输出)
                -- 2026-10-15: 文件名带时间戳(同任务可多次导出不覆盖)
                local nm2 = STORE.slug_head and STORE.slug_head(W.task)
                          or (STORE.slug and STORE.slug(W.task) or W.task)
                local fname = "task_" .. nm2 .. "_"
                    .. fname_stamp(NOW()) .. ".csv"
                local ok = FILEIO.write_all("2:" .. fname,
                                             STORE.export_task_text(W.task))
                if ok and STORE.task_flush then STORE.task_flush(W.task) end
                if ok and STORE.task_export_clear then
                    STORE.task_export_clear(W.task)  -- 3:结果清档(已并入U盘task)
                end
                log(ok and "INF" or "ERR",
                    ok and ("导出任务 " .. W.task .. " -> " .. fname .. "(3:结果已清)")
                       or "导出失败")
            end
        end
    end

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
local FILEIO, CSV, STORE, PATHALGO, LOGGER, PARASTORE, JOBRUN
local pages = {}

-- 屏端时间源(B档): 2026-10-15改用平台 get_date_time()(手册§3.8返回
-- year/month/day/hour/min/sec表), API不可用时回退开机秒计数T+<n>s
local tick_cnt = 0
local TIME_SRC = "T+n"                       -- 启动诊断: 实际生效时间源
local function now_s()
    -- 兼容两种返回形状: 表{year..}(手册§3.8)或多值y,m,d,h,mi,s;
    -- 候选API: get_date_time / get_sys_date_time (2026-10-16)
    for _, api in ipairs({ get_date_time, get_sys_date_time }) do
        if api then
            local ok, a, b, c, d, e, f = pcall(api)
            if ok then
                if type(a) == "table" and a.year then
                    b, c, d, e, f = a.month, a.day, a.hour, a.min, a.sec
                    a = a.year
                end
                if type(a) == "number" and a > 2000 then
                    TIME_SRC = "RTC"
                    return ("%04d-%02d-%02d %02d:%02d:%02d"):format(
                        a, b or 1, c or 1, d or 0, e or 0, f or 0)
                end
            end
        end
    end
    return ("T+%ds"):format(tick_cnt // 2)
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

    -- 参数副本+启动链(2026-09-30对齐QT: 固件0x27不掉电保存, 每次进入工作
    -- 模式前重发0x27->0x25; A档装配, 失败时参数页/启动链退化为直发)
    PARASTORE = load_mod("parastore.lua")
    if PARASTORE then
        PARASTORE.init {
            APP = APP, PROTOCOL = PROTOCOL, CODEC = CODEC, LW = LWMAP,
            rw16 = rw16, rw16w = rw16w, wstr = wstr,
        }
    end

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
            MAPDRAW  = load_mod("mapdraw.lua")
            LOGGER   = load_mod("logger.lua")
            if LOGGER then
                LOGGER.init { fileio = FILEIO, path = "3:log.txt", cap = 500, now = now_s }
                LOGGER.log("SYS", "屏端启动")
                LOGGER.log("SYS", "时间源: " .. TIME_SRC
                    .. (TIME_SRC == "RTC" and now_s() or
                        "(get_date_time不可用, T+n降级)"))
                if PARASTORE then PARASTORE.set_logger(LOGGER) end

                if PARASTORE then PARASTORE.set_fileio(FILEIO) end
            end
            JOBRUN   = STORE and load_mod("jobrun.lua") or nil
            if JOBRUN then
                JOBRUN.init {
                    APP = APP, PROTOCOL = PROTOCOL, CODEC = CODEC,
                    parastore = PARASTORE,
                    STORE = STORE, PATHALGO = PATHALGO, LOGGER = LOGGER,
                    mapdraw = MAPDRAW,          -- 农机定位row_at(可缺省)
                    LW = LWMAP, w16 = w16, w32 = w32, wstr = wstr, now = now_s,
                    rw16 = rw16, rw16w = rw16w,     -- AB线RW持久化(2026-09-23自page_abline迁入)
                    rstr = rstr, r16 = r16,         -- AB对话框: 读名称/请求值(2026-09-24)
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
        rstr = rstr,   -- 2026-10-14五修: 漏配致页面rstr=nil, 任务名恒空
                       --   (PC测试harness自带rstr桩遮蔽了此漏)
        rw16 = rw16, rw16w = rw16w,
        FILEIO = FILEIO, STORE = STORE, JOBRUN = JOBRUN,
        PARASTORE = PARASTORE,
        LOGGER = LOGGER, PATHALGO = PATHALGO, now = now_s,
        MAPDRAW = MAPDRAW,               -- 地图绘制(画面9/24/1画布)
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
    -- 串口显式初始化(二十一修: UartSetup=0工程IDE不自动初始化串口参数,
    -- 往未初始化通道发帧直接崩屏重启; 参数对齐官方示例8N1)
    if uart_setup then pcall(uart_setup, UART_CH, 115200, 8, 0, 0) end
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

    wstr(LWMAP.A.appver, "0.5.0(2026.9.30)")  -- screen app version, QT formconfig.cpp:31-33
    set_run_cycle(POLL_MS)                 -- on_run 轮询周期(仅 on_init 设置)
    APP.set_screen(LWMAP.SCREEN.HOME)      -- 初始页: 触发 on_enter(版本查询=链路自检)

    print("[HMI] on_init done")
end

function on_run(screen)
    tick_cnt = tick_cnt + 1
    if APP then APP.tick() end             -- 心跳+当前页轮询(节流在 APP)
    if PARASTORE then PARASTORE.tick() end -- 启动参数链超时保护(2026-09-30)
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
    if v == 0 then return end              -- 0=复位态不响应
    APP.on_button(addr, v)                 -- 路由到页面(v随addr传, ABP.req=2查看)
end

function on_screen_change(screen)
    if APP then APP.set_screen(screen) end
end

function on_draw(screen_id, control_id)
    -- 动态绘图控件(ID≠0的WidgetBasicGraph)回调: 按画面号路由到页面模块
    -- 的 on_drawctrl(page方法, 收控件ID); PC/lupa环境无此回调不触发
    if APP and APP.pages then
        local pg = APP.pages[screen_id]
        if pg and pg.on_drawctrl then
            local ok, e = pcall(pg.on_drawctrl, pg, control_id)
            if not ok then
                print("[HMI] on_draw s" .. tostring(screen_id)
                      .. " c" .. tostring(control_id)
                      .. " err: " .. tostring(e))
            end
        end
    end
end
