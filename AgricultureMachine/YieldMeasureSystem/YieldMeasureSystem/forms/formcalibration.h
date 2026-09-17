#ifndef FORMCALIBRATION_H
#define FORMCALIBRATION_H

#include <QStackedWidget>

namespace Ui {
class FormCalibration;
}

class FormCalibration : public QStackedWidget
{
	Q_OBJECT

public:
	explicit FormCalibration(QWidget *parent = nullptr);
	~FormCalibration();

private:
	Ui::FormCalibration *ui;
};

#endif // FORMCALIBRATION_H
