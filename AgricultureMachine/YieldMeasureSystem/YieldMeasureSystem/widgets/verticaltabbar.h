#ifndef VERTICALTABBAR_H
#define VERTICALTABBAR_H

#include <QTabBar>

class VerticalTabBar : public QTabBar
{
public:
	VerticalTabBar();
	QSize tabSizeHint(int index) const override;
protected:
	void paintEvent(QPaintEvent *) override;
};

#endif // VERTICALTABBAR_H
