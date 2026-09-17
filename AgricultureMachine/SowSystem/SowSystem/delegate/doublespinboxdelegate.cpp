#include "doublespinboxdelegate.h"
#include <QDoubleSpinBox>
#include <QDebug>

DoubleSpinBoxDelegate::DoubleSpinBoxDelegate()
{

}

QWidget *DoubleSpinBoxDelegate::createEditor(QWidget *parent,const QStyleOptionViewItem &option,const QModelIndex &index) const
{
	QDoubleSpinBox *qsp=new QDoubleSpinBox(parent);
	qsp->setSuffix("m");
	qsp->setButtonSymbols(QDoubleSpinBox::NoButtons);
	return qsp;
}

void DoubleSpinBoxDelegate::setEditorData(QWidget *editor,const QModelIndex &index) const
{
	QDoubleSpinBox *qdsb=(QDoubleSpinBox *)editor;
	qdsb->setValue(index.data(Qt::DisplayRole).toString().replace(qdsb->suffix(),"").toFloat());
}

void DoubleSpinBoxDelegate::setModelData(QWidget *editor,QAbstractItemModel *model,const QModelIndex &index) const
{
	QDoubleSpinBox *spinBox=(QDoubleSpinBox *)editor;
	spinBox->interpretText();
	model->setData(index,QString::number(spinBox->value())+"m",Qt::EditRole);
}

void DoubleSpinBoxDelegate::updateEditorGeometry(QWidget *editor,const QStyleOptionViewItem &option,const QModelIndex &index) const
{
	editor->setGeometry(option.rect);
}
