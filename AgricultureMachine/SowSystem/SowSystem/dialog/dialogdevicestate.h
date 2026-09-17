#ifndef DIALOGDEVICESTATE_H
#define DIALOGDEVICESTATE_H

#include <QDialog>
#include "tool/communication.h"

namespace Ui {
class DialogDeviceState;
}

class DialogDeviceState : public QDialog
{
    Q_OBJECT

public:
    explicit DialogDeviceState(Communication &c,QWidget *parent = nullptr);
    ~DialogDeviceState();

private:
    Ui::DialogDeviceState *ui;
    QTimer timer;
};

#endif // DIALOGDEVICESTATE_H
