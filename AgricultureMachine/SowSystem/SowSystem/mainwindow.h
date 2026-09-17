#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QPropertyAnimation>
#include <QGraphicsOpacityEffect>
#include "widget/widgetstatusbar.h"
#include "tool/communication.h"
#include "form/formtask.h"
#include "form/formmap.h"
#include "form/formhistory.h"
#include "form/formtest.h"
#include "form/formconfig.h"
#include "form/formcontinuoussow.h"
#include <QTimer>

QT_BEGIN_NAMESPACE
namespace Ui { class MainWindow; }
QT_END_NAMESPACE

class MainWindow : public QMainWindow
{
	Q_OBJECT

public:
	MainWindow(QWidget *parent = nullptr);
	~MainWindow();

protected:
	void closeEvent(QCloseEvent *) override;
    void resizeEvent(QResizeEvent *event) override;
    void showEvent(QShowEvent *event) override;

private:
    void fadeInWidget(QWidget *widget, int duration = 280);

	Ui::MainWindow *ui;
	WidgetStatusBar *wsb;
	int lastTab;
    Communication c;
    FormTask *ft;
    FormMap *fm;
    FormHistory *fh;
    FormTest *fte;
    FormConfig *fc;
    FormContinuousSow *fcs;
    QTimer debugInfoTimer;
private slots:
	void slotTabWidgetCurrentIndexChanged(int index);
};
#endif // MAINWINDOW_H
