#include "formtest.h"
#include "ui_formtest.h"
#include <QStandardItemModel>
#include <QDebug>
#include <QSettings>
#include <QTextCodec>
#include "global.h"

#define LEAKSEEDCOLUMN 0
#define LEAKFERTILIZERCOLUMN 1
#define INTERVAL 500
#define ICONWIDTH 50
#define ICONHEIGHT 50

FormTest::FormTest(Communication &c,QWidget *parent) :
    QWidget(parent),
	ui(new Ui::FormTest),c(c)
{
	ui->setupUi(this);
	setTouchable(ui->tableView);
	ui->pushButtonStepperMotor1->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonStepperMotor2->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonStepperMotor3->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonStepperMotor4->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    ui->pushButtonStepperMotor5->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    ui->pushButtonStepperMotor6->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonAutoSeedSupplyMotor->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonScrapeSeed->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonDumpSeed->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonClearSeed->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonPreDropSeed->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonReserve1->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonReserve2->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonTapper->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonHorn->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonWarningLight->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	ui->pushButtonRunningStateLight->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
	QStandardItemModel *model=new QStandardItemModel;
	model->setHorizontalHeaderLabels({
		"漏种","漏肥"
	 });
    connect(&c,&Communication::signalSetUserParameter,this,[=,&c](bool b){
		if(b&&c.getPreMode()==TEST)
			c.setManufacturerParameter(getManufacturerParameterFromSetting());
	});
    connect(&c,&Communication::signalSetManufacturerParameter,this,[=,&c](bool b){
		if(b&&c.getPreMode()==TEST)
			c.enterTestMode();
	});
	ui->tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->setModel(model);
	slotDeviceConfigUpdated();
    connect(&testTimer,&QTimer::timeout,this,[=,&c]{
		c.getTestStatus();
	});
	connect(&c,&Communication::signalEnterTestMode,this,[=]{
		testTimer.start(INTERVAL);
	});
	connect(&c,&Communication::signalExitTestMode,this,[=]{
		testTimer.stop();
	});
	connect(&c,&Communication::signalGetTestStatus,this,[=](TestModeStateType_st tmst){
		QPixmap enabled=QPixmap(":/resource/image/enabled.png").scaled(ICONWIDTH,ICONHEIGHT),disabled=QPixmap(":/resource/image/disabled.png").scaled(ICONWIDTH,ICONHEIGHT),alarmed=QPixmap(":/resource/image/alarm.png").scaled(ICONWIDTH,ICONHEIGHT);
		state=tmst;
		if(bit(tmst.WarningState,0))
		{
			if(ui->checkBoxWarningZeroPosition1->isChecked())
				alarm();
			ui->labelZeroPosition1->setPixmap(alarmed);
		}
		else
			ui->labelZeroPosition1->setPixmap(bit(tmst.InputState,0)?enabled:disabled);
		if(bit(tmst.WarningState,1))
		{
			if(ui->checkBoxWarningZeroPosition2->isChecked())
				alarm();
			ui->labelZeroPosition2->setPixmap(alarmed);
		}
		else
			ui->labelZeroPosition2->setPixmap(bit(tmst.InputState,1)?enabled:disabled);
		if(bit(tmst.WarningState,2))
		{
			if(ui->checkBoxWarningZeroPosition3->isChecked())
				alarm();
			ui->labelZeroPosition3->setPixmap(alarmed);
		}
		else
			ui->labelZeroPosition3->setPixmap(bit(tmst.InputState,2)?enabled:disabled);
		if(bit(tmst.WarningState,3))
		{
			if(ui->checkBoxWarningZeroPosition4->isChecked())
				alarm();
			ui->labelZeroPosition4->setPixmap(alarmed);
		}
		else
			ui->labelZeroPosition4->setPixmap(bit(tmst.InputState,3)?enabled:disabled);
        if(bit(tmst.WarningState,4))
		{
			if(ui->checkBoxWarningAutoSeedSupply->isChecked())
				alarm();
			ui->labelAutoSeedSupply->setPixmap(alarmed);
		}
		else
            ui->labelAutoSeedSupply->setPixmap(bit(tmst.InputState,4)?enabled:disabled);
		if(bit(tmst.WarningState,5))
		{
			if(ui->checkBoxWarningReserve->isChecked())
				alarm();
			ui->labelReserve->setPixmap(alarmed);
		}
		else
			ui->labelReserve->setPixmap(bit(tmst.InputState,5)?enabled:disabled);
		if(bit(tmst.WarningState,6))
		{
			if(ui->checkBoxWarningCable1->isChecked())
				alarm();
			ui->labelCable1->setPixmap(alarmed);
		}
		else
			ui->labelCable1->setPixmap(bit(tmst.InputState,6)?enabled:disabled);
		if(bit(tmst.WarningState,7))
		{
			if(ui->checkBoxWarningCable2->isChecked())
				alarm();
			ui->labelCable2->setPixmap(alarmed);
		}
		else
			ui->labelCable2->setPixmap(bit(tmst.InputState,7)?enabled:disabled);
		if(bit(tmst.WarningState,8))
		{
			if(ui->checkBoxWarningPressure->isChecked())
				alarm();
			ui->labelPressure->setPixmap(alarmed);
		}
		else
			ui->labelPressure->setPixmap(bit(tmst.InputState,8)?enabled:disabled);
		if(bit(tmst.WarningState,9))
		{
			if(ui->checkBoxWarningBlower->isChecked())
				alarm();
			ui->labelBlower->setPixmap(alarmed);
		}
		else
			ui->labelBlower->setPixmap(bit(tmst.InputState,9)?enabled:disabled);
		if(bit(tmst.WarningState,10))
		{
			if(ui->checkBoxWarningPedal->isChecked())
				alarm();
			ui->labelPedal->setPixmap(alarmed);
		}
		else
			ui->labelPedal->setPixmap(bit(tmst.InputState,10)?enabled:disabled);
		if(bit(tmst.WarningState,11))
		{
			if(ui->checkBoxWarningInit->isChecked())
				alarm();
			ui->labelInit->setPixmap(alarmed);
		}
		else
			ui->labelInit->setPixmap(bit(tmst.InputState,11)?enabled:disabled);
		if(bit(tmst.WarningState,12))
		{
			if(ui->checkBoxWarningBeiDou->isChecked())
				alarm();
			ui->labelBeiDou->setPixmap(alarmed);
		}
		else
			ui->labelBeiDou->setPixmap(bit(tmst.InputState,12)?enabled:disabled);
        if(bit(tmst.WarningState,13))
        {
            if(ui->checkBoxWarningZeroPosition5->isChecked())
                alarm();
            ui->labelZeroPosition5->setPixmap(alarmed);
        }
        else
            ui->labelZeroPosition5->setPixmap(bit(tmst.InputState,13)?enabled:disabled);
        if(bit(tmst.WarningState,14))
        {
            if(ui->checkBoxWarningZeroPosition6->isChecked())
                alarm();
            ui->labelZeroPosition6->setPixmap(alarmed);
        }
        else
            ui->labelZeroPosition6->setPixmap(bit(tmst.InputState,14)?enabled:disabled);
		ui->labelEncoder->setText(QString::number((s32)tmst.EncoderCnt));
		ui->labelBeiDouSwitch->setText(QString::number((s32)tmst.BdCnt));
		QStandardItemModel *qsim=(QStandardItemModel *)ui->tableView->model();
        for(int i=0;i<maxSowColumn;i++)
		{
			qsim->item(i,LEAKSEEDCOLUMN)->setText(QString::number(tmst.LouZHCnt[i]));
			qsim->item(i,LEAKFERTILIZERCOLUMN)->setText(QString::number(tmst.LoufeiCnt[i]));
		}
        ui->pushButtonStepperMotor5->setIcon(bit(tmst.CtrlState,21)?enabled:disabled);
        ui->pushButtonStepperMotor6->setIcon(bit(tmst.CtrlState,22)?enabled:disabled);
		if(bit(tmst.WarningState,16))
		{
			if(ui->checkBoxWarningStepperMotor1->isChecked())
				alarm();
			ui->pushButtonStepperMotor1->setIcon(alarmed);
		}
		else
			ui->pushButtonStepperMotor1->setIcon(bit(tmst.CtrlState,16)?enabled:disabled);
		if(bit(tmst.WarningState,17))
		{
			if(ui->checkBoxWarningStepperMotor2->isChecked())
				alarm();
			ui->pushButtonStepperMotor2->setIcon(alarmed);
		}
		else
			ui->pushButtonStepperMotor2->setIcon(bit(tmst.CtrlState,17)?enabled:disabled);
		if(bit(tmst.WarningState,18))
		{
			if(ui->checkBoxWarningStepperMotor3->isChecked())
				alarm();
			ui->pushButtonStepperMotor3->setIcon(alarmed);
		}
		else
			ui->pushButtonStepperMotor3->setIcon(bit(tmst.CtrlState,18)?enabled:disabled);
		if(bit(tmst.WarningState,19))
		{
			if(ui->checkBoxWarningStepperMotor4->isChecked())
				alarm();
			ui->pushButtonStepperMotor4->setIcon(alarmed);
		}
		else
			ui->pushButtonStepperMotor4->setIcon(bit(tmst.CtrlState,19)?enabled:disabled);
		if(bit(tmst.WarningState,20))
		{
			if(ui->checkBoxWarningAutoSeedSupplyMotor->isChecked())
				alarm();
			ui->pushButtonAutoSeedSupplyMotor->setIcon(alarmed);
		}
		else
			ui->pushButtonAutoSeedSupplyMotor->setIcon(bit(tmst.CtrlState,20)?enabled:disabled);
        ui->pushButtonPreDropSeed->setIcon(bit(tmst.CtrlState,0)?enabled:disabled);
		ui->pushButtonDumpSeed->setIcon(bit(tmst.CtrlState,1)?enabled:disabled);
		ui->pushButtonClearSeed->setIcon(bit(tmst.CtrlState,2)?enabled:disabled);
        ui->pushButtonScrapeSeed->setIcon(bit(tmst.CtrlState,3)?enabled:disabled);
		ui->pushButtonReserve1->setIcon(bit(tmst.CtrlState,4)?enabled:disabled);
		ui->pushButtonReserve2->setIcon(bit(tmst.CtrlState,5)?enabled:disabled);
		ui->pushButtonHorn->setIcon(bit(tmst.CtrlState,6)?enabled:disabled);
		ui->pushButtonTapper->setIcon(bit(tmst.CtrlState,7)?enabled:disabled);
		ui->pushButtonWarningLight->setIcon(bit(tmst.CtrlState,8)?enabled:disabled);
		ui->pushButtonRunningStateLight->setIcon(bit(tmst.CtrlState,9)?enabled:disabled);
	});
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(TESTWARNINGGROUP);
	ui->checkBoxWarningZeroPosition1->setCheckState(iniFile.value("ZeroPosition1").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningZeroPosition2->setCheckState(iniFile.value("ZeroPosition2").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningZeroPosition3->setCheckState(iniFile.value("ZeroPosition3").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningZeroPosition4->setCheckState(iniFile.value("ZeroPosition4").toBool()?Qt::Checked:Qt::Unchecked);
    ui->checkBoxWarningZeroPosition5->setCheckState(iniFile.value("ZeroPosition5").toBool()?Qt::Checked:Qt::Unchecked);
    ui->checkBoxWarningZeroPosition6->setCheckState(iniFile.value("ZeroPosition6").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningAutoSeedSupply->setCheckState(iniFile.value("AutoSeedSupply").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningReserve->setCheckState(iniFile.value("Reserve").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningCable1->setCheckState(iniFile.value("Cable1").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningCable2->setCheckState(iniFile.value("Cable2").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningPressure->setCheckState(iniFile.value("Pressure").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningBlower->setCheckState(iniFile.value("Blower").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningPedal->setCheckState(iniFile.value("Pedal").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningInit->setCheckState(iniFile.value("Init").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningBeiDou->setCheckState(iniFile.value("BeiDou").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningStepperMotor1->setCheckState(iniFile.value("StepperMotor1").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningStepperMotor2->setCheckState(iniFile.value("StepperMotor2").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningStepperMotor3->setCheckState(iniFile.value("StepperMotor3").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningStepperMotor4->setCheckState(iniFile.value("StepperMotor4").toBool()?Qt::Checked:Qt::Unchecked);
    ui->checkBoxWarningStepperMotor5->setCheckState(iniFile.value("StepperMotor5").toBool()?Qt::Checked:Qt::Unchecked);
    ui->checkBoxWarningStepperMotor6->setCheckState(iniFile.value("StepperMotor6").toBool()?Qt::Checked:Qt::Unchecked);
	ui->checkBoxWarningAutoSeedSupplyMotor->setCheckState(iniFile.value("AutoSeedSupplyMotor").toBool()?Qt::Checked:Qt::Unchecked);
	iniFile.endGroup();
	connect(ui->checkBoxWarningZeroPosition1,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("ZeroPosition1",state);
	});
	connect(ui->checkBoxWarningZeroPosition2,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("ZeroPosition2",state);
	});
	connect(ui->checkBoxWarningZeroPosition3,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("ZeroPosition3",state);
	});
	connect(ui->checkBoxWarningZeroPosition4,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("ZeroPosition4",state);
	});
    connect(ui->checkBoxWarningZeroPosition5,&QCheckBox::stateChanged,this,[=](int state){
        setWarningEnabled("ZeroPosition5",state);
    });
    connect(ui->checkBoxWarningZeroPosition6,&QCheckBox::stateChanged,this,[=](int state){
        setWarningEnabled("ZeroPosition6",state);
    });
	connect(ui->checkBoxWarningAutoSeedSupply,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("AutoSeedSupply",state);
	});
	connect(ui->checkBoxWarningReserve,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("Reserve",state);
	});
	connect(ui->checkBoxWarningCable1,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("Cable1",state);
	});
	connect(ui->checkBoxWarningCable2,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("Cable2",state);
	});
	connect(ui->checkBoxWarningPressure,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("ZeroPressure",state);
	});
	connect(ui->checkBoxWarningBlower,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("Blower",state);
	});
	connect(ui->checkBoxWarningPedal,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("Pedal",state);
	});
	connect(ui->checkBoxWarningInit,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("Init",state);
	});
	connect(ui->checkBoxWarningInit,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("BeiDou",state);
	});
	connect(ui->checkBoxWarningStepperMotor1,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("StepperMotor1",state);
	});
	connect(ui->checkBoxWarningStepperMotor2,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("StepperMotor2",state);
	});
	connect(ui->checkBoxWarningStepperMotor3,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("StepperMotor3",state);
	});
	connect(ui->checkBoxWarningStepperMotor4,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("StepperMotor4",state);
	});
    connect(ui->checkBoxWarningStepperMotor5,&QCheckBox::stateChanged,this,[=](int state){
        setWarningEnabled("StepperMotor5",state);
    });
    connect(ui->checkBoxWarningStepperMotor6,&QCheckBox::stateChanged,this,[=](int state){
        setWarningEnabled("StepperMotor6",state);
    });
	connect(ui->checkBoxWarningAutoSeedSupplyMotor,&QCheckBox::stateChanged,this,[=](int state){
		setWarningEnabled("AutoSeedSupplyMotor",state);
	});
    connect(ui->pushButtonPreDropSeed,&QPushButton::clicked,this,[=,&c]{
        c.setValveState(0,!bit(state.CtrlState,0));
    });
    connect(ui->pushButtonDumpSeed,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(1,!bit(state.CtrlState,1));
	});
    connect(ui->pushButtonClearSeed,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(2,!bit(state.CtrlState,2));
	});
    connect(ui->pushButtonScrapeSeed,&QPushButton::clicked,this,[=,&c]{
        c.setValveState(3,!bit(state.CtrlState,3));
    });
    connect(ui->pushButtonReserve1,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(4,!bit(state.CtrlState,4));
	});
    connect(ui->pushButtonReserve2,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(5,!bit(state.CtrlState,5));
	});
    connect(ui->pushButtonHorn,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(6,!bit(state.CtrlState,6));
	});
    connect(ui->pushButtonTapper,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(7,!bit(state.CtrlState,7));
	});
    connect(ui->pushButtonWarningLight,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(8,!bit(state.CtrlState,8));
	});
    connect(ui->pushButtonRunningStateLight,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(9,!bit(state.CtrlState,9));
	});
    connect(ui->pushButtonStepperMotor1,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(16,!bit(state.CtrlState,16));
	});
    connect(ui->pushButtonStepperMotor2,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(17,!bit(state.CtrlState,17));
	});
    connect(ui->pushButtonStepperMotor3,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(18,!bit(state.CtrlState,18));
	});
    connect(ui->pushButtonStepperMotor4,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(19,!bit(state.CtrlState,19));
	});
    connect(ui->pushButtonAutoSeedSupplyMotor,&QPushButton::clicked,this,[=,&c]{
		c.setValveState(20,!bit(state.CtrlState,20));
	});
    connect(ui->pushButtonStepperMotor5,&QPushButton::clicked,this,[=,&c]{
        c.setValveState(21,!bit(state.CtrlState,21));
    });
    connect(ui->pushButtonStepperMotor6,&QPushButton::clicked,this,[=,&c]{
        c.setValveState(22,!bit(state.CtrlState,22));
    });
}

