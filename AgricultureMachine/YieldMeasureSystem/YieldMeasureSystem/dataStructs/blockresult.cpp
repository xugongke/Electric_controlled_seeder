#include "blockresult.h"
#include "../../common/database.h"
#include <QVariant>
#include <QDebug>
#include "global.h"
#include <QSqlError>
#include <QFile>

std::vector<BlockResult> BlockResult::loadAll()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT * FROM "+RESULTTABLE+"ORDER BY TaskName,Row,Column");
    std::vector<BlockResult> data;
    for(qsq.exec();qsq.next();)
    {
        BlockResult br;
        br.taskName=qsq.value("TaskName").toString();
        br.startTime=qsq.value("StartTime").toString();
        br.endTime=qsq.value("EndTime").toString();
        br.moisture=qsq.value("Moisture").toFloat();
        br.mass=qsq.value("Mass").toFloat();
        br.unitWeight=qsq.value("UnitWeight").toFloat();
        br.row=qsq.value("Row").toInt();
        br.column=qsq.value("Column").toInt();
        br.crop=qsq.value("Crop").toString();
        br.mark=qsq.value("Mark").toString();
        br.state=qsq.value("State").toInt();
        data.push_back(br);
    }
    d.close();
    return data;
}

std::vector<BlockResult> BlockResult::loadAll(QString taskName)
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT StartTime,EndTime,Moisture,Mass,UnitWeight,[Row],[Column],Crop,Mark,State FROM "+RESULTTABLE+" WHERE TaskName=? ORDER BY Row,Column");
    qsq.addBindValue(taskName);
    BlockResult br;
    br.taskName=taskName;
    std::vector<BlockResult> data;
    for(qsq.exec();qsq.next();)
    {
        br.startTime=qsq.value("StartTime").toString();
        br.endTime=qsq.value("EndTime").toString();
        br.moisture=qsq.value("Moisture").toFloat();
        br.mass=qsq.value("Mass").toFloat();
        br.unitWeight=qsq.value("UnitWeight").toFloat();
        br.row=qsq.value("Row").toInt();
        br.column=qsq.value("Column").toInt();
        br.crop=qsq.value("Crop").toString();
        br.mark=qsq.value("Mark").toString();
        br.state=qsq.value("State").toInt();
        data.push_back(br);
    }
    d.close();
    return data;
}

BlockResult::BlockResult()
{

}

void BlockResult::save()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT TaskName FROM "+RESULTTABLE+" WHERE TaskName=? AND Row=? AND Column=? LIMIT 1");
    qsq.addBindValue(taskName);
    qsq.addBindValue(row);
    qsq.addBindValue(column);
    qsq.exec();
    if(qsq.next())
    {
        qsq.prepare("UPDATE "+RESULTTABLE+" SET StartTime=?,EndTime=?,Moisture=?,Mass=?,UnitWeight=?,Crop=?,Mark=?,State=? WHERE TaskName=? AND Row=? AND Column=?");
        qsq.addBindValue(startTime);
        qsq.addBindValue(endTime);
        qsq.addBindValue(moisture);
        qsq.addBindValue(mass);
        qsq.addBindValue(unitWeight);
        qsq.addBindValue(crop);
        qsq.addBindValue(mark);
        qsq.addBindValue(state);
        qsq.addBindValue(taskName);
        qsq.addBindValue(row);
        qsq.addBindValue(column);
    }
    else
    {
        qsq.prepare("INSERT INTO "+RESULTTABLE+" (TaskName,StartTime,EndTime,Moisture,Mass,UnitWeight,[Row],[Column],Crop,Mark,State) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
        qsq.addBindValue(taskName);
        qsq.addBindValue(startTime);
        qsq.addBindValue(endTime);
        qsq.addBindValue(moisture);
        qsq.addBindValue(mass);
        qsq.addBindValue(unitWeight);
        qsq.addBindValue(row);
        qsq.addBindValue(column);
        qsq.addBindValue(crop);
        qsq.addBindValue(mark);
        qsq.addBindValue(state);
    }
    qsq.exec();qDebug()<<taskName;
    d.close();
}

void BlockResult::load()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT StartTime,EndTime,Moisture,Mass,UnitWeight,Crop,Mark,State FROM "+RESULTTABLE+" WHERE [Row]=? AND [Column]=? TaskName=? LIMIT 1");
    qsq.addBindValue(row);
    qsq.addBindValue(column);
    qsq.addBindValue(taskName);
    qsq.exec();
    qsq.next();
    startTime=qsq.value("StartTime").toString();
    endTime=qsq.value("EndTime").toString();
    moisture=qsq.value("Moisture").toFloat();
    mass=qsq.value("Mass").toFloat();
    unitWeight=qsq.value("UnitWeight").toFloat();
    row=qsq.value("Row").toInt();
    column=qsq.value("Column").toInt();
    crop=qsq.value("Crop").toString();
    mark=qsq.value("Mark").toString();
    state=qsq.value("State").toInt();
    d.close();
}
