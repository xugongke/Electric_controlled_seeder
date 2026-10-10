# -*- coding: utf-8 -*-
"""工作状态机 —— 复刻 hd3005a1/Src/work_proc.c 的对外可观测行为。

两级状态:
    WorkMode: IDLE(0) / BD小区播种(1) / LXBZ连续播种(2) / TEST测试(3)
    RunState: STOP(0) / START(1), MoveOn=0x80 行进中标志
              (0x21 应答的 RunState 字节 = RunState | MoveOn: 0停止/1准备/0x81播种行进)

北斗/行进模型 (对齐 BD_SIMU_TEST 构建的模拟量):
    启动小区播种后: 行号 -10000000 保持 600ms -> 起始行程 = StartPOS∓800cm,
    恒速 BdSimuSpeed 沿 AB 线行进, 垂直偏移初始 -481cm 且每次启动 +240cm。
    停止时行程/垂直偏移上报 0。

所有调试字符串与固件 sprintf 一致(发送时 GB2312 编码)。
"""

import math

import protocol as P
from layout import BzCellPara

# WorkMode
WORK_MODE_IDLE = 0
WORK_MODE_BD = 1
WORK_MODE_LXBZ = 2
WORK_MODE_TEST = 3

# RunState
RUN_S_STOP = 0
RUN_S_START = 1

# SeedMode (对齐 operation.h)
SEED_S_WAIT = 0
SEED_S_WAIT_QZ = 1
SEED_S_WAIT_GZ = 4
SEED_S_GZ = 5
SEED_S_WAIT_END = 6
SEED_WAIT_ZERO = 7
SEED_HALF_CYCLE = 8
SEED_PRE_DZ = 11
SEED_PRE_MOTOR = 12
SEED_S_START = 13
SEED_WAIT_S_BZP = 14
SEED_ERR_WAIT = 15

SEED_MODE_NAMES = {
    SEED_S_WAIT: '等待播种开始', SEED_S_WAIT_QZ: '等待清种', SEED_S_WAIT_GZ: '等待刮种',
    SEED_S_GZ: '刮种', SEED_S_WAIT_END: '等待结束', SEED_WAIT_ZERO: '等待零位',
    SEED_HALF_CYCLE: '旋转半圈', SEED_PRE_DZ: '预充种-倒种', SEED_PRE_MOTOR: '预充种-电机调整',
    SEED_S_START: '等待开始播种', SEED_WAIT_S_BZP: '等待播种盘动作', SEED_ERR_WAIT: '异常等待',
}

WORK_MODE_NAMES = {WORK_MODE_IDLE: '空闲', WORK_MODE_BD: '小区播种',
                   WORK_MODE_LXBZ: '连续播种', WORK_MODE_TEST: '测试'}

ROW_NUM_INVALID = -10000000          # 上位机以此判定"尚未实质播种"

# 阀门位 (CtrlValveState[12] / CtrlState bit0..11)
V_YLZ, V_DZ, V_QZ, V_GZ, V_RSV1, V_RSV2, V_LB, V_TAP, V_WARN, V_RUN = range(10)

U32_MAX = 0xFFFFFFFF
ZERO_HIT_RATIO = 0.35                # 零位开关在盘转动 ~35% 圈处触发的模拟位置


def get_zhu_shu(density, cell_len, hju):
    """单行株数, 对齐 work_proc.c GetZhuShu()。"""
    if cell_len < 20:
        cell_len = 20
    zhushu = math.ceil(max(density, 0) * (hju * 0.01) * (cell_len * 0.01) / 666.67)
    if zhushu < 2:
        zhushu = 2
    return zhushu


