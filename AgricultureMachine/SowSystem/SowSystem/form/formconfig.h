#ifndef FORMCONFIG_H
#define FORMCONFIG_H

#include <QStackedWidget>
#include "tool/communication.h"

namespace Ui {
class FormConfig;
}

class FormConfig : public QStackedWidget
{
	Q_OBJECT

public:
    explicit FormConfig(Communication &c,QWidget *parent = nullptr);
	~FormConfig();

private:
	Ui::FormConfig *ui;
    Communication &c;
    QTimer timer;
    QString port;
private slots:
	void slotPushButtonRefreshPortClicked();
	void slotComboBoxSerialPortCurrentTextChanged(const QString &);
    void slotComboBoxNavigationAntennaCurrentTextChanged(const QString &);
    void slotTimerTimeout();
signals:
    void signalAppConfigUpdated();
    void signalDeviceConfigUpdated();
};

#endif // FORMCONFIG_H
