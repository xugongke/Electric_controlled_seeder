# -*- coding: utf-8 -*-
"""复现用户场景: 5排2列, 6行机, 行长500cm 过道100cm 密度4000 行距60,
路径 (1,1)->(5,1) 掉头 (5,2)->(1,2), 统计每小区6路漏种计数。

排显示号 = 5 - 内部row (地图表头倒序); 排1=内部4, 排5=内部0。
趟1(排1->排5): 内部4->0, 反向 TXFlag=0 (A点方向正, 从排1远端下行)。
趟2(排5->排1): 内部0->4, 同向 TXFlag=1。
换列过渡 (5,1)->(5,2) 与末块回绕 (1,2)->(1,1) 均为"同排号不同列", 忠实模拟。
"""
import sys
import time

sys.path.insert(0, '.')
from device import Device
from workproc import WorkProc
from layout import BzCellPara

RL, AI, DENS = 500, 100, 4500
near = lambda r: r * (RL + AI)


def pkt(row, d, nr, nd):
    """按上位机 setSowParameters 构造 0x20 包 (aRow=0, AB方向正)。"""
    z = BzCellPara()
    z.TXFlag = 1 if d else 0
    z.RowNum, z.NextRowNum = row, nr
    z.CellLen = z.NextCellLen = RL
    z.InS = z.NextInS = AI
    z.Density = z.NextDensity = [DENS] * 6
    z.isAfterNextZoneSow = 1
    z.StartPOS = near(row) + (0 if d else RL)
    z.NextStartPOS = near(nr) + (0 if nd else RL)
    z.DisplayRowNum = 5 - row          # 显示排号
    z.NextDisplayRowNum = 5 - nr
    return z


# (内部row, 方向d, 下一站(内部row, 方向)); None=趟结束(播种结束后人工重启)
TRIP1 = [(4, False), (3, False), (2, False), (1, False), (0, False)]
TRIP2 = [(0, True), (1, True), (2, True), (3, True), (4, True)]
NEXT1 = {4: (3, False), 3: (2, False), 2: (1, False), 1: (0, False),
         0: (0, True)}                 # (5,1)->(5,2): 同排换列, 方向翻转
NEXT2 = {0: (1, True), 1: (2, True), 2: (3, True), 3: (4, True),
         4: (4, False)}                # (1,2) 末块回绕 -> path[0]=(1,1)


def run_trip(tag, order, nxt, wp, t):
    res = {}                            # 内部row -> 6路计数(到达下排前最后读数)
    frozen = {}                         # 播种结束后冻结值
    true_fin = {}                       # 逐tick采样的真实终值(无轮询截断)
    seen, last, true_last = None, None, [0] * 6
    POLL = 20                           # 上位机200ms轮询间隔(tick数)
    (r0, d0), (nr0, nd0) = order[0], nxt[order[0][0]]
    wp.set_bz_para(pkt(r0, d0, nr0, nd0))
    wp.cmd_start_bz()
    print('\n[%s] 启动: 排%d(内部%d) 方向%s' % (tag, 5 - r0, r0, '同向' if d0 else '反向'))
    ended, n = False, 0
    while n < 6000 and not ended:
        t[0] += 10
        wp.step(t[0])
        n += 1
        if wp.debug.startswith('播种结束'):
            ended = True
        true_last = list(wp.get_bz_status()['louzh'])   # 逐tick真实值
        if n % POLL:                    # 上位机 200ms 轮询
            continue
        st = wp.get_bz_status()
        rn = st['row_num']
        if rn <= -10000000:
            continue
        if rn != last:
            if last is not None:
                res[last] = list(seen)
                true_fin[last] = list(true_last)
                print('  到达 排%d(内部%d) | 上一排轮询值%s 真实值%s | %s'
                      % (5 - rn, rn, seen, true_last, wp.debug))
            last = rn
            if rn in nxt:
                wp.set_bz_para(_pkt_for(rn, order, nxt, wp))
        seen = list(st['louzh'])
    if last is not None:
        res[last] = list(seen)
        true_fin[last] = list(true_last)
    frozen[last] = list(wp.get_bz_status()['louzh'])
    wp.cmd_stop_bz()
    for _ in range(50):
        t[0] += 10
        wp.step(t[0])
    print('  [%s] %s | 冻结计数 %s' % (tag, wp.debug, frozen[last]))
    return res


def _pkt_for(rn, order, nxt, wp):
    """到达 rn 后, 上位机重发 packet(rn, Next=nxt[rn]) 的定向参数取本趟方向。"""
    d = dict(order)[rn]
    nr, nd = nxt[rn]
    z = pkt(rn, d, nr, nd)
    z.TXFlag = 1 if d else 0
    return z


def main():
    dev = Device(state_file='seeder_sim_state.json', rows=6)
    dev.bd.StartState = 1
    wp = WorkProc(dev)
    t = [1000]
    t1 = run_trip('趟1 列1', TRIP1, NEXT1, wp, t)
    time.sleep(0)
    t2 = run_trip('趟2 列2', TRIP2, NEXT2, wp, t)

    print('\n=========== 汇总 (排显示号: 路径顺序) ===========')
    label = lambda trip, r: '排%d,%d' % (5 - r, 1 if trip is t1 else 2)
    for trip, tag in ((t1, 1), (t2, 2)):
        for r, cnts in sorted(trip.items(), key=lambda kv: -kv[0] if tag == 1 else kv[0]):
            uniq = sorted(set(cnts))
            print('%s: %s粒/路 (6路: %s)' % (label(trip, r), uniq[-1], cnts))


if __name__ == '__main__':
    main()
