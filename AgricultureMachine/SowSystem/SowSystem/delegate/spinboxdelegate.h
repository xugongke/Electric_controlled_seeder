#ifndef SPINBOXDELEGATE_H
#define SPINBOXDELEGATE_H

#include <QStyledItemDelegate>

class SpinBoxDelegate : public QStyledItemDelegate
{
public:
	SpinBoxDelegate();
	 //创建编辑组件
	QWidget *createEditor(QWidget *parent,const QStyleOptionViewItem &option,const QModelIndex &index) const Q_DECL_OVERRIDE;
	//将代理组件的数据，保存到数据模型中
	void setEditorData(QWidget *editor,const QModelIndex &index) const Q_DECL_OVERRIDE;
	//将代理组件的数据，保存到数据模型中
	void setModelData(QWidget *editor,QAbstractItemModel *model,const QModelIndex &index) const Q_DECL_OVERRIDE;
	//更新代理编辑组件的大小
	void updateEditorGeometry(QWidget *editor,const QStyleOptionViewItem &option,const QModelIndex &index) const Q_DECL_OVERRIDE;
signals:
	void signalValueChanged(int density,int value);
};

#endif // SPINBOXDELEGATE_H
