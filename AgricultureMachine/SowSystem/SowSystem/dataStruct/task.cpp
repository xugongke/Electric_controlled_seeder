#include "task.h"
#include "../../common/database.h"
#include <QVariant>
#include <QDebug>
#include <QSqlError>
#include <QSettings>
#include <QTextCodec>
#include <xlsxdocument.h>
#include <QFileInfo>
#include "../../common/map.h"
#include "global.h"

#define TASKINFOROWATTRIBUTESCOUNT 20
#define BLOCKROWCOLUMN 1
#define BLOCKCOLUMNCOLUMN 2
#define STARTTIMECOLUMN 3
#define ENDTIMECOLUMN 4
#define STATECOLUMN 5
#define SEEDCOLUMN1COLUMN 6
#define SEEDCOLUMN2COLUMN 7
#define SEEDCOLUMN3COLUMN 8
#define SEEDCOLUMN4COLUMN 9
#define SEEDCOLUMN5COLUMN 10
#define SEEDCOLUMN6COLUMN 11
#define FERTILIZER1COLUMN 12
#define FERTILIZER2COLUMN 13
#define FERTILIZER3COLUMN 14
#define FERTILIZER4COLUMN 15
#define FERTILIZER5COLUMN 16
#define FERTILIZER6COLUMN 17
#define MARKCOLUMN 18

Task::Task()
{

}

void Task::load(QString qs)
{
	name=qs;
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
    qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=3 WHERE TaskName=? AND State=1");
    qsq.addBindValue(name);
    qsq.exec();
	qsq.prepare("SELECT MapName,Mark,CreateTime,LastWorkTime,PathType,Positive,LastBlockRow,LastBlockColumn,OutsetRow,OutsetColumn FROM "+TASKTABLE+" WHERE Name=?");
	qsq.addBindValue(qs);
	qsq.exec();
	qsq.next();
	mapName=qsq.value("MapName").toString();
	mark=qsq.value("Mark").toString();
	createTime=qsq.value("CreateTime").toString();
	lastWorkTime=qsq.value("LastWorkTime").toString();
	pathType=qsq.value("PathType").toString().toInt();
	positive=qsq.value("Positive").toBool();
	lastBlockRow=qsq.value("LastBlockRow").toInt();
	lastBlockColumn=qsq.value("LastBlockColumn").toInt();
	outsetRow=qsq.value("OutsetRow").toInt();
	outsetColumn=qsq.value("OutsetColumn").toUInt();
	qsq.prepare("SELECT MAX([Row]),MAX([Column]) FROM "+TASKBLOCKTABLE+" WHERE TaskName=?");
	qsq.addBindValue(qs);
	qsq.exec();
	qsq.next();
	int rowCount=qsq.value("MAX([Row])").toInt()+1,columnCount=qsq.value("MAX([Column])").toInt()+1;
    qsq.prepare("SELECT [Row],[Column],State,Sow FROM "+TASKBLOCKTABLE+" WHERE TaskName=? ORDER BY [Row],[Column]");
	qsq.addBindValue(qs);
	qsq.exec();
	std::vector<std::vector<TaskBlock>>().swap(routeBlockVector);
	for(int i=0;i++<rowCount;)
	{
		std::vector<TaskBlock> rbv;
		for(int j=0;j++<columnCount&&qsq.next();)
		{
			TaskBlock rb;
			rb.state=qsq.value("State").toInt();
            rb.sow=qsq.value("Sow").toBool();
			rbv.push_back(rb);
		}
		routeBlockVector.push_back(rbv);
	}
	d.close();
}

