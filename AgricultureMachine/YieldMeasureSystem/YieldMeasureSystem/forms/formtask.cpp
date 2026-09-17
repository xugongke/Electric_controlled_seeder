#include "formtask.h"
#include "ui_formtask.h"
#include <QSettings>
#include "global.h"
#include <QStandardItemModel>
#include "dialogs/dialognewtask.h"
#include <QDir>
#include <QMessageBox>
#include "../../common/database.h"
//#include "network/tcp.h"
//#include "network/threaddata.h"
//#include "dialogs/dialogresult.h"
#include <xlsxdocument.h>
#include <QDebug>
//#include "models/taskresultmodel.h"
#include "dialogs/dialogrealtimetask.h"
#include <QFileDialog>
#include "mainwindow.h"
#include "widgets/maptable.h"
#include "tools/settingshandle.h"
#include "dialogs/dialogbatchtaskblockinfo.h"
#include <QScreen>

#define TASKSTARTTEXT "开始"
#define TASKSTOPTEXT "中止"

FormTask::FormTask(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormTask),routeView(true)
{
	ui->setupUi(this);
    dstbi=new DialogSingleTaskBlockInfo(this);
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.beginGroup(APPLICATIONGROUP);
    iniFile.endGroup();
    setTouchable(ui->listViewTask);
    ui->tableViewRouteMap->setModel(new QStandardItemModel);
    ui->listViewTask->setModel(new QStandardItemModel);
    ui->textEditTaskMark->setReadOnly(true);
	ui->comboBoxView->addItems(YieldBlock::viewType);
	connect(ui->comboBoxView,&QComboBox::currentTextChanged,this,&FormTask::slotComboBoxViewCurrentTextChanged);
    connect(ui->pushButtonNewTask,&QPushButton::clicked,this,[=]{
        DialogNewTask dnt(this);
        if(dnt.exec()==QDialog::Rejected)
            return;
        QStandardItem *item=new QStandardItem(dnt.newTaskName());
        item->setCheckable(true);
		((QStandardItemModel *)ui->listViewTask->model())->appendRow(item);
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
        if(QMessageBox::question(this,"提示","删除任务会删除所有相关历史记录，确定要删除吗？")==QMessageBox::No)
            return;
        ui->checkBoxMutipleCheckedMode->setEnabled(false);
        ui->checkBoxMutipleCheckedMode->setCheckState(Qt::Unchecked);
        QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewTask->model();
        QString sql="DELETE FROM "+TASKTABLE+" WHERE Name IN (";
        QStringList qsl;
        for(int i=0;i<qsim->rowCount();)
        {
            QStandardItem *qsi=qsim->item(i);
            if(qsi->checkState()!=Qt::Checked)
            {
                ++i;
                continue;
            }
            if(qsl.size()>0)
                sql+=',';
            sql+='?';
            qsl.append(qsi->text());
            ui->listViewTask->model()->removeRow(i);
        }
        sql+=')';
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.exec("PRAGMA foreign_keys=ON");
        qsq.prepare(sql);
        for(int i=0;i<qsl.size();qsq.addBindValue(qsl[i++]));
        qsq.exec();
        d.close();
        QMessageBox::information(this,"提示","删除成功");
        clearCurrentTask();
        emit signalTaskListUpdated();
    });
    connect(ui->tableViewRouteMap,&QTableView::clicked,this,[=](const QModelIndex &index){
        QAbstractItemModel *model=ui->tableViewRouteMap->model();
        int row=index.row();
        int rowCount=model->rowCount();
        if(row%2==1||row==0||row==rowCount-1)
            return;
        int column=index.column();
        if(column==0||column==model->columnCount()-1)
            return;
        QPoint qp(ui->tableViewRouteMap->mapToGlobal(QPoint(0,0)));//转换为相对于屏幕左上角坐标
        int realRow=row/2-1;
        int realColumn=column-1;
        int margin;
        int dialogWidth;
        int x;
        int y;
        int screenWidth=QGuiApplication::primaryScreen()->geometry().width();
        switch(ui->checkBoxMutipleCheckedMode->checkState())
        {
        case Qt::Checked:
            if(!checkedV[realRow][realColumn])
                setBlockCheckedState(realRow,realColumn,!checkedV[realRow][realColumn]);
            break;
        case Qt::Unchecked:
            dstbi->setBlock(&currentTask.routeBlockVector[realRow][realColumn]);
            dstbi->setReadOnly(currentMap.blockVector[realRow][realColumn].crop.isEmpty());
            dstbi->show();//先显示再获取宽高
            margin=dstbi->margin();
            dialogWidth=dstbi->width();
            x=qp.x()+ui->tableViewRouteMap->columnViewportPosition(column)+ui->tableViewRouteMap->verticalHeader()->width()-(dialogWidth-MAPTABLECELLWIDTH)/2;
            y=qp.y()+ui->tableViewRouteMap->rowViewportPosition(row)+ui->tableViewRouteMap->horizontalHeader()->height()+margin-dstbi->height();
            dstbi->setCoordinate((rowCount-row)/2-1,realColumn);
            if(x<0)
                x=-margin;
            else if(x-margin+dialogWidth>screenWidth)
                x=screenWidth-dialogWidth+margin;
            if(y<0)
                y=-margin;
            dstbi->move(x,y);
            break;
        default:;
        }
    });
    connect(dstbi,&DialogSingleTaskBlockInfo::signalDataModified,this,[=](int row,int column){
        row=currentTask.routeBlockVector.size()-row-1;
        QStandardItem *qsi=((QStandardItemModel *)ui->tableViewRouteMap->model())->item((row+1)*2,column+1);
        if(currentTask.routeBlockVector[row][column].measure)
        {
            if(row==currentTask.startRow&&getColumnNode(column)[0]==currentTask.startColumn)
            {
                QPixmap qp;
                switch(currentTask.routeBlockVector[row][column].state)
                {
                case 0:
                    qp=getTransparentPixmap(":/resources/images/outset-unstarted.png");
                    break;
                case 1:
                    qp=getTransparentPixmap(":/resources/images/outset-running.png");
                    break;
                case 2:
                    qp=getTransparentPixmap(":/resources/images/outset-finished.png");
                    break;
                case 3:
                    qp=getTransparentPixmap(":/resources/images/outset-failed.png");
                    break;
                default:;
                }
                if(currentTask.columnDirection(column))
                    qp=qp.transformed(QTransform().rotate(180),Qt::SmoothTransformation);
                qsi->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            }
            else
                switch(currentTask.routeBlockVector[row][column].state)
                {
                case 0:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-unstarted.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 1:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-running.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 2:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-finished.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 3:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-failed.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                default:;
                }
        }
        else
            qsi->setBackground(Qt::NoBrush);
    });
    connect(ui->checkBoxMutipleCheckedMode,&QCheckBox::stateChanged,this,[=](int state){
        QHeaderView *hqhv=ui->tableViewRouteMap->horizontalHeader(),*vqhv=ui->tableViewRouteMap->verticalHeader();
        switch(state)
        {
        case Qt::Checked:
            ui->pushButtonBatchSet->setEnabled(true);
            ui->checkBoxCheckAllBlock->setEnabled(true);
            connect(vqhv,&QHeaderView::sectionClicked,this,&FormTask::slotVerticalSectionClicked);
            connect(hqhv,&QHeaderView::sectionClicked,this,&FormTask::slotHorizontalSectionClicked);
            break;
        case Qt::Unchecked:
            ui->pushButtonBatchSet->setEnabled(false);
            ui->checkBoxCheckAllBlock->setEnabled(false);
            switch(ui->checkBoxCheckAllBlock->checkState())
            {
            case Qt::Unchecked:
                slotCheckBoxCheckAllBlockStateChanged(state);
                break;
            case Qt::Checked:
                ui->checkBoxCheckAllBlock->setCheckState(Qt::Unchecked);
                break;
            default:;
            }
            disconnect(vqhv,&QHeaderView::sectionClicked,this,&FormTask::slotVerticalSectionClicked);
            disconnect(hqhv,&QHeaderView::sectionClicked,this,&FormTask::slotHorizontalSectionClicked);
        }
    });
    connect(ui->pushButtonBatchSet,&QPushButton::clicked,this,[=]{
        size_t rowCount=currentTask.routeBlockVector.size();
        for(size_t i=0;i<rowCount;++i)
            for(size_t j=0;j<currentTask.routeBlockVector[i].size();++j)
                if(checkedV[i][j])
                {
                    DialogBatchTaskBlockInfo dbbi(this);
                    if(dbbi.exec()==QDialog::Accepted)
                    {
                        //若有区域被选中，从该格开始往后找
                        TaskBlock b=dbbi.value();
                        for(size_t t=i;i<rowCount;++i)
                        {
                            if(i>t)
                                j=0;
                            for(;j<currentTask.routeBlockVector[i].size();++j)
                                if(checkedV[i][j])
                                    currentTask.routeBlockVector[i][j]=b;
                        }
                    }
                    return;
                }
        QMessageBox::information(this,"提示","未选中区域");
    });
    connect(ui->checkBoxCheckAllBlock,&QCheckBox::stateChanged,this,&FormTask::slotCheckBoxCheckAllBlockStateChanged);
    connect(ui->pushButtonStart,&QPushButton::clicked,this,[=]{
        if(currentTask.name.isEmpty())
            return;
        if(currentTask.mapName.isEmpty()||!YieldMap::isExist(currentTask.mapName))
        {
            QMessageBox::information(this,"","地图不存在");
            return;
        }
		DialogRealtimeTask a(currentTask,this);
		connect((MainWindow *)parent,&MainWindow::signalValveStateChanged,&a,&DialogRealtimeTask::slotValveStateUpdated);
        a.exec();
        loadCurrentTask(currentTask.name);
    });
    connect(ui->pushButtonModifyTask,&QPushButton::clicked,this,[=]{
        currentTask.mark=ui->textEditTaskMark->toPlainText();
        currentTask.save();
        QMessageBox::information(this,"提示","保存成功");
    });
    slotRefreshTaskList();
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
		for(int i=0;i<qsl.size();i++)
        {
            Task t;
			t.load(qsl[i]);
			(t.exportToXlsx(dirPath)?successList:failedList).append(qsl[i]);
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
//        QStringList qsl=QFileDialog::getOpenFileNames(this,"选择文件","","Excel 工作簿(*.xlsx)"),existList;
//        Task t;
//        QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewTask->model();
//        for(int i=0;i<qsl.size();t.importFromXlsx(qsl[i++]))
//        {
//            QString taskName=QFileInfo(qsl[i]).fileName().section(".",0,0);
//            QStandardItem *qsi=new QStandardItem(taskName);
//            qsi->setCheckable(true);
//            qsim->appendRow(qsi);
//        }
    });
    connect(ui->pushButtonReset,&QPushButton::clicked,this,[=]{
        if(currentTask.name.isEmpty()||QMessageBox::question(this,"提示","确定要重置"+currentTask.name+"吗？")==QMessageBox::No)
            return;
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.prepare("DELETE FROM "+RESULTTABLE+" WHERE TaskName=?");
        qsq.addBindValue(currentTask.name);
        d.qsd.transaction();
        qsq.exec();
        qsq.exec("UPDATE "+TASKBLOCKTABLE+" SET State=0 WHERE TaskName=?");
        qsq.addBindValue(currentTask.name);
        d.qsd.commit();
        d.close();
        currentTask.initPathState();
        currentTask.save();
        loadCurrentTask(currentTask.name);
    });
}

