#include "dialogconfigverification.h"
#include "ui_dialogconfigverification.h"

DialogConfigVerification::DialogConfigVerification(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogConfigVerification)
{
	ui->setupUi(this);
}

DialogConfigVerification::~DialogConfigVerification()
{
	delete ui;
}

QString DialogConfigVerification::password()
{
	return ui->lineEditPassword->text();
}
