#include "dialogsingleblockinfo.h"
#include "ui_dialogsingleblockinfo.h"
#include <QDebug>

DialogSingleBlockInfo::DialogSingleBlockInfo(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogSingleBlockInfo)
{
	ui->setupUi(this);
    setWindowFlags(Qt::FramelessWindowHint|windowFlags());
	setAttribute(Qt::WA_TranslucentBackground);
	connect(ui->frame,&FrameSingleBlockInfo::signalSowSeedModified,this,[=]{
		emit signalSowSeedModified(ui->frame->row(),ui->frame->column());
	});
	connect(ui->frame,&FrameSingleBlockInfo::signalDataModified,this,[=]{
		emit signalDataModified(ui->frame->row(),ui->frame->column());
	});
}

DialogSingleBlockInfo::~DialogSingleBlockInfo()
{
	delete ui;
}

void DialogSingleBlockInfo::setBlock(Block *b)
{
	ui->frame->setBlock(b);
}

void DialogSingleBlockInfo::changeEvent(QEvent *qe)
{
	if(qe->type()==QEvent::ActivationChange&&!isActiveWindow())
		close();
}

void DialogSingleBlockInfo::setCoordinate(int row,int column)
{
	ui->frame->setCoordinate(row,column);
}

int DialogSingleBlockInfo::margin()
{
	return ui->horizontalLayout->margin()+SHADOW_WIDTH;//窗口和ui->frame的间距
}

void DialogSingleBlockInfo::setReadOnly(bool b)
{
	ui->frame->setReadOnly(b);
}
