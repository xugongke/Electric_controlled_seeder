#include "widgetstatusbar.h"
#include "ui_widgetstatusbar.h"
#include "global.h"
//#include "network/threaddata.h"
#include <QDebug>
#include <QSettings>
#include "uart/threaduart.h"
WidgetStatusBar::WidgetStatusBar(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::WidgetStatusBar)
{
	ui->setupUi(this);
	connect(&qt,&QTimer::timeout,this,[=]{
		QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
        iniFile.beginGroup(APPLICATIONGROUP);
        ui->labelRealtimeMoisture->setText(transMoisture(&G.moistureCmMap[iniFile.value("RealtimeMoistureCalibrationTransformMode").toString()],G.rd->newestMoisture(),2));
		iniFile.endGroup();
        ui->labelRealtimeMass->setText(QString::number(Calib_trans(&G.massCmMap["三通道"],G.rd->uniteMass()),'f',3));
	});
    connect(G.tUart,&ThreadUart::sig_errs,this,[=](int e){
        //qDebug()<<"error code:"<<e;
        qt.stop();
        ui->labelConnectionState->setText("断开");
        ui->labelVersion->clear();
    });
    connect(G.tUart,&ThreadUart::sig_uart,this,[=](int cmd,int len,void *args){
        if(!qt.isActive())
            qt.start(500);
        ui->labelConnectionState->setText("连接");
        switch(cmd)
        {
        case CMD_G_INFO:
            ui->labelVersion->setText(QString::fromUtf8(((CmdBody *)args)->buf));
            break;
        default:;
        }
    });
//	connect(G.tData,&ThreadData::signalDisconnected,this,[=]{
//		qt.stop();
//		ui->labelConnectionState->setText("断开");
//	});
}

WidgetStatusBar::~WidgetStatusBar()
{
	delete ui;
}

void WidgetStatusBar::slotValveStateUpdated()
{
    ui->labelValveState->setText(QString((G.valveState&1)>0?"开":"关")+"|"+QString((G.valveState&0b10)>0?"开":"关")+"|"+QString((G.valveState&0b100)>0?"开":"关")+"|"+QString((G.valveState&0b1000)>0?"开":"关")+"|"+QString((G.valveState&0b10000)>0?"开":"关"));
}
