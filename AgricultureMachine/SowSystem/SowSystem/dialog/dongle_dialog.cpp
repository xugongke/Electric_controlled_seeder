#include "dongle_dialog.h"
#include "ui_dongle_dialog.h"

#include <windows.h>
#include <time.h>
#include <QMessageBox>
#include "lib/id2num.h"

#define TIMEDELTA 8000

DongleDialog::DongleDialog(QWidget *parent) :
    QDialog(parent),
    ui(new Ui::DongleDialog)
{
    ui->setupUi(this);
    setWindowTitle("注册");

    fp = fopen("./key/key.sys", "rb+");
    if(fp == NULL)
    {
        fileFlag = false;
    }
    else
    {
        fileFlag = getData();
    }

    connect(&timer, SIGNAL(timeout()), this, SLOT(timerHandler()));
}

DongleDialog::~DongleDialog()
{
    delete ui;
    if(fp != NULL)
    {
        fclose(fp);
    }
    timer.stop();
}

bool DongleDialog::fileOk()
{
    return fileFlag;
}

bool DongleDialog::isAct()
{
    int day;
    time_t sec;
    char buf[32] = {};
    unsigned long id;

    if(!fileFlag)
    {
        probation(-1);
        return false;
    }

    GetVolumeInformationW( L"C:\\ ", NULL, 0, &id, NULL, NULL, NULL, 0);
    transKey(id, buf);
    if(strcmp(buf, key) == 0)
    {
        return true;
    }

    day = QDate::currentDate().daysTo(endDate);
    time(&sec);
    if(sec < timeSec)
    {
        probation(-1);
    }
    else
    {
        probation(day);
        fseek(fp, 0, SEEK_SET);
        fwrite(&sec, sizeof(time_t), 1, fp);
        fflush(fp);
    }

    return false;
}

void DongleDialog::probation(int days)
{
    QString str;
    if(days <= 0)
    {
        ui->label_days->setText("试用期已过");
        ui->btn_days->hide();
    }
    else
    {
        str.sprintf("试用期剩余%3d 天", days);
        ui->label_days->setText(str);
    }
}

void DongleDialog::on_btn_usr_clicked()
{
    unsigned long id;
    QString str;
    GetVolumeInformationW( L"C:\\ ", NULL, 0, &id, NULL, NULL, NULL, 0);
    str.sprintf("%lx", id);
    ui->line_usr->setText(str);
}

void DongleDialog::on_btn_key_clicked()
{
    unsigned long id;
    char argv[32] = {};
    char num[32] = {};
    char buf[256];
    QByteArray text = ui->line_key->text().toLatin1();
    if(text.length() != ui->line_key->maxLength())
    {
        QMessageBox::warning(this, "激活", "序列号格式错误", QMessageBox::Ok);
        return;
    }

    GetVolumeInformationW( L"C:\\ ", NULL, 0, &id, NULL, NULL, NULL, 0);
    transKey(id, argv);
    sscanf(text.data(),
           "%c%c%c%c - %c%c%c%c - %c%c%c%c - %c%c%c%c - %c%c%c%c - %c%c%c%c",
           &num[0],&num[1],&num[2],&num[3],
           &num[4],&num[5],&num[6],&num[7],
           &num[8],&num[9],&num[10],&num[11],
           &num[12],&num[13],&num[14],&num[15],
           &num[16],&num[17],&num[18],&num[19],
           &num[20],&num[21],&num[22],&num[23]);
    if(strcmp(num, argv) == 0)
    {
        fseek(fp, 1024, SEEK_SET);
        for(int i = 0; i < 24; i++)
        {
            buf[i*7 + 5] = argv[i];
        }
        fwrite(buf, 1, 256, fp);
        fflush(fp);

        done(8);
    }
    else
    {
        QMessageBox::warning(this, "激活", "序列号与本机不匹配", QMessageBox::Ok);
    }
}

void DongleDialog::on_btn_days_clicked()
{
    timer.start(TIMEDELTA);
    done(8);
}

void DongleDialog::on_btn_exit_clicked()
{
    done(0);
}

bool DongleDialog::getData()
{
    char buf[256];
    int size;
    int year, moon, day;
    time_t sec;

    fseek(fp, 0, SEEK_SET);
    //上次退出的时间
    size = fread(buf, 1, 256, fp);
    if(size < 256)
    {
        return false;
    }
    timeSec = *(unsigned long *)buf;

    //截止时间
    size = fread(buf, 1, 256, fp);
    if(size < 256)
    {
        return false;
    }
    year = *(int *)buf;

    size = fread(buf, 1, 256, fp);
    if(size < 256)
    {
        return false;
    }
    moon = *(int *)buf;

    size = fread(buf, 1, 256, fp);
    if(size < 256)
    {
        return false;
    }
    day = *(int *)buf;

    endDate.setDate(year, moon, day);

    //序列号
    size = fread(buf, 1, 256, fp);
    if(size < 256)
    {
        return false;
    }

    for(day = 0; day < 24; day++)
    {
        key[day] = buf[day*7 + 5];
    }
    key[24] = '\0';
    return true;
}

void DongleDialog::timerHandler()
{
    time_t t;
    time(&t);

    if(t > timeSec)
        timeSec = t;
    else
        timeSec += TIMEDELTA;

    fseek(fp, 0, SEEK_SET);

    fwrite(&timeSec, sizeof(time_t), 1, fp);
}
