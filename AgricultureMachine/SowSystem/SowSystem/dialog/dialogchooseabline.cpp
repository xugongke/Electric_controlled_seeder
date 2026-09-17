#include "dialogchooseabline.h"
#include "ui_dialogchooseabline.h"
#include "../../common/database.h"
#include "global.h"
#include <QMessageBox>
#include <QPushButton>
#include <QSqlError>
#include "dialog/dialogabline.h"
#include "../../common/map.h"
#include <QListView>

DialogChooseABLine::DialogChooseABLine(QString mapName,QWidget *parent) :
    QDialog(parent),
    ui(new Ui::DialogChooseABLine)
{
    ui->setupUi(this);
    ui->tableWidget->setColumnCount(3);
    ui->tableWidget->setHorizontalHeaderLabels({
        "AB线","","",""
    });
    ui->comboBoxColumn->setView(new QListView);
    setTouchable(ui->tableWidget);
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.exec("SELECT Name FROM "+ABLINETABLE);
    for(int i=0;qsq.next();)
    {
        ui->tableWidget->insertRow(i);
        ui->tableWidget->setItem(i,0,new QTableWidgetItem(qsq.value("Name").toString()));
        ui->tableWidget->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
        QPushButton *qpb=new QPushButton("更多"),*qpb2=new QPushButton("删除");
        connect(qpb,&QPushButton::clicked,this,[=]{
            DialogABLine da(ui->tableWidget->item(((QPushButton *)sender())->property("row").toInt(),0)->text(),this);
			da.setGroupBox2Visible(false);
            da.exec();
        });
        connect(qpb2,&QPushButton::clicked,this,[=]{
            Database d;
            d.open();
            QSqlQuery qsq(d.qsd);
            qsq.exec("PRAGMA foreign_keys = ON");
            qsq.prepare("DELETE FROM "+ABLINETABLE+" WHERE Name=?");
            int row=((QPushButton *)sender())->property("row").toInt();
            qsq.addBindValue(ui->tableWidget->item(row,0)->text());
            if(qsq.exec())
            {
                ui->tableWidget->removeRow(row);
                for(int i=0;i<ui->tableWidget->rowCount();i++)
                {
                    ((QPushButton *)ui->tableWidget->cellWidget(i,1))->setProperty("row",i);
                    ((QPushButton *)ui->tableWidget->cellWidget(i,2))->setProperty("row",i);
                }
            }
            else if(qsq.lastError().nativeErrorCode().toInt()==19)
                QMessageBox::information(this,"提示","删除失败，有地图使用了此AB线");
        });
        ui->tableWidget->setCellWidget(i,1,qpb);
        ui->tableWidget->setCellWidget(i,2,qpb2);
        qpb->setProperty("row",i);
        qpb2->setProperty("row",i++);
    }
    d.close();
    connect(ui->pushButton,&QPushButton::clicked,this,[=]{
        QList<QTableWidgetItem *> ql=ui->tableWidget->selectedItems();
        if(ql.size()<1)
        {
            QMessageBox::information(this,"提示","未选择AB线");
            return;
        }
        bool b1=ui->radioButtonPositive->isChecked(),b2=ui->radioButtonReverse->isChecked();
        if(!b1&&!b2)
        {
            QMessageBox::information(this,"提示","未选择方向");
            return;
        }
        abLineName=ui->tableWidget->item(ql[0]->row(),0)->text();
        if(b1)
            direction=true;
        else if(b2)
            direction=false;
        column=ui->comboBoxColumn->currentText().toInt()-1;
        accept();
    });
    Map m;
    m.load(mapName);
    for(size_t i=0,t=m.blockEachTrip();i<m.blockVector[0].size()/t;)
        ui->comboBoxColumn->addItem(QString::number(i++*t+1));
    ui->tableWidget->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
}

DialogChooseABLine::~DialogChooseABLine()
{
    delete ui;
}

QString DialogChooseABLine::getABLineName()
{
    return abLineName;
}

bool DialogChooseABLine::getDirection()
{
	return !ui->radioButtonReverse->isChecked();
}

int DialogChooseABLine::getColumn()
{
    return ui->comboBoxColumn->currentText().toInt()-1;
}