def get_zhu_ju(cell_len, n):
    """株距 cm 四舍五入, 对齐 GetZhuJu()。"""
    if n <= 1:
        return 0
    return (cell_len * 10 // (n - 1) + 5) // 10


def cal_ab_dir(start_n, start_e, end_n, end_e):
    """AB线方向角, 对齐 operation.c CalABDir()。返回 (角度deg, 距离m)。"""
    rn = 6371393.0 * math.cos(math.radians(start_n))
    x = math.radians(end_e - start_e) * rn
    y = math.radians(end_n - start_n) * 6371393.0
    r = math.hypot(x, y)
    if r == 0:
        return 0.0, 0.0
    ang = math.degrees(math.acos(max(-1.0, min(1.0, y / r))))
    if x < 0:
        ang = 360 - ang
    return ang, r


class WorkProc:
    def __init__(self, device, speed_mm_s=1000):
        self.dev = device
        self.speed_mm_s = speed_mm_s     # BdSimuSpeed
        self.reset_runtime()

    # ================================================================ 运行时复位
    def reset_runtime(self):
        self.work_mode = WORK_MODE_IDLE
        self.run_state = RUN_S_STOP
        self.seed_mode = SEED_S_WAIT
        self.move_on = 0
        self.pending_cmd = P.FNC_CMD_NULL
        self.debug = '空闲模式'
        self.bz_cell = BzCellPara()      # 上位机 0x20 下发缓冲 BZCellPara
        self.bz_curr = BzCellPara()      # 控制板内部当前小区 BZCellParaCurr
        self.zhuju = [0] * 6
        self.row_num_increase = True
        self.next_ylz_on = False
        self.dz_start_flag = False
        self.row_no_update_flag = False
        self.state_start = 0             # StateStartTime ms
        self.wait_until = 0              # SEED_S_WAIT 的 600ms 无效行号窗口
        self.now = 0
        self._tick_dt = 0
        # 北斗/行进模拟
        self.bd_ok = True
        self.paused = False
        self.reverse = False             # 实际行驶方向与 TXFlag 相反(测"方向不符"报错)
        self.zerofail = False            # 注入"零位开关触发错误"
        self.bd_tx_flag = True           # BDTXFlag
        # 垂直偏差模型: 初始 = -(行数x行距), 每次启动小区播种 += 行数x行距,
        # 即第1排压在AB线上(垂直偏差0), 以后每掉头一次增加一个作业幅宽
        # (4行x60cm=240cm, 6行x60cm=360cm)。固件测试代码硬编码-481/+240, 无物理含义。
        self.vertical_off = -(self.dev.rows * self.dev.user.HJ)
        self.pos_cm = 0.0                # 行进方向行程 cm (BdCurrOffCoor.Y*100)
        self.frozen_off = 0              # 停止瞬间冻结的行程(0x23取B点, 停车后位置仍有效)
        self._run_prev = False
        self.movement_armed = False
        self.speed_now = 0               # BdCalcSpeed mm/s 带符号
        self.bd_trig_cnt = 0             # 北斗行程开关触发计数
        self.init_key = False            # 一键初始化按钮(测试模式)
        # 电机/阀门
        self.dj_bits = 0                 # DJCtrlState: bit0..rows-1 播种盘, 其后供种
        self.pulse_target = 0            # TotalOutputPWMNums
        self.pulse_pos = 0.0             # GetCurrPulseNum(各盘最大值)
        self.valve = [0] * 12            # CtrlValveState
        self.dz_time = 0                 # DzStartTime
        self.ylz_time = 0                # YLZStartTime
        self.tap_time = 0                # TapperOnStartTime
        # 打点
        self.qz_tap_done = False
        self.gd_tap_done = False
        self.qz_start_off = 0
        # 计数 (ClearLzCnt 后归零的区段计数; 注意 hd3005a2 仅清前4路)
        self.louzh = [0] * 6
        self.loufei = [0] * 6
        self._lz_frac = [0.0] * 6
        self._lf_frac = [0.0] * 6
        # 连续播种
        self.lxbz_cell_len = 500
        self.lxbz_zhushu = 0

    # ================================================================ 命令入口(FrameProcess -> CurrentCMDAna)
    def cmd_start_bz(self):
        self.pending_cmd = P.FNC_CMD_START_BZ

    def cmd_stop_bz(self):
        self.pending_cmd = P.FNC_CMD_STOP_BZ

    def cmd_start_test(self):
        self.pending_cmd = P.FNC_START_TEST

    def cmd_stop_test(self):
        self.pending_cmd = P.FNC_STOP_TEST

    def cmd_start_lxbz(self):
        self.pending_cmd = P.FNC_CMD_START_LXBZ

    def cmd_stop_lxbz(self):
        self.pending_cmd = P.FNC_CMD_STOP_LXBZ

    def cmd_restart(self):
        """0x10: ACK 后约500ms 重新上电(参数保留, 运行状态复位)。"""
        self.pending_cmd = P.FNC_RESTART_TER

    def press_init(self):
        """一键初始化按钮: 置起 InitKey 供测试模式回零流程使用,
        同时把垂直偏差复位为 -(行数x行距), 模拟机器重新对准AB线准备首排作业,
        下次启动小区播种后垂直偏差回到0。"""
        self.init_key = True
        self.vertical_off = -(self.dev.rows * self.dev.user.HJ)

    def set_bz_para(self, para: BzCellPara):
        self.bz_cell = para

    def test_ctrl(self, ctrl_no, state):
        """0x09: 仅测试模式下由 TestModeProc 应用到阀门/电机位。"""
        max_ctrl = 23 if self.dev.rows == 6 else 21   # MAX_CTRL_NUMS, 6行机扩展到22
        if ctrl_no >= max_ctrl:
            return
        if ctrl_no <= 9:
            self.valve[ctrl_no] = 1 if state else 0
            if ctrl_no == V_YLZ and state:
                self.ylz_time = self.now
            elif ctrl_no == V_DZ and state:
                self.dz_time = self.now
            elif ctrl_no == V_TAP and state:
                self.tap_time = self.now
        elif 16 <= ctrl_no <= 16 + self.dev.rows:     # 16.. 播种盘1..N, 最后一个为供种电机
            bit = ctrl_no - 16
            if state:
                self.dj_bits |= (1 << bit)
            else:
                self.dj_bits &= ~(1 << bit)

    # ================================================================ 属性/查询
    @property
    def disc_mask(self):
        # DJCtrlState 位布局(与上位机 CtrlNo-16 一致, 见 protocol.h CtrlState 注释):
        # bit0-3=播种盘1-4, bit4=自动供种电机(4/6行机相同, CtrlNo20), bit5/6=播种盘5/6
        return 0x6F if self.dev.rows == 6 else 0x0F

    @property
    def supply_bit(self):
        return 1 << 4                                 # CtrlNo 20 自动供种电机

    @property
    def run_state_byte(self):
        return (self.run_state | self.move_on) & 0xFF

    def _off_len(self):
        return int(self.pos_cm)                       # (s32)(Y*100), C 截断

    def _off_disp(self):
        # 显示/上报口径(2026-10-10): 反向列(tx=0)取绝对值, 行程恒为正数递减
        # —— 触发计算仍用 _off_len 的带符号原值(播种基准已锁定, 勿动)
        v = self._off_len()
        return -v if not self.bd_tx_flag else v

    def bd_dist_cm(self):
        """0x23 取 B 点用的当前行程: 运行中=实时 OffLen, 停止=停止瞬间冻结值。

        对齐固件 StoreAB(protocol.c:265): B 点取 CurrBDPos 原始 GNSS 坐标,
        与运行状态无关; 模拟器的"位置"即行程, 停止后 OffLen 清零故用冻结值。
        """
        return self._off_len() if self.run_state == RUN_S_START else self.frozen_off

    def get_bz_status(self):
        vert = self.vertical_off if self.run_state == RUN_S_START else 0
        return dict(run_state=self.run_state_byte,
                    bd_state=1 if self.bd_ok else 0,
                    speed=self.speed_now,
                    row_num=self.bz_curr.RowNum,
                    off_len=self._off_disp(),
                    vertical_off=vert,
                    loufei=list(self.loufei),
                    louzh=list(self.louzh))

    def get_test_status(self):
        inputs = 0
        warn = 0
        zero_bits = 0x0F                                # 零位开关1-4 -> bit0-3
        if self.dev.rows == 6:
            zero_bits |= (3 << 13)                      # 零位开关5-6 -> bit13/14
        if self.zerofail:
            # 零位开关故障注入: 开关永不触发(输入位清0),
            # 并置位对应报警位让上位机测试页显示红色报警(扩展: 固件硬编码0未实现)
            warn |= zero_bits
        elif (self.dj_bits & self.disc_mask) == 0:      # 电机停转在零位 -> 开关触发
            inputs |= zero_bits
        if self.dj_bits & self.supply_bit:
            inputs |= (1 << 4)                          # 自动供种接近开关
        inputs |= (1 << 8) | (1 << 9)                   # 气路/风机压力正常
        if self.init_key:
            inputs |= (1 << 11)                         # 一键初始化按钮
        if self.bd_ok:
            inputs |= (1 << 12)                         # 北斗信号
        ctrl_state = 0
        for i in range(12):
            if self.valve[i]:
                ctrl_state |= (1 << i)
        ctrl_state |= (self.dj_bits << 16) & 0xFFFF0000
        return dict(encoder_cnt=0,                      # hd3005a2: 编码器已删除, 恒为0
                    bd_cnt=self.bd_trig_cnt,
                    loufei=list(self.loufei), louzh=list(self.louzh),
                    input_state=inputs, warning_state=warn, ctrl_state=ctrl_state)

    # ================================================================ 主循环(对齐 WorkProcTask, 由 main 以 ~10ms 周期驱动)
    def step(self, now_ms):
        self._tick_dt = max(0, now_ms - self.now) if self.now else 0
        self.now = now_ms
        self._bd_sim()
        {WORK_MODE_IDLE: self._idle_proc,
         WORK_MODE_BD: self._bz_proc,
         WORK_MODE_LXBZ: self._lxbz_proc,
         WORK_MODE_TEST: self._test_proc}[self.work_mode]()
        self._process_cmd()
        self._io_timers()
        self._counters()

    # ------------------------------------------------ 北斗/行进模拟
    def _bd_sim(self):
        run = self.run_state == RUN_S_START
        moving = run and self.movement_armed and self.bd_ok and not self.paused
        # 等待行程开关触发期间冻结经纬度推进(2026-10-09用户要求:
        # 拖拉机地头停下按开关, 模拟器位置保持不变; 触发后继续模拟运动)
        if (moving and self.work_mode == WORK_MODE_BD
                and self.seed_mode == SEED_S_START
                and self.dev.bd.StartState == 0 and self.bd_trig_cnt == 0):
            moving = False
        if moving:
            sign = -1 if self.reverse else 1          # 相对 BDTXFlag 方向的行驶方向
            dir_pos = (1 if self.bd_tx_flag else -1) * sign
            delta = self.speed_mm_s / 10000.0 * self._tick_dt   # mm/s -> cm/ms
            self.pos_cm += delta * dir_pos
            self.speed_now = int(self.speed_mm_s * sign)
        else:
            self.speed_now = 0
        if not run:
            if self._run_prev:
                # 停止瞬间冻结行程: 真机 GNSS 位置停车后仍有效, 0x23 取 B 点用
                # (固件 StoreAB 用 CurrBDPos 原始坐标, 不随停止清零);
                # OffLen 上报仍按固件 BDTrigCoor 停止分支清零
                self.frozen_off = int(self.pos_cm)
            self.pos_cm = 0.0                         # BDTrigCoor 停止分支: Y=X=0
        self._run_prev = run

    def _sync_curr(self):
        """memcpy(&BZCellParaCurr, &BZCellPara) + 重算各行株距。"""
        c, b = self.bz_curr, self.bz_cell
        c.TXFlag, c.FinalFlag, c.NextFinalFlag, c.isAfterNextZoneSow = \
            b.TXFlag, b.FinalFlag, b.NextFinalFlag, b.isAfterNextZoneSow
        c.RowNum, c.InS = b.RowNum, b.InS
        c.Density = list(b.Density)
        c.CellLen, c.StartPOS, c.DisplayRowNum = b.CellLen, b.StartPOS, b.DisplayRowNum
        c.NextRowNum, c.NextInS = b.NextRowNum, b.NextInS
        c.NextDensity = list(b.NextDensity)
        c.NextCellLen, c.NextStartPOS, c.NextDisplayRowNum = \
            b.NextCellLen, b.NextStartPOS, b.NextDisplayRowNum
        self._calc_zhuju()

    def _calc_zhuju(self):
        for i in range(6):
            dens = max(self.bz_curr.Density[i], 0)
            n = get_zhu_shu(dens, self.bz_curr.CellLen, self.dev.user.HJ)
            self.zhuju[i] = get_zhu_ju(self.bz_curr.CellLen, n)

    def _clear_lz_cnt(self):
        """对齐 hd3005a2 para.c ClearLzCnt() (20260917修复版): 循环上界 LINE_NUM,
        全部 6 路漏种/漏肥计数一并清零。"""
        self.louzh = [0] * 6
        self.loufei = [0] * 6
        self._lz_frac = [0.0] * 6
        self._lf_frac = [0.0] * 6

    def _pulse_rate(self):
        """预充种/测试阶段电机脉冲速率 pulses/s: Rpm -> 盘转速。"""
        t = self.dev.ter
        return self.dev.user.Rpm / 60.0 * t.MicroStepValue * t.GearRatio

    def _motors_run(self):
        if self.pulse_target and (self.dj_bits & self.disc_mask):
            self.pulse_pos += self._pulse_rate() * self._tick_dt / 1000.0

    # ------------------------------------------------ 小区播种模式 BZModeProc
    def _a_minus_b(self):
        return self.dev.ter.A - self.dev.ter.B

    def _full_turn(self):
        t = self.dev.ter
        return t.MicroStepValue * t.GearRatio

    def _enter_pre_dz(self):
        """SEED_WAIT_ZERO 零位到位 -> 预充种(倒种)阶段。"""
        self.dj_bits = 0
        self.pulse_pos = 0
        self.pulse_target = 0
        self.seed_mode = SEED_PRE_DZ
        self.state_start = self.now
        self.next_ylz_on = self.bz_curr.Density[0] > 0
        self._set_valve(V_YLZ, self.next_ylz_on)
        t = self.dev.ter
        if t.GZEn:
            self._set_valve(V_QZ, True)
            self.debug = '预充种-清种[%d]' % self.bz_curr.DisplayRowNum
        else:
            self.debug = ('预充种-预落种[%d]' if self.next_ylz_on
                          else '跳过预充种-预落种[%d]') % self.bz_curr.DisplayRowNum

    def _bz_proc(self):
        t = self.dev.ter
        if self.run_state == RUN_S_STOP:
            self.move_on = 0
            self.debug = '停止模式'
            self._stop_all_ctrl()
            return

        sm = self.seed_mode
        if sm == SEED_S_WAIT:
            if self.wait_until == 0:
                self.wait_until = self.now + 600      # osDelay(600) 让上位机取到无效行号
                self.bz_curr.RowNum = ROW_NUM_INVALID
                return
            if self.now < self.wait_until:
                return
            if not self.bd_ok:
                self.debug = '无法获取定位信息'
                self.wait_until = self.now + 600
                return
            # 北斗模拟初始化 (BD_SIMU_TEST: 起始行程=StartPOS∓800, 垂直偏移+240)
            self.wait_until = 0
            self.bd_tx_flag = self.bz_cell.TXFlag == 1
            self.pos_cm = float(self.bz_cell.StartPOS + (-800 if self.bd_tx_flag else 800))
            self.movement_armed = True
            self.vertical_off += self.dev.rows * self.dev.user.HJ   # 掉头跨行数x行距
            self.row_num_increase = self.bz_cell.DisplayRowNum < self.bz_cell.NextDisplayRowNum
            self._sync_curr()
            if t.ZeroPosEn:
                self.seed_mode = SEED_HALF_CYCLE
                self.debug = '等待零位'
                self.dj_bits |= self.disc_mask
                self.pulse_pos = 0
                self.pulse_target = self._full_turn() + 20
            else:
                self.dj_bits = 0
                self.pulse_target = 0
                self.debug = '预充种'
                self.seed_mode = SEED_WAIT_ZERO
        elif sm == SEED_HALF_CYCLE:
            self._motors_run()
            if self.pulse_pos < self._full_turn() / 2:
                self.dj_bits |= self.disc_mask
                self.debug = '旋转半圈'
            else:
                self.debug = '等待零位'
                self.seed_mode = SEED_WAIT_ZERO
                self.pulse_pos = 0
        elif sm == SEED_WAIT_ZERO:
            if t.ZeroPosEn == 0:
                self._enter_pre_dz()                  # 不使用零位开关: 视为全部到位
                return
            self._motors_run()
            self.dj_bits |= self.disc_mask
            if self.pulse_pos >= self._full_turn() + 20:
                self.debug = '零位开关触发错误'        # 转过一圈仍未触发
                self.dj_bits = 0
                self.seed_mode = SEED_ERR_WAIT
            elif not self.zerofail and self.pulse_pos >= self._full_turn() * ZERO_HIT_RATIO:
                self._enter_pre_dz()
        elif sm == SEED_PRE_DZ:
            if self.now - self.state_start >= self.dev.user.DZTime:
                self._set_valve(V_QZ, False)
                self._set_valve(V_YLZ, False)
                if self.bz_cell.FinalFlag == 0 and self.bz_cell.NextDensity[0] > 0:
                    self._set_valve(V_DZ, True)
                    self.next_ylz_on = True
                else:
                    self._set_valve(V_DZ, False)
                    self.next_ylz_on = False
                if t.GZEn:
                    self._set_valve(V_GZ, True)
                row_num = self.bz_cell.DisplayRowNum + (1 if self.row_num_increase else -1)
                self.debug = ('预充种-播种盘调整[%d] 倒种[%d]' if self.next_ylz_on
                              else '预充种-播种盘调整[%d] 跳过倒种[%d]') \
                             % (self.bz_cell.DisplayRowNum, row_num)
                self.state_start = self.now
                self.seed_mode = SEED_PRE_MOTOR
                self.dj_bits |= self.disc_mask
                self.pulse_pos = 0
                pre_steps = t.HoleNum * (t.PrePercent % 101)
                self.pulse_target = (pre_steps * t.MicroStepValue * t.GearRatio) \
                    // (t.HoleNum * 100)
        elif sm == SEED_PRE_MOTOR:
            self._motors_run()
            if self.pulse_pos >= self.pulse_target:
                self.debug = '等待开始播种[%d]' % self.bz_cell.DisplayRowNum
                self.dj_bits = 0
                self.pulse_target = 0
                self.state_start = self.now
                self.seed_mode = SEED_S_START
                self._clear_lz_cnt()
                self.bd_trig_cnt = 0
                self._set_valve(V_RUN, True)          # 运行指示灯亮, 提示可开始行驶
        elif sm == SEED_S_START:
            self.move_on = 0x80
            if not self.bd_ok:
                self.debug = '无法获取定位信息'
                return
            self._sync_curr()
            bd = self.dev.bd
            if bd.StartState == 0:
                if self.bd_trig_cnt != 0:
                    bd.StartN, bd.StartE = 36.40, 117.00
                    bd.StartState = 1
                    bd.StartDir = 0
                    bd.CalcDirFlag = 0
                    bd.BDOffTime = 100
                    # 冻结期间speed_now=0, 用标称速度(触发即恢复行驶)
                    bd.OffLen = int((100 + 500) * self.speed_mm_s / 10000)
                    self.debug = '等待播种盘动作[%d]' % self.bz_curr.DisplayRowNum
                    self.seed_mode = SEED_WAIT_S_BZP
                    self.state_start = self.now
                else:
                    self.debug = '等待行程开关触发'
            else:
                self.debug = '等待播种盘动作[%d]' % self.bz_curr.DisplayRowNum
                self.seed_mode = SEED_WAIT_S_BZP
                self.state_start = self.now
        elif sm == SEED_WAIT_S_BZP:
            if self.bz_curr.TXFlag != (1 if self.bd_tx_flag else 0):
                self.debug = '下发方向与实际行驶方向不符'
                self.dj_bits = 0
                self.seed_mode = SEED_ERR_WAIT
                return
            threshold = self.bz_curr.StartPOS + self._dir(self._a_minus_b())
            if self.bd_tx_flag:                        # 固件: 同向+3+20, 反向-3-20 (无BDiroff)
                hit = self._off_len() + 23 >= threshold
            else:
                hit = self._off_len() - 23 <= threshold
            if hit:
                self.qz_tap_done = False
                self.gd_tap_done = False
                self.qz_start_off = self._get_qz_start_off()
                self.dj_bits |= self.disc_mask
                self.pulse_pos = 0
                self.pulse_target = U32_MAX           # 播种电机随行进连续动作
                self._set_valve(V_GZ, False)
                self.seed_mode = SEED_S_WAIT_QZ
                self.state_start = self.now
                self.debug = '等待清种[%d]' % self.bz_curr.DisplayRowNum
        elif sm == SEED_S_WAIT_QZ:
            self._tap_proc()
            if self.gd_tap_done:
                self.gd_tap_done = False
            if self._reached(self.qz_start_off, 3):
                if self.bz_curr.Density[0] > 0:
                    self._set_valve(V_QZ, True)
                if t.GZEn:
                    if self.next_ylz_on:
                        self._set_valve(V_YLZ, True)
                    self.debug = '等待刮种[%d]' % self.bz_curr.DisplayRowNum
                    self.seed_mode = SEED_S_WAIT_GZ
                else:
                    self.debug = ('开始清种[%d]' if self.bz_curr.Density[0] > 0
                                  else '跳过清种[%d]') % self.bz_curr.DisplayRowNum
                    self.seed_mode = SEED_S_GZ
                self.state_start = self.now
                self.dz_start_flag = False
        elif sm == SEED_S_WAIT_GZ:
            self._tap_proc()
            if self._reached(self._qz_end_off(), 3):
                self._qz_end_proc()
            if self._reached(self.bz_curr.StartPOS + self._dir(
                self.bz_curr.CellLen + self._a_minus_b()), 3):
                if t.GZEn:
                    self._set_valve(V_GZ, True)
                    self.debug = '开始刮种[%d]' % self.bz_curr.DisplayRowNum
                self.seed_mode = SEED_S_GZ
                self.state_start = self.now
        elif sm == SEED_S_GZ:
            self._tap_proc()
            if self._reached(self._qz_end_off(), 3):
                self._qz_end_proc()
            if self._reached(self.bz_curr.StartPOS + self._dir(
                self.bz_curr.CellLen + self.bz_curr.InS + self._a_minus_b()), 3):
                self._set_valve(V_GZ, False)
                self._set_valve(V_YLZ, False)
                if not self._update_row_num_check():
                    self.debug = '播种结束[%d]' % self.bz_cell.DisplayRowNum
                    self.dj_bits = 0
                    self.seed_mode = SEED_ERR_WAIT
                    return
                self._clear_lz_cnt()
                self.seed_mode = SEED_S_WAIT_QZ
                self.qz_tap_done = False
                self.qz_start_off = self._get_qz_start_off()
                self.state_start = self.now
                self.debug = '等待清种[%d]' % self.bz_curr.DisplayRowNum
        elif sm == SEED_ERR_WAIT:
            self._stop_all_ctrl()
        else:
            self.seed_mode = SEED_S_WAIT

    def _reached(self, off, lead):
        """行程阈值判断: 同向 CURR+lead>=off, 反向 CURR-lead+BDiroff<=off。"""
        if self.bd_tx_flag:
            return self._off_len() + lead >= off
        return self._off_len() - lead + self.dev.ter.BDiroff <= off

    def _dir(self, v):
        """反向排(TXFlag=0)的阈值相对StartPOS取负, 对齐固件 CELL_OFF-(...) 系列公式。"""
        return v if self.bd_tx_flag else -v

    def _get_qz_start_off(self):
        """对齐 GetQzStartOff(): CELL_OFF±(CELL_L+A-B-预充种提前量)。"""
        t = self.dev.ter
        pre_steps = t.HoleNum * (t.PrePercent % 101)
        lead = pre_steps * self.zhuju[0] // 100
        base = self.bz_curr.CellLen + self._a_minus_b() - lead
        if self.bd_tx_flag:
            return self.bz_curr.StartPOS + base
        return self.bz_curr.StartPOS - base

    def _qz_end_off(self):
        """清种停止位置: QZStartOff+(InS-Zhuju[0])。"""
        span = self.bz_curr.InS - self.zhuju[0]
        if span < 0:
            span = 0
        return self.qz_start_off + (span if self.bd_tx_flag else -span)

    def _qz_end_proc(self):
        """清种结束分支(SEED_S_WAIT_GZ / SEED_S_GZ 共用)。"""
        t = self.dev.ter
        self._set_valve(V_QZ, False)
        if t.GZEn:
            self._set_valve(V_YLZ, False)
        else:
            row_num = self.bz_curr.DisplayRowNum + (1 if self.row_num_increase else -1)
            if self.bz_curr.FinalFlag == 0:
                if self.next_ylz_on:
                    self._set_valve(V_YLZ, True)
                    self.debug = '开始预落种[%d]' % row_num
                else:
                    self.debug = '跳过预落种[%d]' % row_num
            else:
                self.debug = '等待当前小区完成[%d]' % self.bz_curr.DisplayRowNum
        if not self.dz_start_flag:
            self.dz_start_flag = True
            if t.GZEn:
                row_num = self.bz_curr.DisplayRowNum + (1 if self.row_num_increase else -1)
                if self.bz_curr.FinalFlag == 0:
                    if self.bz_cell.isAfterNextZoneSow == 1:
                        self._set_valve(V_DZ, True)
                        self.next_ylz_on = True
                        self.debug = '开始倒种[%d]' % row_num
                    else:
                        self.next_ylz_on = False
                        self._set_valve(V_DZ, False)
                        self.debug = '跳过倒种[%d]' % row_num
                else:
                    self.next_ylz_on = False
                    self.debug = '跳过倒种[%d] 等待当前小区结束[%d]' \
                                 % (row_num, self.bz_curr.DisplayRowNum)

    def _tap_proc(self):
        """清种时刻/过道中间打点, 对齐 QZTapProc/GDTapProc。"""
        t = self.dev.ter
        if not self.qz_tap_done:
            off = self.qz_start_off + (-t.TappTrigOff if self.bd_tx_flag else t.TappTrigOff)
            if self._reached(off, 3):
                self.qz_tap_done = True
                if self.dev.qzdd_enable:
                    self._set_valve(V_TAP, True)
        if not self.gd_tap_done:
            c = self.bz_curr
            mid = c.CellLen + c.InS // 2 - t.TappTrigOff
            off = c.StartPOS + (mid if self.bd_tx_flag else -mid)
            if self._reached(off, 3):
                self.gd_tap_done = True
                if self.dev.gddd_enable:
                    self._set_valve(V_TAP, True)

    def _update_row_num_check(self):
        """对齐 UpdateRowNumCheck(): Next->Curr 晋升, 返回上位机是否及时更新。"""
        curr, rx = self.bz_curr, self.bz_cell
        self.row_no_update_flag = False
        if curr.RowNum != curr.NextRowNum:
            if curr.NextDensity[0] >= 0:
                self.row_no_update_flag = True       # NEXT 区未用完
        else:
            if rx.RowNum == curr.RowNum and rx.NextRowNum != curr.RowNum:
                self.row_no_update_flag = True       # 上位机已下发新 NEXT
                curr.NextRowNum = rx.NextRowNum
                curr.NextInS = rx.NextInS
                curr.NextDensity = list(rx.NextDensity)   # 已修复: 全6路(sizeof拷贝)
                curr.NextCellLen = rx.NextCellLen
                curr.NextStartPOS = rx.NextStartPOS
                curr.NextFinalFlag = rx.NextFinalFlag
                curr.DisplayRowNum = rx.DisplayRowNum
                curr.NextDisplayRowNum = rx.NextDisplayRowNum
        curr.FinalFlag = curr.NextFinalFlag
        curr.RowNum = curr.NextRowNum
        curr.DisplayRowNum = curr.NextDisplayRowNum
        curr.InS = curr.NextInS
        curr.Density = list(curr.NextDensity)            # 已修复: 全6路(sizeof拷贝)
        curr.CellLen = curr.NextCellLen
        curr.StartPOS = curr.NextStartPOS
        if curr.NextDensity[0] < 0:
            self.row_no_update_flag = False
        self._calc_zhuju()
        return self.row_no_update_flag

    # ------------------------------------------------ 连续播种 LXBZProc
    def _lxbz_proc(self):
        if self.run_state != RUN_S_START:
            self.move_on = 0
            self._stop_all_ctrl()
            self.debug = '停止模式'
            return
        if self.seed_mode == SEED_S_WAIT:
            if not self.bd_ok:
                self.debug = '无法获取定位信息'
                return
            self.bd_tx_flag = True                     # 固件LXBZ启动固定同向(work_proc.c:529)
            self.pos_cm = 0.0
            self.movement_armed = True
            self.state_start = self.now
            self.bz_curr.RowNum = 0
            self.seed_mode = SEED_S_WAIT_END
            self.move_on = 0x80
            self._clear_lz_cnt()
            self.lxbz_cell_len = self.dev.lxbz.CellLen
            if self.dev.lxbz.ZhuShu > 2:
                self.lxbz_zhushu = self.dev.lxbz.ZhuShu
            else:
                self.lxbz_zhushu = get_zhu_shu(self.dev.lxbz.Density,
                                               self.lxbz_cell_len, self.dev.lxbz.Hju)
        elif self.seed_mode == SEED_S_WAIT_END:
            self.debug = '连续播种模式 株距:%dcm' % get_zhu_ju(self.lxbz_cell_len,
                                                              self.lxbz_zhushu)
            self._set_valve(V_DZ, True)
            self._set_valve(V_YLZ, True)
            self._set_valve(V_QZ, False)
            self._set_valve(V_GZ, False)
            self.dj_bits |= self.disc_mask
            self.pulse_target = U32_MAX

    # ------------------------------------------------ 测试模式 TestModeProc
    def _test_proc(self):
        if self.seed_mode == SEED_S_WAIT:
            self._stop_all_ctrl()
            self.init_key = False
            self.seed_mode = SEED_S_WAIT_END
        elif self.seed_mode == SEED_S_WAIT_END:
            if self.init_key:                        # 一键初始化按钮(控制台 init 命令)
                self.init_key = False
                self.seed_mode = SEED_HALF_CYCLE
                self.dj_bits |= self.disc_mask
                self.pulse_pos = 0
                self.pulse_target = self._full_turn() + 20
                self.debug = '旋转半圈'
        elif self.seed_mode == SEED_HALF_CYCLE:
            self._motors_run()
            if self.pulse_pos < self._full_turn() / 2:
                self.dj_bits |= self.disc_mask
                self.debug = '旋转半圈'
            else:
                self.debug = '等待零位'
                self.seed_mode = SEED_WAIT_ZERO
                self.pulse_pos = 0
        elif self.seed_mode == SEED_WAIT_ZERO:
            self._motors_run()
            self.dj_bits |= self.disc_mask
            if self.zerofail and self.pulse_pos >= self._full_turn() + 20:
                self.dj_bits = 0
                self.pulse_pos = 0
                self.pulse_target = 0
                self.debug = '零位开关触发错误'
                self.seed_mode = SEED_S_WAIT_END
            elif not self.zerofail and self.pulse_pos >= self._full_turn() * ZERO_HIT_RATIO:
                self.dj_bits = 0
                self.pulse_pos = 0
                self.pulse_target = 0
                self.debug = '初始化成功'
                self.seed_mode = SEED_S_WAIT_END
        else:
            self.seed_mode = SEED_S_WAIT

    # ------------------------------------------------ 空闲 IdleModeProc
    def _idle_proc(self):
        self.debug = '空闲模式'

    # ------------------------------------------------ 命令处理(对齐各 ModeProc 末段命令响应)
    def _process_cmd(self):
        cmd = self.pending_cmd
        if cmd == P.FNC_CMD_NULL:
            return
        self.pending_cmd = P.FNC_CMD_NULL
        if cmd == P.FNC_RESTART_TER:
            speed = self.speed_mm_s
            self.reset_runtime()                     # 模拟重新上电, 参数保留
            self.speed_mm_s = speed
            return
        table = {
            WORK_MODE_IDLE: self._cmd_table_idle,
            WORK_MODE_BD: self._cmd_table_bd,
            WORK_MODE_TEST: self._cmd_table_test,
            WORK_MODE_LXBZ: self._cmd_table_lxbz,
        }[self.work_mode]
        table(cmd)

    def _cmd_table_idle(self, cmd):
        if cmd == P.FNC_CMD_START_BZ:
            self._enter(WORK_MODE_BD)
        elif cmd == P.FNC_START_TEST:
            self._enter(WORK_MODE_TEST)
            self.debug = '测试模式'
        elif cmd == P.FNC_CMD_START_LXBZ:
            self._enter(WORK_MODE_LXBZ)

    def _cmd_table_bd(self, cmd):
        if cmd == P.FNC_CMD_START_BZ:
            self._enter(WORK_MODE_BD)
            self.debug = '播种模式'
        elif cmd == P.FNC_START_TEST:
            self._enter(WORK_MODE_TEST)
            self.debug = '测试模式'
        elif cmd == P.FNC_CMD_START_LXBZ:
            self._enter(WORK_MODE_LXBZ)
        elif cmd == P.FNC_CMD_STOP_BZ:
            self.debug = '停止状态'
            self.run_state = RUN_S_STOP
            self.seed_mode = SEED_S_WAIT

    def _cmd_table_test(self, cmd):
        if cmd == P.FNC_CMD_START_BZ:
            self._enter(WORK_MODE_BD)
        elif cmd == P.FNC_START_TEST:
            self._enter(WORK_MODE_TEST)
            self.debug = '测试模式'
        elif cmd == P.FNC_CMD_START_LXBZ:
            self._enter(WORK_MODE_LXBZ)
        elif cmd == P.FNC_STOP_TEST:
            self._enter(WORK_MODE_IDLE)
            self.debug = '停止状态'

    def _cmd_table_lxbz(self, cmd):
        if cmd == P.FNC_CMD_START_BZ:
            self._enter(WORK_MODE_BD)
        elif cmd == P.FNC_START_TEST:
            self._enter(WORK_MODE_TEST)
            self.debug = '测试模式'
        elif cmd == P.FNC_CMD_START_LXBZ:
            self._enter(WORK_MODE_LXBZ)
        elif cmd == P.FNC_CMD_STOP_LXBZ:
            self.debug = '停止状态'
            self.run_state = RUN_S_STOP
            self.seed_mode = SEED_S_WAIT

    def _enter(self, mode):
        self.work_mode = mode
        self.seed_mode = SEED_S_WAIT
        self.run_state = RUN_S_START
        self.wait_until = 0
        self.movement_armed = False
        self.move_on = 0
        self.dj_bits = 0
        self.pulse_target = 0
        self.pulse_pos = 0
        for v in (V_YLZ, V_DZ, V_QZ, V_GZ, V_RUN):
            self.valve[v] = 0

    # ------------------------------------------------ IO 定时(对齐 IOProcessTask)
    def _io_timers(self):
        u = self.dev.user
        if self.valve[V_DZ] and self.now - self.dz_time >= u.DZTime:
            self.valve[V_DZ] = 0                     # 倒种到时自动关闭
        if self.valve[V_YLZ] and self.now - self.ylz_time >= u.DZTime:
            self.valve[V_YLZ] = 0                    # 预落种到时自动关闭
        if self.valve[V_TAP] and self.now - self.tap_time >= self.dev.ter.TapperTime:
            self.valve[V_TAP] = 0                    # 打点器到时自动关闭

    def _set_valve(self, idx, on):
        self.valve[idx] = 1 if on else 0
        if idx == V_YLZ:
            self.ylz_time = self.now
        elif idx == V_DZ:
            self.dz_time = self.now
        elif idx == V_TAP and on:
            self.tap_time = self.now

    def _stop_all_ctrl(self):
        for i in range(12):
            self.valve[i] = 0
        self.dj_bits = 0
        self.pulse_target = 0

    def _disc_bit(self, i):
        """第 i 路(0起)播种盘对应的 DJCtrlState 位。
        4行: bit0-3; 6行: 第5/6路 -> bit5/6 (bit4 固定为供种电机)。"""
        return 1 << (i if i < 4 else i + 1)

    # ------------------------------------------------ 漏种/漏肥计数合成
    def _counters(self):
        dt = self._tick_dt
        if dt <= 0:
            return
        t = self.dev.ter
        discs_on = (self.dj_bits & self.disc_mask) != 0
        speed_cm_s = abs(self.speed_now) / 10.0
        if self.work_mode == WORK_MODE_BD and discs_on \
                and self.seed_mode in (SEED_S_WAIT_QZ, SEED_S_WAIT_GZ, SEED_S_GZ) \
                and speed_cm_s > 0:
            for i in range(min(self.dev.rows, 6)):
                if self.bz_curr.Density[i] > 0 and self.zhuju[i] > 0:
                    self._bump(i, speed_cm_s / self.zhuju[i] * dt / 1000.0)
        elif self.work_mode == WORK_MODE_LXBZ and discs_on \
                and self.seed_mode == SEED_S_WAIT_END and speed_cm_s > 0:
            zj = get_zhu_ju(self.lxbz_cell_len, self.lxbz_zhushu)
            if zj > 0:
                rate = speed_cm_s / zj * dt / 1000.0
                for i in range(min(self.dev.rows, 6)):
                    self._bump(i, rate)
        elif self.work_mode == WORK_MODE_TEST:
            # 测试模式: 每路计数只跟随对应播种盘电机(该路盘转动才有种子流过传感器),
            # 仅开供种电机不产生计数
            rate = self.dev.user.Rpm / 60.0 * t.HoleNum * dt / 1000.0
            for i in range(min(self.dev.rows, 6)):
                if self.dj_bits & self._disc_bit(i):
                    self._bump(i, rate)

    def _bump(self, i, rate):
        self._lz_frac[i] += rate
        self._lf_frac[i] += rate
        if self._lz_frac[i] >= 1.0:
            n = int(self._lz_frac[i])
            self.louzh[i] += n
            self._lz_frac[i] -= n
        if self._lf_frac[i] >= 1.0:
            n = int(self._lf_frac[i])
            self.loufei[i] += n
            self._lf_frac[i] -= n
