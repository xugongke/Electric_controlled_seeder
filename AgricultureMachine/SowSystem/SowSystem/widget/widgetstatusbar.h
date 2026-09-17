#ifndef WIDGETSTATUSBAR_H
#define WIDGETSTATUSBAR_H

#include <QWidget>
#include <QTimer>
#include "tool/communication.h"

namespace Ui {
class WidgetStatusBar;
}

class WidgetStatusBar : public QWidget
{
	Q_OBJECT

public:
    explicit WidgetStatusBar(Communication &c,QWidget *parent = nullptr);
	~WidgetStatusBar();

private:
	Ui::WidgetStatusBar *ui;
    QTimer qt;
    Communication &c;
};

#endif // WIDGETSTATUSBAR_H
