#include "global.h"
#include <QScroller>
#include <QDebug>
#include <QDir>
#include <QDate>
#include <QSettings>
#include <QPainter>

QMap<QString,QStringList> BlockColumnCountMap={
    {"4行机",{"1","2","4"}},
    {"6行机",{"1","6"}}
};
QList<int> SeedGapFineTuningDensityList={
	4000,4500,5000,5500,6000
};
int MaxMotorCount=6;
//const QSettings::Format JsonFormat=QSettings::registerFormat("json",readJsonFile,writeJsonFile);

void setTouchable(QAbstractItemView *qaiv)
{
    QScroller::grabGesture(qaiv,QScroller::LeftMouseButtonGesture);
    qaiv->setHorizontalScrollMode(QAbstractItemView::ScrollPerPixel);
    qaiv->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    qaiv->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    qaiv->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
}

QString listString(QStringList qsl)
{
	int s=qsl.size();
	QString qs;
	for(int i=0;i<s;)
	{
		qs+=qsl[i++];
		if(i<s)
			qs+="、";
	}
	return qs;
}

bool bit(long long number,int index)
{
	return (number&(1<<index))>0;
}

UserParaType getUserParameterFromSetting()
{
	UserParaType upt;
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	upt.DZTime=iniFile.value("DropSeedTime").toInt();
	upt.HJ=iniFile.value("SeedColumnGap").toFloat();
	upt.Rpm=iniFile.value("Rpm").toInt();
    upt.AntennaType=iniFile.value("NavigationAntenna").toInt();
    upt.AntennaDistance=iniFile.value("AntennaDistance").toInt();
    iniFile.endGroup();
	return upt;
}

TerParaType getManufacturerParameterFromSetting()
{
    TerParaType tpt;
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(DEVICEGROUP);
	tpt.A=iniFile.value("DropPortDistance").toFloat();
	tpt.B=iniFile.value("SeedDropDistance").toFloat();
	tpt.EncodeNum=iniFile.value("TransmissionRatio").toInt();
	tpt.EncoderDir=iniFile.value("EncoderDirection").toInt();
	tpt.HoleNum=iniFile.value("SowRouletteHole").toInt();
	tpt.GearRatio=iniFile.value("GearRatio").toInt();
	tpt.ZeroPosEn=iniFile.value("ZeroSwitch").toInt();
	tpt.GZEn=iniFile.value("ScrapeSeed").toInt();
	tpt.MicroStepValue=iniFile.value("MicroStepValue").toInt();
	tpt.X1=iniFile.value("X1").toFloat();
	tpt.BDiroff=iniFile.value("BDiroff").toFloat();
	tpt.TappTrigOff=iniFile.value("TappTrigOff").toFloat();
	tpt.TapperTime=iniFile.value("TapperTime").toInt();
    tpt.PrePercent=iniFile.value("PrePercent",70).toInt();
    tpt.U8Resv2=iniFile.value("Device","4行机").toString().left(1).toInt();
	iniFile.endGroup();
	return tpt;
}

void writeLog(QString log)
{
	QFile qf(QDir::currentPath()+'/'+QDate::currentDate().toString()+"_DebugInfo.log");
	qf.open(QIODevice::Append|QIODevice::Text);
	QTextStream qts(&qf);
    qts<<log<<" "<<QTime::currentTime().toString("hh:mm:ss.zzz")+'\n';
	qf.close();
}

bool densityIsSpecified(int value)
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	for(int i=0,s=iniFile.beginReadArray(SEEDGAPFINETUNINGARRAY);i<s;)
	{
		iniFile.setArrayIndex(i++);
		if(iniFile.value("OriginDensity").toInt()==value)
			return iniFile.value("Enabled").toInt()==1;
	}
	iniFile.endArray();
	iniFile.endGroup();
	return false;
}

int specifiedDensity(int value)
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	for(int i=0,s=iniFile.beginReadArray(SEEDGAPFINETUNINGARRAY);i<s;)
	{
		iniFile.setArrayIndex(i++);
		if(iniFile.value("OriginDensity").toInt()==value&&iniFile.value("Enabled").toInt()==1)
			return iniFile.value("SpecifiedDensity").toInt();
	}
	iniFile.endArray();
	iniFile.endGroup();
    return value;
}

QPixmap getTransparentPixmap(QString path)
{
	QPixmap temp(path),qp(temp.size());
	qp.fill(Qt::transparent);
	QPainter p1(&qp);
	p1.setCompositionMode(QPainter::CompositionMode_Source);
	p1.drawPixmap(0,0,temp);
	p1.setCompositionMode(QPainter::CompositionMode_DestinationIn);
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	p1.fillRect(qp.rect(),QColor(0,0,0,iniFile.value("Alpha",128).toInt()));
	iniFile.endGroup();
	p1.end();
	return qp;
}
