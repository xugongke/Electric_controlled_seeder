#include "dialogrealtimetask.h"
#include "ui_dialogrealtimetask.h"
#include <QStandardItem>
#include "global.h"
#include <QDebug>
#include <QDateTime>
#include <QMessageBox>
#include <cmath>
#include <QCloseEvent>
#include <QScrollBar>
#include "dialog/dialogtaskresult.h"
#include <QSettings>
#include <QDir>
#include "dialog/dialogabline.h"
#include "dialog/dialogchooseabline.h"
#include "../../common/database.h"
#include "dialog/dialoginputablinename.h"
#include <QListView>
#include <QFileDialog>
#include <QTextCodec>
#include "dialog/dialogdevicestate.h"

#define STATUSINTERVAL 200
#define DEBUGINFOINTERVAL 200
#define PATHTYPEICONSIZE 70
#define TRACTORICONSIZE 70
#define ICONWIDTH 50
#define ICONHEIGHT 50
#define LEAKSEEDCOLUMN 0
#define LEAKFERTILIZERCOLUMN 1

DialogRealtimeTask::DialogRealtimeTask(Task ta,Communication &c,QWidget *parent) :
    QDialog(parent),
    ui(new Ui::DialogRealtimeTask),t(ta),sowState(false),c(c)
{
	ui->setupUi(this);
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
    iniFile.beginGroup(DEVICEGROUP);
    maxSowColumn=iniFile.value("DeviceType").toString()=="6行机"?6:4;
    iniFile.endGroup();
    setWindowTitle("实时播种-"+t.name);
	ui->comboBoxView->addItems(Block::viewType);
	ui->comboBoxView->setView(new QListView);
	connect(ui->comboBoxView,&QComboBox::currentTextChanged,this,&DialogRealtimeTask::slotComboBoxViewCurrentTextChanged);
    QStandardItemModel *model=new QStandardItemModel(this);
    ui->tableViewMap->setModel(model);
    ui->tableViewMap->setIconSize(QSize(TRACTORICONSIZE,TRACTORICONSIZE));
    m.load(t.mapName);
    m.loadABLine();
    ui->labelRunState->setStyleSheet("border-radius:30px;border:2px solid #64748b;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #e2e8f0,stop:0.5 #94a3b8,stop:1 #475569);");
    ui->pushButtonDeviceState->setStyleSheet("border-radius:30px;border:2px solid #64748b;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #e2e8f0,stop:0.5 #94a3b8,stop:1 #475569);");
    ui->checkBoxSowExceedMap->setEnabled(!m.abLineName.isEmpty());
    ui->pushButtonABLine->setText(m.abLineName.isEmpty()?"无":m.abLineName);
    int rowCount=t.routeBlockVector.size();
    for(int i=0;i<rowCount;ui->tableViewMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
    {
        for(size_t j=0;j<t.routeBlockVector[i].size();)
		{
			QStandardItem *qsi=new QStandardItem(m.blockVector[i][j].number);
            if(!m.blockVector[i][j].sowSeed)
                qsi->setBackground(Qt::gray);
            else
                switch(t.routeBlockVector[i][j].state)
                {
                case 0:
					qsi->setBackground(getTransparentPixmap(":/resource/image/task-block-unstarted.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 1:
					qsi->setBackground(getTransparentPixmap(":/resource/image/task-block-running.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 2:
					qsi->setBackground(getTransparentPixmap(":/resource/image/task-block-finished.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                case 3:
					qsi->setBackground(getTransparentPixmap(":/resource/image/task-block-failed.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
                    break;
                default:;
                }
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
    qbg1.addButton(ui->radioButtonReverse);
    qbg1.addButton(ui->radioButtonPositive);
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
    connect(ui->radioButtonReverse,&QRadioButton::toggled,this,[=](bool checked){
        if(!checked)
            return;
        showPathTypeIcon(false);
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
    });
    connect(ui->radioButtonPositive,&QRadioButton::toggled,this,[=](bool checked){
        if(!checked)
            return;
        showPathTypeIcon(true);
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
    });
    connect(ui->pushButtonDeviceState,&QPushButton::clicked,this,[=,&c]{
        DialogDeviceState(c,this).exec();
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
    connect(ui->pushButtonStart,&QPushButton::clicked,this,[=,&c]{
        if(nextPathIndex==path.size())
            return;
        if(sowState)
        {
    //         for(size_t i=0;i<t.routeBlockVector.size();i++)
                // for(size_t j=0;j<t.routeBlockVector[0].size();j+=m.blockEachTrip())
    //                 if(t.routeBlockVector[i][j].state==1)
                // 		setBlockState(i,j,2);
            c.stopSow();
        }
        else if(c.getPreMode()==SOW)
            c.setManufacturerParameter(getManufacturerParameterFromSetting());
    });
    connect(&c,&Communication::signalSetManufacturerParameter,this,[=,&c](bool b){
        if(!b||c.getPreMode()!=SOW)
            return;
        t.lastWorkTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
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
        t.saveInfo();
        QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
        iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
        iniFile.beginGroup(APPLICATIONGROUP);
        QString qs=iniFile.value("GapPoint","开").toString();
        if(qs=="开")
            c.enableGapPoint(true);
        else if(qs=="间隔")
            c.enableGapPoint(t.outsetColumn/m.blockEachTrip()%2==0);
        else if(qs=="关")
            c.enableGapPoint(false);
        iniFile.endGroup();
        c.startSow();
    });
    connect(&debugInfoTimer,&QTimer::timeout,this,[=,&c]{
		if(c.getConnectionState())
			c.getDebugInformation(SOW);
    });
    connect(&sowStateTimer,&QTimer::timeout,this,[=,&c]{
        c.getSowStatus();
    });
    sowStateTimer.start(STATUSINTERVAL);
    connect(&c,&Communication::signalStartSow,this,[=]{
        columnEndFlag=false;
        sowState=true;
        ui->pushButtonStart->setText("停止");
        ui->checkBoxModifyOutset->setCheckable(false);
        ui->checkBoxModifyOutset->setCheckState(Qt::Unchecked);
        direction=path[nextPathIndex].positive;
        currentColumn=t.outsetColumn;
        setControlEnable(false);
        if(m.abLineName.isEmpty())
        {
            //除非AB线被保存，否则会每次更新
            m.abLineDirection=direction;
            m.aRow=t.outsetRow;
            m.aColumn=t.outsetColumn;
        }
        if(ui->checkBoxSowExceedMap->checkState()==Qt::Checked)
        {
            //地图外开始
            currentReadRowNum=direction?tractorRow+1:tractorRow-1;
            enterMapFlag=currentReadRowNum>=0&&currentReadRowNum<(int)m.blockVector.size();
            /*待测
            ui->tableViewMap->scrollTo(model->index(currentReadRowNum*2+1,currentColumn+1),QAbstractItemView::PositionAtCenter);*/
            startNode(currentReadRowNum,currentColumn);
            //避免计时器槽中判断超出区域播种时重复下发首排
        }
        else
        {
            enterMapFlag=true;
            ui->tableViewMap->scrollTo(model->index(path[nextPathIndex].row*2+1,currentColumn+1),QAbstractItemView::PositionAtCenter);
            startNode(path[nextPathIndex].row,currentColumn);
        }
    });
    connect(&c,&Communication::signalSetABLine,this,[=](bool b){
        qDebug()<<"下发AB线成功";
    });
    connect(&c,&Communication::signalStopSow,this,[=,&c]{
        if(t.routeBlockVector[path[nextPathIndex].row][path[nextPathIndex].column].state==2)
           nextPathIndex=tempIndex;//更新起点，否则会以上次未结束的区域作为起点
        // if(m.abLineName.isEmpty()&&QMessageBox::question(this,"提示","是否要保存AB线？")==QMessageBox::Yes)
        //     c.getABLine();
        if(m.abLineName.isEmpty())
            msgBox->open();
        sowState=false;
        ui->pushButtonStart->setText("开始");
        setControlEnable(true);
        ui->checkBoxModifyOutset->setCheckable(true);
        showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
    });
    connect(&c,&Communication::signalSetSowParameters,this,[=](bool b){
        writeLog("下发参数成功");
        // for(int i=0;i<m.blockEachTrip();t.routeBlockVector[path[nextPathIndex].row][currentColumn+i++].endTime="")
        //     t.routeBlockVector[path[nextPathIndex].row][currentColumn+i].startTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
        for(int i=0;i<m.blockEachTrip();currentResult[i++].endTime="")
        {
            currentResult[i].row=t.routeBlockVector.size()-path[nextPathIndex].row;
            currentResult[i].column=currentColumn+1+i;
            currentResult[i].startTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
        }
    });
    debugInfoTimer.start(DEBUGINFOINTERVAL);
    connect(&c,&Communication::signalGetSowStatus,this,[=](BZStatusType_st bzst){
        bzState=bzst;
        switch(bzst.RunState)
        {
        case 0:
            ui->labelRunState->setStyleSheet("border-radius:30px;border:2px solid #991b1b;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #fca5a5,stop:0.5 #ef4444,stop:1 #991b1b);");
            break;
        case 1:
            ui->labelRunState->setStyleSheet("border-radius:30px;border:2px solid #92400e;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #fef08a,stop:0.5 #eab308,stop:1 #854d0e);");
            break;
        case 0x81:
            ui->labelRunState->setStyleSheet("border-radius:30px;border:2px solid #166534;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #86efac,stop:0.5 #22c55e,stop:1 #15803d);");
            break;
        default:;
        }
        bool hasABLine=!m.abLineName.isEmpty();
        tractorRow=hasABLine?m.offsetToRow(bzst.OffLen+m.rowToOffset(m.aRow)):m.offsetToRow(bzst.OffLen);
        if(hasABLine)
        {
            if(t.pathType==0||t.pathType==1||t.pathType==2)
            {
                if(m.abLineDirection)
                    bzst.VerticalOff*=-1;
            }
            else if(!m.abLineDirection)
                bzst.VerticalOff*=-1;
        }
        ui->labelTravelDistance->setText(QString::number(bzst.OffLen/100.0)+"m、"+QString::number(bzst.VerticalOff/100.0)+"m");
        ui->labelSpeed->setText(QString::number(bzst.Speed/1000.0,'f',3)+"m/s");
        //车辆位置实时显示
        int tractorColumn;
        if(hasABLine)
        {
            //bzst.VerticalOff为距AB线实际偏移
            int columnOffset=m.centralOffset(currentColumn)-m.centralOffset(m.aColumn);//理论偏移
            //当前播种列与车辆实际所在列的偏差
            int tractorOffset=t.pathType==0||t.pathType==1||t.pathType==2?columnOffset-bzst.VerticalOff:-bzst.VerticalOff-columnOffset;
			//车辆显示的第一列=当前播种列-(tractorOffset/列宽+tractorOffset%列宽/列宽)
			//#每偏移±列宽cm则偏移的列变±1，最后用当前列减去偏移的列
            int columnWidth=m.columnWidth();
            tractorColumn=t.pathType==0||t.pathType==1||t.pathType==2?currentColumn-tractorOffset/columnWidth-tractorOffset%columnWidth/columnWidth:currentColumn+tractorOffset/columnWidth+tractorOffset%columnWidth/columnWidth;
        }
        else
            tractorColumn=floor(bzst.VerticalOff/m.columnWidth())+currentColumn;
        if(tractorRow!=-999999)
        {
            int rowCount=m.blockVector.size(),t=tractorRow;
            if(t<0)
                t=-1;
            else if(t>rowCount)
                t=rowCount;
            int tractorShowRow=t;
			tractorShowRow=hasABLine||direction?(tractorShowRow+1)*2:((QStandardItemModel *)ui->tableViewMap->model())->rowCount()-(tractorShowRow+1)*2-1;
            std::vector<int> showColumn=columnToShowGroup(++tractorColumn);
			for(size_t i=0;i<showColumn.size();)
                ((QStandardItemModel *)ui->tableViewMap->model())->item(tractorShowRow,showColumn[i++])->setIcon(direction?getTransparentPixmap(":/resource/image/tractor.png").transformed(QTransform().rotate(180),Qt::SmoothTransformation):getTransparentPixmap(":/resource/image/tractor.png"));
            if(lastTractorRow!=tractorShowRow||lastTractorColumn!=showColumn)
            {
                //更新车辆图标位置
                if(lastTractorRow!=-1)
                    for(size_t i=0;i<lastTractorColumn.size();((QStandardItemModel *)ui->tableViewMap->model())->item(lastTractorRow,lastTractorColumn[i++])->setIcon(QIcon()));
                lastTractorRow=tractorShowRow;
                lastTractorColumn=showColumn;
            }
        }
        else
            //当前在过道中，清除车辆图标
            for(size_t i=0;i<lastTractorColumn.size();((QStandardItemModel *)ui->tableViewMap->model())->item(lastTractorRow,lastTractorColumn[i++])->setIcon(QIcon()));
        //播种流程
        if(bzst.RowNum<=-10000000)//未开始播种或开始但未播种状态，-10000000为开始但未播种状态
            return;
        if(sowState)
        {
			if(bzst.RowNum<0||bzst.RowNum>=(s32)m.blockVector.size())
            {
				//当前播种的排超出范围
				if(currentReadRowNum==0||currentReadRowNum==(int)m.blockVector.size()-1)
                    setBlockState(currentReadRowNum,currentColumn,2);
                if(ui->checkBoxSowExceedMap->checkState()==Qt::Checked&&bzst.RowNum!=currentReadRowNum)
                    startNode(bzst.RowNum,currentColumn);
            }
            else
            {
                t.lastBlockRow=bzst.RowNum;//最新完成的行
                t.lastBlockColumn=currentColumn;//最新完成的列
                tempIndex=getIndex(bzst.RowNum,currentColumn)+1;
                if(tempIndex==path.size())//下一个区域重置回路径首个区域，省去取A点时做越界判断
                    tempIndex=0;
                t.outsetRow=path[tempIndex].row;
                t.outsetColumn=path[tempIndex].column;
                bool b=ui->checkBoxSowExceedMap->checkState()==Qt::Checked,sowFlag=t.isSow(path[nextPathIndex].row,currentColumn,b);
				if(sowFlag&&path[nextPathIndex].row<(int)m.blockVector.size()&&path[nextPathIndex].row>=0)
                    //记录播种数
                    for(int i=0;i<m.blockEachTrip();currentResult[i++].save())
                    {

                        int c=t.lastBlockColumn+i,temp=i*m.blockColumn;
       //                  t.routeBlockVector[t.lastBlockRow][c].endTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");//要实时更新
       //                  std::vector<int>().swap(t.routeBlockVector[t.lastBlockRow][c].seedCount);
       //                  std::vector<int>().swap(t.routeBlockVector[t.lastBlockRow][c].fertilizerCount);
       //                  //结果中的种子行代表种子在机器内的行
       //                  for(int k=0;k++<temp;t.routeBlockVector[t.lastBlockRow][c].seedCount.push_back(0))
       //                      t.routeBlockVector[t.lastBlockRow][c].fertilizerCount.push_back(0);
       //                  for(int k=0;k<m.blockColumn;t.routeBlockVector[t.lastBlockRow][c].seedCount.push_back(bzst.LouZHCnt[temp+k++]))
       //                      t.routeBlockVector[t.lastBlockRow][c].fertilizerCount.push_back(bzst.LoufeiCnt[temp+k]);
       //                  for(;t.routeBlockVector[t.lastBlockRow][c].seedCount.size()<maxSowColumn;t.routeBlockVector[t.lastBlockRow][c].seedCount.push_back(0))
       //                      t.routeBlockVector[t.lastBlockRow][c].fertilizerCount.push_back(0);
                        currentResult[i].endTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
                        currentResult[i].state=2;//完成
                        for(int k=0;k<m.blockColumn;k++)
                        {
                            currentResult[i].fertilizerCount[k]=bzst.LoufeiCnt[temp+k];
                            currentResult[i].seedCount[k]=bzst.LouZHCnt[temp+k];
                        }
                        t.saveBlock(t.lastBlockRow,t.lastBlockColumn+i);
                    }
                if(bzst.RowNum==path[nextPathIndex].row)
                {
                    //此时bzst.RowNum==nextPathIndex.row为正在播种的排
                    if(!enterMapFlag)
                    {
                        //避免重复下发开始的排
                        startNode(path[nextPathIndex].row,currentColumn);
                        enterMapFlag=true;
                    }
                    if(sowFlag)
                        setBlockState(path[nextPathIndex].row,currentColumn,1);
                    showCurrentBlock(path[nextPathIndex].row,currentColumn);
                }
                else if(t.routeBlockVector[path[nextPathIndex].row][currentColumn].state==1||t.routeBlockVector[path[nextPathIndex].row][currentColumn].state==2||!sowFlag)//刚走完当前区域，或当前区域不播种
                {
                    //此时bzst.RowNum为正在播种的排，nextPathIndex.row为刚结束的排
                    ui->tableViewMap->scrollTo(model->index(path[nextPathIndex].row*2,currentColumn+1),QAbstractItemView::PositionAtCenter);
                    if(sowFlag)
                    {
						setBlockState(path[nextPathIndex].row,currentColumn,2);
                        showLastBlock(path[nextPathIndex].row,currentColumn);
                    }
                    if(nextPathIndex<path.size())
                        startNode(path[++nextPathIndex].row,currentColumn);
                }
            }
        }
        currentReadRowNum=bzst.RowNum;
    });
    connect(&c,&Communication::signalGetDebugInformation,this,[=,&c](QString qs){
        if(c.getDebugInfoMode()==SOW)
        {
            if(recentDebugInfo!=qs)
            {
                writeLog(qs+" "+ui->labelTravelDistance->text());
                recentDebugInfo=qs;
            }
            ui->labelDebugInformation->setText(qs);
        }
    });
    connect(ui->tableViewMap,&QTableView::clicked,this,[=](const QModelIndex &index){
        int row=index.row(),column=index.column();
        QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
        if(!ui->checkBoxModifyOutset->isChecked()||row%2==1||row==0||row==model->rowCount()-1||column==0||column==model->columnCount()-1)//选择了外圈或过道
            return;
        clearOutset();
        showOutset(row/2-1,m.getColumnNode(column-1)[0]);
    });
    connect(ui->pushButtonSetDotWhenClearSeed,&QPushButton::clicked,this,[=,&c]{
        c.setDotWhenClearSeed(ui->checkBoxDotWhenClearSeed->isChecked());
    });
    connect(ui->pushButtonSaveABLine,&QPushButton::clicked,this,[=,&c]{
        if(!sowState)
            return;
        bool b=m.abLineName.isEmpty();
        if((b&&QMessageBox::question(this,"提示","是否要保存AB线？")==QMessageBox::Yes)||(!b&&QMessageBox::question(this,"提示","地图"+m.name+"已存在AB线，确定要覆盖吗？")==QMessageBox::Yes))
			c.getABLine();
	});
    connect(&c,&Communication::signalGetABLine,this,[=](BDParaType bdpt){
		m.abLine=bdpt;
		connect(&slotTimer,&QTimer::timeout,this,&DialogRealtimeTask::slotInputABLineName);
		slotTimer.start(0);
    });
    connect(ui->pushButtonClearABLine,&QPushButton::clicked,this,[=,&c]{
		if(m.abLineName.isEmpty()||QMessageBox::question(this,"提示","清除AB线后使用地图"+m.name+"的任务将全部受影响，确定吗？")==QMessageBox::No)
            return;
        m.clearABLine();
        emit signalABLineStateUpdated(m.name);
        QMessageBox::information(this,"提示","清除AB线成功");
        ui->pushButtonABLine->setText("无");
        c.setEmptyABLine();
    });
    connect(this,&DialogRealtimeTask::signalABLineStateUpdated,this,[=](QString mapName){
        ui->checkBoxSowExceedMap->setEnabled(!m.abLineName.isEmpty());
    });
    msgBox=new QMessageBox(QMessageBox::Question,"提示","是否要保存AB线？",QMessageBox::Yes|QMessageBox::No,this);
    msgBox->setModal(false);
    connect(msgBox,&QMessageBox::finished,this,[=,&c](int result){
        if(result==QMessageBox::Yes)
            c.getABLine();
    });
    setWindowFlags(windowFlags()|Qt::WindowMinMaxButtonsHint);
    lastTractorRow=-1;//未初始化
    showOutset(t.outsetRow,t.outsetColumn);
    tempIndex=nextPathIndex;
    direction=path[nextPathIndex].positive;
    currentColumn=t.outsetColumn;
    setTouchable(ui->tableViewCurrentBlock);
    setTouchable(ui->tableViewLastBlock);
    setTouchable(ui->tableViewCurrentBlock);
    setTouchable(ui->tableViewMap);
    CurrentBlockTableModel *cbtm=new CurrentBlockTableModel(currentBlockVector);
    ui->tableViewCurrentBlock->setModel(cbtm);
    ui->tableViewCurrentBlock->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    ui->tableViewCurrentBlock->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    LastBlockTableModel *lbtm=new LastBlockTableModel(lastBlockVector);
    ui->tableViewLastBlock->setModel(lbtm);
    ui->tableViewLastBlock->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    ui->tableViewLastBlock->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    if(maxSowColumn<6)//4行机只显示4列
        for(int i=maxSowColumn;i<6;i++)
        {
            ui->tableViewCurrentBlock->setColumnHidden(i,true);
            ui->tableViewLastBlock->setColumnHidden(i,true);
        }
    connect(ui->pushButtonResult,&QPushButton::clicked,this,[=]{
        DialogTaskResult(t.name).exec();
    });
    if(m.abLineName.isEmpty())
    {
        //除非AB线被保存，否则会每次更新
        m.abLineDirection=path[nextPathIndex].positive;
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
        c.setEmptyABLine();
    }
    else
        c.setABLine(m.abLine);
    c.setUserParameter(m.getUserParameter(),SOW);
    connect(ui->pushButtonABLine,&QPushButton::clicked,this,[=]{
        if(m.abLineName.isEmpty())
            return;
        DialogABLine da(m.abLineName,this);
        da.setPosition(m.aRow,m.aColumn,m.abLineDirection);
		da.setGroupBox2Visible(true);
        da.exec();
    });
    connect(ui->pushButtonImportABLine,&QPushButton::clicked,this,[=,&c]{
        DialogChooseABLine dca(m.name,this);
        if(dca.exec()==QDialog::Accepted)
        {
            Database d;
            d.open();
            QSqlQuery qsq(d.qsd);
            qsq.prepare("UPDATE "+MAPTABLE+" SET ARow=?,AColumn=?,ABLineDirection=?,ABLineName=? WHERE Name=?");
            bool b=dca.getDirection();
            int aRow=b?0:m.blockVector.size()-1,aColumn=dca.getColumn();
            qsq.addBindValue(aRow);
            qsq.addBindValue(aColumn);
            qsq.addBindValue(b);
            QString abLineName=dca.getABLineName();
            qsq.addBindValue(abLineName);
            qsq.addBindValue(m.name);
            if(qsq.exec())
            {
                m.abLineName=abLineName;
                m.aRow=aRow;
                m.aColumn=aColumn;
                ui->pushButtonABLine->setText(abLineName);
                m.loadABLine();
                c.setABLine(m.abLine);
            }
            emit signalABLineStateUpdated(m.name);
        }
    });
	connect(ui->pushButtonExport,&QPushButton::clicked,this,[=]{
		QString dirPath=QFileDialog::getExistingDirectory(this,"请选择文件保存路径");
		if(dirPath.isEmpty())
			return;
		if(QFile::exists(dirPath+"/任务 "+t.name+".xlsx"))
		{
			QMessageBox::information(this,"信息","无法导出"+t.name+"，文件已存在");
			return;
		}
        QMessageBox::information(this,"信息",t.exportToXlsx(dirPath)?"导出完成":"任务"+t.name+"导出失败");
	});
    connect(&deviceStateTimer,&QTimer::timeout,this,[=,&c]{
        ui->pushButtonDeviceState->setStyleSheet(c.getConnectionState()&&c.getBdState()?"border-radius:30px;border:2px solid #166534;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #86efac,stop:0.5 #22c55e,stop:1 #15803d);":"border-radius:30px;border:2px solid #991b1b;background-color:qradialgradient(cx:0.4,cy:0.35,radius:0.65,fx:0.4,fy:0.35,stop:0 #fca5a5,stop:0.5 #ef4444,stop:1 #991b1b);");
    });
    for(int i=0;i++<m.blockEachTrip();)
    {
        BlockResult br;
        br.taskName=t.name;
        for(int j=0;j++<maxSowColumn;br.seedCount.push_back(0))
            br.fertilizerCount.push_back(0);
        currentResult.push_back(br);
    }
    deviceStateTimer.start(1000);
	slotComboBoxViewCurrentTextChanged(ui->comboBoxView->currentText());
}

DialogRealtimeTask::~DialogRealtimeTask()
{
	delete ui;
}

void DialogRealtimeTask::showOutset(size_t row,size_t column)
{
    if(row>=t.routeBlockVector.size()&&column>=t.routeBlockVector[0].size())
    {
        showOutsetRow=-1;
        return;
    }
    showOutsetRow=row;
    showOutsetColumn=column;
    t.outsetRow=showOutsetRow;
    t.outsetColumn=showOutsetColumn;
    direction=columnDirection(column);
    currentColumn=t.outsetColumn;
    if(lastTractorRow!=-1)
        for(size_t i=0;i<lastTractorColumn.size();((QStandardItemModel *)ui->tableViewMap->model())->item(lastTractorRow,lastTractorColumn[i++])->setIcon(QIcon()));
    lastTractorRow=showOutsetRow;
    nextPathIndex=getIndex(row,column);
    QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
    int blockEachTrip=m.blockEachTrip();
    QPixmap qp;
    std::vector<int> columnVector=m.getColumnNode(column);
    for(int i=0;i<blockEachTrip;i++)
    {
        int c=column+i;
        if(!m.blockVector[row][c].sowSeed)
            continue;
        switch(t.routeBlockVector[row][c].state)
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
		if(direction)
            qp=qp.transformed(QTransform().rotate(180),Qt::SmoothTransformation);
        model->item(2*(row+1),c+1)->setBackground(qp.scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
    }
}

void DialogRealtimeTask::setBackground(int row,int column,int state)
{
    if(m.blockVector[row][column].sowSeed)
        switch(state)
        {
        case 0:
			((QStandardItemModel *)ui->tableViewMap->model())->item(2*(row+1),column+1)->setBackground(getTransparentPixmap(":/resource/image/task-block-unstarted.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        case 1:
			((QStandardItemModel *)ui->tableViewMap->model())->item(2*(row+1),column+1)->setBackground(getTransparentPixmap(":/resource/image/task-block-running.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        case 2:
			((QStandardItemModel *)ui->tableViewMap->model())->item(2*(row+1),column+1)->setBackground(getTransparentPixmap(":/resource/image/task-block-finished.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        case 3:
			((QStandardItemModel *)ui->tableViewMap->model())->item(2*(row+1),column+1)->setBackground(getTransparentPixmap(":/resource/image/task-block-failed.png").scaled(MAPTABLECELLWIDTH,MAPTABLECELLHEIGHT));
            break;
        default:;
        }
}

void DialogRealtimeTask::startNode(int row,int column)
{
    //对于RowNum在地图外的播种排
    BZCellParaType_st bzcpt;
	int rowCount=m.rowAttributesVector.size();
    //若无AB线则默认同向
    bool b=ui->checkBoxSowExceedMap->checkState()==Qt::Checked,d=columnDirection(column);//column对应的行进方向
    bzcpt.TXFlag=m.abLineName.isEmpty()?1:d==m.abLineDirection?1:0;
    bzcpt.isAfterNextZoneSow=t.isSow(d?row+2:row-2,column,b);
    bzcpt.RowNum=row;
    bzcpt.DisplayRowNum=t.routeBlockVector.size()-row;
    if(row>=0&&row<rowCount)
    {
        //在地图内
        if(d)
        {
            //正向
            bzcpt.FinalFlag=(b||row>=rowCount-1)?1:0;
            bzcpt.InS=m.aisleVector[row].length;
        }
        else
        {
            //反向
            bzcpt.FinalFlag=(b||row<=0)?1:0;
            bzcpt.InS=m.aisleVector[row+1].length;
        }
        for(int i=0;i<maxSowColumn;i++)
            bzcpt.Density[i]=t.density(row,column+i/m.blockColumn,b);
        bzcpt.CellLen=m.rowAttributesVector[row].length;//设太小会导致模拟程序小区切换过快，流程异常
    }
    else
    {
        //在地图外
        bzcpt.FinalFlag=b?0:1;
        if(d)
        {
            //正向
            bzcpt.InS=m.aisleVector[rowCount].length;
			for(int i=0;i<maxSowColumn;i++)
				bzcpt.Density[i]=t.density(rowCount,column+i/m.blockColumn,b);
            bzcpt.CellLen=m.rowAttributesVector[rowCount-1].length;
        }
        else
        {
            //反向
            bzcpt.InS=m.aisleVector[0].length;
			for(int i=0;i<maxSowColumn;i++)
				bzcpt.Density[i]=t.density(0,column+i/m.blockColumn,b);
            bzcpt.CellLen=m.rowAttributesVector[0].length;
        }
    }
    bzcpt.StartPOS=m.startPosition(bzcpt.RowNum,d);
    bzcpt.NextRowNum=d?row+1:row-1;
    bzcpt.NextDisplayRowNum=t.routeBlockVector.size()-bzcpt.NextRowNum;
    if(bzcpt.NextRowNum>=0&&bzcpt.NextRowNum<rowCount)
    {
        //在地图内
        if(d)
        {
            //正向
            bzcpt.NextFinalFlag=(b||bzcpt.NextRowNum<rowCount-1)?0:1;
            bzcpt.NextInS=m.aisleVector[bzcpt.NextRowNum+1].length;
        }
        else
        {
            //反向
            bzcpt.NextFinalFlag=(b||bzcpt.NextRowNum>0)?0:1;
            bzcpt.NextInS=m.aisleVector[bzcpt.NextRowNum].length;
        }
        for(int i=0;i<maxSowColumn;i++)
            bzcpt.NextDensity[i]=t.density(bzcpt.NextRowNum,column+i/m.blockColumn,b);
        bzcpt.NextCellLen=m.rowAttributesVector[bzcpt.NextRowNum].length;//设太小会导致模拟程序小区切换过快，流程异常
    }
    else
    {
        //在地图外
        bzcpt.NextFinalFlag=b?0:1;
        if(d)
        {
            //正向
            bzcpt.NextInS=m.aisleVector[rowCount].length;
			for(int i=0;i<maxSowColumn;i++)
				bzcpt.NextDensity[i]=t.density(rowCount,column+i/m.blockColumn,b);
            bzcpt.NextCellLen=m.rowAttributesVector[rowCount-1].length;
        }
        else
        {
            //反向
            bzcpt.NextInS=m.aisleVector[0].length;
			for(int i=0;i<maxSowColumn;i++)
				bzcpt.NextDensity[i]=t.density(-1,column+i/m.blockColumn,b);
            bzcpt.NextCellLen=m.rowAttributesVector[0].length;
        }
    }
    bzcpt.NextStartPOS=m.startPosition(bzcpt.NextRowNum,d);
	qDebug()<<bzcpt;
    writeLog(bzcpt.getString()+" "+ui->labelTravelDistance->text());
    c.setSowParameters(bzcpt);
}

void DialogRealtimeTask::slotRadioButtonPathType1Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(0);
    nextPathIndex=0;
    t.outsetRow=path[nextPathIndex].row;
    t.outsetColumn=path[nextPathIndex].column;
    if(m.abLineName.isEmpty())
    {
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
    }
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}


void DialogRealtimeTask::slotRadioButtonPathType2Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(1);
    nextPathIndex=0;
    t.outsetRow=path[nextPathIndex].row;
    t.outsetColumn=path[nextPathIndex].column;
    if(m.abLineName.isEmpty())
    {
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
    }
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType3Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(2);
    nextPathIndex=0;
    t.outsetRow=path[nextPathIndex].row;
    t.outsetColumn=path[nextPathIndex].column;
    if(m.abLineName.isEmpty())
    {
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
    }
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType4Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(3);
    nextPathIndex=0;
    t.outsetRow=path[nextPathIndex].row;
    t.outsetColumn=path[nextPathIndex].column;
    if(m.abLineName.isEmpty())
    {
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
    }
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType5Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(4);
    nextPathIndex=0;
    t.outsetRow=path[nextPathIndex].row;
    t.outsetColumn=path[nextPathIndex].column;
    if(m.abLineName.isEmpty())
    {
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
    }
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::slotRadioButtonPathType6Toggled(bool checked)
{
    if(!checked)
        return;
    clearOutset();
    createPath(5);
    nextPathIndex=0;
    t.outsetRow=path[nextPathIndex].row;
    t.outsetColumn=path[nextPathIndex].column;
    if(m.abLineName.isEmpty())
    {
        m.aRow=t.outsetRow;
        m.aColumn=t.outsetColumn;
    }
    showOutset(path[nextPathIndex].row,path[nextPathIndex].column);
}

void DialogRealtimeTask::clearOutset()
{
    if(showOutsetRow==-1)
        return;
    std::vector<int> columnVector=m.getColumnNode(showOutsetColumn);
    for(size_t i=0;i<columnVector.size();i++)
        setBackground(showOutsetRow,columnVector[i],t.routeBlockVector[showOutsetRow][columnVector[i]].state);
}

void DialogRealtimeTask::createPath(int pathType)
{
    std::vector<PathNode>().swap(path);
    int blockEachTrip=m.blockEachTrip(),trip=m.blockVector[0].size()/m.blockEachTrip(),i;
    std::vector<int> columnVector;
    std::vector<bool> positiveVector;
    bool positive=ui->radioButtonPositive->isChecked();
    switch(pathType)
    {
    case 0:
        for(i=0;i<trip;)
		{
			columnVector.push_back(blockEachTrip*i++);
			positiveVector.push_back(positive);
			if(i==trip)
				break;
			columnVector.push_back(blockEachTrip*i++);
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
			columnVector.push_back(blockEachTrip*i++);
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
			columnVector.push_back(blockEachTrip*i);
			positiveVector.push_back(positive);
			columnVector.push_back(blockEachTrip*(trip-1-i++));
		}
        if(trip%blockEachTrip==1)
        {
            columnVector.push_back(blockEachTrip*i);
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
			columnVector.push_back(blockEachTrip*i--);
			positiveVector.push_back(positive);
			if(i<0)
				break;
			columnVector.push_back(blockEachTrip*i--);
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
			columnVector.push_back(blockEachTrip*i--);
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
			columnVector.push_back(blockEachTrip*(trip-1-i));
			positiveVector.push_back(positive);
			columnVector.push_back(blockEachTrip*i++);
		}
        if(trip%blockEachTrip==1)
        {
            columnVector.push_back(blockEachTrip*i);
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
	default:;
    }
}

void DialogRealtimeTask::showPathTypeIcon(bool b)
{
    ui->radioButtonPathType1->setIcon(QIcon(b?":/resource/image/positive_1.png":":/resource/image/reverse_1.png"));
    ui->radioButtonPathType2->setIcon(QIcon(b?":/resource/image/positive_2.png":":/resource/image/reverse_2.png"));
    ui->radioButtonPathType3->setIcon(QIcon(b?":/resource/image/positive_3.png":":/resource/image/reverse_3.png"));
    ui->radioButtonPathType4->setIcon(QIcon(b?":/resource/image/positive_4.png":":/resource/image/reverse_4.png"));
    ui->radioButtonPathType5->setIcon(QIcon(b?":/resource/image/positive_5.png":":/resource/image/reverse_5.png"));
    ui->radioButtonPathType6->setIcon(QIcon(b?":/resource/image/positive_6.png":":/resource/image/reverse_6.png"));
}

int DialogRealtimeTask::getIndex(int row,int column)
{
    size_t i=0;
    for(size_t i=0;i<path.size();i++)
        if(row==path[i].row&&column==path[i].column)
            return i;
    return path.size();
}

void DialogRealtimeTask::setBlockState(int row,int column,int state)
{
	for(int i=0;i<m.blockEachTrip();setBackground(row,column+i++,state))
	{
		t.routeBlockVector[row][column+i].state=state;
		if(state==2)
			t.saveBlock(row,column+i);
	}
}

void DialogRealtimeTask::showLastBlock(int row,int column)
{
    //最近完成的排的计数在保存时已写入currentResult
    std::vector<LastBlockTableModel::Data>().swap(lastBlockVector);
    for(size_t i=0;i<currentResult.size();i++)
    {
        LastBlockTableModel::Data d;
        d.seedCount=currentResult[i].seedCount;
        for(int k=d.seedCount.size();k<6;k++)
            d.seedCount.push_back(0);
        lastBlockVector.push_back(d);
    }
    ((LastBlockTableModel *)ui->tableViewLastBlock->model())->updateAll();
}

void DialogRealtimeTask::showCurrentBlock(int row,int column)
{
    //当前正在播的排的实时计数，计数器每次下发参数时清零
    std::vector<CurrentBlockTableModel::Data>().swap(currentBlockVector);
    for(int i=0;i<m.blockEachTrip();i++)
    {
        CurrentBlockTableModel::Data d;
        for(int k=0;k<m.blockColumn;k++)
            d.seedCount.push_back(bzState.LouZHCnt[i*m.blockColumn+k]);
        for(int k=d.seedCount.size();k<6;k++)
            d.seedCount.push_back(0);
        currentBlockVector.push_back(d);
    }
    ((CurrentBlockTableModel *)ui->tableViewCurrentBlock->model())->updateAll();
}

void DialogRealtimeTask::closeEvent(QCloseEvent *e)
{
    c.getMode()==SOW?e->ignore():e->accept();
}

std::vector<int> DialogRealtimeTask::columnToShowGroup(int column)
{
    std::vector<int> showColumnVector;
	for(int i=0;i<m.blockEachTrip();)
    {
		int t=column+i++;
        if(t<1)
        {
            if(std::find(showColumnVector.begin(),showColumnVector.end(),0)==showColumnVector.end())
                showColumnVector.push_back(0);
        }
		else if((size_t)t<=m.blockVector[0].size())
            showColumnVector.push_back(t);
        else if(std::find(showColumnVector.begin(),showColumnVector.end(),m.blockVector[0].size()+1)==showColumnVector.end())
            showColumnVector.push_back(m.blockVector[0].size()+1);
    }
    return showColumnVector;
}

bool DialogRealtimeTask::columnDirection(int column)
{
    for(size_t i=0;i<path.size();i++)
        if(path[i].column==column)
            return path[i].positive;
    return true;
}

void DialogRealtimeTask::setControlEnable(bool b)
{
    ui->radioButtonReverse->setEnabled(b);
    ui->radioButtonPositive->setEnabled(b);
    ui->radioButtonPathType1->setEnabled(b);
    ui->radioButtonPathType2->setEnabled(b);
    ui->radioButtonPathType3->setEnabled(b);
    ui->radioButtonPathType4->setEnabled(b);
    ui->radioButtonPathType5->setEnabled(b);
    ui->radioButtonPathType6->setEnabled(b);
    ui->pushButtonSetDotWhenClearSeed->setEnabled(b);
    ui->checkBoxSowExceedMap->setEnabled(b?!m.abLineName.isEmpty():false);
    ui->pushButtonSaveABLine->setEnabled(!b);
    ui->pushButtonImportABLine->setEnabled(b);
    ui->pushButtonClearABLine->setEnabled(b);
    ui->checkBoxModifyOutset->setEnabled(b);
}

void DialogRealtimeTask::slotInputABLineName()
{
    slotTimer.stop();
	disconnect(&slotTimer,&QTimer::timeout,this,&DialogRealtimeTask::slotInputABLineName);
	DialogInputABLineName dialn(this);
	if(dialn.exec()==QDialog::Accepted)
	{
        m.saveABLine(dialn.getName());
		emit signalABLineStateUpdated(m.name);
		ui->pushButtonABLine->setText(m.abLineName);
	}
}

void DialogRealtimeTask::slotComboBoxViewCurrentTextChanged(const QString &text)
{
    int rowCount=m.blockVector.size();
    for(int i=0;i<rowCount;i++)
		for(size_t j=0;j<m.blockVector[i].size();j++)
		{
			QStandardItem *qsi=((QStandardItemModel *)ui->tableViewMap->model())->item(2*(i+1),j+1);
			qsi->setTextAlignment(Qt::AlignCenter);
			if(text==Block::viewType[0])
                qsi->setText(QString::number(rowCount-i)+','+QString::number(j+1));
            else if(text==Block::viewType[1])
				qsi->setText(m.blockVector[i][j].number);
			else if(text==Block::viewType[2])
				qsi->setText(QString::number(m.blockVector[i][j].density));
		}
}
