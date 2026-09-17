#ifndef FORMSETTING_H
#define FORMSETTING_H

#include <QWidget>

namespace Ui {
class FormSetting;
}

class FormSetting : public QWidget
{
	Q_OBJECT

public:
	explicit FormSetting(QWidget *parent = nullptr);
	~FormSetting();

private:
	Ui::FormSetting *ui;
    QString port;
signals:
    void signalSettingsUpdated();
public slots:
    void slotValveStateUpdated();
    void slotPushButtonRefreshPortClicked();
    void slotComboBoxSerialPortCurrentTextChanged(const QString &);
};

#endif // FORMSETTING_H
