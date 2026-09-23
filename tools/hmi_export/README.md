# hmi_export —— QT地图 → 组态屏CSV 导出工具

把 QT 上位机的地图转成大彩组态屏能识别的 `map_*.csv`，复制到U盘即可在屏端
"任务向导 → 扫描U盘导入地图"。

## 输入（二选一）

- **QT数据库** `data.db`（在 QT 上位机程序运行目录下）：完整读取
  Map/MapBlock/RowAttributes/MapAisle/ABLine，包括绑定的AB线（A点排/方向）。
- **QT导出的xlsx** `地图<名>.xlsx`（QT地图页"导出"生成）：解析
  信息/AB线/编号/密度/是否播种 五个工作表（布局对齐 Map::exportToXlsx，数据始于B2）。

## 用法

```
python tools/hmi_export/hmi_export.py                # 图形界面(推荐)
python tools/hmi_export/hmi_export.py --db data.db --out E:\usb
python tools/hmi_export/hmi_export.py --xlsx 地图自定义田.xlsx --out E:\usb
python tools/hmi_export/hmi_export.py --selftest     # 自测(屏端csv.lua回读验证)
```

依赖：Python3.10+；xlsx 输入需 `openpyxl`；GUI 需 `PySide6`（缺省自动退CLI）。

## 输出约定

- 文件名 `map_<slug>.csv` **纯ASCII**（屏端文件系统限制），slug 算法与屏端
  store.lua 一致（ASCII保留段+FNV1a哈希）；**中文显示名写在文件内 `#MAP,名` 行**，
  导入屏端后以它为显示名。
- 编码 **GB2312 + CRLF**；格式与屏端 `csv.lua render_map` 逐字段一致，
  自测第2步用屏端真实解析器回读验证。
- QT小区"编号"若为非数字文本（屏端CSV要求数字），自动用顺位号替代并在
  结果中给出警告。
- 绑定了AB线的地图带 `#AB` 行（含A点排0基/方向），屏端导入后可直接用。

## 已知限制

- QT里未设置密度/播种标记的小区，默认按密度0不播种导出。
- 任务不导出（屏端任务在屏上创建；结果从屏端U盘导出）。
