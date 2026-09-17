#include "dialogrowattribute.h"
#include "ui_dialogrowattribute.h"
#include <QStandardItemModel>
#include "delegate/doublespinboxdelegate.h"
#include <QDebug>
#include "global.h"

DialogRowAttribute::DialogRowAttribute(std::vector<RowAttributes> rav,QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogRowAttribute),rav(rav)
{
	ui->setupUi(this);
	ui->tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->setItemDelegateForColumn(0,new DoubleSpinBoxDelegate);
	QStandardItemModel *model=new QStandardItemModel;
	ui->tableView->setModel(model);
    int rowCount=rav.size();
    for(int i=0;i<rowCount;i++)
    {
		model->setItem(i,new QStandardItem(QString::number(rav[i].length/100.0)+"m"));
        model->setVerticalHeaderItem(i,new QStandardItem(QString::number(rowCount-i)));
    }
    setTouchable(ui->tableView);
}

DialogRowAttribute::~DialogRowAttribute()
{
	delete ui;
}

std::vector<RowAttributes> DialogRowAttribute::value()
{
	for(size_t i=0;i<rav.size();)
	{
        float a=((QStandardItemModel *)ui->tableView->model())->item(i)->text().replace("m","").toFloat()*100;//直接把结果赋给length会出现误差，故定义一个临时变量
		rav[i++].length=a;
	}
	return rav;
}
