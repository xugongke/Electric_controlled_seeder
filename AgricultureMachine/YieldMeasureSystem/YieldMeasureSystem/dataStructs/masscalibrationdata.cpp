#include "masscalibrationdata.h"
#include "../../common/database.h"
#include <QVariant>
#include <QSqlError>
#include <QDebug>

bool MassCalibrationData::existData(QString channle)
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Channle FROM "+MASSCALIBRATIONTABLE+" WHERE Channle=?");
	qsq.addBindValue(channle);
	qsq.exec();
	bool b=count(qsq)>0;
	qsq.clear();
	d.close();
	return b;
}

MassCalibrationData::MassCalibrationData()
{

}

void MassCalibrationData::load(QString channle)
{
	this->channle=channle;
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT [Range],ZeroValue,Flag FROM "+MASSCALIBRATIONTABLE+" WHERE Channle=?");
	qsq.addBindValue(channle);
	qsq.exec();
	qsq.next();
	range=qsq.value("Range").toFloat();
	zero=qsq.value("ZeroValue").toFloat();
	flag=qsq.value("Flag").toInt();
	qsq.prepare("SELECT Value,Sensitivity FROM "+MASSCALIBRATIONPOINTTABLE+" WHERE Channle=?");
	bool reverse=(flag&1)!=0;
	qsq.addBindValue(channle);
	qsq.exec();
    n=reverse?count(qsq)/2:count(qsq);
	for(int i=0;qsq.next()&&i<n;)
	{
		val[i]=qsq.value("Value").toFloat();
		adc[i++]=qsq.value("Sensitivity").toFloat();
    }
	if(reverse)
		for(int i=0;i<n;qsq.next())
		{
			int t=i+++10;
			val[t]=qsq.value("Value").toFloat();
			adc[t]=qsq.value("Sensitivity").toFloat();
		}
	qsq.clear();
	d.close();
}

void MassCalibrationData::update()
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT Channle FROM "+MASSCALIBRATIONTABLE+" WHERE Channle=?");
    qsq.addBindValue(channle);
    qsq.exec();
    if(qsq.next())
    {
        qsq.prepare("UPDATE "+MASSCALIBRATIONTABLE+" SET [Range]=?,ZeroValue=?,Flag=? WHERE Channle=?");
        qsq.addBindValue(QString::number(range,'f'));
        qsq.addBindValue(QString::number(zero,'f'));
        qsq.addBindValue(flag);
        qsq.addBindValue(channle);
    }
    else
    {
        qsq.prepare("INSERT INTO "+MASSCALIBRATIONTABLE+" VALUES (?,?,?,?)");
        qsq.addBindValue(channle);
        qsq.addBindValue(QString::number(range));
        qsq.addBindValue(QString::number(zero));
        qsq.addBindValue(flag);
    }
	d.qsd.transaction();
    qsq.exec();
	qsq.prepare("DELETE FROM "+MASSCALIBRATIONPOINTTABLE+" WHERE Channle=?");
	qsq.addBindValue(channle);
	qsq.exec();
	bool reverse=(flag&1)!=0;
	for(int i=0;i<n;++i)
	{
		qsq.prepare("INSERT INTO "+MASSCALIBRATIONPOINTTABLE+" (Channle,Value,Sensitivity) VALUES (?,?,?)");
		qsq.addBindValue(channle);
		qsq.addBindValue(QString::number(val[i],'f'));
		qsq.addBindValue(QString::number(adc[i],'f'));
		if(reverse)
		{
			int t=i+10;
			qsq.addBindValue(QString::number(val[t],'f'));
			qsq.addBindValue(QString::number(adc[t],'f'));
		}
		qsq.exec();
	}
	d.qsd.commit();
	qsq.clear();
	d.close();
}
