#include "pushbuttondelegate.h"
#include <QPushButton>
#include <QMouseEvent>

PushButtonDelegate::PushButtonDelegate(QObject *parent)
	: QStyledItemDelegate{parent}
{

}

void PushButtonDelegate::paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const
{
	QStyleOptionButton buttonStyle;
	buttonStyle.text = "删除";
	buttonStyle.rect = option.rect;
	buttonStyle.state = QStyle::State_Enabled;
	QPushButton button;
	button.style()->drawControl(QStyle::CE_PushButton,&buttonStyle,painter,&button);
}

bool PushButtonDelegate::editorEvent(QEvent *event, QAbstractItemModel *model, const QStyleOptionViewItem &option, const QModelIndex &index)
{
	QMouseEvent *mouseEvent =(QMouseEvent *)event;
	switch(mouseEvent->type())
	{
	case QEvent::MouseButtonPress:
		if(option.rect.contains(mouseEvent->pos()))
            emit deleted(index.row());
		break;
	default:;
	}
	return true;
}
