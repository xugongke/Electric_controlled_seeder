#include "dialognewtask.h"
#include "ui_dialognewtask.h"
#include <QMessageBox>
#include <QDir>
#include <QDebug>
#include <QDateTime>
#include "dataStructs/yieldmap.h"
#include <QStandardItem>
#include <QMenu>
#include "dataStructs/task.h"
#include "../../common/database.h"
#include "global.h"
#include "tools/settingshandle.h"

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
		QString name=ui->lineEditTaskName->text();
		if(name.isEmpty())
		{
			QMessageBox::information(this,"提示","任务名不能为空");
			return;
		}
		QString map=ui->comboBoxMap->currentText();
		if(map.isEmpty())
		{
			QMessageBox::information(this,"提示","地图不能为空");
			return;
		}
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("SELECT Name FROM "+TASKTABLE+" WHERE Name=?");
		qsq.addBindValue(name);
		qsq.exec();
		if(qsq.next())
		{
            QMessageBox::information(this,"提示","已有同名任务存在");
			d.close();
			return;
		}
		d.close();
        Task ta;
        YieldMap m;
        m.load(map);
        ta.name=name;
		ta.mapName=map;
		for(size_t i=0;i<m.blockVector.size();i++)
		{
			std::vector<TaskBlock> tbv;
            for(size_t j=0;j<m.blockVector[i].size();)
			{
				TaskBlock tb;
				tb.state=0;
                tb.measure=!m.blockVector[i][j++].crop.isEmpty();
				tbv.push_back(tb);
			}
			ta.routeBlockVector.push_back(tbv);
		}
		ta.createTime=QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
        ta.mark=ui->textEditTaskMark->toPlainText();
        ta.startRow=m.blockVector.size()-1;
        ta.startColumn=0;
        ta.lastRow=-1;
        ta.lastColumn=0;
        ta.pathType=0;
        ta.positive=false;
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

//void DialogNewTask::calculatePath(QString routeType)
//{
//	QStandardItemModel *model=(QStandardItemModel *)ui->tableViewCheckRouteMap->model();
//	std::vector<std::vector<RouteBlock>>().swap(routeBlockVector);
//	int rowCount=model->rowCount(),lastRow=rowCount-1,columnCount=model->columnCount(),lastColumn=columnCount-1;
//	Map m;
//	m.load(ui->comboBoxMap->currentText());
//	for(int i=0;i<rowCount;++i)
//	{
//		std::vector<RouteBlock> rbv;
//		for(int j=0;j<columnCount;)
//		{
//			RouteBlock rb;
//			rb.isPath=m.blockVector[i][j++].crop!="无";
//			rbv.push_back(rb);
//		}
//		routeBlockVector.push_back(rbv);
//	}
//	std::vector<int>().swap(pathRowVector);
//	std::vector<int>().swap(pathColumnVector);
//	if(routeType=="蛇形")
//		switch(currentStartDirection)
//		{
//		case 0:
//			for(int column=0;column<columnCount;++column)
//			{
//				int row=lastRow;
//				for(;row>0;addPath(row--,column))
//					routeBlockVector[row][column].direction=currentStartDirection;
//				routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				addPath(row,column);
//				if(++column==columnCount)
//					break;
//				for(;row<lastRow;addPath(row++,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+2)%4;
//				routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				addPath(row,column);
//			}
//			break;
//		case 1:
//			for(int column=0;column<columnCount;++column)
//			{
//				int row=0;
//				for(;row<lastRow;addPath(row++,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//				if(++column==columnCount)
//					break;
//				for(;row>0;addPath(row--,column))
//					routeBlockVector[row][column].direction=(currentStartDirection-1)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//			}
//			break;
//		case 2:
//			for(int column=lastColumn;column>=0;)
//			{
//				int row=0;
//				for(;row<lastRow;addPath(row++,column))
//					routeBlockVector[row][column].direction=currentStartDirection;
//				routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				addPath(row,column);
//				if(column--==0)
//					continue;
//				for(;row>0;addPath(row--,column))
//					routeBlockVector[row][column].direction=(currentStartDirection-2)%4;
//				routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				addPath(row,column--);
//			}
//			break;
//		case 3:
//			for(int column=lastColumn;column>=0;)
//			{
//				int row=lastRow;
//				for(;row>0;addPath(row--,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//				if(column--==0)
//					continue;
//				for(;row<lastRow;addPath(row++,column))
//					routeBlockVector[row][column].direction=(currentStartDirection-1)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column--);
//			}
//		}
//	else if(routeType=="回形")
//	{
//		int loop=rowCount<columnCount?rowCount:columnCount,t,row,column;
//		loop=loop/2+loop%2;//+1或0的多余行
//		for(int l=0;l<loop;++l)
//			switch(currentStartDirection)
//			{
//			case 0:
//				t=lastRow-l;
//				row=t;
//				column=l;//last-l,0+l
//				for(;row>l;addPath(row--,column))
//					routeBlockVector[row][column].direction=currentStartDirection;
//				for(;column<lastColumn-l;addPath(row,column++))
//					routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				for(;row<t;addPath(row++,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+2)%4;
//				for(;column>l+1;addPath(row,column--))
//					routeBlockVector[row][column].direction=(currentStartDirection+3)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//				break;
//			case 1:
//				row=l;
//				column=l;
//				for(;column<lastColumn-l;addPath(row,column++))
//					routeBlockVector[row][column].direction=currentStartDirection;
//				for(;row<lastRow-l;addPath(row++,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				for(;column>l;addPath(row,column--))
//					routeBlockVector[row][column].direction=(currentStartDirection+2)%4;
//				for(;row>l+1;addPath(row--,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+3)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//				break;
//			case 2:
//				row=l;
//				column=l;
//				for(;row<lastRow-l;addPath(row++,column))
//					routeBlockVector[row][column].direction=currentStartDirection;
//				for(;column<lastColumn-l;addPath(row,column++))
//					routeBlockVector[row][column].direction=(currentStartDirection+3)%4;//逆时针
//				for(;row>l;addPath(row--,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+2)%4;
//				for(;column>l+1;addPath(row,column--))
//					routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//				break;
//			case 3:
//				t=lastColumn-l;
//				row=l;
//				column=t;
//				for(;column>l;addPath(row,column--))
//					routeBlockVector[row][column].direction=currentStartDirection;
//				for(;row<lastRow-l;addPath(row++,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+3)%4;
//				for(;column<t;addPath(row,column++))
//					routeBlockVector[row][column].direction=(currentStartDirection+2)%4;
//				for(;row>l+1;addPath(row--,column))
//					routeBlockVector[row][column].direction=(currentStartDirection+1)%4;
//				routeBlockVector[row][column].direction=currentStartDirection;
//				addPath(row,column);
//			}
//	}
//	size_t s=pathRowVector.size();
//	if(s==0)
//		return;
//	end=s-1;
//	for(size_t i=0;i<end;++i)
//		if(routeBlockVector[pathRowVector[i]][pathColumnVector[i]].isPath)
//		{
//			outset=i;
//			break;
//		}
//	for(size_t i=outset;i<s;++i)
//		if(routeBlockVector[pathRowVector[i]][pathColumnVector[i]].isPath)
//			end=i;
//	for(size_t i=outset+1;i<end;++i)
//	{
//		int t=i-1;
//		routeBlockVector[pathRowVector[i]][pathColumnVector[i]].incomeDirection=routeBlockVector[pathRowVector[t]][pathColumnVector[t]].direction;
//	}
//}
