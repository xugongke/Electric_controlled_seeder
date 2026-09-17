#include "formsetting.h"
#include "ui_formsetting.h"
#include <QSettings>
#include "global.h"
#include <QTextCodec>
#include <QFile>
#include <QDebug>
#include <QSerialPortInfo>
#include "uart/threaduart.h"
#include <cmath>
#include <QListView>
#include "tools/settingshandle.h"

#define ICONWIDTH 50
#define ICONHEIGHT 50

FormSetting::FormSetting(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormSetting)
{
    ui->setupUi(this);
	//设置
    ui->comboBoxPort->setView(new QListView);
    connect(ui->pushButtonRefreshPort,&QPushButton::clicked,this,&FormSetting::slotPushButtonRefreshPortClicked);
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    connect(ui->comboBoxPort,&QComboBox::currentTextChanged,this,&FormSetting::slotComboBoxSerialPortCurrentTextChanged);
    ui->comboBoxPort->setCurrentText(iniFile.value("Port").toString());
	int alpha=100-iniFile.value("Alpha",128).toInt()*100/255;
	ui->horizontalSlider->setValue(alpha);
	connect(ui->horizontalSlider,&QSlider::valueChanged,this,[=](int value){
		ui->labelAlpha->setNum(value);
	});
	if(alpha==ui->horizontalSlider->value())
		ui->labelAlpha->setNum(alpha);
    connect(ui->comboBoxMoistureSensor,&QComboBox::currentTextChanged,this,[=](const QString &text){
        ui->comboBoxMoistureValueMode->clear();
        ui->comboBoxMoistureValueMode->addItems(moistureSensorModeMap[text]);
    });
    ui->comboBoxMeasureColumnCount->setCurrentText(iniFile.value("MeasureColumnCount").toString());
    ui->doubleSpinBoxBigBin1FlowTime->setValue(iniFile.value("BigBin1FlowTime").toDouble());
    ui->doubleSpinBoxBigBin2FlowTime->setValue(iniFile.value("BigBin2FlowTime").toDouble());
    ui->doubleSpinBoxBigBinFlowEndTime->setValue(iniFile.value("BigBinFlowEndTime").toDouble());
    ui->doubleSpinBoxUnitWeightBinFlowTime->setValue(iniFile.value("UnitWeightBinFlowTime").toDouble());
    ui->doubleSpinBoxUnitWeightBinFlowEndTime->setValue(iniFile.value("UnitWeightBinFlowEndTime").toDouble());
    ui->doubleSpinBoxUnitWeightBinDetachTime->setValue(iniFile.value("UnitWeightBinDetachTime").toDouble());
    ui->doubleSpinBoxUnitWeightBinRepositionTime->setValue(iniFile.value("UnitWeightBinRepositionTime").toDouble());
    ui->doubleSpinBoxDropTime->setValue(iniFile.value("DropTime").toDouble());
    ui->doubleSpinBoxDropEndTime->setValue(iniFile.value("DropEndTime").toDouble());
    ui->doubleSpinBoxUnitWeightBucketVolumn->setValue(iniFile.value("UnitWeightBucketVolumn").toDouble());
    for(std::map<QString,QStringList>::iterator i=moistureSensorModeMap.begin();i!=moistureSensorModeMap.end();ui->comboBoxMoistureSensor->addItem(i++->first));
    ui->comboBoxMoistureSensor->setCurrentText(iniFile.value("MoistureSensor").toString());
    ui->comboBoxMoistureValueMode->setCurrentText(iniFile.value("MoistureValueMode").toString());
    ui->comboBoxRealtimeMoistureCalibrationTransformMode->addItems(cropList);
    ui->comboBoxRealtimeMoistureCalibrationTransformMode->setCurrentText(iniFile.value("RealtimeMoistureCalibrationTransformMode").toString());
    ui->doubleSpinBoxMaxMoisture->setValue(iniFile.value("MaxMoisture").toFloat());
    iniFile.endGroup();
    connect(ui->pushButtonReset,&QPushButton::clicked,this,[=]{
        ui->comboBoxMeasureColumnCount->setCurrentIndex(0);
        ui->doubleSpinBoxBigBin1FlowTime->setValue(1.5);
        ui->doubleSpinBoxBigBin2FlowTime->setValue(1.5);
        ui->doubleSpinBoxBigBinFlowEndTime->setValue(1.5);
        ui->doubleSpinBoxUnitWeightBinFlowTime->setValue(1);
        ui->doubleSpinBoxUnitWeightBinFlowEndTime->setValue(0.2);
        ui->doubleSpinBoxUnitWeightBinDetachTime->setValue(1.5);
        ui->doubleSpinBoxUnitWeightBinRepositionTime->setValue(0.2);
        ui->doubleSpinBoxDropTime->setValue(1.5);
        ui->doubleSpinBoxDropEndTime->setValue(0.4);
        ui->doubleSpinBoxUnitWeightBucketVolumn->setValue(2);
    });
    connect(ui->pushButtonSaveConfig,&QPushButton::clicked,this,[=]{
        QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
        iniFile.beginGroup(APPLICATIONGROUP);
        iniFile.setValue("MeasureColumnCount",ui->comboBoxMeasureColumnCount->currentText());
        iniFile.setValue("BigBin1FlowTime",ui->doubleSpinBoxBigBin1FlowTime->value());
        iniFile.setValue("BigBin2FlowTime",ui->doubleSpinBoxBigBin1FlowTime->value());
        iniFile.setValue("BigBinFlowEndTime",ui->doubleSpinBoxBigBinFlowEndTime->value());
        iniFile.setValue("UnitWeightBinFlowTime",ui->doubleSpinBoxUnitWeightBinFlowTime->value());
        iniFile.setValue("UnitWeightBinFlowEndTime",ui->doubleSpinBoxUnitWeightBinFlowEndTime->value());
        iniFile.setValue("UnitWeightBinDetachTime",ui->doubleSpinBoxUnitWeightBinDetachTime->value());
        iniFile.setValue("UnitWeightBinRepositionTime",ui->doubleSpinBoxUnitWeightBinRepositionTime->value());
        iniFile.setValue("DropTime",ui->doubleSpinBoxDropTime->value());
        iniFile.setValue("DropEndTime",ui->doubleSpinBoxDropEndTime->value());
        iniFile.setValue("UnitWeightBucketVolumn",ui->doubleSpinBoxUnitWeightBucketVolumn->value());
        iniFile.setValue("MoistureSensor",ui->comboBoxMoistureSensor->currentText());
        iniFile.setValue("MoistureValueMode",ui->comboBoxMoistureValueMode->currentText());
        iniFile.setValue("RealtimeMoistureCalibrationTransformMode",ui->comboBoxRealtimeMoistureCalibrationTransformMode->currentText());
		iniFile.setValue("Alpha",round(255*(100-ui->horizontalSlider->value())/100.0));
        iniFile.setValue("MaxMoisture",ui->doubleSpinBoxMaxMoisture->value());
        iniFile.endGroup();
        iniFile.beginGroup(DEVICEGROUP);
        iniFile.endGroup();
        iniFile.sync();
        emit signalSettingsUpdated();
    });
    connect(ui->pushButtonValve1,&QPushButton::clicked,this,[=]{
        setValve((G.valveState&1)>0?G.valveState&~1:G.valveState|1);
    });
    connect(ui->pushButtonValve2,&QPushButton::clicked,this,[=]{
        setValve((G.valveState&2)>0?G.valveState&~2:G.valveState|2);
    });
    connect(ui->pushButtonValve3,&QPushButton::clicked,this,[=]{
        setValve((G.valveState&4)>0?G.valveState&~4:G.valveState|4);
    });
    connect(ui->pushButtonValve4,&QPushButton::clicked,this,[=]{
        setValve((G.valveState&8)>0?G.valveState&~8:G.valveState|8);
    });
    connect(ui->pushButtonValve5,&QPushButton::clicked,this,[=]{
        setValve((G.valveState&16)>0?G.valveState&~16:G.valveState|16);
    });
    ui->pushButtonValve1->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    ui->pushButtonValve2->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    ui->pushButtonValve3->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    ui->pushButtonValve4->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    ui->pushButtonValve5->setIconSize(QSize(ICONWIDTH,ICONHEIGHT));
    slotPushButtonRefreshPortClicked();
    ui->comboBoxPort->setSizeAdjustPolicy(QComboBox::AdjustToContents);
}

