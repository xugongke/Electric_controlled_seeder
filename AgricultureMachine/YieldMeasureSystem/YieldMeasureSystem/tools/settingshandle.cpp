#include "settingshandle.h"
#include <QSettings>
#include <QTextCodec>
#include "global.h"
#include <QDebug>

void setMeasureColumnCount(int measureColumnCount)
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    iniFile.setValue("MeasureColumnCount",measureColumnCount);
    iniFile.endGroup();
}

int getMeasureColumnCount()
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    int a=iniFile.value("MeasureColumnCount",1).toInt();
    iniFile.endGroup();
    return a;
}

void setMoistureValueMode(char mode)
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    iniFile.setValue("MoistureValueMode",mode);
    iniFile.endGroup();
}

char getMoistureValueMode()
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    char a=iniFile.value("MoistureValueMode",moistureSensorModeMap[iniFile.value("MoistureSensor").toString()][0]).toString().at(0).toLatin1();
    iniFile.endGroup();
    return a;
}

void setPort(QString port)
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    iniFile.setValue("Port",port);
    iniFile.endGroup();
}

QString getPort()
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    QString port=iniFile.value("Port","COM1").toString();
    iniFile.endGroup();
    return port;
}
