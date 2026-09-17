#ifndef DONGLE_DIALOG_H
#define DONGLE_DIALOG_H

#include <QDialog>
#include <stdio.h>
#include <QDate>
#include <QTimer>

namespace Ui {
class DongleDialog;
}

class DongleDialog : public QDialog
{
    Q_OBJECT

public:
    explicit DongleDialog(QWidget *parent = 0);
    ~DongleDialog();

    bool fileOk();
    bool isAct();

private slots:
    void on_btn_usr_clicked();

    void on_btn_key_clicked();

    void on_btn_days_clicked();

    void on_btn_exit_clicked();

    void timerHandler();

private:
    Ui::DongleDialog *ui;

    bool fileFlag;
    char key[32];
    time_t timeSec;
    QDate endDate;
    QDate currentDate;
    FILE *fp;

    QTimer timer;

    void probation(int days);
    bool getData();
};

#endif // DONGLE_DIALOG_H
