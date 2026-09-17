#include "dialogrealtimetask.h"
#include "ui_dialogrealtimetask.h"
#include <QStandardItem>
//#include "network/tcp.h"
#include "global.h"
//#include "network/threaddata.h"
#include "dataStructs/blockresult.h"
#include <QFile>
#include <QScrollBar>
#include "dialogs/dialogresult.h"
#include "uart/threaduart.h"
#include <QSettings>
#include <QListView>
#include "../../common/database.h"
#include <QFileDialog>
#include <QFile>
#include <QMessageBox>
#include <QDateTime>
#include "tools/settingshandle.h"
#include <QCloseEvent>

#define TRACTORICONSIZE 70
#define PATHTYPEICONSIZE 70
#define STARTBUTTONLISTENINTERVAL 200

DialogRealtimeTask::DialogRealtimeTask(Task ta,QWidget *parent) :
    QDialog(parent),
    ui(new Ui::DialogRealtimeTask),t(ta),yieldState(0)
{
    ui->setupUi(this);
    setWindowTitle("实时测产-"+t.name);
	ui->comboBoxView->addItems(YieldBlock::viewType);
	ui->comboBoxView->setView(new QListView);
	connect(ui->comboBoxView,&QComboBox::currentTextChanged,this,&DialogRealtimeTask::slotComboBoxViewCurrentTextChanged);
    setTouchable(ui->tableViewMap);
    QStandardItemModel *model=new QStandardItemModel;
    ui->tableViewMap->setModel(model);
    ui->tableViewMap->setIconSize(QSize(TRACTORICONSIZE,TRACTORICONSIZE));
    yieldColumnCount=getMeasureColumnCount();
    m.load(t.mapName);
    currentResult.taskName=t.name;
    int rowCount=t.routeBlockVector.size();
    for(int i=0;i<rowCount;ui->tableViewMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
    {
        for(size_t j=0;j<t.routeBlockVector[i].size();)
        {
            QStandardItem *qsi=new QStandardItem;
            if(m.blockVector[i][j].crop.isEmpty())
                qsi->setBackground(Qt::gray);
            else if(t.routeBlockVector[i][j].measure)
                switch(t.routeBlockVector[i][j].state)
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
        }
        model->setVerticalHeaderItem(i,new QStandardItem("排"+QString::number(rowCount-i)));
    }
    for(size_t i=0;i<m.blockVector.size()+1;)
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
    for(int i=0;i<model->columnCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(0,i++,item);
    }
    ui->tableViewMap->setRowHeight(0,MAPTABLECELLHEIGHT);
    model->setVerticalHeaderItem(0,new QStandardItem);
    int row=model->rowCount();
    model->insertRow(row);
    for(int i=0;i<model->columnCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(row,i++,item);
    }
    ui->tableViewMap->setRowHeight(row,MAPTABLECELLHEIGHT);
    model->setVerticalHeaderItem(row,new QStandardItem);
    model->insertColumn(0);
    for(int i=0;i<model->rowCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(i++,0,item);
    }
    model->setHorizontalHeaderItem(0,new QStandardItem);
    int column=model->columnCount();
    model->insertColumn(column);
    for(int i=0;i<model->rowCount();)
    {
        QStandardItem *item=new QStandardItem;
        item->setBackground(Qt::gray);
        model->setItem(i++,column,item);
    }
    model->setHorizontalHeaderItem(column,new QStandardItem);
    for(int i=0;i<model->columnCount();ui->tableViewMap->setColumnWidth(i++,MAPTABLECELLWIDTH));
    qbg1.addButton(ui->radioButtonPositive);
    qbg1.addButton(ui->radioButtonReverse);
    qbg2.addButton(ui->radioButtonPathType1);
    qbg2.addButton(ui->radioButtonPathType2);
    qbg2.addButton(ui->radioButtonPathType3);
    qbg2.addButton(ui->radioButtonPathType4);
    qbg2.addButton(ui->radioButtonPathType5);
    qbg2.addButton(ui->radioButtonPathType6);
    ui->radioButtonPathType1->setIconSize(QSize(PATHTYPEICONSIZE,PATHTYPEICONSIZE));
    ui->radioButtonPathType2->setIconSize(QSize(PATHTYPEICONSIZE,PATHTYPEICONSIZE));
    ui->radioButtonPathType3->setIconSize(QSize(PATHTYPEICONSIZE,PATHTYPEICONSIZE));
    ui->radioButtonPathType4->setIconSize(QSize(PATHTYPEICONSIZE,PATHTYPEICONSIZE));
    ui->radioButtonPathType5->setIconSize(QSize(PATHTYPEICONSIZE,PATHTYPEICONSIZE));
    ui->radioButtonPathType6->setIconSize(QSize(PATHTYPEICONSIZE,PATHTYPEICONSIZE));
    connect(ui->radioButtonPositive,&QRadioButton::toggled,this,[=](bool checked){
        if(!checked)
            return;
        showPathTypeIcon(true);
        pathTypeToggled();
    });
    connect(ui->radioButtonReverse,&QRadioButton::toggled,this,[=](bool checked){
        if(!checked)
            return;
        showPathTypeIcon(false);
        pathTypeToggled();
    });
    t.positive?ui->radioButtonPositive->setChecked(true):ui->radioButtonReverse->setChecked(true);
    switch(t.pathType)
    {
    case 0:
        ui->radioButtonPathType1->setChecked(true);
        break;
    case 1:
        ui->radioButtonPathType2->setChecked(true);
        break;
    case 2:
        ui->radioButtonPathType3->setChecked(true);
        break;
    case 3:
        ui->radioButtonPathType4->setChecked(true);
        break;
    case 4:
        ui->radioButtonPathType5->setChecked(true);
        break;
    case 5:
        ui->radioButtonPathType6->setChecked(true);
        break;
    }
    createPath(t.pathType);
    connect(ui->radioButtonPathType1,&QRadioButton::toggled,this,&DialogRealtimeTask::slotRadioButtonPathType1Toggled);
    connect(ui->radioButtonPathType2,&QRadioButton::toggled,this,&DialogRealtimeTask::slotRadioButtonPathType2Toggled);
    connect(ui->radioButtonPathType3,&QRadioButton::toggled,this,&DialogRealtimeTask::slotRadioButtonPathType3Toggled);
    connect(ui->radioButtonPathType4,&QRadioButton::toggled,this,&DialogRealtimeTask::slotRadioButtonPathType4Toggled);
    connect(ui->radioButtonPathType5,&QRadioButton::toggled,this,&DialogRealtimeTask::slotRadioButtonPathType5Toggled);
    connect(ui->radioButtonPathType6,&QRadioButton::toggled,this,&DialogRealtimeTask::slotRadioButtonPathType6Toggled);
    showOutset(t.startRow,t.startColumn);
    setWindowFlags(windowFlags()|Qt::WindowMinMaxButtonsHint);
    connect(ui->pushButtonStart,&QPushButton::clicked,this,&DialogRealtimeTask::slotPushButtonStartClicked);
    connect(ui->pushButtonCycleMeasure,&QPushButton::clicked,this,&DialogRealtimeTask::slotPushButtonCycleMeasureClicked);
    connect(G.tUart,&ThreadUart::sig_uart,this,&DialogRealtimeTask::slotPhysicalButtonPushed,Qt::BlockingQueuedConnection);
    connect(&ymt,&YieldMeasurementThread::signalFinish,this,[=]{
        ui->pushButtonStart->setEnabled(true);
        ui->pushButtonCycleMeasure->setEnabled(true);
        ui->checkBoxModifyOutset->setCheckable(true);
        ymt.close();
        int row=t.routeBlockVector.size()-currentResult.row;
        int column=currentResult.column-1;
        connect(G.tUart,&ThreadUart::sig_uart,this,&DialogRealtimeTask::slotPhysicalButtonPushed);
        currentResult.endTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
        bool b=++currentColumnNodeIndex==yieldColumnCount;
        if(b)
            currentColumnNodeIndex=0;
        switch(yieldState)
        {
        case 1:
            currentResult.save();
            if(!b)
                startMeasure();
            break;
        case 2:
            if(b)
            {
                lastBlock.setX(t.routeBlockVector.size()-t.startRow);
                lastBlock.setY(t.startColumn+1);
                if(++nextPathIndex>=path.size())
                    nextPathIndex=0;
                t.startRow=path[nextPathIndex].row;
                t.startColumn=path[nextPathIndex].column;
                t.saveInfo();
                ymt.clear();
                showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
            }
            currentResult.state=2;
            setBackground(row,column,2);
            t.routeBlockVector[row][column].state=2;
            t.saveBlock(row,column);
            yieldState=0;
            currentResult.save();
            if(!b)
                slotPushButtonStartClicked();
            break;
        default:;
        }
    });
    connect(&ymt,&YieldMeasurementThread::signalReadMoistureFinished,this,[=](float f){
        currentResult.moisture=f;
        ui->labelMoisture->setText(QString::number(f)+"%");
    });
    connect(&ymt,&YieldMeasurementThread::signalReadTotalMassFinished,this,[=](float f){
        currentResult.mass+=f;
        ui->labelMass->setText(QString::number(currentResult.mass)+"kg");
    });
    connect(&ymt,&YieldMeasurementThread::signalReadUnitWeightFinished,this,[=](float f){
        currentResult.unitWeight=f;
        ui->labelUnitWeight->setText(QString::number(f)+"kg/L");
    });
    connect(ui->tableViewMap,&QTableView::clicked,this,[=](const QModelIndex &index){
        int row=index.row(),column=index.column();
        QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
        if(!ui->checkBoxModifyOutset->isChecked()||row%2==1||row==0||row==model->rowCount()-1||column==0||column==model->columnCount()-1)//选择了外圈或过道
            return;
        clearOutset();
        showOutset(row/2-1,column-1);
    });
    connect(ui->pushButtonResult,&QPushButton::clicked,this,[=]{
        DialogResult(t.name,this).exec();
	});
	connect(ui->pushButtonExport,&QPushButton::clicked,this,[=]{
		QString dirPath=QFileDialog::getExistingDirectory(this,"请选择文件保存路径");
		if(dirPath.isEmpty())
			return;
		if(QFile::exists(dirPath+"/任务 "+t.name+".xlsx"))
			QMessageBox::information(this,"信息","无法导出"+t.name+"，文件已存在");
		if(t.exportToXlsx(dirPath))
			QMessageBox::information(this,"信息",t.exportToXlsx(dirPath)?"导出完成":"任务"+t.name+"导出失败");
	});
	connect(&ymt,&YieldMeasurementThread::signalInfo,this,[=](QString qs){
        QString log=QTime::currentTime().toString("hh:mm:ss")+"："+qs;
        ui->textEdit->append(log);
        writeLog(log);
	});
    connect(this,&DialogRealtimeTask::signalYieldMeasure,&ymt,&YieldMeasurementThread::slotMeasureYield);
	connect(G.tUart,&ThreadUart::sig_uart,this,[=](int cmd,int len,void *args){
		switch(cmd)
		{
		case CMD_EX_ANA:
            emit signalYieldMeasure(((CmdBody *)args)->fa[0],((CmdBody *)args)->fa[1],((CmdBody *)args)->fa[2],((CmdBody *)args)->fa[3]);
			break;
		default:;
		}
	},Qt::BlockingQueuedConnection);
	connect(&qt,&QTimer::timeout,this,[=]{
		QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
		iniFile.beginGroup(APPLICATIONGROUP);
		iniFile.endGroup();
        ui->labelRealtimeMoisture->setText(transMoisture(&G.moistureCmMap[iniFile.value("RealtimeMoistureCalibrationTransformMode").toString()],G.rd->newestMoisture(),2));
        iniFile.endGroup();
		ui->labelRealtimeMass->setText(QString::number(Calib_trans(&G.massCmMap["三通道"],G.rd->uniteMass()),'f',3)+"kg");
	});
	connect(G.tUart,&ThreadUart::sig_errs,this,[=](int e){
		qt.stop();
		ui->labelConnectionState->setText("断开");
	});
	connect(G.tUart,&ThreadUart::sig_uart,this,[=](int cmd,int len,void *args){
		if(!qt.isActive())
			qt.start(500);
		ui->labelConnectionState->setText("连接");
	});
	slotComboBoxViewCurrentTextChanged(ui->comboBoxView->currentText());
    showMaximized();
}

DialogRealtimeTask::~DialogRealtimeTask()
{
    delete ui;
}

void DialogRealtimeTask::closeEvent(QCloseEvent *e)
{
    yieldState>0?e->ignore():e->accept();
}

void DialogRealtimeTask::showPathTypeIcon(bool b)
{
	ui->radioButtonPathType1->setIcon(QIcon(b?":/resources/images/positive_1.png":":/resources/images/reverse_1.png"));
	ui->radioButtonPathType2->setIcon(QIcon(b?":/resources/images/positive_2.png":":/resources/images/reverse_2.png"));
	ui->radioButtonPathType3->setIcon(QIcon(b?":/resources/images/positive_3.png":":/resources/images/reverse_3.png"));
	ui->radioButtonPathType4->setIcon(QIcon(b?":/resources/images/positive_4.png":":/resources/images/reverse_4.png"));
	ui->radioButtonPathType5->setIcon(QIcon(b?":/resources/images/positive_5.png":":/resources/images/reverse_5.png"));
	ui->radioButtonPathType6->setIcon(QIcon(b?":/resources/images/positive_6.png":":/resources/images/reverse_6.png"));
}

void DialogRealtimeTask::slotRadioButtonPathType1Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(0);
    nextPathIndex=0;
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    updateTaskPath();
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType2Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(1);
    nextPathIndex=0;
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    updateTaskPath();
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType3Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(2);
    nextPathIndex=0;
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    updateTaskPath();
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType4Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(3);
    nextPathIndex=0;
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    updateTaskPath();
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType5Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(4);
    nextPathIndex=0;
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    updateTaskPath();
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType6Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(5);
    nextPathIndex=0;
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    updateTaskPath();
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::createPath(int pathType)
{
    std::vector<PathNode>().swap(path);
    int trip=t.routeBlockVector[0].size()/getMeasureColumnCount(),i;
    std::vector<int> columnVector;
    std::vector<bool> positiveVector;
    bool positive=ui->radioButtonPositive->isChecked();
    switch(pathType)
    {
    case 0:
        for(i=0;i<trip;)
		{
            columnVector.push_back(yieldColumnCount*i++);
			positiveVector.push_back(positive);
			if(i==trip)
				break;
            columnVector.push_back(yieldColumnCount*i++);
			positiveVector.push_back(!positive);
		}
        for(i=0;(size_t)i<columnVector.size();i++)
            if(positiveVector[i])
                for(int j=0;(size_t)j<m.blockVector.size();)
                {
                    PathNode pn;
                    pn.row=j++;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
            else
                for(int j=m.blockVector.size()-1;j>=0;)
                {
                    PathNode pn;
                    pn.row=j--;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
        break;
    case 1:
		for(i=0;i<trip;positiveVector.push_back(positive))
            columnVector.push_back(yieldColumnCount*i++);
        for(i=0;(size_t)i<columnVector.size();i++)
            if(positiveVector[i])
                for(size_t j=0;j<m.blockVector.size();)
                {
                    PathNode pn;
                    pn.row=j++;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
            else
                for(int j=m.blockVector.size()-1;j>=0;)
                {
                    PathNode pn;
                    pn.row=j--;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
        break;
    case 2:
		for(i=0;i<trip/2;positiveVector.push_back(!positive))
		{
            columnVector.push_back(yieldColumnCount*i);
			positiveVector.push_back(positive);
            columnVector.push_back(yieldColumnCount*(trip-1-i++));
		}
        if(trip%yieldColumnCount==1)
        {
            columnVector.push_back(yieldColumnCount*i);
			positiveVector.push_back(positive);
        }
        for(i=0;(size_t)i<columnVector.size();i++)
            if(positiveVector[i])
                for(size_t j=0;j<m.blockVector.size();)
                {
                    PathNode pn;
                    pn.row=j++;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
            else
                for(int j=m.blockVector.size()-1;j>=0;)
                {
                    PathNode pn;
                    pn.row=j--;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
        break;
    case 3:
        for(i=trip-1;i>=0;)
		{
            columnVector.push_back(yieldColumnCount*i--);
			positiveVector.push_back(positive);
			if(i<0)
				break;
            columnVector.push_back(yieldColumnCount*i--);
			positiveVector.push_back(!positive);
		}
        for(i=0;(size_t)i<columnVector.size();i++)
            if(positiveVector[i])
                for(size_t j=0;j<m.blockVector.size();)
                {
                    PathNode pn;
                    pn.row=j++;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
            else
                for(int j=m.blockVector.size()-1;j>=0;)
                {
                    PathNode pn;
                    pn.row=j--;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
        break;
    case 4:
		for(i=trip-1;i>=0;positiveVector.push_back(positive))
            columnVector.push_back(yieldColumnCount*i--);
        for(i=0;(size_t)i<columnVector.size();i++)
            if(positiveVector[i])
                for(size_t j=0;j<m.blockVector.size();)
                {
                    PathNode pn;
                    pn.row=j++;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
            else
                for(int j=m.blockVector.size()-1;j>=0;)
                {
                    PathNode pn;
                    pn.row=j--;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
        break;
    case 5:
		for(i=0;i<trip/2;positiveVector.push_back(!positive))
		{
            columnVector.push_back(yieldColumnCount*(trip-1-i));
			positiveVector.push_back(positive);
            columnVector.push_back(yieldColumnCount*i++);
		}
        if(trip%yieldColumnCount==1)
        {
            columnVector.push_back(yieldColumnCount*i);
			positiveVector.push_back(positive);
        }
        for(i=0;(size_t)i<columnVector.size();i++)
            if(positiveVector[i])
                for(size_t j=0;j<m.blockVector.size();)
                {
                    PathNode pn;
                    pn.row=j++;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
            else
                for(int j=m.blockVector.size()-1;j>=0;)
                {
                    PathNode pn;
                    pn.row=j--;
                    pn.column=columnVector[i];
                    pn.positive=positiveVector[i];
                    path.push_back(pn);
                }
        break;
    }
}

void DialogRealtimeTask::clearOutset()
{
    if(t.startRow==-1)
        return;
    std::vector<int> columnVector=getColumnNode(t.startColumn);
    for(int i=0;i<yieldColumnCount;i++)
        setBackground(t.startRow,columnVector[i],t.routeBlockVector[t.startRow][columnVector[i]].state);
}

void DialogRealtimeTask::setBackground(int row,int column,int state)
{
    QStandardItem *item=((QStandardItemModel *)ui->tableViewMap->model())->item(2*(row+1),column+1);
    if(m.blockVector[row][column].crop.isEmpty())
        item->setBackground(Qt::gray);
    else if(t.routeBlockVector[row][column].measure)
        switch(state)
        {
        case 0:
            item->setBackground(getTransparentPixmap(":/resources/images/task-block-unstarted.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        case 1:
            item->setBackground(getTransparentPixmap(":/resources/images/task-block-running.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        case 2:
            item->setBackground(getTransparentPixmap(":/resources/images/task-block-finished.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        case 3:
            item->setBackground(getTransparentPixmap(":/resources/images/task-block-failed.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        default:;
        }
    else
        item->setBackground(Qt::NoBrush);
}

void DialogRealtimeTask::showOutset(size_t row,size_t column)
{
	if(row>=t.routeBlockVector.size()&&column>=t.routeBlockVector[0].size())
	{
        t.startRow=-1;
        return;
    }
    std::vector<int> columnVector=getColumnNode(column);
    t.startRow=row;
    t.startColumn=columnVector[0];qDebug()<<column;
    direction=t.columnDirection(column);
    currentColumnNodeIndex=0;
    nextPathIndex=getIndex(row,columnVector[0]);
    QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
    QPixmap qp;
    for(int i=0;i<yieldColumnCount;i++)
    {
        int c=columnVector[0]+i;
        if(m.blockVector[row][c].crop.isEmpty()||!t.routeBlockVector[row][c].measure)
            continue;
        switch(t.routeBlockVector[row][c].state)
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
		if(direction)
            qp=qp.transformed(QTransform().rotate(180),Qt::SmoothTransformation);
        model->item(2*(row+1),c+1)->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
    }
}

int DialogRealtimeTask::getIndex(int row,int column)
{
    size_t i=0;
    for(size_t i=0;i<path.size();i++)
        if(row==path[i].row&&column==path[i].column)
            return i;
    return i;
}

void DialogRealtimeTask::slotPushButtonStartClicked()
{
    if(startMeasure())
        yieldState=2;
}

void DialogRealtimeTask::slotPhysicalButtonPushed(int cmd,int len,void *args)
{
    if(cmd==CMD_EX_R_REG&&yieldState==0)
        switch(((CmdBody *)args)->ia[0]&0xffff0000)
        {
        case 0x10000:
            slotPushButtonStartClicked();
            break;
        case 0x20000:
            slotPushButtonCycleMeasureClicked();
            break;
        default:;
        }
}

void DialogRealtimeTask::slotValveStateUpdated()
{
    ui->labelValveState->setText(QString((G.valveState&1)>0?"开":"关")+"|"+QString((G.valveState&0b10)>0?"开":"关")+"|"+QString((G.valveState&0b100)>0?"开":"关")+"|"+QString((G.valveState&0b1000)>0?"开":"关")+"|"+QString((G.valveState&0b10000)>0?"开":"关"));
}

void DialogRealtimeTask::slotComboBoxViewCurrentTextChanged(const QString &text)
{
    int rowCount=m.blockVector.size();
    for(int i=0;i<rowCount;i++)
		for(size_t j=0;j<m.blockVector[i].size();j++)
		{
			QStandardItem *qsi=((QStandardItemModel *)ui->tableViewMap->model())->item(2*(i+1),j+1);
			qsi->setTextAlignment(Qt::AlignCenter);
			if(text==YieldBlock::viewType[0])
                qsi->setText(QString::number(rowCount-i)+','+QString::number(j+1));
			else if(text==YieldBlock::viewType[1])
			{
				QString qs;
				if(t.routeBlockVector[i][j].state==2)
				{
					Database d;
					d.open();
					QSqlQuery qsq(d.qsd);
					qsq.prepare("SELECT Moisture,Mass,UnitWeight FROM "+RESULTTABLE+" WHERE TaskName=? AND [Row]=? AND [Column]=?");
					qsq.addBindValue(t.name);
					qsq.addBindValue(i);
					qsq.addBindValue(j);
					qsq.exec();
					qsq.next();
					qs='\n'+QString::number(qsq.value("Moisture").toFloat(),'f',2)+'\n'+QString::number(qsq.value("Mass").toFloat(),'f',3)+'\n'+QString::number(qsq.value("UnitWeight").toFloat(),'f',2);
					d.close();
				}
				qsi->setText(m.blockVector[i][j].number+qs);
			}
			else if(text==YieldBlock::viewType[2])
				qsi->setText(m.blockVector[i][j].crop);
		}
}

bool DialogRealtimeTask::startMeasure()
{
    t.startRow=path[nextPathIndex].row;
    t.startColumn=path[nextPathIndex].column;
    for(;currentColumnNodeIndex<yieldColumnCount;currentColumnNodeIndex++)
    {
        int column=t.startColumn+currentColumnNodeIndex;
        if(t.routeBlockVector[t.startRow][column].measure&&(t.routeBlockVector[t.startRow][column].state==0||t.routeBlockVector[t.startRow][column].state==1))
            break;
    }
    if(yieldState==0)
    {
        ui->labelMass->clear();
        ui->labelMoisture->clear();
        ui->labelUnitWeight->clear();
        if(currentColumnNodeIndex==yieldColumnCount)
        {
            if(++nextPathIndex>=path.size())
                nextPathIndex=0;
            clearOutset();
            t.startRow=path[nextPathIndex].row;
            t.startColumn=path[nextPathIndex].column;
            t.saveInfo();
            showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
            return false;
        }
    }
    currentResult.row=t.routeBlockVector.size()-path[nextPathIndex].row;
    int column=t.startColumn+currentColumnNodeIndex;
    currentResult.column=column+1;
    switch(t.routeBlockVector[t.startRow][column].state)
    {
    case 0:
        t.routeBlockVector[t.startRow][column].state=1;
        t.saveBlock(t.startRow,column);
        setBackground(t.startRow,column,1);
        currentResult.startTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
        currentResult.crop=m.blockVector[t.startRow][column].crop;
        currentResult.unitWeight=0;
        currentResult.mass=0;
        currentResult.moisture=0;
        currentResult.state=1;
        currentResult.save();
        ui->textEdit->clear();
        ymt.setMeasureMoisture(true);
        ymt.setMeasureUnitWeight(true);
        break;
    case 1:
        ymt.setMeasureMoisture(false);
        ymt.setMeasureUnitWeight(false);
        break;
    default:;
    }
    t.lastWorkTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
    updateTaskPath();
    t.saveInfo();
    ui->pushButtonStart->setEnabled(false);
    ui->pushButtonCycleMeasure->setEnabled(false);
    ui->checkBoxModifyOutset->setCheckable(false);
    ui->checkBoxModifyOutset->setCheckState(Qt::Unchecked);
    int x=lastBlock.x();
    int y=lastBlock.y();
    if(x!=0&&y!=0)
        ui->labelLastBlock->setText(QString::number(x)+","+QString::number(y));
    ui->labelCurrentBlock->setText(QString::number(currentResult.row)+","+QString::number(currentResult.column));
    unsigned te=nextPathIndex+1;
    if(te==path.size())
        te=0;
    ui->labelNextBlock->setText(QString::number(t.routeBlockVector.size()-path[te].row)+","+QString::number(path[te].column+1));
    currentResult.crop=m.blockVector[t.startRow][column].crop;
    G.rd->setYieldMeasurementCrop(currentResult.crop);
    //若排列超出视图范围则更新视图位置
    ui->tableViewMap->scrollTo(ui->tableViewMap->model()->index((t.startRow+1)*2,t.startColumn),QAbstractItemView::PositionAtCenter);
    ymt.setCrop(currentResult.crop);
    ymt.setRunValve(currentColumnNodeIndex);
    ymt.start();
    writeLog(QString::number(currentResult.row)+"排"+QString::number(currentResult.column)+"列开始测产");
    return true;
}

void DialogRealtimeTask::slotPushButtonCycleMeasureClicked()
{
    startMeasure();
    yieldState=1;
}

void DialogRealtimeTask::pathTypeToggled()
{
    if(ui->radioButtonPathType1->isChecked())
        slotRadioButtonPathType1Toggled(true);
    else if(ui->radioButtonPathType2->isChecked())
        slotRadioButtonPathType2Toggled(true);
    else if(ui->radioButtonPathType3->isChecked())
        slotRadioButtonPathType3Toggled(true);
    else if(ui->radioButtonPathType4->isChecked())
        slotRadioButtonPathType4Toggled(true);
    else if(ui->radioButtonPathType5->isChecked())
        slotRadioButtonPathType5Toggled(true);
    else if(ui->radioButtonPathType6->isChecked())
        slotRadioButtonPathType6Toggled(true);
}

void DialogRealtimeTask::updateTaskPath()
{
    t.positive=ui->radioButtonPositive->isChecked();
    if(ui->radioButtonPathType1->isChecked())
        t.pathType=0;
    else if(ui->radioButtonPathType2->isChecked())
        t.pathType=1;
    else if(ui->radioButtonPathType3->isChecked())
        t.pathType=2;
    else if(ui->radioButtonPathType4->isChecked())
        t.pathType=3;
    else if(ui->radioButtonPathType5->isChecked())
        t.pathType=4;
    else if(ui->radioButtonPathType6->isChecked())
        t.pathType=5;
}
