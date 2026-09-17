#ifndef VERTICALBARTABWIDGET_H
#define VERTICALBARTABWIDGET_H

#include <QTabWidget>
#include <QStringList>

class VerticalBarTabWidget : public QTabWidget
{
public:
	VerticalBarTabWidget(QWidget *parent = nullptr);
	static QStringList tabText;
};

#endif // VERTICALBARTABWIDGET_H
