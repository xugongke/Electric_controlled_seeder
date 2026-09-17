#include "dialogabline.h"
#include "ui_dialogabline.h"
#include "../../common/database.h"
#include "global.h"
#include <QSqlError>

DialogABLine::DialogABLine(QString name,QWidget *parent) :
    QDialog(parent),
    ui(new Ui::DialogABLine)
{
    ui->setupUi(this);
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT StartN,StartE,EndBN,EndBE,StartDir,CalcDir,StartState,CalcDirFlag,OffLen,BDOffTime,Resv,CrcCheck FROM "+ABLINETABLE+" WHERE Name=?");
	qsq.addBindValue(name);
	qsq.exec();
    if(qsq.next())
	{
        ui->labelName->setText(name);
        ui->labelStartN->setText(qsq.value("StartN").toString());
        ui->labelStartE->setText(qsq.value("StartE").toString());
        ui->labelEndBN->setText(qsq.value("EndBN").toString());
        ui->labelEndBE->setText(qsq.value("EndBE").toString());
        ui->labelStartDir->setText(qsq.value("StartDir").toString());
        ui->labelCalcDir->setText(qsq.value("CalcDir").toString());
        ui->labelStartState->setNum(qsq.value("StartState").toInt());
        ui->labelCalcDirFlag->setNum(qsq.value("CalcDirFlag").toInt());
        ui->labelOffLen->setNum(qsq.value("OffLen").toInt());
        ui->labelBDOffTime->setNum(qsq.value("BDOffTime").toInt());
        ui->labelResv->setText(QString::number(qsq.value("Resv").toLongLong()));
        ui->labelCrcCheck->setText(QString::number(qsq.value("CrcCheck").toLongLong()));
    }
    d.close();

}

DialogABLine::~DialogABLine()
{
    delete ui;
}

void DialogABLine::setGroupBox2Visible(bool b)
{
	ui->groupBox_2->setVisible(b);
}

void DialogABLine::setPosition(int row,int column,bool direction)
{
	ui->labelARowColumn->setText(QString::number(row+1)+','+QString::number(column+1));
    ui->labelDirection->setText(direction?"正":"反");
}
