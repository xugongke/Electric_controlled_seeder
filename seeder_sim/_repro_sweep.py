# -*- coding: utf-8 -*-
"""轮询相位扫掠: 验证密度4000时记录值波动规律。

0x21轮询周期200ms(STATUSINTERVAL), 速度1000mm/s -> 每拍20cm。
小区记录值 = 换排前最后一拍读数 = floor((窗口-δ)/株距), δ为最后一拍距
换排阈值的行程(0<δ<=20cm, 取决于轮询相位)。扫掠20个相位统计分布。
"""
import sys
from collections import Counter

sys.path.insert(0, '.')
from device import Device
from workproc import WorkProc
from layout import BzCellPara

RL, AI, DENS = 500, 100, 4000
near = lambda r: r * (RL + AI)


def pkt(row, d, nr, nd):
    z = BzCellPara()
    z.TXFlag = 1 if d else 0
    z.RowNum, z.NextRowNum = row, nr
    z.CellLen = z.NextCellLen = RL
    z.InS = z.NextInS = AI
    z.Density = z.NextDensity = [DENS] * 6
    z.isAfterNextZoneSow = 1
    z.StartPOS = near(row) + (0 if d else RL)
    z.NextStartPOS = near(nr) + (0 if nd else RL)
    return z


TRIP1 = [(4, False), (3, False), (2, False), (1, False), (0, False)]
TRIP2 = [(0, True), (1, True), (2, True), (3, True), (4, True)]
NEXT1 = {4: (3, False), 3: (2, False), 2: (1, False), 1: (0, False), 0: (0, True)}
NEXT2 = {0: (1, True), 1: (2, True), 2: (3, True), 3: (4, True), 4: (4, False)}


def run_trip(order, nxt, wp, t, off):
    res, seen, last = {}, None, None
    saw_invalid = False                   # 先观察到600ms无效行号窗口, 再识别到达
                                          # (避免启动前陈旧行号被误当到达, 真实上位机
                                          #  走 RowNum<=-10000000 分支不会误判)
    (r0, d0) = order[0]
    nr0, nd0 = nxt[r0]
    wp.set_bz_para(pkt(r0, d0, nr0, nd0))
    wp.cmd_start_bz()
    n = 0
    while n < 6000:
        t[0] += 10
        wp.step(t[0])
        n += 1
        if wp.debug.startswith('播种结束'):
            break
        if (n + off) % 20:                  # 200ms轮询, 相位off
            continue
        st = wp.get_bz_status()
        rn = st['row_num']
        if rn <= -10000000:
            saw_invalid = True
            continue
        if not saw_invalid:
            continue
        if rn != last:
            if last is not None:
                res[last] = seen[0]
            last = rn
            if rn in nxt:
                nr, nd = nxt[rn]
                d = dict(order)[rn]
                wp.set_bz_para(pkt(rn, d, nr, nd))
        seen = st['louzh']
    if last is not None:
        res[last] = wp.get_bz_status()['louzh'][0]   # 冻结值(播种结束后轮询持续读)
    wp.cmd_stop_bz()
    for _ in range(50):
        t[0] += 10
        wp.step(t[0])
    return res


def main():
    tally = {}                          # (标签) -> Counter
    for off in range(20):               # 20个轮询相位
        dev = Device(state_file='seeder_sim_state.json', rows=6)
        dev.bd.StartState = 1
        wp = WorkProc(dev)
        t = [1000]
        t1 = run_trip(TRIP1, NEXT1, wp, t, off)
        t2 = run_trip(TRIP2, NEXT2, wp, t, off)
        seq = [t1[r] for r in (4, 3, 2, 1, 0)] + [t2[r] for r in (0, 1, 2, 3, 4)]
        names = ['(1,1)首', '(2,1)', '(3,1)', '(4,1)', '(5,1)末趟',
                 '(5,2)首', '(4,2)', '(3,2)', '(2,2)', '(1,2)末任务']
        for name, v in zip(names, seq):
            tally.setdefault(name, Counter())[v] += 1
    print('密度4000 株距29cm | 20个轮询相位下各小区记录值分布:')
    for name, c in tally.items():
        total = sum(c.values())
        dist = '  '.join('%d粒:%2d次' % (v, n) for v, n in sorted(c.items()))
        print('  %-10s %s' % (name, dist))


if __name__ == '__main__':
    main()
