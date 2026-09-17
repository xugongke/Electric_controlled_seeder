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
