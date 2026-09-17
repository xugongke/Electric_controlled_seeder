#include "mainwindow.h"
#include "form/formtask.h"
#include "ui_mainwindow.h"
#include <QSettings>
#include <QTextCodec>
#include <QMessageBox>
#include <QCloseEvent>
#include <QDebug>
#include "global.h"

MainWindow::MainWindow(QWidget *parent)
	: QMainWindow(parent)
	, ui(new Ui::MainWindow),lastTab(0)
{
	ui->setupUi(this);
	//move(0,0);
    wsb=new WidgetStatusBar(c,ui->statusbar);
	ui->statusbar->addWidget(wsb);
	connect(ui->tabWidget,&QTabWidget::currentChanged,this,&MainWindow::slotTabWidgetCurrentIndexChanged);
    ft=new FormTask(c,this);
    ui->horizontalLayout_2->addWidget(ft);
    fm=new FormMap(this);
    ui->horizontalLayout_4->addWidget(fm);
    connect(ft,&FormTask::signalABLineStateUpdated,fm,&FormMap::slotABLineStateUpdated);
    fh=new FormHistory(this);
    ui->horizontalLayout_5->addWidget(fh);
    connect(ft,&FormTask::signalTaskListUpdated,fh,&FormHistory::slotRefreshComboBoxTaskFilter);
    fte=new FormTest(c,this);
    ui->horizontalLayout_6->addWidget(fte);
    fc=new FormConfig(c,this);
    connect(fc,&FormConfig::signalAppConfigUpdated,ft,&FormTask::slotAlphaUpdated);
    connect(fc,&FormConfig::signalDeviceConfigUpdated,fte,&FormTest::slotDeviceConfigUpdated);
    ui->horizontalLayout_3->addWidget(fc);
    fcs=new FormContinuousSow(c,this);
    ui->horizontalLayout_7->addWidget(fcs);
    connect(fc,&FormConfig::signalDeviceConfigUpdated,fcs,&FormContinuousSow::slotDeviceConfigUpdated);
	c.openPort();
    showMaximized();
    connect(&debugInfoTimer,&QTimer::timeout,this,[=]{
        if(c.getConnectionState())
            c.getDebugInformation(TEST);
    });
    debugInfoTimer.start(500);
    connect(&c,&Communication::signalGetDebugInformation,this,[=](QString qs){
        qDebug()<<qs;
        writeLog(qs);
    });
}

MainWindow::~MainWindow()
{
	delete ui;
}

void MainWindow::closeEvent(QCloseEvent *e)
{
    // if(c.getMode()==STOP)
    // {
    //     e->accept();
    //     return;
    // }
    // QMessageBox::information(this,"提示","下位机正在工作");
    // e->ignore();
}

void MainWindow::slotTabWidgetCurrentIndexChanged(int index)
{
	switch(lastTab)
	{
	case 3:
        fte->exitTestMode();
		break;
	case 5:
        fcs->stopDebugInfoTimer();
		if(c.getMode()==CONTINUOUSSOW)
		{
			disconnect(ui->tabWidget,&QTabWidget::currentChanged,this,&MainWindow::slotTabWidgetCurrentIndexChanged);
			ui->tabWidget->setCurrentIndex(lastTab);
			connect(ui->tabWidget,&QTabWidget::currentChanged,this,&MainWindow::slotTabWidgetCurrentIndexChanged);
            return;
		}
		break;
    default:;
	}
	switch(index)
	{
	case 3:
        fte->enterTestMode();
		break;
	case 5:
        fcs->startDebugInfoTimer();
		break;
    default:;
	}
    lastTab=index;
    fadeInWidget(ui->tabWidget->widget(index));
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
    // 启动时中心区域淡入
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