void Task::save()
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Name From "+TASKTABLE+" WHERE Name=?");
	qsq.addBindValue(name);
	qsq.exec();
	d.qsd.transaction();
	if(qsq.next())
	{
		qsq.prepare("UPDATE "+TASKTABLE+" SET Mark=?,LastWorkTime=?,PathType=?,Positive=?,LastBlockRow=?,LastBlockColumn=?,OutsetRow=?,OutsetColumn=? WHERE Name=?");
		qsq.addBindValue(mark);
		qsq.addBindValue(lastWorkTime);
		qsq.addBindValue(pathType);
		qsq.addBindValue(positive);
		qsq.addBindValue(lastBlockRow);
		qsq.addBindValue(lastBlockColumn);
		qsq.addBindValue(outsetRow);
		qsq.addBindValue(outsetColumn);
		qsq.addBindValue(name);
        qsq.exec();
		for(size_t i=0;i<routeBlockVector.size();++i)
			for(size_t j=0;j<routeBlockVector[i].size();qsq.exec())
			{
                qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=?,Sow=? WHERE TaskName=? AND [Row]=? AND [Column]=?");
				qsq.addBindValue(routeBlockVector[i][j].state);
                qsq.addBindValue(routeBlockVector[i][j].sow);
				qsq.addBindValue(name);
				qsq.addBindValue(i);
				qsq.addBindValue(j++);
			}
	}
	else
	{
		qsq.prepare("INSERT INTO "+TASKTABLE+" (Name,MapName,Mark,CreateTime,LastWorkTime,PathType,Positive,LastBlockRow,LastBlockColumn,OutsetRow,OutsetColumn) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
		qsq.addBindValue(name);
		qsq.addBindValue(mapName);
		qsq.addBindValue(mark);
		qsq.addBindValue(createTime);
		qsq.addBindValue(lastWorkTime);
		qsq.addBindValue(pathType);
		qsq.addBindValue(positive);
		qsq.addBindValue(lastBlockRow);
		qsq.addBindValue(lastBlockColumn);
		qsq.addBindValue(outsetRow);
		qsq.addBindValue(outsetColumn);
		qsq.exec();
		for(size_t i=0;i<routeBlockVector.size();++i)
            for(size_t j=0;j<routeBlockVector[i].size();qsq.exec())
			{
                qsq.prepare("INSERT INTO "+TASKBLOCKTABLE+" (TaskName,[Row],[Column],State,Sow) VALUES (?,?,?,?,?)");
				qsq.addBindValue(name);
				qsq.addBindValue(i);
				qsq.addBindValue(j);
				qsq.addBindValue(routeBlockVector[i][j].state);
                qsq.addBindValue(routeBlockVector[i][j++].sow);
			}
	}
	d.qsd.commit();
	d.close();
}

float Task::completionDegree()
{
	int totalCount=0,completedCount=0;
	for(size_t i=0;i<routeBlockVector.size();++i)
		for(size_t j=0;j<routeBlockVector[i].size();totalCount++)
			if(routeBlockVector[i][j++].state==2)
				completedCount++;
	return completedCount*100.0/totalCount;
}

