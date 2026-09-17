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
