#include "moisturecalibrationdata.h"
#include "../../common/database.h"
#include <QVariant>
#include <QDebug>
#include <QSqlError>

bool MoistureCalibrationData::existData(QString crop)
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Crop FROM "+MOISTURECALIBRATIONPOINTTABLE+" WHERE Crop=?");
	qsq.addBindValue(crop);
	qsq.exec();
	bool b=count(qsq)>0;
	qsq.clear();
	d.close();
	return b;
}

MoistureCalibrationData::MoistureCalibrationData()
{

}

void MoistureCalibrationData::load(QString crop)
{
	this->crop=crop;
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Moisture,NonCalibrationValue FROM "+MOISTURECALIBRATIONPOINTTABLE+" WHERE Crop=?");
	qsq.addBindValue(crop);
	qsq.exec();
    for(n=0;qsq.next()&&n<MAXCALIBRATIONCOUNT;adc[n++]=qsq.value("NonCalibrationValue").toDouble())
		val[n]=qsq.value("Moisture").toDouble();
	qsq.clear();
	d.close();
}

void MoistureCalibrationData::update()
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("DELETE FROM "+MOISTURECALIBRATIONPOINTTABLE+" WHERE Crop=?");
	qsq.addBindValue(crop);
	d.qsd.transaction();
	qsq.exec();
	for(int i=0;i<n;qsq.exec())
	{
		qsq.prepare("INSERT INTO "+MOISTURECALIBRATIONPOINTTABLE+" (Crop,Moisture,NonCalibrationValue) VALUES (?,?,?)");
		qsq.addBindValue(crop);
		qsq.addBindValue(QString::number(val[i],'f'));
        qsq.addBindValue(QString::number(adc[i++],'f'));
    }
	d.qsd.commit();
	qsq.clear();
	d.close();
}

bool MoistureCalibrationData::isValid(float f)
{
	return f<=adc[n-1]&&f>=adc[0];
}
