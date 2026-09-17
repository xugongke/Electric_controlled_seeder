#include "formconfig.h"
#include "ui_formconfig.h"
#include <QSettings>
#include "global.h"
#include <QTextCodec>
#include <QSerialPortInfo>
#include "dialog/dialogconfigverification.h"
#include <QStandardItem>
#include <cmath>
#include <QListView>
#include <QMessageBox>
#include "delegate/spinboxdelegate.h"

FormConfig::FormConfig(Communication &c,QWidget *parent) :
    QStackedWidget(parent),
    ui(new Ui::FormConfig),c(c)
{
	ui->setupUi(this);
    setTouchable(ui->tableViewSeedGapFineTuning);
	ui->comboBoxSerialPort->setSizeAdjustPolicy(QComboBox::AdjustToContents);
    ui->comboBoxSerialPort->setView(new QListView);
    ui->comboBoxEncoderDirection->setView(new QListView);
    ui->comboBoxMachineColumnCount->setView(new QListView);
    ui->comboBoxDeviceType->setView(new QListView);
    connect(ui->comboBoxDeviceType,&QComboBox::currentTextChanged,this,[=](const QString &text){
        ui->comboBoxMachineColumnCount->clear();
        ui->comboBoxMachineColumnCount->addItems(BlockColumnCountMap[text]);

    });
    ui->comboBoxDeviceType->addItems(BlockColumnCountMap.keys());
    int mainVersion=0,subVersion=5,fix=0;
    QString date="2026.8.17";
    ui->labelVersion->setText(QString::number(mainVersion)+"."+QString::number(subVersion)+"."+QString::number(fix)+"("+date+")");
    slotPushButtonRefreshPortClicked();
    connect(ui->pushButtonRefreshPort,&QPushButton::clicked,this,&FormConfig::slotPushButtonRefreshPortClicked);
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(APPLICATIONGROUP);
    connect(ui->comboBoxSerialPort,&QComboBox::currentTextChanged,this,&FormConfig::slotComboBoxSerialPortCurrentTextChanged);
	int alpha=100-iniFile.value("Alpha",128).toInt()*100/255;
	ui->horizontalSlider->setValue(alpha);
	connect(ui->horizontalSlider,&QSlider::valueChanged,this,[=](int value){
		ui->labelAlpha->setNum(value);
	});
	if(alpha==ui->horizontalSlider->value())
		ui->labelAlpha->setNum(alpha);
    ui->comboBoxBlockColumnCount->addItems(BlockColumnCountMap[iniFile.value("DeviceType","4行机").toString()]);
    ui->tableViewSeedGapFineTuning->setItemDelegateForColumn(1,new SpinBoxDelegate);
    QStandardItemModel *qsim=new QStandardItemModel;
    ui->tableViewSeedGapFineTuning->setModel(qsim);
    qsim->setHorizontalHeaderLabels({
        "原密度","新密度"
    });
    for(int i=0,s=iniFile.beginReadArray(SEEDGAPFINETUNINGARRAY);i<s;qsim->setItem(i++,1,new QStandardItem(iniFile.value("SpecifiedDensity").toString())))
    {
        iniFile.setArrayIndex(i);
        QStandardItem *qsi=new QStandardItem(iniFile.value("OriginDensity").toString());
        qsi->setEditable(false);
        qsi->setCheckable(true);
        qsi->setCheckState(iniFile.value("Enabled").toInt()==0?Qt::Unchecked:Qt::Checked);
        qsim->setItem(i,0,qsi);
    }
    iniFile.endArray();
    ui->tableViewSeedGapFineTuning->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    ui->tableViewSeedGapFineTuning->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    ui->doubleSpinBoxDropSeedTime->setValue(iniFile.value("DropSeedTime").toFloat()/1000);
    ui->doubleSpinBoxSeedColumnGap->setValue(iniFile.value("SeedColumnGap").toFloat()/100);
    ui->spinBoxRpm->setValue(iniFile.value("Rpm").toInt());
    ui->comboBoxNavigationAntenna->setCurrentIndex(iniFile.value("NavigationAntenna").toInt());
    ui->doubleSpinBoxAntennaDistance->setValue(iniFile.value("AntennaDistance").toFloat()/100);
    slotComboBoxNavigationAntennaCurrentTextChanged(ui->comboBoxNavigationAntenna->currentText());
    connect(ui->comboBoxNavigationAntenna,&QComboBox::currentTextChanged,this,&FormConfig::slotComboBoxNavigationAntennaCurrentTextChanged);
    ui->comboBoxGapPoint->setCurrentText(iniFile.value("GapPoint","开").toString());
    iniFile.endGroup();
    iniFile.beginGroup(DEVICEGROUP);
    ui->comboBoxMachineColumnCount->setCurrentText(iniFile.value("MachineColumnCount").toString());
    ui->doubleSpinBoxDropPortDistance->setValue(iniFile.value("dropPortDistance").toFloat()/100);
    ui->doubleSpinBoxSeedDropDistance->setValue(iniFile.value("SeedDropDistance").toFloat()/100);
    ui->spinBoxTransmissionRatio->setValue(iniFile.value("TransmissionRatio").toInt());
    ui->spinBoxGearRatio->setValue(iniFile.value("GearRatio").toInt());
    ui->comboBoxEncoderDirection->setCurrentText(iniFile.value("EncoderDirection").toString());
    ui->spinBoxSowRouletteHole->setValue(iniFile.value("SowRouletteHole").toInt());
    ui->checkBoxZeroSwitch->setCheckState(iniFile.value("ZeroSwitch").toInt()>0?Qt::Checked:Qt::Unchecked);
    ui->spinBoxMicroStepValue->setValue(iniFile.value("MicroStepValue").toInt());
    ui->doubleSpinBoxX1->setValue(iniFile.value("X1").toFloat()/100);
    ui->doubleSpinBoxBDiroff->setValue(iniFile.value("BDiroff").toFloat()/100);
    ui->doubleSpinBoxTappTrigOff->setValue(iniFile.value("TappTrigOff").toFloat()/100);
    ui->doubleSpinBoxTapperTime->setValue(iniFile.value("TapperTime").toFloat()/1000);
    ui->spinBoxPrePercent->setValue(iniFile.value("PrePercent",70).toInt());
    ui->checkBoxScrapeSeed->setCheckState(iniFile.value("ScrapeSeed").toInt()>0?Qt::Checked:Qt::Unchecked);
    ui->comboBoxDeviceType->setCurrentText(iniFile.value("DeviceType",BlockColumnCountMap.keys()[0]).toString());
    iniFile.endGroup();
    connect(ui->pushButtonSaveApplication,&QPushButton::clicked,this,[=]{
//        if(ui->comboBoxSerialPort->currentText().isEmpty())
//        {
//            QMessageBox::information(this,"提示","串口不能为空");
//            return;
//        }
        QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
        iniFile.beginGroup(APPLICATIONGROUP);
		iniFile.setValue("Alpha",round(255*(100-ui->horizontalSlider->value())/100.0));
        iniFile.setValue("BlockColumnCount",ui->comboBoxBlockColumnCount->currentText());
        int s=iniFile.beginReadArray(SEEDGAPFINETUNINGARRAY);
        iniFile.endArray();
        iniFile.beginWriteArray(SEEDGAPFINETUNINGARRAY);
        for(int i=0;i<s;iniFile.setValue("SpecifiedDensity",qsim->item(i++,1)->text().toInt()))
        {
            iniFile.setArrayIndex(i);
            switch(qsim->item(i,0)->checkState())
            {
            case Qt::Unchecked:
                iniFile.setValue("Enabled",0);
                break;
            case Qt::Checked:
                iniFile.setValue("Enabled",1);
                break;
            default:;
            }
        }
        iniFile.endArray();
        iniFile.setValue("DropSeedTime",ui->doubleSpinBoxDropSeedTime->value()*1000);
        iniFile.setValue("SeedColumnGap",ui->doubleSpinBoxSeedColumnGap->value()*100);
        iniFile.setValue("Rpm",ui->spinBoxRpm->value());
        iniFile.setValue("NavigationAntenna",ui->comboBoxNavigationAntenna->currentIndex());
        iniFile.setValue("AntennaDistance",ui->doubleSpinBoxAntennaDistance->value()*100);
        iniFile.setValue("GapPoint",ui->comboBoxGapPoint->currentText());
        iniFile.endGroup();
        iniFile.sync();
        emit signalAppConfigUpdated();
    });
    connect(ui->pushButtonSaveDevice,&QPushButton::clicked,this,[=]{
        QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
        iniFile.beginGroup(DEVICEGROUP);
        iniFile.setValue("MachineColumnCount",ui->comboBoxMachineColumnCount->currentText());
        iniFile.setValue("DropPortDistance",ui->doubleSpinBoxDropPortDistance->value()*100);
        iniFile.setValue("SeedDropDistance",ui->doubleSpinBoxSeedDropDistance->value()*100);
        iniFile.setValue("TransmissionRatio",ui->spinBoxTransmissionRatio->value());
        iniFile.setValue("EncoderDirection",ui->comboBoxEncoderDirection->currentText()=="正"?0:1);
        iniFile.setValue("SowRouletteHole",ui->spinBoxSowRouletteHole->value());
        switch(ui->checkBoxZeroSwitch->checkState())
        {
        case Qt::Unchecked:
            iniFile.setValue("ZeroSwitch",0);
            break;
        case Qt::Checked:
            iniFile.setValue("ZeroSwitch",1);
            break;
        default:;
        }
        iniFile.setValue("GearRatio",ui->spinBoxGearRatio->value());
        iniFile.setValue("MicroStepValue",ui->spinBoxMicroStepValue->value());
        iniFile.setValue("X1",ui->doubleSpinBoxX1->value()*100);
        iniFile.setValue("BDiroff",ui->doubleSpinBoxBDiroff->value()*100);
        iniFile.setValue("TappTrigOff",ui->doubleSpinBoxTappTrigOff->value()*100);
        iniFile.setValue("TapperTime",ui->doubleSpinBoxTapperTime->value()*1000);
        iniFile.setValue("PrePercent",ui->spinBoxPrePercent->value());
        switch(ui->checkBoxScrapeSeed->checkState())
        {
        case Qt::Unchecked:
            iniFile.setValue("ScrapeSeed",0);
            break;
        case Qt::Checked:
            iniFile.setValue("ScrapeSeed",1);
            break;
        default:;
        }
        iniFile.setValue("DeviceType",ui->comboBoxDeviceType->currentText());
        iniFile.endGroup();
        iniFile.sync();
        emit signalDeviceConfigUpdated();
    });
    connect(ui->pushButtonBackgroungConfig,&QPushButton::clicked,this,[=]{
#ifdef QT_DEBUG
        setCurrentIndex(1);
#else
        DialogConfigVerification dcv(this);
        if(dcv.exec()==QDialog::Accepted&&dcv.password()=="515516")
            setCurrentIndex(1);
#endif
    });
    connect(ui->pushButtonBack,&QPushButton::clicked,this,[=]{
        setCurrentIndex(0);
    });
    connect(ui->pushButtonReset,&QPushButton::clicked,this,[=]{
        if(QMessageBox::question(this,"提示","确定要重置用户参数吗？")==QMessageBox::No)
            return;
        ui->doubleSpinBoxDropSeedTime->setValue(1.5);
        ui->doubleSpinBoxSeedColumnGap->setValue(0.6);
        ui->spinBoxRpm->setValue(36);
        QStandardItemModel *qsim=(QStandardItemModel *)ui->tableViewSeedGapFineTuning->model();
        for(int i=0;i<qsim->rowCount();)
        {
            QStandardItem *qsi=qsim->item(i,0);
            qsi->setCheckState(Qt::Unchecked);
            qsim->item(i++,1)->setText(qsi->text());
        }
        ui->comboBoxNavigationAntenna->setCurrentIndex(0);
        ui->doubleSpinBoxAntennaDistance->setValue(0);
        ui->comboBoxGapPoint->setCurrentIndex(0);
    });
    connect(ui->pushButtonReset2,&QPushButton::clicked,this,[=]{
        if(QMessageBox::question(this,"提示","确定要重置厂家参数吗？")==QMessageBox::No)
            return;
        ui->doubleSpinBoxDropPortDistance->setValue(0.6);
        ui->doubleSpinBoxSeedDropDistance->setValue(0.9);
        ui->spinBoxTransmissionRatio->setValue(2000);
        ui->comboBoxEncoderDirection->setCurrentText("正");
        ui->spinBoxSowRouletteHole->setValue(9);
        ui->spinBoxGearRatio->setValue(5);
        ui->checkBoxZeroSwitch->setCheckState(Qt::Checked);
        ui->spinBoxMicroStepValue->setValue(800);
        ui->doubleSpinBoxX1->setValue(1.5);
        ui->doubleSpinBoxBDiroff->setValue(0);
        ui->doubleSpinBoxTappTrigOff->setValue(0.2);
        ui->doubleSpinBoxTapperTime->setValue(0.1);
        ui->spinBoxPrePercent->setValue(70);
		ui->horizontalSlider->setValue(128);
        ui->comboBoxBlockColumnCount->setCurrentText("4");
        ui->checkBoxScrapeSeed->setCheckState(Qt::Checked);
        ui->comboBoxDeviceType->setCurrentIndex(0);
    });
    connect(&timer,&QTimer::timeout,this,&FormConfig::slotTimerTimeout);
    connect(&c,&Communication::signalPortConnected,this,[=]{
        timer.stop();
    });
    connect(&c,&Communication::signalPortDisconnected,this,[=]{
        slotPushButtonRefreshPortClicked();
        timer.start(3000);
    });
    slotTimerTimeout();
}