bool Task::exportToXlsx(QString dir)
{
    QXlsx::Document d(dir+"/任务 "+name+".xlsx");
	d.addSheet("信息");
	d.write(1,1,"地图");
    QXlsx::Format f;
    f.setPatternBackgroundColor("#99ff99");
    f.setBorderStyle(QXlsx::Format::BorderThin);
    f.setBorderColor("#d4d4d4");
    d.write(1,2,mapName);
	d.write(2,1,"创建时间");
    d.write(2,2,createTime,f);
	d.write(3,1,"最后工作时间");
    d.write(3,2,lastWorkTime,f);
	d.write(4,1,"备注");
    d.write(4,2,mark,f);
	d.write(5,1,"排");
    int rowCount=routeBlockVector.size();
    d.write(5,2,rowCount);
	d.write(6,1,"列");
    int columnCount=routeBlockVector[0].size();
    d.write(6,2,columnCount);
	d.write(7,1,"路线类型");
    d.write(7,2,pathType);
	d.write(8,1,"路线方向");
    d.write(8,2,positive?"反":"正");
	d.write(9,1,"起点排列");
    d.write(9,2,outsetRow);
    d.write(9,3,outsetColumn);
	d.write(10,1,"最近完成排列");
    d.write(10,2,lastBlockRow);
    d.write(10,3,lastBlockColumn);
	d.addSheet("状态");
	d.selectSheet("状态");
    for(int i=0;i<rowCount;i++)
        d.write(i+2,1,QString::number(rowCount-i)+"排");
    for(int i=0;i<columnCount;i++)
        d.write(1,i+2,QString::number(i+1)+"列");
	for(size_t i=0;i<routeBlockVector.size();i++)
		for(size_t j=0;j<routeBlockVector[i].size();j++)
            d.write(i+2,j+2,routeBlockVector[i][j].state);
    d.addSheet("是否播种");
    d.selectSheet("是否播种");
    for(int i=0;i<rowCount;i++)
        d.write(i+2,1,QString::number(rowCount-i)+"排");
    for(int i=0;i<columnCount;i++)
        d.write(1,i+2,QString::number(i+1)+"列");
    for(size_t i=0;i<routeBlockVector.size();i++)
        for(size_t j=0;j<routeBlockVector[i].size();j++)
            if(routeBlockVector[i][j].sow)
                d.write(i+2,j+2,"√");
	d.addSheet("结果");
	d.selectSheet("结果");
	for(int i=1;i<=resultHeader.size();++i)
		d.write(1,i,resultHeader[i-1]);
	Database db;
	db.open();
	QSqlQuery qsq(db.qsd);
    qsq.prepare("SELECT Row,Column,State,StartTime,EndTime,SeedCount1,FertilizerCount1,SeedCount2,FertilizerCount2,SeedCount3,FertilizerCount3,SeedCount4,FertilizerCount4,SeedCount5,FertilizerCount5,SeedCount6,FertilizerCount6,Mark FROM "+RESULTTABLE+" WHERE TaskName=?");
    qsq.addBindValue(name);
    qsq.exec();
    for(int i=2;qsq.next();d.write(i++,MARKCOLUMN,qsq.value("Mark").toString()))
    {
        d.write(i,BLOCKROWCOLUMN,qsq.value("Row").toInt());
        d.write(i,BLOCKCOLUMNCOLUMN,qsq.value("Column").toInt());
        d.write(i,STARTTIMECOLUMN,qsq.value("StartTime").toString());
        d.write(i,ENDTIMECOLUMN,qsq.value("EndTime").toString());
        d.write(i,STATECOLUMN,qsq.value("State").toInt());
        d.write(i,SEEDCOLUMN1COLUMN,qsq.value("SeedCount1").toInt());
        d.write(i,SEEDCOLUMN2COLUMN,qsq.value("SeedCount2").toInt());
        d.write(i,SEEDCOLUMN3COLUMN,qsq.value("SeedCount3").toInt());
        d.write(i,SEEDCOLUMN4COLUMN,qsq.value("SeedCount4").toInt());
        d.write(i,SEEDCOLUMN5COLUMN,qsq.value("SeedCount5").toInt());
        d.write(i,SEEDCOLUMN6COLUMN,qsq.value("SeedCount6").toInt());
        d.write(i,FERTILIZER1COLUMN,qsq.value("FertilizerCount1").toInt());
        d.write(i,FERTILIZER2COLUMN,qsq.value("FertilizerCount2").toInt());
        d.write(i,FERTILIZER3COLUMN,qsq.value("FertilizerCount3").toInt());
        d.write(i,FERTILIZER4COLUMN,qsq.value("FertilizerCount4").toInt());
        d.write(i,FERTILIZER5COLUMN,qsq.value("FertilizerCount5").toInt());
        d.write(i,FERTILIZER6COLUMN,qsq.value("FertilizerCount6").toInt());
    }
	db.close();
	d.selectSheet("信息");
	return d.save();
}

void Task::importFromXlsx(QString file,QString name)
{
    this->name=name;//QFileInfo(file).fileName().section("任务",1,1).section(".",0,0);
	QXlsx::Document d(file);
	d.selectSheet("信息");
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="地图")
		{
			mapName=d.read(i,2).toString();
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="创建时间")
		{
			createTime=d.read(i,2).toString();
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="最后工作时间")
		{
			lastWorkTime=d.read(i,2).toString();
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="备注")
		{
			mark=d.read(i,2).toString();
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="路线类型")
		{
			pathType=d.read(i,2).toInt();
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="路线方向")
		{
            positive=d.read(i,2).toString()=="反";
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="起点排列")
		{
			outsetRow=d.read(i,2).toInt();
			outsetColumn=d.read(i,3).toInt();
			break;
		}
	for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="最近完成排列")
		{
			lastBlockRow=d.read(i,2).toInt();
			lastBlockColumn=d.read(i,3).toInt();
			break;
		}
	int rowCount=d.read(5,2).toInt(),columnCount=d.read(6,2).toInt();
	d.selectSheet("状态");
	std::vector<std::vector<TaskBlock>>().swap(routeBlockVector);
    for(int i=0;i<rowCount;i++)
	{
		std::vector<TaskBlock> bv;
        for(int j=0;j<columnCount;)
		{
			TaskBlock b;
            b.state=d.read(i+2,2+j++).toInt();
			bv.push_back(b);
		}
		routeBlockVector.push_back(bv);
	}
    d.selectSheet("是否播种");
    for(int i=0;i<rowCount;i++)
        for(int j=0;j<columnCount;routeBlockVector[i][j].sow=d.read(i+2,2+j++).toString()=="√");
 //    d.selectSheet("结果");
 //    Database db;
 //    db.open();
 //    QSqlQuery qsq(db.qsd);
 //    db.qsd.transaction();
 //    for(int i=2;i<=d.dimension().rowCount();qsq.exec())
 //    {
 //        int row=d.read(i,BLOCKROWCOLUMN).toInt()-1,column=d.read(i,BLOCKCOLUMNCOLUMN).toInt()-1;
 //        routeBlockVector[row][column].startTime=d.read(i,STARTTIMECOLUMN).toString();
 //        routeBlockVector[row][column].endTime=d.read(i,ENDTIMECOLUMN).toString();
 //        routeBlockVector[row][column].mark=d.read(i,MARKCOLUMN).toString();
 //        for(int i=0;i<4;qsq.exec())
 //        {
 //            qsq.prepare("INSERT INTO "+RESULTTABLE+" (TaskName,[Row],[Column],SeedColumn,SeedCount,FertilizerCoun) VALUES (?,?,?,?,?,?)");
 //            qsq.addBindValue(name);
 //            qsq.addBindValue(row);
 //            qsq.addBindValue(column);
 //            qsq.addBindValue(i);
 //            qsq.addBindValue(d.read(row,i+++SEEDCOLUMN1COLUMN).toInt());
 //            qsq.addBindValue(0);
 //        }
 //    }
    // db.qsd.commit();
    // db.close();
	d.selectSheet("信息");
	save();
}