FormSetting::~FormSetting()
{
	delete ui;
}

void FormSetting::slotValveStateUpdated()
{
    ui->pushButtonValve1->setIcon(QIcon((G.valveState&1)>0?":/resources/images/enabled.png":":/resources/images/disabled.png"));
    ui->pushButtonValve2->setIcon(QIcon((G.valveState&2)>0?":/resources/images/enabled.png":":/resources/images/disabled.png"));
    ui->pushButtonValve3->setIcon(QIcon((G.valveState&4)>0?":/resources/images/enabled.png":":/resources/images/disabled.png"));
    ui->pushButtonValve4->setIcon(QIcon((G.valveState&8)>0?":/resources/images/enabled.png":":/resources/images/disabled.png"));
    ui->pushButtonValve5->setIcon(QIcon((G.valveState&16)>0?":/resources/images/enabled.png":":/resources/images/disabled.png"));
}

void FormSetting::slotPushButtonRefreshPortClicked()
{
    QStringList qsl;
    foreach(const QSerialPortInfo &Info,QSerialPortInfo::availablePorts())
        qsl.push_back(Info.portName());
    qsl.sort();
    disconnect(ui->comboBoxPort,&QComboBox::currentTextChanged,this,&FormSetting::slotComboBoxSerialPortCurrentTextChanged);
    ui->comboBoxPort->clear();
    ui->comboBoxPort->addItem("");
    ui->comboBoxPort->addItems(qsl);
    ui->comboBoxPort->setCurrentText(getPort());
	connect(ui->comboBoxPort,&QComboBox::currentTextChanged,this,&FormSetting::slotComboBoxSerialPortCurrentTextChanged);
}

void FormSetting::slotComboBoxSerialPortCurrentTextChanged(const QString &text)
{
    setPort(text);
    port=text;
    G.tUart->threadStop();
    G.tUart->threadCreate();
}
