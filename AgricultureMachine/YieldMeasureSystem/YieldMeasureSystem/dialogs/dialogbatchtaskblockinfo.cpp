#include "dialogbatchtaskblockinfo.h"
#include "ui_dialogbatchtaskblockinfo.h"

DialogBatchTaskBlockInfo::DialogBatchTaskBlockInfo(QWidget *parent)
    : QDialog(parent)
    , ui(new Ui::DialogBatchTaskBlockInfo)
{
    ui->setupUi(this);
    connect(ui->pushButton,&QPushButton::clicked,this,[=]{
        accept();
    });
}

DialogBatchTaskBlockInfo::~DialogBatchTaskBlockInfo()
{
    delete ui;
}

TaskBlock DialogBatchTaskBlockInfo::value()
{
    TaskBlock b;
    b.measure=ui->checkBoxMeasure->checkState()==Qt::Checked;
    b.updateFlag=true;
    return b;
}
