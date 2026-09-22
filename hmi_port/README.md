# 组态屏移植 (QT上位机 → 大彩 HMI80480KM070_C011_40T / VisualHMI Lua 5.3)

屏经 RS232 (115200-8N1, 6P端子 TXD/RXD) 直连下位机, 用 Lua 实现全部协议与业务。
开发期联调链: **VisualHMI 虚拟屏(PC, 串口映射COM9) ↔ ELTIMA虚拟串口对 ↔ seeder_sim 模拟器(COM8)**。

## 目录

```
hmi_port/
  lua/
    sow_protocol.lua   帧层: 0x68/FNC/len/CRC16-Kermit(0x8408反射查表)/0x0D
                        增量解析FSM(分包/粘包/CRC错丢1字节重同步), 与上位机
                        communication.cpp 逐字节一致
    sow_layout.lua     8种结构体 pack/unpack (92/84/68/56/40/16/12/4B),
                        全小端, 纯Lua IEEE754 double/float 编解码,
                        加载时尺寸自检; 与 seeder_sim/layout.py 位级一致
  tests/
    test_lua_protocol.py  M0-M1验收(lupa锁定Lua5.3): CRC向量/查表比对/帧容错/
                        结构体互证/与模拟器进程内全链路联测
```

两个 Lua 文件是**纯 Lua 5.3**（不用 string.pack/rep/gmatch、不用 io/os、不依赖
math.frexp），屏内与 PC 测试双端同一份代码；全局命名空间 `SOW`，多文件 dofile
或整段拼接加载均可。

## 运行验收测试

```
python hmi_port/tests/test_lua_protocol.py     # 21项, 应全部通过
```

测试把模拟器 `Simulator` 跑在无串口模式（进程内直调 process_frame，用状态文件
副本，不碰 COM 口与真实存档），Lua 构帧 → 模拟器应答 → Lua 解析器解出 → 断言。

## M0: 把 Lua 装进 VisualHMI 工程 (在 PC 上操作一次)

1. 安装 VisualHMI（大彩官网下载, 医用级组态屏配套版）。
2. 新建工程: 分辨率 800×480, 选对型号系列。
3. 把 `hmi_port/lua/` 下两个文件加入工程脚本（工程 → LUA编程 → 添加脚本文件;
   若版本只支持单脚本, 按 sow_protocol.lua 在前、sow_layout.lua 在后拼接整段粘贴,
   两个文件本身设计为可拼接）。
4. 临时验证脚本（虚拟屏控制台/调试输出观察）:
   ```lua
   -- on_init 里:
   print(SOW.protocol.hex(SOW.protocol.build_frame(0xA3, '')))
   -- 期望输出: 68 A3 00 00 71 93 0D
   ```
5. 虚拟屏联调: 编译工程 → 虚拟串口屏 → 串口设置选 COM9 @115200
   （本机 ELTIMA 虚拟串口对的另一端）; 再启动 `python seeder_sim/main.py --port COM8`。
   屏内发 0xA3、收版本串即 M0 通过（真机版本见下方接线）。

## 屏内 API 差异备忘 (写给后续 comm/glue 层)

- `uart_setup(0, 115200, 8, 0, 0)`; **`uart_send(ch, 字节表)`** — 发送前把帧字符串
  转字节表: `local t={} for i=1,#s do t[i]=string.byte(s,i) end uart_send(0,t)`。
- `on_uart_recv(ch, packet)` 为系统轮询回调, 官方确认存在分包/粘包, 直接喂
  `SOW.protocol.feed(parser, packet)` 即可（FSM 已处理）; 回调内禁止耗时操作。
- 200ms 轮询用 `start_timer(id,200,0,1)` + `on_timer(id)`; 心跳 0xA3 可共用
  connectionTimer 模式 (500ms)。
- 下位机调试串是 GB2312: 显示用 `draw_text(..., charcode=1)`(GBK) 直显,
  字库需含 GB2312 全集（工程字符+GB2312 模式）。
- 结果/配置存储: `'2:'`=U盘 `'3:'`=Flash, file_* 单次读写≤2048B; RW 掉电区只放
  低频配置（10万次擦写寿命）。

## 里程碑状态

- [x] M0-M1 协议层 + PC 验收 (21项全通过)
- [ ] M2 测试模式页 (0x0E/0x0F/0x08/0x09) + sow_comm.lua 屏内通信胶水
- [ ] M3 PC导出工具(SQLite→CSV) + U盘导入 + 地图网格自绘 + 任务选择
- [ ] M4 实时任务页 (startNode/换排/currentResult, 验收判据复用 _repro_sweep)
- [ ] M5 连续播种/历史/设置 + CSV导出
- [ ] M6 真机部署 (串口/SD下载, RS232 接线: 屏TXD→MCU RXD, 屏RXD→MCU TXD, 共地)
