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
