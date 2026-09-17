#ifndef FORMMASSCALIBRATION_H
#define FORMMASSCALIBRATION_H

#include <QWidget>
#include "dataStructs/masscalibrationdata.h"

namespace Ui {
class FormMassCalibration;
}

class FormMassCalibration : public QWidget
{
	Q_OBJECT

public:
	explicit FormMassCalibration(QWidget *parent = nullptr);
	~FormMassCalibration();

private slots:
    void slotSbPointValueChanged(int value);

private:
	void createCalibrationRow(int row);
	void setCailbrationPoint(int row,float value,float sensitivity);
	MassCalibrationData currentCalibrationData();
	void showRealtimeSensitivity(float f);
    void redrawChart();
    void updatePoint(int index,double x,double y);
    void connectUpdatePointSlots(int row);

	Ui::FormMassCalibration *ui;
	QTimer realtimeSensitivityTimer;
};

#endif // FORMMASSCALIBRATION_H
