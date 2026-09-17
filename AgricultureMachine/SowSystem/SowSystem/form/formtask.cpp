#include "formtask.h"
#include "ui_formtask.h"
#include "global.h"
#include <QStandardItemModel>
#include "dialog/dialognewtask.h"
#include "../../common/database.h"
#include "../../common/map.h"
#include <QButtonGroup>
#include <QDebug>
#include <QMessageBox>
#include <QSqlError>
#include <QSettings>
#include <QTextCodec>
#include "dialog/dialogrealtimetask.h"
#include <QFileDialog>
#include <QPainter>

FormTask::FormTask(Communication &c,QWidget *parent) :
    QWidget(parent),
    ui(new Ui::FormTask),c(c)
{
	ui->setupUi(this);
	setFocus();
	setTouchable(ui->listViewTask);
	setTouchable(ui->tableViewMap);
	ui->tableViewMap->setModel(new QStandardItemModel);
	ui->listViewTask->setModel(new QStandardItemModel);
	ui->comboBoxView->addItems(Block::viewType);
	connect(ui->comboBoxView,&QComboBox::currentTextChanged,this,&FormTask::slotComboBoxViewCurrentTextChanged);
	connect(ui->pushButtonNewTask,&QPushButton::clicked,this,[=]{
		DialogNewTask dnt(this);
		if(dnt.exec()==QDialog::Rejected)
			return;
		QStandardItem *qsi=new QStandardItem(dnt.newTaskName());
		qsi->setCheckable(true);
		((QStandardItemModel *)ui->listViewTask->model())->appendRow(qsi);
		emit signalTaskListUpdated();
	});
	connect(ui->listViewTask,&QListView::clicked,this,[=](const QModelIndex &index){
		QString task=index.data().toString();
		if(task!=currentTask.name)
			loadCurrentTask(task);
	});
	connect(ui->pushButtonDeleteTask,&QPushButton::clicked,this,[=]{
		if(checkedTaskList().isEmpty())
		{
			QMessageBox::information(this,"提示","未选中任务");
			return;
		}
		QString sql="DELETE FROM "+TASKTABLE+" WHERE Name IN (";
		QStringList qsl;
		QStandardItemModel *model=(QStandardItemModel *)ui->listViewTask->model();
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		for(int i=0;i<model->rowCount();)
		{
			QStandardItem *qsi=model->item(i);
			if(qsi->checkState()==Qt::Checked)
			{
				if(qsl.size()>0)
					sql+=',';
				sql+='?';
				qsl.push_back(qsi->text());
				model->removeRow(i);
			}
			else
				i++;
		}
		if(qsl.isEmpty())
		{
			QMessageBox::information(this,"提示","未选中任务");
			return;
		}
		sql+=')';
		qsq.exec("PRAGMA foreign_keys=ON");
		qsq.prepare(sql);
		for(int i=0;i<qsl.size();qsq.addBindValue(qsl[i++]));
		qsq.exec();
		d.close();
		QMessageBox::information(this,"提示","删除成功");
		clearCurrentTask();
		emit signalTaskListUpdated();
	});
    connect(ui->pushButtonStart,&QPushButton::clicked,this,[=,&c]{
		if(currentTask.name.isEmpty())
			return;
        if(currentTask.mapName.isEmpty()||!Map::isExist(currentTask.mapName))
        {
            QMessageBox::information(this,"","地图不存在");
            return;
        }
        DialogRealtimeTask(currentTask,c,this).exec();
		loadCurrentTask(currentTask.name);
	});
	connect(ui->pushButtonModifyTask,&QPushButton::clicked,this,[=]{
		currentTask.mark=ui->textEditTaskMark->toPlainText();
        currentTask.saveInfo();
	});
	connect(ui->pushButtonExport,&QPushButton::clicked,this,[=]{
		QStringList qsl=checkedTaskList();
		if(qsl.isEmpty())
		{
			QMessageBox::information(this,"提示","未选中任务");
			return;
		}
		QString dirPath=QFileDialog::getExistingDirectory(this,"请选择文件保存路径");
		if(dirPath.isEmpty())
			return;
		QStringList existMapList,failedList,successList;
		for(int i=0;i<qsl.size();)
			if(QFile::exists(dirPath+"/任务 "+qsl[i]+".xlsx"))
			{
				existMapList.append(qsl[i]);
				qsl.removeOne(qsl[i]);
			}
			else
				i++;
		if(existMapList.size()>0)
			QMessageBox::information(this,"信息","无法导出"+listString(existMapList)+"，文件已存在");
		for(int i=0;i<qsl.size();)
		{
			Task t;
			t.load(qsl[i]);
			(t.exportToXlsx(dirPath)?successList:failedList).append(qsl[i++]);
		}
		if(failedList.size()>0)
			QMessageBox::information(this,"信息","任务"+listString(failedList)+"导出失败");
		if(successList.size()>0)
			QMessageBox::information(this,"信息","导出完成");
	});
	connect(ui->pushButtonImport,&QPushButton::clicked,this,[=]{
		QStringList qsl=QFileDialog::getOpenFileNames(this,"选择文件","","Excel 工作簿(*.xlsx)"),existList;
		Task t;
		QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewTask->model();
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		bool b=false;
		for(int i=0;i<qsl.size();i++)
		{
			QString taskName=QFileInfo(qsl[i]).fileName().section(" ",1,1).section(".",0,0);;
			qsq.prepare("SELECT Name FROM "+TASKTABLE+" WHERE Name=?");
			qsq.addBindValue(taskName);
			qsq.exec();
			if(qsq.next())
				existList.append(taskName);
			else
			{
				QStandardItem *qsi=new QStandardItem(taskName);
				qsi->setCheckable(true);
				qsim->appendRow(qsi);
				t.importFromXlsx(qsl[i],taskName);
				b=true;
			}
		}
		d.close();
		if(existList.size()>0)
			QMessageBox::information(this,"提示","任务"+listString(existList)+"已存在");
		if(b)
			QMessageBox::information(this,"提示","导入成功");
	});
	slotRefreshTaskList();
	connect(ui->pushButtonReset,&QPushButton::clicked,this,[=]{
		if(currentTask.name.isEmpty()||QMessageBox::question(this,"提示","确定要重置"+currentTask.name+"吗？")==QMessageBox::No)
			return;
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
        qsq.prepare("UPDATE "+RESULTTABLE+" SET SeedCount1=0,SeedCount2=0,SeedCount3=0,SeedCount4=0,SeedCount5=0,SeedCount6=0,FertilizerCount1=0,FertilizerCount2=0,FertilizerCount3=0,FertilizerCount4=0,FertilizerCount5=0,FertilizerCount6=0 WHERE TaskName=?");
		qsq.addBindValue(currentTask.name);
		qsq.exec();
		d.close();
		for(size_t i=0;i<currentTask.routeBlockVector.size();i++)
			for(size_t j=0;j<currentTask.routeBlockVector[i].size();j++)
				if(currentTask.routeBlockVector[i][j].state!=0)
					currentTask.routeBlockVector[i][j].state=0;
		currentTask.initPathState();
		currentTask.save();
		loadCurrentTask(currentTask.name);
	});
}

