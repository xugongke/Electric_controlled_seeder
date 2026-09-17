#include "formcontinuoussow.h"
#include "ui_formcontinuoussow.h"
#include <QSettings>
#include <QTextCodec>
#include "global.h"
#include <QStandardItemModel>
#include <cmath>

#define INTERVAL 500
#define LEAKSEEDCOLUMN 0
#define LEAKFERTILIZERCOLUMN 1

FormContinuousSow::FormContinuousSow(Communication &c,QWidget *parent) :
    QWidget(parent),
    ui(new Ui::FormContinuousSow),c(c)
{
	ui->setupUi(this);
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(CONTINUOUSSOWMODEGROUP);
	ui->spinBoxDensity->setValue(iniFile.value("Density").toInt());
	iniFile.endGroup();
	connect(ui->pushButtonSaveContinuousSowParameter,&QPushButton::clicked,this,[=]{
		QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
		iniFile.beginGroup(CONTINUOUSSOWMODEGROUP);
		iniFile.setValue("Density",ui->spinBoxDensity->value());
		iniFile.endGroup();
	});
    connect(ui->pushButtonStartContinuousSow,&QPushButton::clicked,this,[=,&c]{
		c.setEmptyABLine();
		ui->pushButtonStartContinuousSow->text()=="停止"?c.stopContinuousSow():c.setUserParameter(getUserParameterFromSetting(),CONTINUOUSSOW);
	});
    connect(&c,&Communication::signalSetUserParameter,this,[=,&c](bool b){
		if(b&&c.getPreMode()==CONTINUOUSSOW)
			c.setManufacturerParameter(getManufacturerParameterFromSetting());
	});
    connect(&c,&Communication::signalSetManufacturerParameter,this,[=,&c](bool b){
		if(!b||c.getPreMode()!=CONTINUOUSSOW)
			return;
		QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
		iniFile.beginGroup(APPLICATIONGROUP);
		LXBZParaType lpt;
		lpt.Hju=iniFile.value("SeedColumnGap").toInt();
		iniFile.endGroup();
		lpt.CellLen=rowLength();
		iniFile.beginGroup(CONTINUOUSSOWMODEGROUP);
		lpt.Density=iniFile.value("Density").toInt();
		iniFile.endGroup();
		lpt.ZhuShu=0;
		c.startContinuousSow(lpt);
	});
	connect(&c,&Communication::signalGetSowStatus,this,[=](BZStatusType_st bzst){
		ui->labelDistance->setText(QString::number(bzst.OffLen/100.0)+"m、"+QString::number(bzst.VerticalOff/100.0)+"m");
		ui->labelSpeed->setText(QString::number(bzst.Speed/1000.0)+"m/s");
		QStandardItemModel *qsim=(QStandardItemModel *)ui->tableView->model();
		for(int i=0;i<maxSowColumn;i++)
		{
			qsim->item(i,LEAKSEEDCOLUMN)->setText(QString::number(bzst.LouZHCnt[i]));
			qsim->item(i,LEAKFERTILIZERCOLUMN)->setText(QString::number(bzst.LoufeiCnt[i]));
		}
	});
    connect(&qt,&QTimer::timeout,this,[=,&c]{
		c.getSowStatus();
	});
	connect(&c,&Communication::signalStartContinuousSow,this,[=]{
		ui->pushButtonStartContinuousSow->setText("停止");
		qt.start(INTERVAL);
	});
	connect(&c,&Communication::signalStopContinuousSow,this,[=]{
		ui->pushButtonStartContinuousSow->setText("开始");
		qt.stop();
	});
    connect(&debugInfoTimer,&QTimer::timeout,this,[=,&c]{
		if(c.getConnectionState())
			c.getDebugInformation(CONTINUOUSSOW);
	});
    connect(&c,&Communication::signalGetDebugInformation,this,[=,&c](QString qs){
		if(c.getDebugInfoMode()==CONTINUOUSSOW)
			ui->labelDebugInfo->setText(qs);
	});
	connect(ui->spinBoxDensity,static_cast<void(QSpinBox:: *)(int)>(&QSpinBox::valueChanged),this,&FormContinuousSow::slotUpdateSeedCount);
	QStandardItemModel *model=new QStandardItemModel;
	model->setHorizontalHeaderLabels({
		"漏种","漏肥"
	 });
	ui->tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->setModel(model);
	slotDeviceConfigUpdated();
	slotUpdateSeedCount(ui->spinBoxDensity->value());
}

FormContinuousSow::~FormContinuousSow()
{
	delete ui;
}

void FormContinuousSow::slotDeviceConfigUpdated()
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(DEVICEGROUP);
	maxSowColumn=iniFile.value("DeviceType").toString()=="6行机"?6:4;
	iniFile.endGroup();
	QStandardItemModel *qsim=(QStandardItemModel *)ui->tableView->model();
	qsim->clear();
	qsim->setHorizontalHeaderLabels({"漏种","漏肥"});
	for(int i=0;i<maxSowColumn;qsim->setItem(i++,LEAKFERTILIZERCOLUMN,new QStandardItem))
		qsim->setItem(i,LEAKSEEDCOLUMN,new QStandardItem);
}

void FormContinuousSow::slotUpdateSeedCount(int value)
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	ui->labelSeedRowGap->setText(QString::number(((rowLength()*10/(value-1)+5)/10))+"cm"); /*株距四舍五入*/
	iniFile.endGroup();
}

void FormContinuousSow::startDebugInfoTimer()
{
	debugInfoTimer.start(INTERVAL);
}

void FormContinuousSow::stopDebugInfoTimer()
{
	debugInfoTimer.stop();
}

int FormContinuousSow::rowLength()
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	//1亩=666.6667m³*10000=6666667cm³
	int length=6666667/iniFile.value("SeedColumnGap").toInt();
	iniFile.endGroup();
	return length;
}
