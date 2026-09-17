#include "formhistory.h"
#include "ui_formhistory.h"
#include "global.h"
#include "../../common/database.h"
#include "models/recordmodel.h"
#include <xlsxdocument.h>
#include <QMessageBox>
#include <QDir>
#include <QDebug>
#include <QSqlError>
#include <QListView>
#include "delegate/pushbuttondelegate.h"
#include "dataStructs/task.h"

#define RECORDDATERANGE 10
#define BLOCKROWCOLUMN 1
#define BLOCKCOLUMNCOLUMN 2
#define MOISTURECOLUMN 3
#define MASSCOLUMN 4
#define UNITWEIGHTCOLUMN 5
#define CROPCOLUMN 6
#define STARTTIMECOLUMN 7
#define ENDTIMECOLUMN 8
#define STATECOLUMN 9
#define MARKCOLUMN 10
#define DELETEBUTTONCOLUMN 11

FormHistory::FormHistory(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormHistory)
{
	ui->setupUi(this);
    setTouchable(ui->tableViewRecord);
    ui->checkBoxAutoUpdateCurrentTime->setCheckState(Qt::Checked);
    connect(ui->pushButtonFilter,&QPushButton::clicked,this,[=]{
        if(ui->checkBoxAutoUpdateCurrentTime->checkState()==Qt::Checked)
            ui->dateTimeEditEnd->setDateTime(QDateTime::currentDateTime());
        std::vector<BlockResult>().swap(recordData);
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.prepare("SELECT StartTime,EndTime,Moisture,Mass,UnitWeight,[Row],[Column],Crop,Mark,State FROM "+RESULTTABLE+" WHERE State=3 OR TaskName=? AND StartTime>=? AND EndTime<=? ORDER BY Row,Column");
        BlockResult br;
        br.taskName=ui->comboBoxTaskFilter->currentText();
        qsq.addBindValue(br.taskName);
        qsq.addBindValue(ui->dateTimeEditBegin->dateTime().toString("yyyy-MM-dd hh:mm:ss"));
        qsq.addBindValue(ui->dateTimeEditEnd->dateTime().toString("yyyy-MM-dd hh:mm:ss"));
        for(qsq.exec();qsq.next();recordData.push_back(br))
        {
            br.startTime=qsq.value("StartTime").toString();
            br.endTime=qsq.value("EndTime").toString();
            br.moisture=qsq.value("Moisture").toDouble();
            br.mass=qsq.value("Mass").toDouble();
            br.unitWeight=qsq.value("UnitWeight").toDouble();
            br.row=qsq.value("Row").toInt();
            br.column=qsq.value("Column").toInt();
            br.crop=qsq.value("Crop").toString();
            br.mark=qsq.value("Mark").toString();
            br.state=qsq.value("State").toInt();
        };
        d.close();
        ((RecordModel *)ui->tableViewRecord->model())->updateAll();
    });
    ui->comboBoxTaskFilter->setView(new QListView);
    slotRefreshComboBoxTaskFilter();
    QDateTime qdt=QDateTime::currentDateTime();
    ui->dateTimeEditBegin->setDateTime(qdt.addDays(-RECORDDATERANGE));
    ui->dateTimeEditEnd->setDateTime(qdt);
    RecordModel *rm=new RecordModel(recordData);
    connect(rm,&RecordModel::signalMarkChanged,this,[=](int index,QString mark){
        recordData[index].mark=mark;
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET Mark=? WHERE [Row]=? AND [Column]=? AND TaskName=?");
        qsq.addBindValue(mark);
        qsq.addBindValue(recordData[index].row);
        qsq.addBindValue(recordData[index].column);
        qsq.addBindValue(ui->comboBoxTaskFilter->currentText());
        qsq.exec();
        d.close();
    });
	ui->tableViewRecord->setModel(rm);
	ui->tableViewRecord->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
	PushButtonDelegate *pbd=new PushButtonDelegate;
	connect(pbd,&PushButtonDelegate::deleted,this,[=](int row){
        if(QMessageBox::question(this,"提示","确定要删除"+QString::number(recordData[row].row)+"排"+QString::number(recordData[row].column)+"列的记录吗？")==QMessageBox::No)
			return;
        Task t;
        t.load(recordData[row].taskName);
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=0 WHERE TaskName=? AND [Row]=? AND [Column]=?");
        qsq.addBindValue(recordData[row].taskName);
        qsq.addBindValue(t.routeBlockVector.size()-recordData[row].row);
        qsq.addBindValue(recordData[row].column-1);
        d.qsd.transaction();
        qsq.exec();
        qsq.prepare("DELETE FROM "+RESULTTABLE+" WHERE TaskName=? AND [Row]=? AND [Column]=?");
        qsq.addBindValue(recordData[row].taskName);
        qsq.addBindValue(recordData[row].row);
        qsq.addBindValue(recordData[row].column);
        qsq.exec();
        d.qsd.commit();
		d.close();
		rm->removeRow(row);
        emit signalResultDeleted(recordData[row].taskName);
        recordData.erase(recordData.begin()+row);
	});
	ui->tableViewRecord->setItemDelegateForColumn(DELETEBUTTONCOLUMN-1,pbd);
    connect(ui->pushButtonExport,&QPushButton::clicked,this,[=]{
        if(recordData.size()<1)
            return;
        QXlsx::Document xlsx(ui->comboBoxTaskFilter->currentText()+"历史记录.xlsx");
        QStringList qsl=rm->getHeader();
        int columnCount=qsl.size();
        for(int i=1;i<=columnCount;++i)
            xlsx.write(1,i,qsl[i-1]);
        for(size_t i=0;i<recordData.size();++i)
            for(int j=1;j<=columnCount;++j)
                switch(j)
                {
                case BLOCKROWCOLUMN:
                    xlsx.write(i+2,j,recordData[i].row);
                    break;
                case BLOCKCOLUMNCOLUMN:
                    xlsx.write(i+2,j,recordData[i].column);
                    break;
                case MOISTURECOLUMN:
                    xlsx.write(i+2,j,recordData[i].moisture);
                    break;
                case MASSCOLUMN:
                    xlsx.write(i+2,j,recordData[i].mass);
                    break;
                case UNITWEIGHTCOLUMN:
                    xlsx.write(i+2,j,recordData[i].unitWeight);
                    break;
                case CROPCOLUMN:
                    xlsx.write(i+2,j,recordData[i].crop);
                    break;
                case STARTTIMECOLUMN:
                    xlsx.write(i+2,j,recordData[i].startTime);
                    break;
                case ENDTIMECOLUMN:
                    xlsx.write(i+2,j,recordData[i].endTime);
                    break;
                case STATECOLUMN:
                    switch(recordData[i].state)
                    {
                    case 1:
                        xlsx.write(i+2,j,"未完成");
                        break;
                    case 2:
                        xlsx.write(i+2,j,"完成");
                        break;
                    case 3:
                        xlsx.write(i+2,j,"失败");
                        break;
                    default:;
                    }
                    break;
                case MARKCOLUMN:
                    xlsx.write(i+2,j,recordData[i].mark);
                    break;
                default:;
                }
        QMessageBox::information(this,"提示",QString("导出")+(xlsx.save()?"成功":"失败"));
    });
}

FormHistory::~FormHistory()
{
	delete ui;
}

void FormHistory::slotRefreshComboBoxTaskFilter()
{
	ui->comboBoxTaskFilter->clear();
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	for(qsq.exec("SELECT Name FROM "+TASKTABLE);qsq.next();ui->comboBoxTaskFilter->addItem(qsq.value("Name").toString()));
	d.close();
}

void FormHistory::showEvent(QShowEvent *event)
{
    updateResultFailureState();
    QWidget::showEvent(event);
}
