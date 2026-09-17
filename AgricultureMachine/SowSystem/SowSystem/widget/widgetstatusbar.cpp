#include "widgetstatusbar.h"
#include "ui_widgetstatusbar.h"
#include "global.h"

WidgetStatusBar::WidgetStatusBar(Communication &c,QWidget *parent) :
    QWidget(parent),
    ui(new Ui::WidgetStatusBar),c(c)
{
	ui->setupUi(this);
	ui->labelPort->setText("断开");
//	connect(&c,&Communication::signalGetVersion,this,[=](QString version){
//		ui->labelVersion->setText(version);
//	});
    connect(&c,&Communication::signalPortConnected,this,[=,&c]{
        ui->labelPort->setText("连接");
        ui->labelVersion->setText(c.getVersion());
    });
    connect(&c,&Communication::signalPortDisconnected,this,[=]{
        ui->labelPort->setText("断开");
        ui->labelVersion->clear();
    });
    // connect(&qt,&QTimer::timeout,this,[=,&c]{
    //     ui->labelPort->setText(c.getConnectionState()?"连接":"断开");
    //     ui->labelVersion->setText(c.getVersion());
    // });
    // qt.start(500);
//	connect(&c,&Communication::signalPortConnected,this,[=]{
//		ui->labelPort->setText("连接");
//	});
//	connect(&c,&Communication::signalPortDisconnected,this,[=]{
//		ui->labelPort->setText("断开");
//		ui->labelVersion->setText("无");
//	});
}

WidgetStatusBar::~WidgetStatusBar()
{
	delete ui;
}
