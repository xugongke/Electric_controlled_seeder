#include "dialogsinglemapblockinfo.h"
#include "ui_dialogsinglemapblockinfo.h"
#include <QDebug>

DialogSingleMapBlockInfo::DialogSingleMapBlockInfo(QWidget *parent) :
	QDialog(parent),
    ui(new Ui::DialogSingleMapBlockInfo)
{
	ui->setupUi(this);
	setWindowFlags(Qt::FramelessWindowHint|windowFlags());
	setAttribute(Qt::WA_TranslucentBackground);
    connect(ui->frame,&FrameSingleMapBlockInfo::signalDataModified,this,[=]{
		emit signalDataModified(ui->frame->row(),ui->frame->column());
	});
}

DialogSingleMapBlockInfo::~DialogSingleMapBlockInfo()
{
	delete ui;
}

void DialogSingleMapBlockInfo::setBlock(YieldBlock *b)
{
	ui->frame->setBlock(b);
}

void DialogSingleMapBlockInfo::changeEvent(QEvent *qe)
{
	if(qe->type()==QEvent::ActivationChange&&!isActiveWindow())
		close();
}

void DialogSingleMapBlockInfo::setCoordinate(int row,int column)
{
	ui->frame->setCoordinate(row,column);
}

int DialogSingleMapBlockInfo::margin()
{
	return ui->horizontalLayout->margin()+SHADOW_WIDTH;//窗口和ui->frame的间距
}

void DialogSingleMapBlockInfo::setReadOnly(bool b)
{
	ui->frame->setReadOnly(b);
}

QString DialogSingleMapBlockInfo::crop()
{
	return ui->frame->crop();
}
