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
