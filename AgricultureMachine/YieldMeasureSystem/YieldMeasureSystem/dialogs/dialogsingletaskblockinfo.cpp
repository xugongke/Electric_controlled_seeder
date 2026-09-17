#include "dialogsingletaskblockinfo.h"
#include "ui_dialogsingletaskblockinfo.h"
#include <QDebug>

DialogSingleTaskBlockInfo::DialogSingleTaskBlockInfo(QWidget *parent)
    : QDialog(parent)
    , ui(new Ui::DialogSingleTaskBlockInfo)
{
    ui->setupUi(this);
    setWindowFlags(Qt::FramelessWindowHint|windowFlags());
    setAttribute(Qt::WA_TranslucentBackground);
    connect(ui->frame,&FrameSingleTaskBlockInfo::signalDataModified,this,[=]{
        emit signalDataModified(ui->frame->row(),ui->frame->column());
    });
}

DialogSingleTaskBlockInfo::~DialogSingleTaskBlockInfo()
{
    delete ui;
}

void DialogSingleTaskBlockInfo::setBlock(TaskBlock *b)
{
    ui->frame->setBlock(b);
}

void DialogSingleTaskBlockInfo::changeEvent(QEvent *qe)
{
    if(qe->type()==QEvent::ActivationChange&&!isActiveWindow())
        close();
}

void DialogSingleTaskBlockInfo::setCoordinate(int row,int column)
{
    ui->frame->setCoordinate(row,column);
}

int DialogSingleTaskBlockInfo::margin()
{
    return ui->horizontalLayout->margin()+SHADOW_WIDTH;//窗口和ui->frame的间距
}

void DialogSingleTaskBlockInfo::setReadOnly(bool b)
{
    ui->frame->setReadOnly(b);
}

bool DialogSingleTaskBlockInfo::measure()
{
    return ui->frame->measure();
}
