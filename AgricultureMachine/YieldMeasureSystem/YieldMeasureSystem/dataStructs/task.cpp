#include "task.h"
#include <QDir>
#include <QDataStream>
#include <QDebug>
#include "../../common/database.h"
#include <QSqlError>
#include "global.h"
#include "xlsxdocument.h"
#include "../../common/database.h"
#include "tools/settingshandle.h"

#define TASKINFOROWATTRIBUTESCOUNT 20
#define BLOCKROWCOLUMN 1
#define BLOCKCOLUMNCOLUMN 2
#define STARTTIMECOLUMN 3
#define ENDTIMECOLUMN 4
#define MOISTURECOLUMN 5
#define MASSCOLUMN 6
#define UNITWEIGHTCOLUMN 7
#define CROPCOLUMN 8
#define STATECOLUMN 9
#define MARKCOLUMN 10

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
    qsq.prepare("SELECT MapName,Mark,CreateTime,LastWorkTime,PathType,StartRow,StartColumn,LastRow,LastColumn,Positive FROM "+TASKTABLE+" WHERE Name=?");
	qsq.addBindValue(qs);
	qsq.exec();
	qsq.next();
	mapName=qsq.value("MapName").toString();
	mark=qsq.value("Mark").toString();
	createTime=qsq.value("CreateTime").toString();
	lastWorkTime=qsq.value("LastWorkTime").toString();
	pathType=qsq.value("PathType").toString().toInt();
	startRow=qsq.value("StartRow").toString().toInt();
    startColumn=qsq.value("StartColumn").toString().toInt();
	lastRow=qsq.value("lastRow").toString().toInt();
	lastColumn=qsq.value("lastRow").toString().toInt();
    positive=qsq.value("Positive").toBool();
	qsq.prepare("SELECT MAX([Row]),MAX([Column]) FROM "+TASKBLOCKTABLE+" WHERE TaskName=?");
	qsq.addBindValue(qs);
	qsq.exec();
	qsq.next();
	int rowCount=qsq.value("MAX([Row])").toInt()+1,columnCount=qsq.value("MAX([Column])").toInt()+1;
    qsq.prepare("SELECT [Row],[Column],State,Measure FROM "+TASKBLOCKTABLE+" WHERE TaskName=? ORDER BY [Row],[Column]");
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
            rb.measure=qsq.value("Measure").toBool();
            rb.updateFlag=false;
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
        qsq.prepare("UPDATE "+TASKTABLE+" SET Mark=?,LastWorkTime=?,PathType=?,Positive=?,LastRow=?,LastColumn=?,StartRow=?,StartColumn=? WHERE Name=?");
        qsq.addBindValue(mark);
        qsq.addBindValue(lastWorkTime);
        qsq.addBindValue(pathType);
        qsq.addBindValue(positive?1:0);
        qsq.addBindValue(lastRow);
        qsq.addBindValue(lastColumn);
        qsq.addBindValue(startRow);
        qsq.addBindValue(startColumn);
        qsq.addBindValue(name);
        qsq.exec();
        for(size_t i=0;i<routeBlockVector.size();++i)
            for(size_t j=0;j<routeBlockVector[i].size();j++)
                if(routeBlockVector[i][j].updateFlag)
                {
                    qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=?,Measure=? WHERE TaskName=? AND [Row]=? AND [Column]=?");
                    qsq.addBindValue(routeBlockVector[i][j].state);
                    qsq.addBindValue(routeBlockVector[i][j].measure);
                    qsq.addBindValue(name);
                    qsq.addBindValue(i);
                    qsq.addBindValue(j);
                    qsq.exec();
                    routeBlockVector[i][j].updateFlag=false;
                }
    }
    else
    {
        qsq.prepare("INSERT INTO "+TASKTABLE+" (Name,MapName,Mark,CreateTime,LastWorkTime,PathType,StartRow,StartColumn,LastRow,LastColumn,Positive) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
        qsq.addBindValue(name);
        qsq.addBindValue(mapName);
        qsq.addBindValue(mark);
        qsq.addBindValue(createTime);
        qsq.addBindValue(lastWorkTime);
        qsq.addBindValue(pathType);
        qsq.addBindValue(startRow);
        qsq.addBindValue(startColumn);
        qsq.addBindValue(lastRow);
        qsq.addBindValue(lastColumn);
        qsq.addBindValue(positive?1:0);
        qsq.exec();
        for(size_t i=0;i<routeBlockVector.size();++i)
            for(size_t j=0;j<routeBlockVector[i].size();qsq.exec())
            {
                qsq.prepare("INSERT INTO "+TASKBLOCKTABLE+" (TaskName,[Row],[Column],State,Measure) VALUES (?,?,?,?,?)");
                qsq.addBindValue(name);
                qsq.addBindValue(i);
                qsq.addBindValue(j);
                qsq.addBindValue(routeBlockVector[i][j].state);
                qsq.addBindValue(routeBlockVector[i][j++].measure);
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

bool Task::columnDirection(int column)
{
    int yieldColumnCount=getMeasureColumnCount();
    column=column/yieldColumnCount*yieldColumnCount;//获取该列所在组的第一列，每yieldColumnCount列为一组
    switch(pathType)
    {
    case 0:
    case 1:
    case 3:
    case 4:
        return positive;
	case 2:
        return (column/yieldColumnCount<((int)routeBlockVector[0].size()/yieldColumnCount+1)/2)?positive:!positive;
	case 5:
        return (column/yieldColumnCount<((int)routeBlockVector[0].size()/yieldColumnCount-1)/2)?!positive:positive;
    }
	return false;
}

void Task::saveInfo()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("UPDATE "+TASKTABLE+" SET Mark=?,LastWorkTime=?,PathType=?,Positive=?,LastRow=?,LastColumn=?,StartRow=?,StartColumn=? WHERE Name=?");
    qsq.addBindValue(mark);
    qsq.addBindValue(lastWorkTime);
    qsq.addBindValue(pathType);
    qsq.addBindValue(positive);
    qsq.addBindValue(lastRow);
    qsq.addBindValue(lastColumn);
    qsq.addBindValue(startRow);
    qsq.addBindValue(startColumn);
    qsq.addBindValue(name);
    qsq.exec();
    d.close();
}

void Task::saveBlock(int row,int column)
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("UPDATE "+TASKBLOCKTABLE+" SET State=?,Measure=? WHERE TaskName=? AND Row=? AND Column=?");
    qsq.addBindValue(routeBlockVector[row][column].state);
    qsq.addBindValue(routeBlockVector[row][column].measure);
    qsq.addBindValue(name);
    qsq.addBindValue(row);
    qsq.addBindValue(column);
    qsq.exec();
    d.close();
}

bool Task::exportToXlsx(QString dir)
{
    QXlsx::Document d(dir+"/任务"+name+".xlsx");
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
    size_t rowCount=routeBlockVector.size();
    d.write(5,2,rowCount);
    d.write(6,1,"列");
    size_t columnCount=routeBlockVector[0].size();
    d.write(6,2,columnCount);
    d.write(7,1,"路线类型");
    d.write(7,2,pathType);
    d.write(8,1,"路线方向");
    d.write(8,2,positive?"反":"正");
    d.write(9,1,"起点排列");
    d.write(9,2,startRow);
    d.write(9,3,startColumn);
    d.write(10,1,"最近完成排列");
    d.write(10,2,lastRow);
    d.write(10,3,lastColumn);
    d.addSheet("状态");
    d.selectSheet("状态");
    for(int i=0;i<rowCount;i++)
        d.write(i+2,1,QString::number(rowCount-i)+"排");
    for(int i=0;i<columnCount;i++)
        d.write(1,i+2,QString::number(i+1)+"列");
	for(size_t i=0;i<routeBlockVector.size();i++)
		for(size_t j=0;j<routeBlockVector[i].size();j++)
            d.write(i+2,j+2,routeBlockVector[i][j].state);
    d.addSheet("测产");
    d.selectSheet("测产");
    for(int i=0;i<rowCount;i++)
        d.write(i+2,1,QString::number(rowCount-i)+"排");
    for(int i=0;i<columnCount;i++)
        d.write(1,i+2,QString::number(i+1)+"列");
    for(size_t i=0;i<routeBlockVector.size();i++)
        for(size_t j=0;j<routeBlockVector[i].size();j++)
            if(routeBlockVector[i][j].measure)
                d.write(i+2,j+2,"√");
	d.addSheet("结果");
	d.selectSheet("结果");
	for(int i=0;i<resultHeader.size();i++)
		d.write(1,i+1,resultHeader[i]);
	Database db;
	db.open();
	QSqlQuery qsq(db.qsd);
    qsq.prepare("SELECT StartTime,EndTime,Moisture,Mass,UnitWeight,[Row],[Column],Crop,Mark,State FROM "+RESULTTABLE+" WHERE State>0 AND TaskName=? ORDER BY [Row],[Column]");
	qsq.addBindValue(name);
	qsq.exec();
    for(int i=2;qsq.next();d.write(i++,MARKCOLUMN,qsq.value("Mark").toString()))
	{
        d.write(i,BLOCKROWCOLUMN,qsq.value("Row").toInt());
        d.write(i,BLOCKCOLUMNCOLUMN,qsq.value("Column").toInt());
		d.write(i,STARTTIMECOLUMN,qsq.value("StartTime").toString());
		d.write(i,ENDTIMECOLUMN,qsq.value("EndTime").toString());
		d.write(i,MOISTURECOLUMN,QString::number(qsq.value("Moisture").toFloat(),'f',2));
		d.write(i,MASSCOLUMN,QString::number(qsq.value("Mass").toFloat(),'f',3));
		d.write(i,UNITWEIGHTCOLUMN,QString::number(qsq.value("UnitWeight").toFloat(),'f',2));
		d.write(i,CROPCOLUMN,qsq.value("Crop").toString());
        d.write(i,STATECOLUMN,qsq.value("State").toInt());
	}
	db.close();
    d.selectSheet("信息");
    return d.save();
}

void Task::importFromXlsx(QString file,QString name)
{
    this->name=name;//=QFileInfo(file).fileName().section("任务",1,1).section(".",0,0);
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
            startRow=d.read(i,2).toInt();
            startColumn=d.read(i,3).toInt();
            break;
        }
    for(int i=1;i<TASKINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="最近完成排列")
        {
            lastRow=d.read(i,2).toInt();
            lastColumn=d.read(i,3).toInt();
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
    d.selectSheet("是否测产");
    std::vector<std::vector<TaskBlock>>().swap(routeBlockVector);
    for(int i=0;i<rowCount;i++)
    {
        std::vector<TaskBlock> bv;
        for(int j=0;j<columnCount;)
        {
            TaskBlock b;
            b.measure=d.read(i+2,2+j++).toString()=="√";
            bv.push_back(b);
        }
        routeBlockVector.push_back(bv);
    }
    // d.selectSheet("结果");
    // Database db;
    // db.open();
    // QSqlQuery qsq(db.qsd);
    // db.qsd.transaction();
    // for(int i=2;i<=d.dimension().rowCount();qsq.exec())
    // {
 //        qsq.prepare("INSERT INTO "+RESULTTABLE+" (TaskName,StartTime,EndTime,Moisture,Mass,UnitWeight,[Row],[Column],Crop,State,Mark) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
    // 	qsq.addBindValue(name);
    // 	qsq.addBindValue(d.read(i,STARTTIMECOLUMN).toString());
    // 	qsq.addBindValue(d.read(i,ENDTIMECOLUMN).toString());
    // 	qsq.addBindValue(d.read(i,MOISTURECOLUMN).toString().toFloat());
    // 	qsq.addBindValue(d.read(i,MASSCOLUMN).toString().toFloat());
    // 	qsq.addBindValue(d.read(i,UNITWEIGHTCOLUMN).toString().toFloat());
    // 	qsq.addBindValue(d.read(i,BLOCKROWCOLUMN).toInt()-1);
    // 	qsq.addBindValue(d.read(i,BLOCKCOLUMNCOLUMN).toInt()-1);
    // 	qsq.addBindValue(d.read(i,CROPCOLUMN).toString());
 //        qsq.addBindValue(d.read(i,STATECOLUMN).toInt());
 //        qsq.addBindValue(d.read(i++,MARKCOLUMN).toString());
    // }
    // db.qsd.commit();
    // db.close();
    d.selectSheet("信息");
    save();
}

void Task::initPathState()
{
    startRow=routeBlockVector.size()-1;
    startColumn=0;
    lastRow=-1;
    lastColumn=-1;
    positive=false;
    pathType=0;
}
