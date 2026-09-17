#include "mainwindow.h"
#include "ui_mainwindow.h"
#include "widgets/widgetstatusbar.h"
#include <QMessageBox>
//#include "network/tcp.h"
#include "global.h"
//#include "network/threaddata.h"
#include "uart/threaduart.h"

#define ROUTEMAPTABLECELLHEIGHT 70
#define ROUTEMAPTABLECELLWIDTH 70

MainWindow::MainWindow(QWidget *parent)
	: QMainWindow(parent)
	, ui(new Ui::MainWindow)
{
	ui->setupUi(this);
    WidgetStatusBar *wsb=new WidgetStatusBar;
    ui->statusbar->addWidget(wsb);
    connect(ui->widget,&FormTask::signalTaskListUpdated,ui->widget_3,&FormHistory::slotRefreshComboBoxTaskFilter);
    connect(G.tUart,&ThreadUart::sig_uart,this,[=](int cmd,int len,void *args){
        if(cmd!=CMD_EX_R_REG)
            return;
        int t=((CmdBody *)args)->ia[0]&31;
        if(G.valveState!=t)
        {
            G.valveState=t;
            emit signalValveStateChanged();
        }
    });
//    connect(&qt,&QTimer::timeout,this,[=]{
//        TcpFormat tf;
//        tf.h.h=CMD_HEAD;
//        tf.h.cmd=CMD_EX_R_REG;
//        tf.h.len=sizeof(CmdHead);
//        if(G.tData->sendCmd(0,&tf)!=-1&&G.valveState!=tf.b.i)
//        {
//            G.valveState=tf.b.i;
//            emit signalValveStateChanged();
//        }
//    });
    connect(this,&MainWindow::signalValveStateChanged,wsb,&WidgetStatusBar::slotValveStateUpdated);
    connect(this,&MainWindow::signalValveStateChanged,ui->widget_4,&FormSetting::slotValveStateUpdated);
    connect(ui->widget_4,&FormSetting::signalSettingsUpdated,ui->widget,(void(FormTask:: *)())(&FormTask::slotReloadTask));
    connect(ui->widget_3,&FormHistory::signalResultDeleted,ui->widget,(void(FormTask:: *)(QString))(&FormTask::slotReloadTask));
    connect(ui->tabWidget,&QTabWidget::currentChanged,this,[=](int index){
        fadeInWidget(ui->tabWidget->widget(index));
    });
    showMaximized();
    //qt.start(500);
}

MainWindow::~MainWindow()
{
	delete ui;
}

void MainWindow::resizeEvent(QResizeEvent *event)
{
    ui->tabWidget->tabBar()->setMinimumWidth(ui->tabWidget->width());
    QWidget::resizeEvent(event);
}

void MainWindow::showEvent(QShowEvent *event)
{
    ui->tabWidget->tabBar()->setMinimumWidth(ui->tabWidget->width());
    QWidget::showEvent(event);
    static bool firstShow = true;
    if (firstShow) {
        firstShow = false;
        fadeInWidget(centralWidget(), 500);
    }
}

void MainWindow::fadeInWidget(QWidget *widget, int duration)
{
    auto *effect = new QGraphicsOpacityEffect(widget);
    widget->setGraphicsEffect(effect);
    auto *anim = new QPropertyAnimation(effect, "opacity", widget);
    anim->setDuration(duration);
    anim->setStartValue(0.0);
    anim->setEndValue(1.0);
    anim->setEasingCurve(QEasingCurve::OutCubic);
    anim->start(QAbstractAnimation::DeleteWhenStopped);
    connect(anim, &QPropertyAnimation::finished, widget, [widget](){
        widget->setGraphicsEffect(nullptr);
    });
}
