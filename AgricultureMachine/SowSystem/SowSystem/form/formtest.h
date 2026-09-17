#ifndef FORMTEST_H
#define FORMTEST_H

#include <QWidget>
#include "tool/communication.h"

namespace Ui {
class FormTest;
}

class FormTest : public QWidget
{
	Q_OBJECT

public:
    explicit FormTest(Communication &c,QWidget *parent = nullptr);
	~FormTest();
	void enterTestMode();
	void exitTestMode();
public slots:
	void slotDeviceConfigUpdated();

private:
	void alarm();
	void setWarningEnabled(QString setting,int checkState);

	Ui::FormTest *ui;
	TestModeStateType_st state;
	QTimer testTimer;
    Communication &c;
	int maxSowColumn;
};

#endif // FORMTEST_H
