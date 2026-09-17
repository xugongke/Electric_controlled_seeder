#ifndef PUSHBUTTONDELEGATE_H
#define PUSHBUTTONDELEGATE_H

#include <QStyledItemDelegate>

class PushButtonDelegate : public QStyledItemDelegate
{
	Q_OBJECT
public:
	explicit PushButtonDelegate(QObject *parent = nullptr);
	void paint(QPainter *painter, const QStyleOptionViewItem &option, const QModelIndex &index) const override;
	bool editorEvent(QEvent *event, QAbstractItemModel *model, const QStyleOptionViewItem &option,
	const QModelIndex &index) override;
signals:
    void deleted(int row);
};

#endif // PUSHBUTTONDELEGATE_H
