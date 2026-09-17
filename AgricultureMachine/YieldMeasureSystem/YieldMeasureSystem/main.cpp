#include "mainwindow.h"
#include "../../common/database.h"
#include <QApplication>
#include "../../common/globalfilter.h"
#include "global.h"
//#include "network/threadaccept.h"
//#include "network/threaddata.h"
//#include "network/tcp.h"
#include <QDir>
#include <QDebug>
#include <QSettings>
#include <QTextCodec>
#include <QDateTime>
#include "uart/threaduart.h"
#include <QMutex>
#include <synchapi.h>
#include <errhandlingapi.h>
#include <winerror.h>
#include <handleapi.h>
#include <QMessageBox>

#define LOGDIRECTORY QString("log")

void outputLog(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
	static QMutex mutex;
	mutex.lock();
	QDir qd;
	if(!qd.exists(LOGDIRECTORY))
		qd.mkdir(LOGDIRECTORY);
	QFile file(LOGDIRECTORY+'/'+G.logFile);
	file.open(QIODevice::WriteOnly);
	QTextStream text_stream(&file);
	switch(type)
	{
	case QtDebugMsg:
		text_stream <<QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss")<<"[debug]"<<msg<< "\r\n";
		break;
	case QtWarningMsg:
		text_stream <<QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss")<<"[warning]"<<msg<< "\r\n";
		break;
	case QtCriticalMsg:
		text_stream <<QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss")<<"[critical]"<<msg<< "\r\n";
		break;
	case QtFatalMsg:
		text_stream <<QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss")<<"[fatal]"<<msg<< "\r\n";
		break;
	case QtInfoMsg:
		text_stream <<QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss")<<"[info]"<<msg<< "\r\n";
		break;
	default:;
	}
	file.flush();
	file.close();
	mutex.unlock();
}