FormConfig::~FormConfig()
{
	delete ui;
}

void FormConfig::slotPushButtonRefreshPortClicked()
{
	QStringList qsl;
	foreach(const QSerialPortInfo &Info,QSerialPortInfo::availablePorts())
		qsl.push_back(Info.portName());
	qsl.sort();
	disconnect(ui->comboBoxSerialPort,&QComboBox::currentTextChanged,this,&FormConfig::slotComboBoxSerialPortCurrentTextChanged);
	ui->comboBoxSerialPort->clear();
    ui->comboBoxSerialPort->addItem("");
	ui->comboBoxSerialPort->addItems(qsl);
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(APPLICATIONGROUP);
    port=iniFile.value("SerialPort").toString();
    ui->comboBoxSerialPort->setCurrentText(port);
	iniFile.endGroup();
	connect(ui->comboBoxSerialPort,&QComboBox::currentTextChanged,this,&FormConfig::slotComboBoxSerialPortCurrentTextChanged);
    ui->comboBoxSerialPort->adjustSize();
}

void FormConfig::slotComboBoxSerialPortCurrentTextChanged(const QString &text)
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(APPLICATIONGROUP);
	iniFile.setValue("SerialPort",text);
    port=text;
	iniFile.endGroup();
	c.closePort();
	c.openPort();
}

void FormConfig::slotComboBoxNavigationAntennaCurrentTextChanged(const QString &text)
{
    bool b=text=="双";
    ui->label_8->setVisible(b);
    ui->doubleSpinBoxAntennaDistance->setVisible(b);
}

void FormConfig::slotTimerTimeout()
{
    if(ui->comboBoxSerialPort->currentText()!=port)
        timer.start(3000);
}
