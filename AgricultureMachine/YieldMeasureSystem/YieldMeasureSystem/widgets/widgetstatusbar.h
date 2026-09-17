#ifndef WIDGETSTATUSBAR_H
#define WIDGETSTATUSBAR_H

#include <QWidget>
#include <QTimer>

namespace Ui {
class WidgetStatusBar;
}

class WidgetStatusBar : public QWidget
{
	Q_OBJECT

public:
	explicit WidgetStatusBar(QWidget *parent = nullptr);
	~WidgetStatusBar();

private:
	Ui::WidgetStatusBar *ui;
	QTimer qt;
public slots:
    void slotValveStateUpdated();
};

#endif // WIDGETSTATUSBAR_H