FormTask::~FormTask()
{
	delete ui;
}

void FormTask::loadCurrentTask(QString task)
{
	currentTask.load(task);
    currentMap.load(currentTask.mapName);
    ui->labelMapName->setText(currentTask.mapName);
    ui->labelTaskCreateTime->setText(currentTask.createTime);
    ui->labelTaskCompletionDegree->setText(QString::number(currentTask.completionDegree())+'%');
    ui->labelLastWorkTime->setText(currentTask.lastWorkTime);
    ui->textEditTaskMark->setText(currentTask.mark);
    ui->textEditTaskMark->setReadOnly(false);
    ui->pushButtonModifyTask->setEnabled(true);
    ui->checkBoxMutipleCheckedMode->setEnabled(true);
    ui->pushButtonStart->setEnabled(true);
    QStandardItemModel *model=(QStandardItemModel *)ui->tableViewRouteMap->model();
    model->clear();
    std::vector<std::deque<bool>>().swap(checkedV);
    int rowCount=currentTask.routeBlockVector.size();
    for(int i=0;i<rowCount;ui->tableViewRouteMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
    {
        std::deque<bool> bd;
        for(size_t j=0;j<currentTask.routeBlockVector[i].size();)
        {
            QStandardItem *qsi=new QStandardItem;
            if(currentMap.blockVector[i][j].crop.isEmpty())
                qsi->setBackground(Qt::gray);
            else if(currentTask.routeBlockVector[i][j].measure)
                switch(currentTask.routeBlockVector[i][j].state)
                {
                case 0:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-unstarted.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 1:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-running.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 2:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-finished.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 3:
                    qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-failed.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                default:;
                }
            else
                qsi->setBackground(Qt::NoBrush);
            model->setItem(i,j++,qsi);
            bd.push_back(false);
        }
        model->setVerticalHeaderItem(i,new QStandardItem("排"+QString::number(rowCount-i)));
        checkedV.push_back(bd);
    }
    for(int i=0;i<rowCount+1;)
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
        ui->tableViewRouteMap->setRowHeight(r,MAPTABLEAISLEHEIGHT);
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
    ui->tableViewRouteMap->setRowHeight(0,MAPTABLECELLHEIGHT);
    model->setVerticalHeaderItem(0,new QStandardItem);
    int row=model->rowCount();
    model->insertRow(row);
    for(int j=0;j<model->columnCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(row,j++,item);
    }
    ui->tableViewRouteMap->setRowHeight(row,MAPTABLECELLHEIGHT);
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
    for(int i=0;i<model->columnCount();ui->tableViewRouteMap->setColumnWidth(i++,MAPTABLECELLWIDTH));
    QPixmap qp;
    bool b=currentTask.columnDirection(currentTask.startColumn);
    for(int i=0;i<getMeasureColumnCount();i++)
    {
        int c=currentTask.startColumn+i;
        if(!currentMap.blockVector[currentTask.startRow][c].crop.isEmpty()&&currentTask.routeBlockVector[currentTask.startRow][c].measure)
        {
            switch(currentTask.routeBlockVector[currentTask.startRow][c].state)
            {
            case 0:
                qp=getTransparentPixmap(":/resources/images/outset-unstarted.png");
                break;
            case 1:
                qp=getTransparentPixmap(":/resources/images/outset-running.png");
                break;
            case 2:
                qp=getTransparentPixmap(":/resources/images/outset-finished.png");
                break;
            case 3:
                qp=getTransparentPixmap(":/resources/images/outset-failed.png");
                break;
            default:;
            }
            if(b)
                qp=qp.transformed(QTransform().rotate(180),Qt::SmoothTransformation);
            model->item(2*(currentTask.startRow+1),c+1)->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
        }
    }
	slotComboBoxViewCurrentTextChanged(ui->comboBoxView->currentText());
}

void FormTask::slotVerticalSectionClicked(int logicalIndex)
{
    bool f=false;
    int columnCount=currentTask.routeBlockVector[0].size(),row=(logicalIndex-1)/2;
    for(int i=0;i<columnCount;)
        if(!checkedV[row][i++])
        {
            f=true;
            break;
        }
    for(int i=0;i<columnCount;setBlockCheckedState(row,i++,f));
}

void FormTask::slotHorizontalSectionClicked(int logicalIndex)
{
    bool f=false;
    int rowCount=currentTask.routeBlockVector.size();
    int column=logicalIndex-1;
    for(int i=0;i<rowCount;)
        if(!checkedV[i++][column])
        {
            f=true;
            break;
        }
    for(int i=0;i<rowCount;setBlockCheckedState(i++,column,f));
}

void FormTask::setBlockCheckedState(int row,int column,bool b)
{
    checkedV[row][column]=b;
    if(b)
    {
        row=(row+1)*2;
        column++;
        ((QStandardItemModel *)ui->tableViewRouteMap->model())->item(row,column)->setBackground(QPixmap(":/resources/images/block-checked.png").scaled(ui->tableViewRouteMap->columnWidth(column),ui->tableViewRouteMap->rowHeight(row)));
    }
    else
        setBackground(row,column);
}

void FormTask::slotCheckBoxCheckAllBlockStateChanged(int state)
{
    for(size_t i=0;i<currentTask.routeBlockVector.size();++i)
        for(size_t j=0;j<currentTask.routeBlockVector[i].size();++j)
            if(!currentMap.blockVector[i][j].crop.isEmpty())
                switch(state)
                {
                case Qt::Checked:
                    if(!checkedV[i][j])
                        setBlockCheckedState(i,j,true);
                    break;
                case Qt::Unchecked:
                    if(checkedV[i][j])
                        setBlockCheckedState(i,j,false);
                    break;
                default:;
                }
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
        QStandardItem *qsi=new QStandardItem(qsq.value("Name").toString());
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
    ((QStandardItemModel *)ui->tableViewRouteMap->model())->clear();
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

void FormTask::slotComboBoxViewCurrentTextChanged(const QString &text)
{
	if(currentTask.name.isEmpty())
		return;
    int rowCount=currentTask.routeBlockVector.size();
    for(int i=0;i<rowCount;i++)
        for(size_t j=0;j<currentTask.routeBlockVector[i].size();j++)
		{
			QStandardItem *qsi=((QStandardItemModel *)ui->tableViewRouteMap->model())->item(2*(i+1),j+1);
			qsi->setTextAlignment(Qt::AlignCenter);
			if(text==YieldBlock::viewType[0])
                qsi->setText(QString::number(rowCount-i)+','+QString::number(j+1));
			else if(text==YieldBlock::viewType[1])
			{
				QString qs;
				if(currentTask.routeBlockVector[i][j].state==2)
				{
					Database d;
					d.open();
					QSqlQuery qsq(d.qsd);
					qsq.prepare("SELECT Moisture,Mass,UnitWeight FROM "+RESULTTABLE+" WHERE TaskName=? AND [Row]=? AND [Column]=?");
					qsq.addBindValue(currentTask.name);
					qsq.addBindValue(i);
					qsq.addBindValue(j);
					qsq.exec();
					qsq.next();
					qs='\n'+QString::number(qsq.value("Moisture").toFloat(),'f',2)+'\n'+QString::number(qsq.value("Mass").toFloat(),'f',3)+'\n'+QString::number(qsq.value("UnitWeight").toFloat(),'f',2);
					d.close();
				}
                qsi->setText(currentMap.blockVector[i][j].number+qs);
			}
			else if(text==YieldBlock::viewType[2])
                qsi->setText(currentMap.blockVector[i][j].crop);
		}
}

void FormTask::slotReloadTask()
{
    if(!currentTask.name.isEmpty())
        loadCurrentTask(currentTask.name);
}

void FormTask::slotReloadTask(QString name)
{
    if(!currentTask.name.isEmpty()&&currentTask.name==name)
        loadCurrentTask(currentTask.name);
}

void FormTask::setBackground(int row,int column)
{
    QStandardItem *qsi=((QStandardItemModel *)ui->tableViewRouteMap->model())->item((row+1)*2,column+1);
    if(currentTask.routeBlockVector[row][column].measure)
    {
        if(row==currentTask.startRow&&getColumnNode(column)[0]==currentTask.startColumn)
        {
            QPixmap qp;
            switch(currentTask.routeBlockVector[row][column].state)
            {
            case 0:
                qp=getTransparentPixmap(":/resources/images/outset-unstarted.png");
                break;
            case 1:
                qp=getTransparentPixmap(":/resources/images/outset-running.png");
                break;
            case 2:
                qp=getTransparentPixmap(":/resources/images/outset-finished.png");
                break;
            case 3:
                qp=getTransparentPixmap(":/resources/images/outset-failed.png");
                break;
            default:;
            }
            if(currentTask.columnDirection(column))
                qp=qp.transformed(QTransform().rotate(180),Qt::SmoothTransformation);
            qsi->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
        }
        else
            switch(currentTask.routeBlockVector[row][column].state)
            {
            case 0:
                qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-unstarted.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                break;
            case 1:
                qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-running.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                break;
            case 2:
                qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-finished.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                break;
            case 3:
                qsi->setBackground(getTransparentPixmap(":/resources/images/task-block-failed.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                break;
            default:;
            }
    }
    else
        qsi->setBackground(Qt::NoBrush);
}
