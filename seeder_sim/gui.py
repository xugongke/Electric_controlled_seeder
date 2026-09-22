# -*- coding: utf-8 -*-
"""电控播种机下位机模拟器 - 图形界面 (PySide6)

启动: python gui.py            或   python main.py --gui
依赖: pip install PySide6 pyserial

界面分区:
  顶部    串口连接 / 行数 / 速度 / 帧记录开关
  左侧    实时状态面板 (模式/行号/行程/计数/调试信息)
  中部    工况控制按钮 (暂停/北斗丢失/方向相反/零位故障/初始化/触发)
  右侧    三个页签: 收发帧(可导出) / 调试信息(可导出) / 运行日志
"""

import argparse
import datetime
import sys

from PySide6.QtCore import QObject, QTimer, Qt, Signal
from PySide6.QtGui import QColor, QFont
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QFileDialog,
                               QGridLayout, QGroupBox, QHBoxLayout, QHeaderView,
                               QLabel, QMainWindow, QMessageBox, QPlainTextEdit,
                               QPushButton, QSpinBox, QTableWidget, QTableWidgetItem,
                               QTabWidget, QVBoxLayout, QWidget, QAbstractItemView)

import protocol as P
from main import Simulator
from recorder import describe_frame
from workproc import WORK_MODE_NAMES, SEED_MODE_NAMES

MAX_DISPLAY_FRAMES = 2000          # 表格最多显示的行数(导出不受限)


class Bridge(QObject):
    """工作线程 -> GUI 的日志信号桥。"""
    sig_log = Signal(str)


def _mono_font():
    f = QFont('Consolas')
    f.setStyleHint(QFont.Monospace)
    return f


