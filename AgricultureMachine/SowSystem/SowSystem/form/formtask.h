#ifndef FORMTASK_H
#define FORMTASK_H

#include <QWidget>
#include "dataStruct/task.h"
#include <QButtonGroup>
#include <QTableView>
#include <QStandardItem>
#include "tool/communication.h"

namespace Ui {
class FormTask;
}

class FormTask : public QWidget
{
	Q_OBJECT

public:
    explicit FormTask(Communication &c,QWidget *parent = nullptr);
	~FormTask();

public slots:
	void slotRefreshTaskList();
	void slotAlphaUpdated();
	void slotComboBoxViewCurrentTextChanged(const QString &);
private:
	Ui::FormTask *ui;
	Task currentTask;
	QButtonGroup qbg1,qbg2;
    Communication &c;

	void clearCurrentTask();
	void loadCurrentTask(QString task);
	QStringList checkedTaskList();
signals:
	void signalTaskListUpdated();
	void signalABLineStateUpdated(QString mapName);
};

#endif // FORMTASK_H
