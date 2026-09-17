#include "maptable.h"
#include <QStandardItem>
#include <QScroller>
#include <QHeaderView>
#include <QDebug>
#include "global.h"
#include <QApplication>
#include <QScreen>

MapTable::MapTable(QWidget *parent):QTableView(parent),dsbi(new DialogSingleMapBlockInfo(this))
{
	setModel(new QStandardItemModel);
	setTouchable(this);
	horizontalHeader()->setSectionResizeMode(QHeaderView::Fixed);
	verticalHeader()->setSectionResizeMode(QHeaderView::Fixed);
    connect(dsbi,&DialogSingleMapBlockInfo::signalDataModified,this,[=](int row,int column){
        setItemCrop(((((QStandardItemModel *)model())->rowCount()-1)/2-row)*2-1,column,dsbi->crop());
        emit signalDataModified(row,column);
	});
}

void MapTable::setItemCrop(int row,int column,QString crop)
{
	QStandardItem *item=((QStandardItemModel *)model())->item(row,column);
    if(crop.isEmpty())
        item->setBackground(Qt::gray);
	else if(crop=="玉米")
		item->setBackground(Qt::yellow);
	else if(crop=="小麦")
		item->setBackground(Qt::darkYellow);
}

void MapTable::setItemBackground(int row,int column,int type,int direction,int state)
{
//	QStandardItem *item=((QStandardItemModel *)model())->item(row,column);
//	item->setText("");
//	switch(type)
//	{
//	case OUTSET:
//		item->setBackground(QPixmap(statePicture(":/resources/images/route-outset",state)).transformed(QMatrix().rotate(90*direction),Qt::SmoothTransformation).scaled(columnWidth(column),rowHeight(row)));
//		break;
//	case PATH:
//		item->setBackground(QPixmap(statePicture(":/resources/images/route-path",state)).transformed(QMatrix().rotate(90*direction),Qt::SmoothTransformation).scaled(columnWidth(column),rowHeight(row)));
//		break;
//	case END:
//		item->setBackground(QPixmap(statePicture(":/resources/images/route-end",state)).scaled(columnWidth(column),rowHeight(row)));
//	}
}

void MapTable::setItemIgnoreBackground(int row,int column,int direction,int incomeDirection)
{
	QStandardItem *item=((QStandardItemModel *)model())->item(row,column);
	item->setText("");
	switch(incomeDirection-direction)
	{
	case -3:
        item->setBackground(QPixmap(":/resources/images/route-rightangle.png").transformed(QTransform().rotate(90*2),Qt::SmoothTransformation).scaled(columnWidth(column),rowHeight(row)));
		break;
	case -1:
        item->setBackground(QPixmap(":/resources/images/route-rightangle.png").transformed(QTransform().rotate(90*direction),Qt::SmoothTransformation).scaled(columnWidth(column),rowHeight(row)));
		break;
	case 0:
		switch(direction)
		{
		case 0:
		case 2:
            item->setBackground(QPixmap(":/resources/images/route-line.png").transformed(QTransform().rotate(90),Qt::SmoothTransformation).scaled(columnWidth(column),rowHeight(row)));
			break;
		case 1:
		case 3:
			item->setBackground(QPixmap(":/resources/images/route-line.png").scaled(columnWidth(column),rowHeight(row)));
            break;
        default:;
		}
		break;
	case 1:
        item->setBackground(QPixmap(":/resources/images/route-rightangle.png").transformed(QTransform().rotate(90*(direction-1)),Qt::SmoothTransformation).scaled(columnWidth(column),rowHeight(row)));
		break;
	case 3:
		item->setBackground(QPixmap(":/resources/images/route-rightangle.png").scaled(columnWidth(column),rowHeight(row)));
        break;
    default:;
	}
}

QString MapTable::statePicture(QString picture,int state)
{
	switch(state)
	{
	case 0:
		return picture+".png";
	case 1:
		return picture+"-uncompleted.png";
	case 2:
		return picture+"-completed.png";
    case 3:
        return picture+"-failed.png";
	}
	return "";
}

void MapTable::setBlock(YieldBlock *b)
{
	dsbi->setBlock(b);
}

void MapTable::clear(int row,int column)
{
	QStandardItem *item=((QStandardItemModel *)model())->item(row,column);
	item->setText("");
	item->setBackground(Qt::NoBrush);
}

void MapTable::showBlockDialog(int row,int column)
{
	dsbi->show();//先显示再获取宽高
    dsbi->setCoordinate((model()->rowCount()-row)/2-1,column);
	QPoint qp(mapToGlobal(QPoint(0,0)));//转换为相对于屏幕左上角坐标
    int margin=dsbi->margin(),dialogWidth=dsbi->width(),x=qp.x()+columnViewportPosition(column)+verticalHeader()->width()-(dialogWidth-MAPTABLECELLWIDTH)/2,y=qp.y()+rowViewportPosition(row)+horizontalHeader()->height()+margin-dsbi->height(),screenWidth=QGuiApplication::primaryScreen()->geometry().width();
    if(x<0)
        x=-margin;
    else if(x-margin+dialogWidth>screenWidth)
        x=screenWidth-dialogWidth+margin;
    if(y<0)
        y=-margin;
    dsbi->move(x,y);
}

void MapTable::setDialogReadOnly(bool b)
{
	dsbi->setReadOnly(b);
}
