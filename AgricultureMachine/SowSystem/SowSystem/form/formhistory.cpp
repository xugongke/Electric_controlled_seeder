#include "formhistory.h"
#include "ui_formhistory.h"
#include <QDebug>
#include <QStandardItem>
#include "../../common/database.h"
#include <QListView>
#include "global.h"
#include "dataStruct/task.h"
#include "../../common/map.h"
#include <QSqlError>
#include <xlsxdocument.h>
#include <QMessageBox>
#include "delegate/pushbuttondelegate.h"
#include "model/resultmodel.h"

#define RECORDDATERANGE 10
//列顺序须与ResultModel::header一致
#define BLOCKROWCOLUMN 0
#define BLOCKCOLUMNCOLUMN 1
#define STATECOLUMN 2
#define SEED1COLUMN 3
#define SEED2COLUMN 4
#define SEED3COLUMN 5
#define SEED4COLUMN 6
#define SEED5COLUMN 7
#define SEED6COLUMN 8
#define FERTILIZER1COLUMN 9
#define FERTILIZER2COLUMN 10
#define FERTILIZER3COLUMN 11
#define FERTILIZER4COLUMN 12
#define FERTILIZER5COLUMN 13
#define FERTILIZER6COLUMN 14
#define STARTTIMECOLUMN 15
#define ENDTIMECOLUMN 16
#define MARKCOLUMN 17
#define DELETEBUTTONCOLUMN 18

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
        std::vector<BlockResult>().swap(data);
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
        qsq.prepare("SELECT StartTime,EndTime,[Row],[Column],SeedCount1,SeedCount2,SeedCount3,SeedCount4,SeedCount5,SeedCount6,FertilizerCount1,FertilizerCount2,FertilizerCount3,FertilizerCount4,FertilizerCount5,FertilizerCount6,Mark,State FROM "+RESULTTABLE+" WHERE TaskName=? AND StartTime>=? AND EndTime<=? ORDER BY Row,Column");
        BlockResult br;
        br.taskName=ui->comboBoxTaskFilter->currentText();
        qsq.addBindValue(br.taskName);
        qsq.addBindValue(ui->dateTimeEditBegin->dateTime().toString("yyyy-MM-dd hh:mm:ss"));
        qsq.addBindValue(ui->dateTimeEditEnd->dateTime().toString("yyyy-MM-dd hh:mm:ss"));
        for(qsq.exec();qsq.next();data.push_back(br))
        {
            br.seedCount.clear();
            br.fertilizerCount.clear();
            br.startTime=qsq.value("StartTime").toString();
            br.endTime=qsq.value("EndTime").toString();
            br.row=qsq.value("Row").toInt();
            br.column=qsq.value("Column").toInt();
            br.mark=qsq.value("Mark").toString();
            br.state=qsq.value("State").toInt();
            br.seedCount.push_back(qsq.value("SeedCount1").toInt());
            br.seedCount.push_back(qsq.value("SeedCount2").toInt());
            br.seedCount.push_back(qsq.value("SeedCount3").toInt());
            br.seedCount.push_back(qsq.value("SeedCount4").toInt());
            br.seedCount.push_back(qsq.value("SeedCount5").toInt());
            br.seedCount.push_back(qsq.value("SeedCount6").toInt());
            br.fertilizerCount.push_back(qsq.value("FertilizerCount1").toInt());
            br.fertilizerCount.push_back(qsq.value("FertilizerCount2").toInt());
            br.fertilizerCount.push_back(qsq.value("FertilizerCount3").toInt());
            br.fertilizerCount.push_back(qsq.value("FertilizerCount4").toInt());
            br.fertilizerCount.push_back(qsq.value("FertilizerCount5").toInt());
            br.fertilizerCount.push_back(qsq.value("FertilizerCount6").toInt());
        };
        d.close();
        ((ResultModel *)ui->tableViewRecord->model())->updateAll();
	});
	ui->comboBoxTaskFilter->setView(new QListView);
	slotRefreshComboBoxTaskFilter();
	QDateTime qdt=QDateTime::currentDateTime();
	ui->dateTimeEditBegin->setDateTime(qdt.addDays(-RECORDDATERANGE));
	ui->dateTimeEditEnd->setDateTime(qdt);
	ui->tableViewRecord->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
	ResultModel *rm=new ResultModel(data);
	PushButtonDelegate *pbd=new PushButtonDelegate;
	connect(pbd,&PushButtonDelegate::deleted,this,[=](int row){
		if(QMessageBox::question(this,"提示","确定要删除"+QString::number(data[row].row)+"排"+QString::number(data[row].column)+"列的记录吗？")==QMessageBox::No)
			return;
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		d.qsd.transaction();
		qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=0 WHERE TaskName=? AND [Row]=? AND [Column]=?");
		qsq.addBindValue(ui->comboBoxTaskFilter->currentText());
		qsq.addBindValue(data[row].row);
		qsq.addBindValue(data[row].column);
		qsq.exec();
        qsq.prepare("UPDATE "+RESULTTABLE+" SET SeedCount1=0,SeedCount2=0,SeedCount3=0,SeedCount4=0,SeedCount5=0,SeedCount6=0,FertilizerCount1=0,FertilizerCount2=0,FertilizerCount3=0,FertilizerCount4=0,FertilizerCount5=0,FertilizerCount6=0 WHERE TaskName=? AND [Row]=? AND [Column]=?");
		qsq.addBindValue(ui->comboBoxTaskFilter->currentText());
		qsq.addBindValue(data[row].row);
		qsq.addBindValue(data[row].column);
		qsq.exec();
		d.qsd.commit();
		d.close();
		rm->removeRow(row);
		data.erase(data.begin()+row);
	});
	ui->tableViewRecord->setItemDelegateForColumn(DELETEBUTTONCOLUMN,pbd);
	connect(rm,&ResultModel::signalMarkChanged,this,[=](int row,QString mark){
		data[row].mark=mark;
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET Mark=? WHERE TaskName=? AND [Row]=? AND [Column]=?");
		qsq.addBindValue(mark);
		qsq.addBindValue(ui->comboBoxTaskFilter->currentText());
		qsq.addBindValue(data[row].row);
		qsq.addBindValue(data[row].column);
		qsq.exec();
		d.close();
	});
	ui->tableViewRecord->setModel(rm);
	ui->tableViewRecord->setColumnHidden(STATECOLUMN,true);//状态列暂不显示
	connect(ui->pushButtonExport,&QPushButton::clicked,this,[=]{
		if(data.size()<1)
			return;
        QXlsx::Document xlsx("任务"+ui->comboBoxTaskFilter->currentText()+"历史记录.xlsx");
		QStringList qsl=rm->getHeader();
		int columnCount=qsl.size();
		for(int i=1,j=0;i<=columnCount;++i)//状态列不导出
			if(i-1!=STATECOLUMN)
				xlsx.write(1,++j,qsl[i-1]);
		for(size_t i=0;i<data.size();++i)
			for(int j=0;j<columnCount;++j)
				switch(j)
				{
				case BLOCKROWCOLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].row);
					break;
				case BLOCKCOLUMNCOLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].column);
					break;
                case STARTTIMECOLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].startTime);
                    break;
                case ENDTIMECOLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].endTime);
                    break;
				case SEED1COLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].seedCount[0]);
					break;
				case SEED2COLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].seedCount[1]);
					break;
				case SEED3COLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].seedCount[2]);
					break;
				case SEED4COLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].seedCount[3]);
					break;
                case SEED5COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].seedCount[4]);
                    break;
                case SEED6COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].seedCount[5]);
                    break;
                case FERTILIZER1COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].fertilizerCount[0]);
                    break;
                case FERTILIZER2COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].fertilizerCount[1]);
                    break;
                case FERTILIZER3COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].fertilizerCount[2]);
                    break;
                case FERTILIZER4COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].fertilizerCount[3]);
                    break;
                case FERTILIZER5COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].fertilizerCount[4]);
                    break;
                case FERTILIZER6COLUMN:
                    xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].fertilizerCount[5]);
                    break;
				case MARKCOLUMN:
					xlsx.write(i+2,j<STATECOLUMN?j+1:j,data[i].mark);
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
	ui->comboBoxTaskFilter->setSizeAdjustPolicy(QComboBox::AdjustToContents);
}