int main(int argc, char *argv[])
{
	QApplication a(argc, argv);
    HANDLE m_hMutex = CreateMutex(nullptr, FALSE,L"YieldMeasureSystem");
    if (GetLastError() == ERROR_ALREADY_EXISTS)
    {
        CloseHandle(m_hMutex);
        QMessageBox::information(nullptr,"提示","程序已经在运行中，不能重复启动！");

        m_hMutex =nullptr;
        return 1;
    }
	//qInstallMessageHandler(outputLog);
	a.installEventFilter(new GlobalFilter);
    QFile file(":/style/style.qss");
	file.open(QFile::ReadOnly);
	a.setStyleSheet(file.readAll());
	file.close();
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	if(!QFile::exists(CONFIGFILE))
	{
		iniFile.beginGroup(APPLICATIONGROUP);
        iniFile.setValue("Port","COM1");
        iniFile.setValue("MeasuleColumnCount",1);
		iniFile.setValue("Valve1StabilizationTime",1);
		iniFile.setValue("Valve2StabilizationTime",1);
		iniFile.setValue("Valve1GrainFlowTime",1);
		iniFile.setValue("Valve2GrainFlowTime",1);
		iniFile.setValue("Valve3GrainFlowTime",1);
		iniFile.setValue("UnitWeightBucketVolumn",2.14);
		iniFile.setValue("CyclicMeasureYieldThreshold",20);
		iniFile.setValue("MeasureUnitWeight",true);
        iniFile.setValue("MoistureSensor","新");
        iniFile.setValue("MoistureValueMode","0");
		iniFile.setValue("RealtimeMoistureCalibrationTransformMode",cropList[0]);
		iniFile.setValue("Alpha",128);
        iniFile.setValue("MaxMoisture",128);
		iniFile.endGroup();
		iniFile.beginGroup(DEVICEGROUP);
		iniFile.endGroup();
		iniFile.sync();
	}
	if(!QFile::exists(DATABASE))
	{
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
        d.qsd.transaction();
		qsq.exec("CREATE TABLE "+MASSCALIBRATIONTABLE+" (Channle TEXT PRIMARY KEY,[Range] TEXT,ZeroValue TEXT,Flag INTEGER)");
		qsq.exec("CREATE TABLE "+MASSCALIBRATIONPOINTTABLE+" (Channle TEXT REFERENCES "+MASSCALIBRATIONTABLE+" (Channle) ON DELETE CASCADE ON UPDATE CASCADE,Value TEXT,Sensitivity TEXT)");
        qsq.exec("CREATE TABLE "+MOISTURECALIBRATIONPOINTTABLE+" (Crop TEXT,Moisture TEXT,NonCalibrationValue TEXT)");
		foreach(QString channle,channleList)
		{
			qsq.prepare("INSERT INTO "+MASSCALIBRATIONTABLE+" (Channle,[Range],ZeroValue,Flag) VALUES (?,?,?,?)");
			qsq.addBindValue(channle);
            qsq.addBindValue(10);
            qsq.addBindValue(0);
            qsq.addBindValue(0);
			qsq.exec();
			qsq.prepare("INSERT INTO "+MASSCALIBRATIONPOINTTABLE+" (Channle,Value,Sensitivity) VALUES (?,?,?)");
			qsq.addBindValue(channle);
			qsq.addBindValue(1);
			qsq.addBindValue(1);
			qsq.exec();
		}
		foreach(QString crop,cropList)
		{
			qsq.prepare("INSERT INTO "+MOISTURECALIBRATIONPOINTTABLE+" (Crop,Moisture,NonCalibrationValue) VALUES (?,?,?)");
			qsq.addBindValue(crop);
			qsq.addBindValue(1);
			qsq.addBindValue(1);
            qsq.exec();
            qsq.prepare("INSERT INTO "+MOISTURECALIBRATIONPOINTTABLE+" (Crop,Moisture,NonCalibrationValue) VALUES (?,?,?)");
            qsq.addBindValue(crop);
            qsq.addBindValue(2);
            qsq.addBindValue(2);
            qsq.exec();
		}
        qsq.exec("CREATE TABLE "+MAPTABLE+" (Name TEXT PRIMARY KEY,CreateTime TEXT DEFAULT (datetime('now','localtime')),ModifyTime TEXT,Mark TEXT)");
        qsq.exec("CREATE TRIGGER TriggerUpdateModifyTime AFTER UPDATE OF CreateTime,Mark ON "+MAPTABLE+" FOR EACH ROW BEGIN UPDATE "+MAPTABLE+" SET ModifyTime=datetime('now','localtime') WHERE Name=NEW.Name;END");
        qsq.exec("CREATE TABLE "+MAPBLOCKTABLE+" (MapName TEXT REFERENCES "+MAPTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,[Row] INTEGER,[Column] INTEGER,Crop TEXT,Number TEXT)");
        qsq.exec("CREATE TABLE "+TASKTABLE+" (Name TEXT PRIMARY KEY,MapName TEXT REFERENCES "+MAPTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,Mark TEXT,CreateTime TEXT DEFAULT (datetime('now','localtime')),LastWorkTime TEXT,PathType INTEGER,StartRow INTEGER,StartColumn INTEGER,LastRow INTEGER,LastColumn INTEGER,Positive INTEGER)");
        qsq.exec("CREATE TABLE "+TASKBLOCKTABLE+" (TaskName TEXT REFERENCES "+TASKTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,[Row] INTEGER,[Column] INTEGER,State INTEGER,Measure BOOLEAN)");
        qsq.exec("CREATE TABLE "+RESULTTABLE+" (TaskName TEXT REFERENCES "+TASKTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,StartTime TEXT,EndTime TEXT DEFAULT (datetime('now','localtime')),Moisture TEXT,Mass TEXT,UnitWeight TEXT,[Row] INTEGER,[Column] INTEGER,Crop TEXT,Mark TEXT,State TEXT)");
        d.qsd.commit();
		qsq.clear();
		d.close();
	}
    initMassCalibMap();
	initMoistureCalibMap();
//	G.tAccept=new ThreadAccept(nullptr);
//	G.tData=new ThreadData(nullptr);
//	QObject::connect(G.tAccept, &ThreadAccept::sig_data_link, G.tData, &ThreadData::addSensor);
//	QObject::connect(G.tAccept, &ThreadAccept::sig_cmd_link,  G.tData, &ThreadData::addCard);
//    G.tAccept->startServer(6,16);
//    G.tData->startServer(6,16);
    G.tUart=new ThreadUart(nullptr);
    G.tUart->threadCreate();
    G.rd=new RealtimeData;
	MainWindow w;
	w.show();
	int i=a.exec();
    G.tUart->threadStop();
//	TcpFormat tf;
//	tf.h.h=CMD_HEAD;
//	tf.h.cmd=CMD_STOP;
//	tf.h.len=sizeof(CmdHead);
//	G.tData->sendCmd(0,&tf);
//	delete G.tData;
//	G.tData=nullptr;
//	delete G.tAccept;
//	G.tAccept=nullptr;
	return i;
}
