#ifndef DIALOGNEWTASK_H
#define DIALOGNEWTASK_H

#include <QDialog>

namespace Ui {
class DialogNewTask;
}

class DialogNewTask : public QDialog
{
	Q_OBJECT

public:
	explicit DialogNewTask(QWidget *parent = nullptr);
	~DialogNewTask();
	QString newTaskName();

private:
	Ui::DialogNewTask *ui;
};

#endif // DIALOGNEWTASK_H
