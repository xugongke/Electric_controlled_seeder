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
