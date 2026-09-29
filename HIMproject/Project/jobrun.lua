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
local w16, w32, wstr, NOW, rw16, rw16w, RSTR, r16

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
    w16, w32, wstr, NOW = deps.w16, deps.w32, deps.wstr, deps.now
    rw16, rw16w = deps.rw16, deps.rw16w
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
             a_row = a_row, abdir = abdir, has = true }
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
              StartState = 1, CalcDirFlag = 1, OffLen = 0, BDOffTime = 100 }
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
    }

    -- 状态展示: 主页 taskinfo / TW 页
    if APP then APP.set_always_poll(PROTOCOL.FNC.GET_BZ_STATUS) end
    log("INF", ("作业启动 %s 地图=%s 路径=%d 起点组=%d"):format(
        task_name, m.name, t.path_type, start_idx))

    -- 2026-09-23 对齐QT(dialogrealtimetask.cpp:559-568): 启动先下发AB线——
    -- 有绑定->存储值(StartState=1); 无绑定->全零(StartState=0, 固件清空BDParam,
    -- 地头等待行程开关触发设A点后才开播)。此前屏端从不发0x24, 下位机沿用上次
    -- 持久化的StartState=1, 无AB线任务跳过触发直接开播(用户联调暴露)。
    jobrun.ab_send_map(m)

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
    log("INF", "作业停止 " .. J.task)
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
        local m = ab_dlg_map and STORE.maps[ab_dlg_map]
        wstr(LW.ABP.name, (m and m.ab and m.ab.name) or "")
    else
        wstr(LW.ABP.name, "")
    end
    PROTOCOL.send(PROTOCOL.FNC.STORE_AB)
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
        w16(LW.A.runstate, st.RunState)
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
end


return jobrun
