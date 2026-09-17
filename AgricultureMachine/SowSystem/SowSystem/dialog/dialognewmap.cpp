#include "dialognewmap.h"
#include "ui_dialognewmap.h"
#include <QMessageBox>
#include <QDateTime>
#include <QDebug>
#include "../../common/database.h"
#include "../../common/map.h"
#include "global.h"
#include <QSettings>
#include <QTextCodec>
#include <QListView>

DialogNewMap::DialogNewMap(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogNewMap)
{
	ui->setupUi(this);
	setFocus();
	ui->comboBoxBlockColumnCount->setView(new QListView);
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(APPLICATIONGROUP);
	QVariant qv=iniFile.value("BlockColumnCount");
	ui->labelSeedColumnGap->setText(QString::number(iniFile.value("SeedColumnGap").toFloat()/100)+"m");
	iniFile.endGroup();
	iniFile.beginGroup(DEVICEGROUP);
    int machineColumn=iniFile.value("MachineColumnCount").toInt();
    ui->labelMachineColumnCount->setNum(machineColumn);
    ui->labelBlockEachTime->setNum(machineColumn/qv.toInt());
    ui->comboBoxBlockColumnCount->addItems(BlockColumnCountMap[iniFile.value("DeviceType","4行机").toString()]);
    ui->comboBoxBlockColumnCount->setCurrentText(qv.toString());
	iniFile.endGroup();
	connect(ui->comboBoxBlockColumnCount,&QComboBox::currentTextChanged,this,[=](const QString &text){
		QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
		iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
        iniFile.beginGroup(DEVICEGROUP);
        ui->labelBlockEachTime->setNum(machineColumn/text.toInt());
		iniFile.endGroup();
	});
	connect(ui->pushButtonOk,&QPushButton::clicked,this,[=]{
		map=ui->lineEditName->text();
		if(map.isEmpty())
		{
			QMessageBox::information(this,"提示","地图名不能为空");
			return;
		}
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("SELECT Name FROM "+MAPTABLE+" WHERE Name=?");
		qsq.addBindValue(map);
		qsq.exec();
		if(qsq.next())
		{
			QMessageBox::information(this,"提示","已有同名地图存在");
			d.close();
			return;
		}
		d.close();
        if(ui->labelBlockEachTime->text()=="0")
        {
            QMessageBox::information(this,"提示","每次播种小区不能为0");
            return;
        }
		Map m;
		m.name=map;
		RowAttributes ra;
		ra.length=ui->doubleSpinBoxRowLength->value()*100;
		Aisle a;
		a.length=ui->doubleSpinBoxAisleLength->value()*100;
        for(int i=0;i++<ui->spinBoxRowCount->value();m.aisleVector.push_back(a))
		{
			std::vector<Block> bv;
            for(int j=0;j++<ui->spinBoxColumnCount->value();)
			{
				Block b;
				b.density=ui->spinBoxDensity->value();
				b.sowSeed=true;
                b.updateFlag=false;
				bv.push_back(b);
			}
			m.blockVector.push_back(bv);
			m.rowAttributesVector.push_back(ra);
        }
        m.blockColumn=ui->comboBoxBlockColumnCount->currentText().toInt();
        QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
        iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
        iniFile.beginGroup(DEVICEGROUP);
        m.machineColumn=iniFile.value("MachineColumnCount").toInt();
        iniFile.endGroup();
        if(m.blockVector[0].size()%(m.machineColumn/m.blockColumn)>0)
        {
            QMessageBox::information(this,"提示","总列数需为每趟播种小区的正整数倍");
            return;
        }
		m.aisleVector.push_back(a);
		m.mark=ui->textEditMark->toPlainText();
        iniFile.beginGroup(APPLICATIONGROUP);
		m.seedColumnGap=iniFile.value("SeedColumnGap").toInt();
		iniFile.endGroup();
        m.abLineName.clear();
		m.save();
		QMessageBox::information(this,"提示","创建成功");
		accept();
	});
}

DialogNewMap::~DialogNewMap()
{
	delete ui;
}

QString DialogNewMap::newMapName()
{
	return map;
}
