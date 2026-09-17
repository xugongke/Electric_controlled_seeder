#include "widgetmapinfo.h"
#include "ui_widgetmapinfo.h"

WidgetMapInfo::WidgetMapInfo(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::WidgetMapInfo)
{
	ui->setupUi(this);
}

WidgetMapInfo::~WidgetMapInfo()
{
	delete ui;
}

void WidgetMapInfo::setMap(QString m)
{
	Map a;
	a.load(m);
	ui->labelCreateTime->setText(a.createTime);
	ui->labelModifyTime->setText(a.modifyTime);
	ui->labelMapMark->setText(a.mark);
}

void WidgetMapInfo::clear()
{
	ui->labelCreateTime->clear();
	ui->labelModifyTime->clear();
	ui->labelCompass->clear();
	ui->labelMapMark->clear();
}
