#ifndef FORMMOISTURECALIBRATION_H
#define FORMMOISTURECALIBRATION_H

#include <QWidget>
#include "dataStructs/moisturecalibrationdata.h"

namespace Ui {
class FormMoistureCalibration;
}

class FormMoistureCalibration : public QWidget
{
	Q_OBJECT

public:
	explicit FormMoistureCalibration(QWidget *parent = nullptr);
	~FormMoistureCalibration();

private slots:
    void slotSbPointValueChanged(int value);

private:
    void redrawChart();
	void createCalibrationRow(int row);
	void setCailbrationPoint(int row,float moisture,float nonCalibrationValue);
	MoistureCalibrationData currentCalibrationData();
    void updatePoint(int index,double x,double y);
    void connectUpdatePointSlots(int row);

	Ui::FormMoistureCalibration *ui;
    QTimer qt;
};

#endif // FORMMOISTURECALIBRATION_H
