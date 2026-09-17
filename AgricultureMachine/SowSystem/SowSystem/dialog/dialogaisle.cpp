#include "dialogaisle.h"
#include "ui_dialogaisle.h"
#include <QStandardItemModel>
#include "delegate/doublespinboxdelegate.h"
#include "global.h"

DialogAisle::DialogAisle(std::vector<Aisle> av,QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogAisle),av(av)
{
	ui->setupUi(this);
	ui->tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
	ui->tableView->setItemDelegateForColumn(0,new DoubleSpinBoxDelegate);
	QStandardItemModel *model=new QStandardItemModel;
	ui->tableView->setModel(model);
    int rowCount=av.size();
    for(int i=0;i<rowCount;i++)
    {
		model->setItem(i,new QStandardItem(QString::number(av[i].length/100.0)+"m"));
        model->setVerticalHeaderItem(i,new QStandardItem(QString::number(rowCount-i)));
    }
    setTouchable(ui->tableView);
}

DialogAisle::~DialogAisle()
{
	delete ui;
}

std::vector<Aisle> DialogAisle::value()
{
	for(size_t i=0;i<av.size();)
	{
		float a=((QStandardItemModel *)ui->tableView->model())->item(i)->text().replace("m","").toFloat()*100;//直接把结果赋给length会出现误差（可能是因为类型转换），故定义一个临时变量
		av[i++].length=a;
	}
	return av;
}
