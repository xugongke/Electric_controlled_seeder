#ifndef FORMTASK_H
#define FORMTASK_H

#include <QWidget>
#include "dataStructs/task.h"
#include <deque>
#include "dialogs/dialogsingletaskblockinfo.h"
#include "dataStructs/yieldmap.h"

namespace Ui {
class FormTask;
}

class FormTask : public QWidget
{
	Q_OBJECT

public:
	explicit FormTask(QWidget *parent = nullptr);
	~FormTask();

private:
    void clearCurrentTask();
    QStringList checkedTaskList();
    void setBlockCheckedState(int row,int column,bool b);
    void loadCurrentTask(QString task);
    void setBackground(int row,int column);

	Ui::FormTask *ui;
	Task currentTask;
	bool routeView;
    std::vector<std::deque<bool>> checkedV;
    DialogSingleTaskBlockInfo *dstbi;
    YieldMap currentMap;

public slots:
	void slotRefreshTaskList();
    void slotReloadTask();
    void slotReloadTask(QString name);

private slots:
    void slotVerticalSectionClicked(int logicalIndex);
    void slotHorizontalSectionClicked(int logicalIndex);
    void slotCheckBoxCheckAllBlockStateChanged(int state);
    void slotComboBoxViewCurrentTextChanged(const QString &text);

signals:
	void signalTaskListUpdated();
};

#endif // FORMTASK_H