FormTask::~FormTask()
{
	delete ui;
}

void FormTask::slotRefreshTaskList()
{
	QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewTask->model();
	qsim->clear();
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	for(qsq.exec("SELECT Name FROM "+TASKTABLE);qsq.next();)
	{
		QString mapName=qsq.value("Name").toString();
		QStandardItem *qsi=new QStandardItem(mapName);
		qsi->setCheckable(true);
		qsim->appendRow(qsi);
	}
	d.close();
}

void FormTask::clearCurrentTask()
{
	currentTask.name.clear();
	ui->labelMapName->clear();
	ui->labelTaskCreateTime->clear();
	ui->labelLastWorkTime->clear();
	ui->labelTaskCompletionDegree->clear();
	ui->textEditTaskMark->clear();
	ui->textEditTaskMark->setReadOnly(true);
	ui->pushButtonModifyTask->setEnabled(false);
	ui->pushButtonStart->setEnabled(false);
	((QStandardItemModel *)ui->tableViewMap->model())->clear();
}

void FormTask::loadCurrentTask(QString task)
{
	currentTask.load(task);
    ui->labelMapName->setText(currentTask.mapName);
    ui->labelTaskCreateTime->setText(currentTask.createTime);
    ui->labelTaskCompletionDegree->setText(QString::number(currentTask.completionDegree())+'%');
    ui->labelLastWorkTime->setText(currentTask.lastWorkTime);
    ui->textEditTaskMark->setText(currentTask.mark);
    ui->textEditTaskMark->setReadOnly(false);
    ui->pushButtonModifyTask->setEnabled(true);
    ui->pushButtonStart->setEnabled(true);
    QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
    model->clear();
    Map m;
    m.load(currentTask.mapName);
    int rowCount=currentTask.routeBlockVector.size();
    for(int i=0;i<rowCount;ui->tableViewMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
    {
        for(size_t j=0;j<currentTask.routeBlockVector[i].size();)
        {
            QStandardItem *qsi=new QStandardItem;
            qsi->setText(m.blockVector[i][j].number);
//			qsi->setForeground(QBrush(Qt::yellow));
            if(m.blockVector[i][j].sowSeed)
            {
                QPixmap qp;
                switch(currentTask.routeBlockVector[i][j].state)
                {
                case 0:
                    qp=getTransparentPixmap(":/resource/image/task-block-unstarted.png");
                    break;
                case 1:
                    qp=getTransparentPixmap(":/resource/image/task-block-running.png");
                    break;
                case 2:
                    qp=getTransparentPixmap(":/resource/image/task-block-finished.png");
                    break;
                case 3:
                    qp=getTransparentPixmap(":/resource/image/task-block-failed.png");
                    break;
                default:;
                }
                qsi->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            }
            else
                qsi->setBackground(Qt::gray);
            model->setItem(i,j++,qsi);
        }
        model->setVerticalHeaderItem(i,new QStandardItem("排"+QString::number(rowCount-i)));
    }
    for(size_t i=0;i<m.aisleVector.size();)
    {
        int r=2*i++;
        model->insertRow(r);
        for(int j=0;j<model->columnCount();)
        {
            QStandardItem *item=new QStandardItem;
            item->setBackground(Qt::gray);
            model->setItem(r,j++,item);
        }
        model->setVerticalHeaderItem(r,new QStandardItem);
        ui->tableViewMap->setRowHeight(r,MAPTABLEAISLEHEIGHT);
    }
    for(int i=0;i<model->columnCount();i++)
        model->setHorizontalHeaderItem(i,new QStandardItem("列"+QString::number(i+1)));
    model->insertRow(0);
    for(int j=0;j<model->columnCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(0,j++,item);
    }
    ui->tableViewMap->setRowHeight(0,MAPTABLECELLHEIGHT);
    model->setVerticalHeaderItem(0,new QStandardItem);
    int row=model->rowCount();
    model->insertRow(row);
    for(int j=0;j<model->columnCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(row,j++,item);
    }
    ui->tableViewMap->setRowHeight(row,MAPTABLECELLHEIGHT);
    model->setVerticalHeaderItem(row,new QStandardItem);
    model->insertColumn(0);
    for(int j=0;j<model->rowCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(j++,0,item);
    }
    model->setHorizontalHeaderItem(0,new QStandardItem);
    int column=model->columnCount();
    model->insertColumn(column);
    for(int j=0;j<model->rowCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(j++,column,item);
    }
    model->setHorizontalHeaderItem(column,new QStandardItem);
    for(int i=0;i<model->columnCount();ui->tableViewMap->setColumnWidth(i++,MAPTABLECELLWIDTH));
    int blockEachTrip=m.blockEachTrip();
    QPixmap qp;
    bool b=currentTask.columnDirection(currentTask.outsetColumn);
    std::vector<int> columnVector=m.getColumnNode(currentTask.outsetColumn);
    for(int i=0;i<blockEachTrip;i++)
    {
        int c=currentTask.outsetColumn+i;
        if(!m.blockVector[currentTask.outsetRow][c].sowSeed)
            continue;
        switch(currentTask.routeBlockVector[currentTask.outsetRow][c].state)
        {
        case 0:
            qp=getTransparentPixmap(":/resource/image/outset-unstarted.png");
            break;
        case 1:
            qp=getTransparentPixmap(":/resource/image/outset-running.png");
            break;
        case 2:
            qp=getTransparentPixmap(":/resource/image/outset-finished.png");
            break;
        case 3:
            qp=getTransparentPixmap(":/resource/image/outset-failed.png");
            break;
        default:;
        }
        if(b)
            qp=qp.transformed(QTransform().rotate(180),Qt::SmoothTransformation);
        model->item(2*(currentTask.outsetRow+1),c+1)->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
    }
    slotComboBoxViewCurrentTextChanged(ui->comboBoxView->currentText());
}

QStringList FormTask::checkedTaskList()
{
	QStringList qsl;
	QStandardItemModel *model=(QStandardItemModel *)ui->listViewTask->model();
	for(int i=0;i<model->rowCount();)
	{
		QStandardItem *qsi=model->item(i++);
		if(qsi->checkState()==Qt::Checked)
			qsl.append(qsi->text());
	}
	return qsl;
}

void FormTask::slotAlphaUpdated()
{
	if(currentTask.mapName.isEmpty())
		return;
	Map m;
	m.load(currentTask.mapName);
	for(size_t i=0;i<currentTask.routeBlockVector.size();ui->tableViewMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
		for(size_t j=0;j<currentTask.routeBlockVector[i].size();j++)
			if(m.blockVector[i][j].sowSeed)
			{
				QPixmap qp;
				switch(currentTask.routeBlockVector[i][j].state)
				{
				case 0:
					qp=getTransparentPixmap(":/resource/image/task-block-unstarted.png");
					break;
				case 1:
					qp=getTransparentPixmap(":/resource/image/task-block-running.png");
					break;
				case 2:
					qp=getTransparentPixmap(":/resource/image/task-block-finished.png");
					break;
				case 3:
					qp=getTransparentPixmap(":/resource/image/task-block-failed.png");
					break;
				default:;
				}
				((QStandardItemModel *)ui->tableViewMap->model())->item((i+1)*2,j+1)->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
			}
}

void FormTask::slotComboBoxViewCurrentTextChanged(const QString &text)
{
	if(currentTask.name.isEmpty())
		return;
	Map m;
	m.load(currentTask.mapName);
    int rowCount=m.blockVector.size();
    for(int i=0;i<rowCount;i++)
		for(size_t j=0;j<m.blockVector[i].size();j++)
		{
			QStandardItem *qsi=((QStandardItemModel *)ui->tableViewMap->model())->item(2*(i+1),j+1);
			qsi->setTextAlignment(Qt::AlignCenter);
			if(text==Block::viewType[0])
                qsi->setText(QString::number(rowCount-i)+','+QString::number(j+1));
			else if(text==Block::viewType[1])
			{
				QString qs;
//				if(currentTask.routeBlockVector[i][j].state==2)
//				{
//					Database d;
//					d.open();
//					QSqlQuery qsq(d.qsd);
//					qsq.prepare("SELECT Moisture,Mass,UnitWeight FROM "+RESULTTABLE+" WHERE TaskName=? AND [Row]=? AND [Column]=?");
//					qsq.addBindValue(currentTask.name);
//					qsq.addBindValue(i);
//					qsq.addBindValue(j);
//					qsq.exec();
//					qsq.next();
//					qs='\n'+QString::number(qsq.value("Moisture").toFloat(),'f',2)+'\n'+QString::number(qsq.value("Mass").toFloat(),'f',3)+'\n'+QString::number(qsq.value("UnitWeight").toFloat(),'f',2);
//					d.qsd.close();
//				}
				qsi->setText(m.blockVector[i][j].number+qs);
			}
			else if(text==Block::viewType[2])
				qsi->setText(QString::number(m.blockVector[i][j].density));
		}
}
