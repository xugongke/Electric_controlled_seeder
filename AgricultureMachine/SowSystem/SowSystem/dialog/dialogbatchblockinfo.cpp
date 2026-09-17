#include "dialogbatchblockinfo.h"
#include "ui_dialogbatchblockinfo.h"
#include <QListView>

DialogBatchBlockInfo::DialogBatchBlockInfo(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogBatchBlockInfo)
{
	ui->setupUi(this);
}

DialogBatchBlockInfo::~DialogBatchBlockInfo()
{
	delete ui;
}

Block DialogBatchBlockInfo::value()
{
	Block b;
	b.density=ui->spinBoxDensity->value();
	switch(ui->checkBoxSowSeed->checkState())
	{
	case Qt::Unchecked:
		b.sowSeed=false;
		break;
	case Qt::Checked:
		b.sowSeed=true;
		break;
	default:;
	}
	return b;
}