bool Task::isSow(int row,int column,bool b)
{
	if(row>=0&&row<(int)routeBlockVector.size())
	{
        Map m;
        m.load(mapName);
        for(int i=0;i<m.blockEachTrip();)
        {
            int c=column+i++;
            //有区域未完成，则该组需要播种
            if(routeBlockVector[row][c].sow&&(routeBlockVector[row][c].state==0||routeBlockVector[row][c].state==1))
                return true;
        }
	}
	else
		return b;
	return false;
}

void Task::initPathState()
{
    outsetRow=routeBlockVector.size()-1;
	outsetColumn=0;
	lastBlockRow=-1;
	lastBlockColumn=-1;
    positive=false;
	pathType=0;
}

int Task::density(int row,int column,bool b)
{
	int density,rowCount=routeBlockVector.size();
	Map m;
	m.load(mapName);
	if(b)
	{
        //地图外播种
		if(row<0)
			density=m.blockVector[0][column].density;
		else if(row<rowCount)
        {
            if(isSow(row,column,b))
                density=m.blockVector[row][column].density;
            else
                density=0;
        }
		else
			density=m.blockVector[rowCount-1][column].density;
	}
	else
	{
		if(row>=0&&row<rowCount)
        {
            if(isSow(row,column,b))
                density=m.blockVector[row][column].density;
            else
                density=0;
        }
		else
			density=-1;
	}
	if(densityIsSpecified(density))
		density=specifiedDensity(density);
	return density;
}

bool Task::columnDirection(int column)
{
    Map m;
    m.load(mapName);
    column=m.getColumnNode(column)[0];
    switch(pathType)
    {
    case 0:
    case 3:
        return column/m.blockEachTrip()%2==(positive?0:1);
    case 1:
    case 4:
        return positive;
	case 2:
        return (column/m.blockEachTrip()<((int)routeBlockVector[0].size()/m.blockEachTrip()+1)/2)?positive:!positive;
	case 5:
        return (column/m.blockEachTrip()<((int)routeBlockVector[0].size()/m.blockEachTrip()-1)/2)?positive:!positive;
    }
    return true;
}

void Task::saveInfo()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
	qsq.prepare("UPDATE "+TASKTABLE+" SET Mark=?,LastWorkTime=?,PathType=?,Positive=?,LastBlockRow=?,LastBlockColumn=?,OutsetRow=?,OutsetColumn=? WHERE Name=?");
    qsq.addBindValue(mark);
    qsq.addBindValue(lastWorkTime);
    qsq.addBindValue(pathType);
    qsq.addBindValue(positive);
    qsq.addBindValue(lastBlockRow);
    qsq.addBindValue(lastBlockColumn);
    qsq.addBindValue(outsetRow);
    qsq.addBindValue(outsetColumn);
    qsq.addBindValue(name);
    qsq.exec();
    d.close();
}

void Task::saveBlock(int row,int column)
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
    qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=?,Sow=? WHERE TaskName=? AND [Row]=? AND [Column]=?");
	qsq.addBindValue(routeBlockVector[row][column].state);
    qsq.addBindValue(routeBlockVector[row][column].sow);
	qsq.addBindValue(name);
	qsq.addBindValue(row);
	qsq.addBindValue(column);
    qsq.exec();
	d.close();
}
