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
-- 图内(:473 刚走完 next_idx 排)与图外(出图帧, 2026-10-20新增)两处殊途同归:
--   指针无条件推进并下发下一节点; 跨列组自动续发下一趟首节点——对齐QT
--   :473-474(推进无跨趟检查/无挂起)。旧trip_wait挂起系误读QT"现场实操",
--   致100%重驶卡在趟1、趟2永不发送(2026-10-20用户实测QT模拟器按选定路径
--   连续走完两趟后撤除)
local function advance()
    if J.next_idx < #J.path then
        J.next_idx = J.next_idx + 1
        local np = J.path[J.next_idx]
        local old_col = J.cur_col
        J.cur_col = np.column                 -- 跨趟随节点切列组(QT :474沿用旧列系其缺陷, 密度查询须新列)
        local exceed = STORE.tasks[J.task].sow_exceed == 1
        if exceed and np.column ~= old_col then
            -- M56(用户语义): 趟末出图后不下发新参数——机器保持出图前末小区
            -- 参数继续播(出图段); 再入图新趟首排时由in-map入口分支
            -- (need_entry)补发新趟首小区参数
            J.need_entry = true
        else
            send_node(np.row, J.cur_col)      -- 同趟下一排/非图外趟间: QT :474 自动
        end
        -- QT 语义: startNode 只下发参数不置 state=1(state 仅由在播帧
        -- RowNum==path[next].row 建立, :456) -> 行程不符(未走到预期排)
        -- 时 :459 推进条件永不满足, 完成率挂住; 屏端此前在此预置
        -- mark_dispatched(state=1)打穿该保护, 乱序排帧也会推进落库
        -- 一路到100%. 2026-09-11 对齐 QT 删预置(用户联调暴露)
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
    local function locate_outset()
        local osr = (t.outset and t.outset.r) or 0
        local osc = (t.outset and t.outset.c) or 0
        for i, pn in ipairs(path) do
            if pn.row == osr and pn.column == osc then
                return i
            end
        end
        return 1                                  -- 起点不在路径内: 从头
    end
    local start_idx = locate_outset()
    -- 2026-10-26二十二修: 回退到起点节点所在趟的首节点。降序趟的
    -- (0,0)默认起点=趟末节点, 而图外虚拟排/地头进入只与趟首相邻,
    -- 到达帧与pn.row永不匹配->屏端停止下发->固件NEXT链自耗尽->
    -- 播1排即'播种结束'(试验田1实测+e2e复现); 无图外同病=只播末
    -- 排即挂趟。QT开窗nextPathIndex=0即趟首
    while start_idx > 1
          and path[start_idx - 1].column == path[start_idx].column do
        start_idx = start_idx - 1
    end
    while start_idx <= #path do
        local pn = path[start_idx]
        local blk = t.blocks[pn.row] and t.blocks[pn.row][pn.column]
        -- 中断(3)与完成(2)同跳: isSow对3为false->密度0驶过不补播(QT同),
        -- 否则半趟停止后续作永远锚在半趟块上, 同一趟无限重走(2026-10-21实测)
        if not blk or (blk.sow == 1 and blk.state ~= 2 and blk.state ~= 3) then
            break
        end
        start_idx = start_idx + 1
    end
    if start_idx > #path then
        -- 任务100%完成: 开始键照常可用(2026-10-20用户澄清, M23误读已撤回
        -- 致歉)。QT :306-307停止续作指针=tempIndex=getIndex(bzst.RowNum,
        -- currentColumn)+1(机器实时位置+1, 越尾回绕:415-417)——100%后每次
        -- 开始按选定路径顺序走下一趟(趟1->趟2->回绕趟1)。锚点必须用机器
        -- 实时上报位置(_feed逐帧更新的t.last_r/last_c): 重驶不再产生落库,
        -- 落库位置t.last恒停在趟2末尾会使回绕失效(实测每次都重走趟1,
        -- 用户报告"-700到3000重复"); t.last仅作掉电后实时位置丢失的兜底。
        -- 已完成小区isSow=false->密度0驶过(不播不漏计不重记), 图外开出图
        -- 后按出图前小区参数继续播
        local lr = t.last_r or (t.last and t.last.r) or -1
        local lc = t.last_c or (t.last and t.last.c) or -1
        local ti = nil
        if lr >= 0 then
            for i, pn in ipairs(path) do
                if pn.row == lr and pn.column == lc then
                    ti = i
                    break
                end
            end
        end
        if ti then
            start_idx = ti % #path + 1
            log("INF", ("任务已100%%完成: 自第%d节点(下一趟)续驶, "
                .. "已完成小区不播不计"):format(start_idx))
        else
            start_idx = locate_outset()
            log("INF", "任务已100%完成: 无作业位置, 自播种起点重驶")
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
        need_entry = false, boundary_advanced = false,
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
    -- 停止即中断标红(2026-10-21用户要求): 进行中(1)->中断(3), 与boot掉电
    -- 转换(store.boot 1->3, QT task.cpp:44加载时转换)同口径; QT本体在重新
    -- 打开对话框重载任务时才转红, 屏端任务常驻内存无重载时机, 故提前到停止
    local tt = STORE.tasks[J.task]
    if tt then
        local n3 = 0
        for _, row in pairs(tt.blocks) do
            for _, b in pairs(row) do
                if b.state == 1 then b.state = 3; n3 = n3 + 1 end
            end
        end
        if n3 > 0 then
            log("INF", ("中断小区%d块已标红(停止)"):format(n3))
        end
    end
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
            -- 防重记(2026-10-20): 组内全部已完成(is_sow=false)则跳过——
            -- QT :404 setBlockState(..,2)幂等不记结果; 此前无条件落库,
            -- 100%重驶出图帧以0计数追加重复行(e2e实测11行/0计数)
            if PATHALGO.is_sow(t, m, J.cur_read_row, J.cur_col, b) then
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
            -- M56(用户语义: 出图后按末小区参数继续播): 边界排完成帧(一次性)推进:
            --   exceed=1 -> advance发出口侧虚拟节点(末小区参数), 出图段继续播;
            --   exceed=0 -> 下趟首排(边界Final=1已停播不受影响);
            --   boundary_advanced旗标防出图帧连发重复推进, 回图内清除
            if not J.boundary_advanced then
                J.boundary_advanced = true
                advance()
            end
        end
        -- 非图外开出图帧不下发不推进(QT :403-409同): 趟界节点NextDensity=-1
        -- 令机器在地头保持等待, 跨趟由停止->开始的重启指针完成(见start)
    else
        ---- 图内(QT :411-470)
        local pn = J.path[J.next_idx]
        if not pn then jobrun._complete(); return end
        J.boundary_advanced = false            -- M56: 回图内清出图推进旗标

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
            elseif J.need_entry then
                send_node(pn.row, J.cur_col)         -- M56: 出图段后再入图,
                J.need_entry = false                 --   补发新趟首小区参数
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
