#include "dialognewmap.h"
#include "ui_dialognewmap.h"
#include <QDir>
#include <QMessageBox>
#include <QDateTime>
#include <QDebug>
#include "../../common/database.h"
#include "global.h"
#include "dataStructs/yieldmap.h"

DialogNewMap::DialogNewMap(QWidget *parent) :
	QDialog(parent),
	ui(new Ui::DialogNewMap)
{
	ui->setupUi(this);
	setFocus();
	connect(ui->pushButtonOk,&QPushButton::clicked,this,[=]{
		map=ui->lineEditName->text();
		if(map.isEmpty())
		{
			QMessageBox::information(this,"提示","地图名不能为空");
			return;
		}
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		qsq.prepare("SELECT Name FROM "+MAPTABLE+" WHERE Name=?");
		qsq.addBindValue(map);
		qsq.exec();
		if(qsq.next())
		{
			QMessageBox::information(this,"提示","已有同名地图存在");
			d.close();
			return;
		}
		d.close();
        YieldMap m;
		m.name=map;
		for(int i=0;i++<ui->spinBoxRowCount->value();)
		{
            std::vector<YieldBlock> bv;
            for(int j=0;j++<ui->spinBoxColumnCount->value();)
			{
                YieldBlock b;
				b.crop=cropList[0];
                b.updateFlag=false;
				bv.push_back(b);
			}
			m.blockVector.push_back(bv);
		}
		m.mark=ui->textEditMark->toPlainText();
		m.save();
		QMessageBox::information(this,"提示","创建成功");
		accept();
	});
}

DialogNewMap::~DialogNewMap()
{
	delete ui;
}

QString DialogNewMap::newMapName()
{
	return map;
}
