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
    qsq.prepare("SELECT * FROM "+RESULTTABLE+" ORDER BY TaskName,Row,Column");
    std::vector<BlockResult> data;
    for(qsq.exec();qsq.next();)
    {
        BlockResult br;
        br.taskName=qsq.value("TaskName").toString();
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
    qsq.prepare("SELECT StartTime,EndTime,[Row],[Column],SeedCount1,SeedCount2,SeedCount3,SeedCount4,SeedCount5,SeedCount6,FertilizerCount1,FertilizerCount2,FertilizerCount3,FertilizerCount4,FertilizerCount5,FertilizerCount6,Mark,State FROM "+RESULTTABLE+" WHERE TaskName=? ORDER BY Row,Column");
    qsq.addBindValue(taskName);
    std::vector<BlockResult> data;
    for(qsq.exec();qsq.next();)
    {
        BlockResult br;
        br.taskName=taskName;
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
        qsq.prepare("UPDATE "+RESULTTABLE+" SET StartTime=?,EndTime=?,Mark=?,State=?,SeedCount1=?,SeedCount2=?,SeedCount3=?,SeedCount4=?,SeedCount5=?,SeedCount6=?,FertilizerCount1=?,FertilizerCount2=?,FertilizerCount3=?,FertilizerCount4=?,FertilizerCount5=?,FertilizerCount6=? WHERE TaskName=? AND Row=? AND Column=?");
        qsq.addBindValue(startTime);
        qsq.addBindValue(endTime);
        qsq.addBindValue(mark);
        qsq.addBindValue(state);
        for(int i=0;i<MaxMotorCount;i++)
            qsq.addBindValue(i<(int)seedCount.size()?seedCount[i]:0);
        for(int i=0;i<MaxMotorCount;i++)
            qsq.addBindValue(i<(int)fertilizerCount.size()?fertilizerCount[i]:0);
        qsq.addBindValue(taskName);
        qsq.addBindValue(row);
        qsq.addBindValue(column);
    }
    else
    {
        qsq.prepare("INSERT INTO "+RESULTTABLE+" (TaskName,StartTime,EndTime,[Row],[Column],Mark,State,SeedCount1,SeedCount2,SeedCount3,SeedCount4,SeedCount5,SeedCount6,FertilizerCount1,FertilizerCount2,FertilizerCount3,FertilizerCount4,FertilizerCount5,FertilizerCount6) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
        qsq.addBindValue(taskName);
        qsq.addBindValue(startTime);
        qsq.addBindValue(endTime);
        qsq.addBindValue(row);
        qsq.addBindValue(column);
        qsq.addBindValue(mark);
        qsq.addBindValue(state);
        for(int i=0;i<MaxMotorCount;i++)
            qsq.addBindValue(i<(int)seedCount.size()?seedCount[i]:0);
        for(int i=0;i<MaxMotorCount;i++)
            qsq.addBindValue(i<(int)fertilizerCount.size()?fertilizerCount[i]:0);
    }
    qsq.exec();
    d.close();
}

void BlockResult::load()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT StartTime,EndTime,Mark,State,SeedCount1,SeedCount2,SeedCount3,SeedCount4,SeedCount5,SeedCount6,FertilizerCount1,FertilizerCount2,FertilizerCount3,FertilizerCount4,FertilizerCount5,FertilizerCount6 FROM "+RESULTTABLE+" WHERE [Row]=? AND [Column]=? AND TaskName=? LIMIT 1");
    qsq.addBindValue(row);
    qsq.addBindValue(column);
    qsq.addBindValue(taskName);
    qsq.exec();
    qsq.next();
    startTime=qsq.value("StartTime").toString();
    endTime=qsq.value("EndTime").toString();
    row=qsq.value("Row").toInt();
    column=qsq.value("Column").toInt();
    mark=qsq.value("Mark").toString();
    state=qsq.value("State").toInt();
    seedCount.push_back(qsq.value("SeedCount1").toInt());
    seedCount.push_back(qsq.value("SeedCount2").toInt());
    seedCount.push_back(qsq.value("SeedCount3").toInt());
    seedCount.push_back(qsq.value("SeedCount4").toInt());
    seedCount.push_back(qsq.value("SeedCount5").toInt());
    seedCount.push_back(qsq.value("SeedCount6").toInt());
    fertilizerCount.push_back(qsq.value("FertilizerCount1").toInt());
    fertilizerCount.push_back(qsq.value("FertilizerCount2").toInt());
    fertilizerCount.push_back(qsq.value("FertilizerCount3").toInt());
    fertilizerCount.push_back(qsq.value("FertilizerCount4").toInt());
    fertilizerCount.push_back(qsq.value("FertilizerCount5").toInt());
    fertilizerCount.push_back(qsq.value("FertilizerCount6").toInt());
    d.close();
}
