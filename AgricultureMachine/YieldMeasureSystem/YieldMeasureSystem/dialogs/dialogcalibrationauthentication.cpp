#include "dialogcalibrationauthentication.h"
#include "ui_dialogcalibrationauthentication.h"
#include <QMessageBox>

DialogCalibrationAuthentication::DialogCalibrationAuthentication(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogCalibrationAuthentication)
{
	ui->setupUi(this);
	connect(ui->pushButton,&QPushButton::clicked,this,[=]{
		if(ui->lineEdit->text()=="123456")
			accept();
		else
			QMessageBox::information(this,"提示","密码错误");
	});
}

DialogCalibrationAuthentication::~DialogCalibrationAuthentication()
{
	delete ui;
}
