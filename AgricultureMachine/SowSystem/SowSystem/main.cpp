#include "mainwindow.h"
#include <QFile>
#include <QApplication>
#include "../../common/database.h"
#include <QSettings>
#include "global.h"
#include <QTextCodec>
#include <QDebug>
#include "../../common/globalfilter.h"
#include "dialog/dongle_dialog.h"
#include <QMessageBox>
#include <synchapi.h>
#include <errhandlingapi.h>
#include <winerror.h>
#include <handleapi.h>

int main(int argc, char *argv[])
{
	QApplication a(argc, argv);
    HANDLE m_hMutex = CreateMutex(nullptr, FALSE,L"SowSystem");
    if (GetLastError() == ERROR_ALREADY_EXISTS)
    {
        CloseHandle(m_hMutex);
        QMessageBox::information(nullptr,"提示","程序已经在运行中，不能重复启动！");

        m_hMutex =nullptr;
        return 1;
    }
//	DongleDialog d;
//	if(!d.fileOk()||(!d.isAct()&&d.exec())!= 8)
//		return 0;
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
		iniFile.setValue("SerialPort","COM1");
		iniFile.setValue("Alpha",128);
		iniFile.setValue("BlockColumnCount",1);
		iniFile.beginWriteArray(SEEDGAPFINETUNINGARRAY);
		for(int i=0;i<SeedGapFineTuningDensityList.size();iniFile.setValue("Enabled",0))
		{
			iniFile.setArrayIndex(i);
			int t=SeedGapFineTuningDensityList[i++];
			iniFile.setValue("OriginDensity",t);
			iniFile.setValue("SpecifiedDensity",t);
		}
		iniFile.endArray();
		iniFile.setValue("DropSeedTime",1500);
		iniFile.setValue("SeedColumnGap",60);
		iniFile.setValue("Rpm",36);
		iniFile.setValue("NavigationAntenna",0);
		iniFile.setValue("AntennaDistance",0);
		iniFile.endGroup();
		iniFile.beginGroup(DEVICEGROUP);
		iniFile.setValue("DeviceType","4行机");
		iniFile.setValue("MachineColumnCount",4);
		iniFile.setValue("DropPortDistance",60);
		iniFile.setValue("SeedDropDistance",90);
		iniFile.setValue("TransmissionRatio",2000);
		iniFile.setValue("EncoderDirection",0);
		iniFile.setValue("SowRouletteHole",9);
		iniFile.setValue("GearRatio",5);
		iniFile.setValue("ZeroSwitch",1);
		iniFile.setValue("MicroStepValue",800);
		iniFile.setValue("X1",150);
		iniFile.setValue("BDiroff",0);
		iniFile.setValue("TappTrigOff",20);
		iniFile.setValue("TapperTime",100);
		iniFile.setValue("ScrapeSeed",1);
		iniFile.endGroup();
		iniFile.beginGroup(TESTWARNINGGROUP);
		iniFile.setValue("ZeroPosition1",false);
		iniFile.setValue("ZeroPosition2",false);
		iniFile.setValue("ZeroPosition3",false);
		iniFile.setValue("ZeroPosition4",false);
        iniFile.setValue("ZeroPosition5",false);
        iniFile.setValue("ZeroPosition6",false);
		iniFile.setValue("AutoSeedSupply",false);
		iniFile.setValue("Reserve",false);
		iniFile.setValue("Cable1",false);
		iniFile.setValue("Cable2",false);
		iniFile.setValue("Pressure",false);
		iniFile.setValue("Blower",false);
		iniFile.setValue("Pedal",false);
		iniFile.setValue("Init",false);
		iniFile.setValue("BeiDou",false);
		iniFile.setValue("StepperMotor1",false);
		iniFile.setValue("StepperMotor2",false);
		iniFile.setValue("StepperMotor3",false);
		iniFile.setValue("StepperMotor4",false);
        iniFile.setValue("StepperMotor5",false);
        iniFile.setValue("StepperMotor6",false);
		iniFile.setValue("AutoSeedSupplyMotor",false);
		iniFile.endGroup();
		iniFile.beginGroup(CONTINUOUSSOWMODEGROUP);
		iniFile.setValue("Density",4000);
		iniFile.sync();
	}
	if(!QFile::exists(DATABASE))
	{
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.exec("CREATE TABLE "+MAPTABLE+" (Name TEXT PRIMARY KEY,CreateTime TEXT DEFAULT (datetime('now','localtime')),ModifyTime TEXT,Mark TEXT,BlockColumn INTEGER,MachineColumn INTEGER,SeedColumnGap INTEGER,ARow INTEGER,AColumn INTEGER,ABLineDirection INTEGER,ABLineName TEXT REFERENCES "+ABLINETABLE+" (Name) ON DELETE RESTRICT ON UPDATE CASCADE)");
        qsq.exec("CREATE TRIGGER TriggerUpdateModifyTime AFTER UPDATE OF Name,CreateTime,Mark ON "+MAPTABLE+" FOR EACH ROW BEGIN UPDATE "+MAPTABLE+" SET ModifyTime=datetime('now','localtime') WHERE Name=NEW.Name;END");
		qsq.exec("CREATE TABLE "+MAPBLOCKTABLE+" (MapName TEXT REFERENCES "+MAPTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,[Row] INTEGER,[Column] INTEGER,Number TEXT,Density INTEGER,SowSeed BOOLEAN)");
		qsq.exec("CREATE TABLE "+ROWATTRIBUTESTABLE+" (MapName TEXT REFERENCES "+MAPTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,[Row] INTEGER,Length REAL)");
		qsq.exec("CREATE TABLE "+MAPAISLETABLE+" (MapName TEXT REFERENCES "+MAPTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,[Index] INTEGER,Length REAL)");
		qsq.exec("CREATE TABLE "+TASKTABLE+" (Name TEXT PRIMARY KEY,MapName TEXT REFERENCES "+MAPTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,Mark TEXT,CreateTime TEXT DEFAULT (datetime('now','localtime')),LastWorkTime TEXT,PathType INTEGER,Positive BOOLEAN,LastBlockRow INTEGER,LastBlockColumn INTEGER,OutsetRow INTEGER,OutsetColumn INTEGER)");
        qsq.exec("CREATE TABLE "+TASKBLOCKTABLE+" (TaskName TEXT REFERENCES "+TASKTABLE+" (Name) ON DELETE CASCADE ON UPDATE CASCADE,[Row] INTEGER,[Column] INTEGER,State INTEGER,Sow BOOLEAN)");
        qsq.exec("CREATE TABLE "+RESULTTABLE+" (TaskName TEXT,[Row] INTEGER,[Column] INTEGER,State INTEGER,StartTime TEXT,EndTime TEXT,SeedCount1 INTEGER,FertilizerCount1 INTEGER,SeedCount2 INTEGER,FertilizerCount2 INTEGER,SeedCount3 INTEGER,FertilizerCount3 INTEGER,SeedCount4 INTEGER,FertilizerCount4 INTEGER,SeedCount5 INTEGER,FertilizerCount5 INTEGER,SeedCount6 INTEGER,FertilizerCount6 INTEGER,Mark TEXT)");
		qsq.exec("CREATE TABLE "+ABLINETABLE+" (Name TEXT PRIMARY KEY,StartN TEXT,StartE TEXT,EndBN TEXT,EndBE TEXT,StartDir TEXT,CalcDir TEXT,StartState INTEGER,CalcDirFlag INTEGER,OffLen INTEGER,BDOffTime INTEGER,Resv INTEGER,CrcCheck INTEGER)");
		d.close();
	}
	MainWindow w;
	w.show();
	return a.exec();
}
