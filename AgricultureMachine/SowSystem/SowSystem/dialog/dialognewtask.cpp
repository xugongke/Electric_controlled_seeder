#include "dialognewtask.h"
#include "ui_dialognewtask.h"
#include <QMessageBox>
#include <QDir>
#include <QDebug>
#include <QDateTime>
#include "../../common/map.h"
#include <QStandardItem>
#include <QMenu>
#include "dataStruct/task.h"
#include <QDesktopWidget>
#include "../../common/database.h"
#include "global.h"

DialogNewTask::DialogNewTask(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogNewTask)
{
	ui->setupUi(this);
	setFocus();
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	for(qsq.exec("SELECT Name FROM "+MAPTABLE);qsq.next();ui->comboBoxMap->addItem(qsq.value("Name").toString()));
	d.close();
	ui->comboBoxMap->setSizeAdjustPolicy(QComboBox::AdjustToContents);
	connect(ui->pushButtonOk,&QPushButton::clicked,this,[=]{
		Task ta;
		ta.name=ui->lineEditTaskName->text();
		if(ta.name.isEmpty())
		{
			QMessageBox::information(this,"提示","任务名不能为空");
			return;
		}
		ta.mapName=ui->comboBoxMap->currentText();
		if(ta.mapName.isEmpty())
		{
			QMessageBox::information(this,"提示","地图不能为空");
			return;
		}
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("SELECT Name FROM "+TASKTABLE+" WHERE Name=?");
		qsq.addBindValue(ta.name);
		qsq.exec();
		if(qsq.next())
		{
            QMessageBox::information(this,"提示","已有同名任务存在");
			d.close();
			return;
		}
		d.close();
		Map m;
		m.load(ta.mapName);
		for(size_t i=0;i<m.blockVector.size();i++)
		{
			std::vector<TaskBlock> tbv;
            for(size_t j=0;j<m.blockVector[i].size();)
			{
				TaskBlock tb;
                tb.state=0;
                tb.sow=m.blockVector[i][j++].sowSeed;
				tbv.push_back(tb);
			}
			ta.routeBlockVector.push_back(tbv);
		}
		ta.createTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
		ta.mark=ui->textEditTaskMark->toPlainText();
		ta.initPathState();
		ta.save();
		QMessageBox::information(this,"提示","创建成功");
		accept();
	});
}

DialogNewTask::~DialogNewTask()
{
	delete ui;
}

QString DialogNewTask::newTaskName()
{
	return ui->lineEditTaskName->text();
}
