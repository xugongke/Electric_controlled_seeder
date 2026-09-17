#ifndef DIALOGREALTIMETASK_H
#define DIALOGREALTIMETASK_H

#include <QDialog>
#include "dataStruct/task.h"
#include <QTimer>
#include <QButtonGroup>
#include "../../common/map.h"
#include "model/lastblocktablemodel.h"
#include "model/currentblocktablemodel.h"
#include "tool/communication.h"
#include "dataStruct/blockresult.h"
#include <QMessageBox>

namespace Ui {
class DialogRealtimeTask;
}

class DialogRealtimeTask : public QDialog
{
	Q_OBJECT

public:
    explicit DialogRealtimeTask(Task t,Communication &c,QWidget *parent = nullptr);
	~DialogRealtimeTask();

protected:
    void closeEvent(QCloseEvent *) override;

private:
	Ui::DialogRealtimeTask *ui;
	Task t;
	bool sowState;//正在进行播种任务
	QTimer debugInfoTimer,sowStateTimer;
	QTimer slotTimer;//处理接收通讯类信号的槽中的耗时操作，一次性connect/disconnect
	bool columnEndFlag;//是否超出地图范围
	QButtonGroup qbg1,qbg2;
	std::vector<PathNode> path;
	size_t nextPathIndex;
	size_t tempIndex;//临时存储最新起点索引，每次停止任务时更新nextPathIndex
	int showOutsetRow,showOutsetColumn;//当前显示的起点，仅用于清除时读，-1代表未显示
	Map m;
    int currentReadRowNum;//这次从控制板读到的当前行
    int maxSowColumn;//播种种子行数（通道数），从ini读取
    int lastTractorRow;//上次显示的车辆排
	std::vector<int> lastTractorColumn;
	QString recentDebugInfo;
	std::vector<LastBlockTableModel::Data> lastBlockVector;
	std::vector<CurrentBlockTableModel::Data> currentBlockVector;
	bool direction;
    int currentColumn;
    int tractorRow;//车当前所在排，实时更新
    bool enterMapFlag;
    Communication &c;
    QTimer deviceStateTimer;
    BZStatusType bzState;
    std::vector<BlockResult> currentResult;
    QMessageBox *msgBox;

	void showOutset(size_t row,size_t column);//显示起点，实际排列
	void setBackground(int row,int column,int state);
	void startNode(int row,int column);
	void clearOutset();//清除起点显示
	void createPath(int pathType);
	int getIndex(int row,int column);//返回区域在路中的索引
	void setBlockState(int row,int column,int state);
	void showLastBlock(int row,int column);
	void showCurrentBlock(int row,int column);
	void showPathTypeIcon(bool);
	std::vector<int> columnToShowGroup(int column);//车辆显示的起始列转换为车辆要显示的列集合
    bool columnDirection(int column);//0正向，1反向，2超范围
    void setControlEnable(bool b);
private slots:
    void slotRadioButtonPathType1Toggled(bool);
    void slotRadioButtonPathType2Toggled(bool);
    void slotRadioButtonPathType3Toggled(bool);
    void slotRadioButtonPathType4Toggled(bool);
    void slotRadioButtonPathType5Toggled(bool);
    void slotRadioButtonPathType6Toggled(bool);
	void slotInputABLineName();
	void slotComboBoxViewCurrentTextChanged(const QString &);
signals:
    void signalABLineStateUpdated(QString mapName);
};

#endif // DIALOGREALTIMETASK_H
