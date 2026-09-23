# -*- coding: utf-8 -*-
"""模拟器AB线语义回归 (2026-09-23 修复项, 无串口进程内)。

1) 无AB线(0x24全零StartState=0): 启动后停在"等待行程开关触发",
   触发计数+1后才设A点继续 —— 对齐QT setEmptyABLine语义(用户要求)。
2) 停止后0x23取B点: B点=停止瞬间冻结位置(真机GNSS停车仍有效),
   不再因OffLen清零而得到0经纬度(用户报告的停止保存B=0)。

运行: python hmi_port/tests/test_sim_ab_semantics.py
"""
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'seeder_sim'))

import protocol as PP                     # noqa: E402
from layout import BdPara, BzCellPara     # noqa: E402
from main import Simulator                # noqa: E402

PASS = FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    print('  [%s] %s' % ('通过' if cond else '失败', msg))
    if cond:
        PASS += 1
    else:
        FAIL += 1


def new_sim(tmpdir):
    state = os.path.join(tmpdir, 's%d.json' % PASS)
    shutil.copy(os.path.join(ROOT, 'seeder_sim', 'seeder_sim_state.json'), state)
    sim = Simulator(port=None, rows=6, state_file=state)
    return sim


def cell_para(row=3, nr=2, sp=0, nsp=600):
    z = BzCellPara(TXFlag=1, RowNum=row, NextRowNum=nr, InS=100,
                   CellLen=500, StartPOS=sp, DisplayRowNum=1,
                   NextInS=100, NextCellLen=500, NextStartPOS=nsp,
                   NextDisplayRowNum=2)
    z.Density = [4000] * 6
    z.NextDensity = [4000] * 6
    z.isAfterNextZoneSow = 1
    return z


def step(sim, t, ms):
    for _ in range(ms // 10):
        t[0] += 10
        sim.wp.step(t[0])


def main():
    tmp = tempfile.mkdtemp()

    print('1) 无AB线: 等待行程开关触发')
    sim = new_sim(tmp)
    t = [1000]
    sim.process_frame(0x24, BdPara(StartState=0).pack())     # 空AB(QT setEmptyABLine)
    check(sim.dev.bd.StartState == 0, '0x24 StartState=0 后bd清零等待触发')
    sim.process_frame(0x20, cell_para().pack())
    sim.process_frame(0x0A, b'')
    # 零位寻位(半圈+整圈≈22s@Rpm36) + 预充种后到达 SEED_S_START 触发等待
    step(sim, t, 30000)
    dbg = sim.wp.debug
    check(dbg == '等待行程开关触发', '启动后停在等待触发: %s' % dbg)
    sim.wp.bd_trig_cnt += 1                                   # 地头按下行程开关
    step(sim, t, 200)
    check(sim.dev.bd.StartState == 1 and sim.wp.debug != '等待行程开关触发',
          '触发后A点生效继续流程: %s (A点N=%.2f)' % (sim.wp.debug, sim.dev.bd.StartN))

    print('2) 停止后0x23的B点(冻结位置)')
    sim2 = new_sim(tmp)
    t2 = [1000]
    sim2.process_frame(0x24, BdPara(StartN=36.4, StartE=117.0,
                                    StartState=1).pack())     # 已有A点
    sim2.process_frame(0x20, cell_para().pack())
    sim2.process_frame(0x0A, b'')
    step(sim2, t2, 8000)                                      # 走一段(过预充种/起步)
    pos = sim2.wp._off_len()
    check(pos != 0, '运行中行程非零: %dcm' % pos)
    sim2.process_frame(0x0B, b'')                             # 停止
    step(sim2, t2, 300)
    check(sim2.wp._off_len() == 0 and abs(sim2.wp.frozen_off - pos) <= 1,
          '停止后OffLen清零但冻结位置保留: off=%d frozen=%d(采样%d, 截断±1)'
          % (sim2.wp._off_len(), sim2.wp.frozen_off, pos))
    resp = sim2.process_frame(0x23, b'')                      # 停止后采集AB
    bd = BdPara.unpack(resp)
    check(bd.EndBN > bd.StartN and bd.EndBE == bd.StartE,
          '0x23的B点非零(沿北向偏移): B=(%.7f,%.7f) A=(%.7f,%.7f)'
          % (bd.EndBN, bd.EndBE, bd.StartN, bd.StartE))

    print()
    if FAIL:
        print('AB语义回归: %d项失败' % FAIL)
    else:
        print('AB语义回归: 全部通过 (%d项)' % PASS)
    shutil.rmtree(tmp, ignore_errors=True)
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
