#ifndef FORMCONTINUOUSSOW_H
#define FORMCONTINUOUSSOW_H

#include <QWidget>
#include <QTimer>
#include "tool/communication.h"

namespace Ui {
class FormContinuousSow;
}

class FormContinuousSow : public QWidget
{
	Q_OBJECT

public:
    explicit FormContinuousSow(Communication &c,QWidget *parent = nullptr);
	~FormContinuousSow();
	void startDebugInfoTimer();
	void stopDebugInfoTimer();
public slots:
	void slotDeviceConfigUpdated();

private:
	Ui::FormContinuousSow *ui;
	QTimer qt,debugInfoTimer;
    Communication &c;
	int maxSowColumn;
	int rowLength();
private slots:
	void slotUpdateSeedCount(int value);
};

#endif // FORMCONTINUOUSSOW_H
