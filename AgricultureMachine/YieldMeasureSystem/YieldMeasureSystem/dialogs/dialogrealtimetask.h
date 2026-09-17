#ifndef DIALOGREALTIMETASK_H
#define DIALOGREALTIMETASK_H

#include <QDialog>
#include "dataStructs/task.h"
#include "dataStructs/yieldmap.h"
#include <QButtonGroup>
//#include <QTimer>
#include "threads/yieldmeasurementthread.h"
#include "dataStructs/blockresult.h"

namespace Ui {
class DialogRealtimeTask;
}

class DialogRealtimeTask : public QDialog
{
    Q_OBJECT

public:
    explicit DialogRealtimeTask(Task ta,QWidget *parent = nullptr);
    ~DialogRealtimeTask();

protected:
    void closeEvent(QCloseEvent *) override;

signals:
    void signalYieldMeasure(float value0,float value1,float value2,float value3);

private:
    void showPathTypeIcon(bool b);
    void createPath(int pathType);
    void clearOutset();
	void showOutset(size_t row,size_t column);
    void setBackground(int row,int column,int state);
    int getIndex(int row,int column);
    bool startMeasure();
    void pathTypeToggled();
    void updateTaskPath();

    Ui::DialogRealtimeTask *ui;
    Task t;
    YieldMap m;
    QButtonGroup qbg1,qbg2;
	std::vector<PathNode> path;
	size_t nextPathIndex;
    int currentColumnNodeIndex;
    bool direction;
    int yieldState;//0停止 1循环测产 2测产
    YieldMeasurementThread ymt;
	QTimer qt;
    float moisture,totalMass,unitWeight;
    BlockResult currentResult;
    int yieldColumnCount;
    QPoint lastBlock;

public slots:
	void slotValveStateUpdated();
private slots:
    void slotRadioButtonPathType1Toggled(bool);
    void slotRadioButtonPathType2Toggled(bool);
    void slotRadioButtonPathType3Toggled(bool);
    void slotRadioButtonPathType4Toggled(bool);
    void slotRadioButtonPathType5Toggled(bool);
    void slotRadioButtonPathType6Toggled(bool);
    void slotPushButtonStartClicked();
    void slotPhysicalButtonPushed(int,int,void *);
	void slotComboBoxViewCurrentTextChanged(const QString &);
    void slotPushButtonCycleMeasureClicked();
};

#endif // DIALOGREALTIMETASK_H
