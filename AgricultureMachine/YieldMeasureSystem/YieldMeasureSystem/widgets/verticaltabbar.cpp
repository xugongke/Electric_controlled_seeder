#include "verticaltabbar.h"
#include <QStyleOptionTab>
#include <QStylePainter>

VerticalTabBar::VerticalTabBar()
{

}

QSize VerticalTabBar::tabSizeHint(int index) const
{
	QSize s = QTabBar::tabSizeHint(index);
	s.transpose();
	return s;
}

void VerticalTabBar::paintEvent(QPaintEvent *)
{
	QStylePainter painter(this);
	for(int i = 0;i < count();painter.restore())
	{
		QStyleOptionTab opt;
		initStyleOption(&opt,i);
		painter.drawControl(QStyle::CE_TabBarTabShape, opt);
		painter.save();
		QSize s = opt.rect.size();
		s.transpose();
		QRect r(QPoint(), s);
		r.moveCenter(opt.rect.center());
		opt.rect = r;
		QPoint c = tabRect(i++).center();
		painter.translate(c);
		painter.rotate(90);
		painter.translate(-c);
		painter.drawControl(QStyle::CE_TabBarTabLabel,opt);
	}
}
