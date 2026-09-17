#ifndef DIALOGCALIBRATIONAUTHENTICATION_H
#define DIALOGCALIBRATIONAUTHENTICATION_H

#include <QDialog>

namespace Ui {
class DialogCalibrationAuthentication;
}

class DialogCalibrationAuthentication : public QDialog
{
	Q_OBJECT

public:
	explicit DialogCalibrationAuthentication(QWidget *parent = nullptr);
	~DialogCalibrationAuthentication();

private:
	Ui::DialogCalibrationAuthentication *ui;
};

#endif // DIALOGCALIBRATIONAUTHENTICATION_H
