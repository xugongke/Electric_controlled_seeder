#include "spinboxdelegate.h"
#include <QSpinBox>
#include <QDebug>

SpinBoxDelegate::SpinBoxDelegate()
{

}

QWidget *SpinBoxDelegate::createEditor(QWidget *parent,const QStyleOptionViewItem &option,const QModelIndex &index) const
{
	QSpinBox *qsb=new QSpinBox(parent);
	qsb->setButtonSymbols(QSpinBox::NoButtons);
	qsb->setMaximum(10000);
	return qsb;
}

void SpinBoxDelegate::setEditorData(QWidget *editor,const QModelIndex &index) const
{
	QSpinBox *qsb=(QSpinBox *)editor;
	qsb->setValue(index.data(Qt::DisplayRole).toInt());
}

void SpinBoxDelegate::setModelData(QWidget *editor,QAbstractItemModel *model,const QModelIndex &index) const
{
	QSpinBox *spinBox=(QSpinBox *)editor;
	spinBox->interpretText();
	int value=spinBox->value();
	model->setData(index,QString::number(value),Qt::EditRole);
//	int density=model->data(model->index(index.row(),0)).toInt();
	//emit signalValueChanged(density,value);
}

void SpinBoxDelegate::updateEditorGeometry(QWidget *editor,const QStyleOptionViewItem &option,const QModelIndex &index) const
{
	editor->setGeometry(option.rect);
}