class MainWindow(QMainWindow):
    def __init__(self, args):
        super().__init__()
        self.setWindowTitle('电控播种机下位机模拟器  (hd3005a2_sim)')
        self.resize(1280, 780)

        self.sim = Simulator(rows=args.rows, speed=args.speed,
                             state_file=args.state, version_str=args.version_str,
                             hex_dump=False)
        self.rec = self.sim.recorder
        self.bridge = Bridge()
        self.sim.log_fn = self.bridge.sig_log.emit
        self.bridge.sig_log.connect(lambda s: self.txt_log.appendPlainText(s))

        self._frame_cursor = 0
        self._event_cursor = 0
        self._build_ui()
        self.refresh_ports(args.port)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(200)

    # ================================================================ 界面
    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.addWidget(self._build_conn_group())

        mid = QHBoxLayout()
        mid.addWidget(self._build_ctrl_group(), 1)
        mid.addWidget(self._build_tabs(), 3)
        root.addLayout(mid, 1)

        side = QHBoxLayout()
        side.addWidget(self._build_status_group())
        root.addLayout(side)

        self.statusBar().showMessage('未连接')

    def _build_conn_group(self):
        g = QGroupBox('连接')
        lay = QHBoxLayout(g)
        lay.addWidget(QLabel('串口'))
        self.cmb_port = QComboBox()
        self.cmb_port.setMinimumWidth(140)
        lay.addWidget(self.cmb_port)
        self.btn_refresh = QPushButton('刷新')
        self.btn_refresh.clicked.connect(lambda: self.refresh_ports(None))
        lay.addWidget(self.btn_refresh)
        lay.addWidget(QLabel('115200-8N1'))
        lay.addSpacing(12)
        lay.addWidget(QLabel('行数'))
        self.cmb_rows = QComboBox()
        self.cmb_rows.addItems(['4', '6'])
        self.cmb_rows.currentTextChanged.connect(self.on_rows_changed)
        lay.addWidget(self.cmb_rows)
        lay.addSpacing(12)
        lay.addWidget(QLabel('速度mm/s'))
        self.spn_speed = QSpinBox()
        self.spn_speed.setRange(0, 5000)
        self.spn_speed.setValue(self.sim.wp.speed_mm_s)
        self.spn_speed.valueChanged.connect(
            lambda v: setattr(self.sim.wp, 'speed_mm_s', v))
        lay.addWidget(self.spn_speed)
        lay.addSpacing(12)
        self.chk_record = QCheckBox('记录收发帧')
        self.chk_record.setChecked(True)
        self.chk_record.toggled.connect(self.on_record_toggled)
        lay.addWidget(self.chk_record)
        lay.addStretch(1)
        self.btn_conn = QPushButton('连接')
        self.btn_conn.setMinimumHeight(34)
        self.btn_conn.clicked.connect(self.on_connect)
        lay.addWidget(self.btn_conn)
        return g

    def _build_ctrl_group(self):
        g = QGroupBox('工况控制')
        lay = QVBoxLayout(g)

        def mkbtn(text, slot):
            b = QPushButton(text)
            b.setMinimumHeight(30)
            b.clicked.connect(slot)
            return b

        self.btn_pause = mkbtn('', self.on_pause)
        self.btn_bd = mkbtn('', self.on_bd)
        self.btn_reverse = mkbtn('', self.on_reverse)
        self.btn_zero = mkbtn('', self.on_zerofail)
        grid = QGridLayout()
        grid.addWidget(self.btn_pause, 0, 0)
        grid.addWidget(self.btn_bd, 0, 1)
        grid.addWidget(self.btn_reverse, 0, 2)
        grid.addWidget(self.btn_zero, 1, 0)
        grid.addWidget(mkbtn('一键初始化', self.on_init), 1, 1)
        grid.addWidget(mkbtn('行程开关触发', self.on_trigger), 1, 2)
        lay.addLayout(grid)

        self._sync_ctrl_buttons()
        tip = QLabel('故障注入用于测试上位机的报警/异常显示:\n'
                     '北斗丢失→"无法获取定位信息"; 反向→"下发方向与实际行驶方向不符";\n'
                     '零位故障→测试页零位开关显示红色报警且回零失败(注: 真机固件未实现\n'
                     'WarningState上报, 此报警为模拟器扩展, 方便验证上位机报警界面)。')
        tip.setWordWrap(True)
        tip.setStyleSheet('color: gray;')
        lay.addWidget(tip)
        lay.addStretch(1)
        return g

    def _build_status_group(self):
        g = QGroupBox('实时状态 (0x21 视角)')
        grid = QGridLayout(g)
        grid.setColumnStretch(1, 2)
        grid.setColumnStretch(3, 4)
        self.lbl = {}

        def mk(name, key, row, col):
            lab = QLabel(name + ':')
            lab.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
            val = QLabel('-')
            val.setFont(_mono_font())
            grid.addWidget(lab, row, col)
            grid.addWidget(val, row, col + 1)
            self.lbl[key] = val
            return val

        mk('连接状态', 'conn', 0, 0)
        mk('速度mm/s', 'speed', 0, 2)
        mk('工作模式', 'mode', 1, 0)
        mk('北斗', 'bd', 1, 2)
        mk('RunState', 'run', 2, 0)
        mk('漏种计数', 'louzh', 2, 2)
        mk('当前行号', 'row', 3, 0)
        mk('漏肥计数', 'loufei', 3, 2)
        mk('行程cm', 'off', 4, 0)
        mk('垂直偏差cm', 'vert', 4, 2)
        mk('调试信息', 'debug', 5, 0)
        self.lbl['debug'].setWordWrap(True)
        grid.addWidget(self.lbl['debug'], 5, 1, 1, 3)
        self.lbl['louzh'].setWordWrap(True)
        self.lbl['loufei'].setWordWrap(True)
        return g

    def _build_tabs(self):
        self.tabs = QTabWidget()
        mono = _mono_font()

        # ---- 收发帧
        w1 = QWidget()
        v1 = QVBoxLayout(w1)
        h1 = QHBoxLayout()
        b = QPushButton('导出收发帧…')
        b.clicked.connect(self.export_frames)
        h1.addWidget(b)
        b = QPushButton('复制选中帧HEX')
        b.clicked.connect(self.copy_selected_hex)
        h1.addWidget(b)
        b = QPushButton('清空显示')
        b.clicked.connect(self.clear_frames)
        h1.addWidget(b)
        self.chk_scroll = QCheckBox('自动滚动')
        self.chk_scroll.setChecked(True)
        h1.addWidget(self.chk_scroll)
        self.cmb_dir_filter = QComboBox()
        self.cmb_dir_filter.addItems(['全部', '只看收', '只看发'])
        self.cmb_dir_filter.currentTextChanged.connect(self.refilter_frames)
        h1.addWidget(self.cmb_dir_filter)
        h1.addStretch(1)
        self.lbl_frame_cnt = QLabel('0')
        h1.addWidget(self.lbl_frame_cnt)
        v1.addLayout(h1)
        self.tbl_frames = QTableWidget(0, 5)
        self.tbl_frames.setHorizontalHeaderLabels(['时间', '方向', '功能码', '长度', '摘要'])
        self.tbl_frames.setFont(mono)
        self.tbl_frames.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.tbl_frames.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.tbl_frames.horizontalHeader().setSectionResizeMode(
            0, QHeaderView.ResizeToContents)
        self.tbl_frames.horizontalHeader().setSectionResizeMode(
            1, QHeaderView.ResizeToContents)
        self.tbl_frames.horizontalHeader().setSectionResizeMode(
            2, QHeaderView.ResizeToContents)
        self.tbl_frames.horizontalHeader().setSectionResizeMode(
            3, QHeaderView.ResizeToContents)
        self.tbl_frames.horizontalHeader().setSectionResizeMode(4, QHeaderView.Stretch)
        self.tbl_frames.verticalHeader().setSectionResizeMode(QHeaderView.Fixed)
        self.tbl_frames.verticalHeader().setDefaultSectionSize(20)
        self.tbl_frames.setWordWrap(False)
        v1.addWidget(self.tbl_frames)
        self.tabs.addTab(w1, '收发帧')

        # ---- 调试信息
        w2 = QWidget()
        v2 = QVBoxLayout(w2)
        h2 = QHBoxLayout()
        b = QPushButton('导出调试信息…')
        b.clicked.connect(self.export_events)
        h2.addWidget(b)
        b = QPushButton('清空显示')
        b.clicked.connect(self.clear_events)
        h2.addWidget(b)
        h2.addStretch(1)
        self.lbl_event_cnt = QLabel('0')
        h2.addWidget(self.lbl_event_cnt)
        v2.addLayout(h2)
        self.txt_events = QPlainTextEdit()
        self.txt_events.setReadOnly(True)
        self.txt_events.setFont(mono)
        self.txt_events.setMaximumBlockCount(5000)     # 封顶防止长会话UI变慢
        v2.addWidget(self.txt_events)
        self.tabs.addTab(w2, '调试信息')

        # ---- 运行日志
        w3 = QWidget()
        v3 = QVBoxLayout(w3)
        self.txt_log = QPlainTextEdit()
        self.txt_log.setReadOnly(True)
        self.txt_log.setFont(mono)
        self.txt_log.setMaximumBlockCount(5000)        # 封顶(hex打印时增长极快)
        v3.addWidget(self.txt_log)
        self.tabs.addTab(w3, '运行日志')
        return self.tabs

    # ================================================================ 串口
    def refresh_ports(self, prefer=None):
        from serial.tools import list_ports
        ports = [p.device for p in list_ports.comports()]
        self.cmb_port.clear()
        self.cmb_port.addItems(ports)
        if prefer and prefer in ports:
            self.cmb_port.setCurrentText(prefer)
        elif ports:
            self.cmb_port.setCurrentIndex(0)

    def on_connect(self):
        if self.sim.running:
            self.sim.stop()
            self.btn_conn.setText('连接')
            self.rec.note('关闭串口')
            self.statusBar().showMessage('已断开')
            return
        port = self.cmb_port.currentText()
        if not port:
            QMessageBox.warning(self, '提示', '未选择串口')
            return
        self.sim.port = port
        try:
            self.sim.start()
        except Exception as exc:
            QMessageBox.critical(self, '连接失败', '打开 %s 失败:\n%s' % (port, exc))
            return
        self.btn_conn.setText('断开')
        self.statusBar().showMessage('已连接 %s @115200-8N1' % port)

    # ================================================================ 控制
    def on_rows_changed(self, text):
        rows = int(text)
        self.sim.dev.rows = rows
        self.sim.dev.ter.U8Resv2 = rows
        self.rec.meta['行数'] = rows
        self.rec.note('手动切换为%d行机' % rows)

    def on_record_toggled(self, on):
        self.rec.recording = on
        self.rec.note('收发帧记录 %s' % ('开启' if on else '暂停'))

    def on_pause(self):
        wp = self.sim.wp
        wp.paused = not wp.paused
        self.rec.note('行进 %s' % ('暂停' if wp.paused else '恢复'))
        self._sync_ctrl_buttons()

    def on_bd(self):
        wp = self.sim.wp
        wp.bd_ok = not wp.bd_ok
        self.rec.note('北斗信号 %s' % ('恢复' if wp.bd_ok else '丢失'))
        self._sync_ctrl_buttons()

    def on_reverse(self):
        wp = self.sim.wp
        wp.reverse = not wp.reverse
        self.rec.note('实际行驶方向反向 %s' % ('开启' if wp.reverse else '关闭'))
        self._sync_ctrl_buttons()

    def on_zerofail(self):
        wp = self.sim.wp
        wp.zerofail = not wp.zerofail
        self.rec.note('零位开关故障注入 %s' % ('开启' if wp.zerofail else '关闭'))
        self._sync_ctrl_buttons()

    def on_init(self):
        with self.sim.lock:
            self.sim.wp.press_init()
        self.rec.note('模拟按下一键初始化按钮, 垂直偏差复位为-%dcm (-行数x行距)'
                      % (self.sim.dev.rows * self.sim.dev.user.HJ))

    def on_trigger(self):
        with self.sim.lock:
            self.sim.wp.bd_trig_cnt += 1
        self.rec.note('模拟北斗行程开关触发')

    def _sync_ctrl_buttons(self):
        wp = self.sim.wp
        self.btn_pause.setText('继续行进' if wp.paused else '暂停行进')
        self.btn_bd.setText('北斗: 丢失' if wp.bd_ok else '北斗: 恢复')
        self.btn_reverse.setText('行驶反向: 开' if not wp.reverse else '行驶反向: 关')
        self.btn_zero.setText('零位故障: 开' if not wp.zerofail else '零位故障: 关')
        if wp.bd_ok:
            self.btn_bd.setStyleSheet('')
        else:
            self.btn_bd.setStyleSheet('color: red; font-weight: bold;')
        if wp.reverse:
            self.btn_reverse.setStyleSheet('color: red; font-weight: bold;')
        else:
            self.btn_reverse.setStyleSheet('')
        if wp.zerofail:
            self.btn_zero.setStyleSheet('color: red; font-weight: bold;')
        else:
            self.btn_zero.setStyleSheet('')

    # ================================================================ 导出
    def _save_dialog(self, prefix):
        name = '%s_%s.txt' % (prefix, datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
        path, _ = QFileDialog.getSaveFileName(self, '导出', name, '文本文件 (*.txt)')
        return path

    def export_frames(self):
        path = self._save_dialog('seeder_frames')
        if not path:
            return
        n = self.rec.export_frames(path)
        self.sim.log('[模拟器] 收发帧记录已导出: %s (%d帧)' % (path, n))
        QMessageBox.information(self, '导出完成', '已导出 %d 帧到\n%s' % (n, path))

    def export_events(self):
        path = self._save_dialog('seeder_debug')
        if not path:
            return
        n = self.rec.export_events(path)
        self.sim.log('[模拟器] 调试信息已导出: %s (%d条)' % (path, n))
        QMessageBox.information(self, '导出完成', '已导出 %d 条到\n%s' % (n, path))

    # ================================================================ 刷新(200ms)
    def refresh(self):
        sim = self.sim
        with sim.lock:
            wp, dev = sim.wp, sim.dev
            st = wp.get_bz_status()
            mode = WORK_MODE_NAMES[wp.work_mode]
            seed = SEED_MODE_NAMES.get(wp.seed_mode, str(wp.seed_mode))
            rows = dev.rows
            debug = wp.debug
            conn = sim.running
        # 行数跟随 0x25 自动变化
        if str(rows) != self.cmb_rows.currentText():
            self.cmb_rows.blockSignals(True)
            self.cmb_rows.setCurrentText(str(rows))
            self.cmb_rows.blockSignals(False)
        self._sync_ctrl_buttons()

        lbl = self.lbl
        lbl['conn'].setText('已连接 %s' % self.sim.port if conn else '未连接')
        lbl['mode'].setText('%s / %s' % (mode, seed))
        run = st['run_state']
        run_txt = {0: '0 停止', 1: '1 准备', 0x81: '0x81 播种行进'}.get(run, hex(run))
        lbl['run'].setText(run_txt)
        color = {0: '#c0392b', 1: '#b7950b', 0x81: '#1e8449'}.get(run, 'black')
        lbl['run'].setStyleSheet('color: %s; font-weight: bold;' % color)
        lbl['row'].setText(str(st['row_num']))
        lbl['off'].setText(str(st['off_len']))
        lbl['vert'].setText(str(st['vertical_off']))
        lbl['speed'].setText(str(st['speed']))
        lbl['bd'].setText('正常' if st['bd_state'] else '丢失')
        lbl['louzh'].setText(' '.join(str(x) for x in st['louzh']))
        lbl['loufei'].setText(' '.join(str(x) for x in st['loufei']))
        lbl['debug'].setText(debug)

        if conn:
            self.statusBar().showMessage(
                '已连接 %s  |  收%d帧 发%d帧  |  记录%s'
                % (self.sim.port, self.rec.rx_cnt, self.rec.tx_cnt,
                   '开' if self.rec.recording else '停'))

        self._append_new_frames()
        self._append_new_events()

    def _append_new_frames(self):
        rec = self.rec
        frames, total = rec.snapshot_frames(self._frame_cursor)
        self._frame_cursor = total
        self.lbl_frame_cnt.setText('%d' % total)
        if not frames:
            return
        filt = self.cmb_dir_filter.currentText()
        tbl = self.tbl_frames
        for t, d, fnc, payload in frames:
            if filt == '只看收' and d != 'RX':
                continue
            if filt == '只看发' and d != 'TX':
                continue
            items = [QTableWidgetItem(datetime.datetime.fromtimestamp(t).strftime(
                '%H:%M:%S.%f')[:-3]),
                QTableWidgetItem('收' if d == 'RX' else '发'),
                QTableWidgetItem('%s(0x%02X)' % (P.FNC_NAMES.get(fnc, '?'), fnc)),
                QTableWidgetItem(str(len(payload))),
                QTableWidgetItem(describe_frame(d, fnc, payload))]
            items[1].setForeground(QColor('#1565c0') if d == 'RX' else QColor('#2e7d32'))
            items[1].setTextAlignment(Qt.AlignCenter)
            items[3].setTextAlignment(Qt.AlignCenter)
            items[0].setToolTip(P.build_frame(fnc, payload).hex(' ').upper())
            tbl.insertRow(tbl.rowCount())
            for col, it in enumerate(items):
                tbl.setItem(tbl.rowCount() - 1, col, it)
        overflow = tbl.rowCount() - MAX_DISPLAY_FRAMES
        if overflow > 0:
            for _ in range(overflow):
                tbl.removeRow(0)
        if self.chk_scroll.isChecked():
            tbl.scrollToBottom()

    def _append_new_events(self):
        rec = self.rec
        events, total = rec.snapshot_events(self._event_cursor)
        self._event_cursor = total
        self.lbl_event_cnt.setText('%d' % total)
        if not events:
            return
        chunk = []
        for t, kind, text in events:
            ts = datetime.datetime.fromtimestamp(t).strftime('%H:%M:%S.%f')[:-3]
            chunk.append('[%s] %-3s %s' % (ts, kind, text))
        self.txt_events.appendPlainText('\n'.join(chunk))
        sb = self.txt_events.verticalScrollBar()
        sb.setValue(sb.maximum())

    # ================================================================ 显示区操作
    def refilter_frames(self, _):
        self.tbl_frames.setRowCount(0)
        self._frame_cursor = 0
        self._append_new_frames()

    def clear_frames(self):
        self.tbl_frames.setRowCount(0)

    def clear_events(self):
        self.txt_events.clear()

    def copy_selected_hex(self):
        rows = sorted({i.row() for i in self.tbl_frames.selectedIndexes()})
        if not rows:
            QMessageBox.information(self, '提示', '请先在表格中选中帧')
            return
        lines = []
        for r in rows:
            tip = self.tbl_frames.item(r, 0).toolTip()
            fnc = self.tbl_frames.item(r, 2).text()
            lines.append('%s  %s' % (fnc, tip))
        QApplication.clipboard().setText('\n'.join(lines))
        self.statusBar().showMessage('已复制 %d 帧HEX到剪贴板' % len(lines), 3000)

    def closeEvent(self, event):
        self.sim.stop()
        super().closeEvent(event)


def run_gui(args=None):
    app = QApplication(sys.argv)
    font = QFont('Microsoft YaHei UI', 9)      # Windows 下确保中文正常显示
    font.setStyleHint(QFont.SansSerif)
    app.setFont(font)
    win = MainWindow(args)
    win.show()
    sys.exit(app.exec())


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description='电控播种机下位机模拟器 GUI')
    ap.add_argument('--port', help='预选串口')
    ap.add_argument('--rows', type=int, default=6, choices=(4, 6))
    ap.add_argument('--speed', type=int, default=1000)
    ap.add_argument('--state')
    ap.add_argument('--version-str')
    run_gui(ap.parse_args())
