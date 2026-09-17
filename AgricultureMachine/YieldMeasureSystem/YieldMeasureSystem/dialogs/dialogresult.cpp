#include "dialogresult.h"
#include "ui_dialogresult.h"
#include <QStandardItem>
#include "../../common/database.h"
#include "models/taskresultmodel.h"
#include <QDebug>
#include "global.h"
#include <QMessageBox>

DialogResult::DialogResult(QString taskName,QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogResult)
{
	ui->setupUi(this);
	setTouchable(ui->tableView);
	ui->tableView->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
    setWindowTitle("任务结果-"+taskName);
	data=BlockResult::loadAll(taskName);
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
		qsq.addBindValue(taskName);
		qsq.exec();
		d.close();
	});
	ui->tableView->setModel(trm);
}

DialogResult::~DialogResult()
{
	delete ui;
}
