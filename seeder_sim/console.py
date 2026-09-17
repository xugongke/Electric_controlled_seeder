# -*- coding: utf-8 -*-
"""模拟器交互控制台 —— 运行中注入工况, 便于测试上位机各界面。"""

from workproc import WORK_MODE_NAMES, SEED_MODE_NAMES


HELP = """可用命令:
  help              帮助
  stat              当前状态(模式/行号/行程/计数/调试信息)
  para              查看厂家/用户参数
  ab                查看 AB 线参数
  speed <mm/s>      设置模拟行进速度 (默认1000, 即1m/s)
  rows <4|6>        强制切换行数(上位机 0x25 也会自动切换)
  pause             暂停行进(速度上报0, 行程冻结)
  resume            恢复行进
  bd off|on         模拟北斗信号丢失/恢复 (BdState=0, 触发"无法获取定位信息")
  reverse on|off    实际行驶方向与下发方向相反 (触发"下发方向与实际行驶方向不符")
  zerofail on|off   注入零位开关故障 (触发"零位开关触发错误")
  init              模拟按下一键初始化按钮(测试模式下回零流程)
  trigger           模拟北斗行程开关触发一次 (BdCnt+1, 无A点时记录A点)
  hex on|off        串口原始帧十六进制打印开关
  quit              退出
"""


class Console:
    def __init__(self, sim):
        self.sim = sim

    @property
    def wp(self):
        return self.sim.wp

    @property
    def dev(self):
        return self.sim.dev

    def handle(self, line):
        """处理一行命令, 返回 False 表示退出。"""
        args = line.split()
        if not args:
            return True
        cmd, rest = args[0].lower(), args[1:]
        sim, wp, dev = self.sim, self.wp, self.dev
        if cmd in ('quit', 'exit'):
            return False
        elif cmd == 'help':
            print(HELP)
        elif cmd == 'stat':
            self._stat()
        elif cmd == 'para':
            print('厂家参数: ' + ', '.join('%s=%s' % kv for kv in vars(dev.ter).items()))
            print('用户参数: ' + ', '.join('%s=%s' % kv for kv in vars(dev.user).items()))
            print('连续播种参数: ' + ', '.join('%s=%s' % kv for kv in vars(dev.lxbz).items()))
            print('清种打点=%s 过道打点=%s' % (dev.qzdd_enable, dev.gddd_enable))
        elif cmd == 'ab':
            print('AB线参数: ' + ', '.join('%s=%s' % kv for kv in vars(dev.bd).items()))
        elif cmd == 'speed':
            if rest:
                try:
                    wp.speed_mm_s = int(rest[0])
                    print('行进速度 = %d mm/s' % wp.speed_mm_s)
                except ValueError:
                    print('用法: speed <mm/s>')
            else:
                print('当前速度 %d mm/s' % wp.speed_mm_s)
        elif cmd == 'rows':
            if rest and rest[0] in ('4', '6'):
                dev.rows = int(rest[0])
                dev.ter.U8Resv2 = dev.rows
                print('行数 = %d' % dev.rows)
            else:
                print('用法: rows <4|6>, 当前 %d' % dev.rows)
        elif cmd == 'pause':
            wp.paused = True
            print('行进已暂停')
        elif cmd == 'resume':
            wp.paused = False
            print('行进已恢复')
        elif cmd == 'bd':
            wp.bd_ok = (rest and rest[0].lower() == 'on')
            print('北斗信号 = %s' % ('正常' if wp.bd_ok else '丢失'))
        elif cmd == 'reverse':
            wp.reverse = bool(rest and rest[0].lower() == 'on')
            print('实际行驶方向反向 = %s' % wp.reverse)
        elif cmd == 'zerofail':
            wp.zerofail = bool(rest and rest[0].lower() == 'on')
            print('零位开关故障注入 = %s' % wp.zerofail)
        elif cmd == 'init':
            wp.press_init()
            print('已模拟按下一键初始化按钮, 垂直偏差复位为-%dcm'
                  % (self.dev.rows * self.dev.user.HJ))
        elif cmd == 'trigger':
            wp.bd_trig_cnt += 1
            print('北斗行程开关触发, BdCnt=%d' % wp.bd_trig_cnt)
        elif cmd == 'hex':
            sim.hex_dump = bool(rest and rest[0].lower() == 'on')
            print('原始帧打印 = %s' % sim.hex_dump)
        else:
            print('未知命令 %s, 输入 help 查看帮助' % cmd)
        return True

    def _stat(self):
        wp = self.wp
        print('工作模式: %s  RunState=%d MoveOn=0x%02X  阶段: %s'
              % (WORK_MODE_NAMES[wp.work_mode], wp.run_state, wp.move_on,
                 SEED_MODE_NAMES.get(wp.seed_mode, wp.seed_mode)))
        print('调试信息(0x22): %s' % wp.debug)
        print('行数=%d  速度=%dmm/s  行程=%dcm  垂直偏差=%dcm  行号=%d'
              % (self.dev.rows, wp.speed_now, wp._off_len(),
                 wp.vertical_off, wp.bz_curr.RowNum))
        print('漏种=%s' % wp.louzh)
        print('漏肥=%s' % wp.loufei)
        print('小区参数(RX): 行号=%d 下一行号=%d CellLen=%d InS=%d StartPOS=%d 密度=%s'
              % (wp.bz_cell.RowNum, wp.bz_cell.NextRowNum, wp.bz_cell.CellLen,
                 wp.bz_cell.InS, wp.bz_cell.StartPOS, wp.bz_cell.Density))
