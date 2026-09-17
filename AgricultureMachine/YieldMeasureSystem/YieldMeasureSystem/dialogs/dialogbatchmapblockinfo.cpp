#include "dialogbatchmapblockinfo.h"
#include "ui_dialogbatchmapblockinfo.h"
#include "global.h"
#include <QListView>

DialogBatchMapBlockInfo::DialogBatchMapBlockInfo(QWidget *parent) :
	QDialog(parent),
    ui(new Ui::DialogBatchMapBlockInfo)
{
	ui->setupUi(this);
	ui->comboBoxCrop->setView(new QListView);
	ui->comboBoxCrop->addItem("无");
	ui->comboBoxCrop->addItems(cropList);
}

DialogBatchMapBlockInfo::~DialogBatchMapBlockInfo()
{
	delete ui;
}

YieldBlock DialogBatchMapBlockInfo::value()
{
    YieldBlock b;
    QString text=ui->comboBoxCrop->currentText();
    if(text=="无")
        b.crop.clear();
    else
        b.crop=text;
	b.number=ui->lineEditNumber->text();
	return b;
}
