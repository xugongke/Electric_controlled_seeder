#include "dialogtaskresult.h"
#include "ui_dialogtaskresult.h"
#include "global.h"
#include "model/taskresultmodel.h"
#include "../../common/database.h"

#define STATECOLUMN 2//须与TaskResultModel::header一致

DialogTaskResult::DialogTaskResult(QString task,QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogTaskResult)
{
	ui->setupUi(this);
	setTouchable(ui->tableView);
    setWindowTitle("任务结果-"+task);
	ui->tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
	ui->tableView->verticalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    data=BlockResult::loadAll(task);
    TaskResultModel *trm=new TaskResultModel(data);
    connect(trm,&TaskResultModel::signalMarkChanged,this,[=](int index,QString mark){
        data[index].mark=mark;
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.prepare("UPDATE "+RESULTTABLE+" SET Mark=? WHERE [Row]=? AND [Column]=? AND TaskName=?");
        qsq.addBindValue(mark);
        qsq.addBindValue(data[index].row);
        qsq.addBindValue(data[index].column);
        qsq.addBindValue(task);
        qsq.exec();
        d.close();
    });
    ui->tableView->setModel(trm);
    ui->tableView->setColumnHidden(STATECOLUMN,true);//状态列暂不显示
}

DialogTaskResult::~DialogTaskResult()
{
	delete ui;
}
