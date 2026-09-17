#include "dialoginputablinename.h"
#include "ui_dialoginputablinename.h"
#include "../../common/database.h"
#include <QMessageBox>
#include "global.h"
#include <QCloseEvent>

DialogInputABLineName::DialogInputABLineName(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogInputABLineName)
{
	ui->setupUi(this);
	connect(ui->pushButton,&QPushButton::clicked,this,[=]{
		QString name=ui->lineEdit->text();
		if(name.isEmpty())
		{
			QMessageBox::information(this,"提示","名称不能为空");
			return;
		}
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("SELECT Name FROM "+ABLINETABLE+" WHERE Name=?");
        qsq.addBindValue(name);
		qsq.exec();
		if(count(qsq)>0)
			QMessageBox::information(this,"提示","AB线已存在");
		else
			accept();
        d.close();
	});
}

DialogInputABLineName::~DialogInputABLineName()
{
	delete ui;
}

QString DialogInputABLineName::getName()
{
	return ui->lineEdit->text();
}
