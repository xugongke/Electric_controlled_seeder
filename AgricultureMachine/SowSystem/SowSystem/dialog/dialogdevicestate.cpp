#include "dialogdevicestate.h"
#include "ui_dialogdevicestate.h"

DialogDeviceState::DialogDeviceState(Communication &c,QWidget *parent)
    : QDialog(parent)
    , ui(new Ui::DialogDeviceState)
{
    ui->setupUi(this);
    connect(&timer,&QTimer::timeout,this,[=,&c]{
        ui->label232->setPixmap(QPixmap(c.getConnectionState()?":/resource/image/enabled.png":":/resource/image/disabled.png"));
        ui->labelBeiDou->setPixmap(QPixmap(c.getBdState()?":/resource/image/enabled.png":":/resource/image/disabled.png"));
    });
    timer.start(1000);
}

DialogDeviceState::~DialogDeviceState()
{
    delete ui;
}