FormTest::~FormTest()
{
	delete ui;
}

void FormTest::alarm()
{

}

void FormTest::setWarningEnabled(QString setting,int checkState)
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(TESTWARNINGGROUP);
	switch(checkState)
	{
	case Qt::Unchecked:
		iniFile.setValue(setting,false);
		break;
	case Qt::Checked:
		iniFile.setValue(setting,true);
		break;
	default:;
	}
	iniFile.endGroup();
	iniFile.sync();
}

void FormTest::exitTestMode()
{
	c.exitTestMode();
}

void FormTest::enterTestMode()
{
	c.setUserParameter(getUserParameterFromSetting(),TEST);
}

void FormTest::slotDeviceConfigUpdated()
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
	bool show56=(maxSowColumn>=6);
	ui->label_5->setVisible(show56);
	ui->label_6->setVisible(show56);
    ui->label_7->setVisible(show56);
    ui->label_8->setVisible(show56);
	ui->pushButtonStepperMotor5->setVisible(show56);
	ui->pushButtonStepperMotor6->setVisible(show56);
	ui->checkBoxWarningStepperMotor5->setVisible(show56);
	ui->checkBoxWarningStepperMotor6->setVisible(show56);
	ui->labelZeroPosition5->setVisible(show56);
	ui->labelZeroPosition6->setVisible(show56);
	ui->checkBoxWarningZeroPosition5->setVisible(show56);
	ui->checkBoxWarningZeroPosition6->setVisible(show56);
}
