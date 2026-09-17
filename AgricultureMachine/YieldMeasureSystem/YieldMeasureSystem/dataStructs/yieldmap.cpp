#include "yieldmap.h"
#include <QDataStream>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include "../../common/database.h"
#include <QSqlError>
#include "global.h"
#include <xlsxdocument.h>

#define MAPINFOROWATTRIBUTESCOUNT 20

bool YieldMap::isExist(QString name)
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT Name FROM "+MAPTABLE+" WHERE Name=?");
    qsq.addBindValue(name);
    qsq.exec();
    bool b=qsq.next();
    d.close();
    return b;
}

YieldMap::YieldMap()
{
//	QDir qd;
//	if(!qd.exists(MAPDIRECTORY))
//		qd.mkdir(MAPDIRECTORY);
}

void YieldMap::load(QString qs)
{
//	QFile qf(MAPDIRECTORY+'/'+qs);
//	qf.open(QIODevice::ReadOnly);
//	QDataStream qds(&qf);
//	size_t rowCount,columnCount;
//	qds>>rowCount>>columnCount>>createTime>>modifyTime>>mark/*>>version*/;
//	name=qs;
//	std::vector<std::vector<Block>>().swap(blockVector);
//	for(size_t i=0;i++<rowCount;)
//	{
//		std::vector<Block> bv;
//		for(size_t j=0;j++<columnCount;)
//		{
//			Block b;
//			qds>>b.crop;
//			bv.push_back(b);
//		}
//		blockVector.push_back(bv);
//	}
//	qf.close();

    name=qs;
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT CreateTime,ModifyTime,Mark FROM "+MAPTABLE+" WHERE Name=?");
    qsq.addBindValue(qs);
    qsq.exec();
    qsq.next();
    createTime=qsq.value("CreateTime").toString();
    modifyTime=qsq.value("ModifyTime").toString();
    mark=qsq.value("Mark").toString();
    qsq.prepare("SELECT MAX([Row]),MAX([Column]) FROM "+MAPBLOCKTABLE+" WHERE MapName=?");
    qsq.addBindValue(qs);
    qsq.exec();
	qsq.next();
	int rowCount=qsq.value("MAX([Row])").toInt()+1,columnCount=qsq.value("MAX([Column])").toInt()+1;
    qsq.prepare("SELECT [Row],[Column],Crop,Number FROM "+MAPBLOCKTABLE+" WHERE MapName=? ORDER BY [Row],[Column]");
    qsq.addBindValue(qs);
    qsq.exec();
    std::vector<std::vector<YieldBlock>>().swap(blockVector);
    for(int i=0;i++<rowCount;)
    {
		std::vector<YieldBlock> bv;
		std::deque<bool> bd;
        for(int j=0;j++<columnCount&&qsq.next();bd.push_back(false))
        {
            YieldBlock b;
            b.crop=qsq.value("Crop").toString();
			b.number=qsq.value("Number").toString();
            b.updateFlag=false;
			bv.push_back(b);
        }
        blockVector.push_back(bv);
    }
    d.close();
}

void YieldMap::save()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT Name From "+MAPTABLE+" WHERE Name=?");
    qsq.addBindValue(name);
    qsq.exec();
    d.qsd.transaction();
    if(qsq.next())
    {
        qsq.prepare("UPDATE "+MAPTABLE+" SET Mark=? WHERE Name=?");
        qsq.addBindValue(mark);
        qsq.addBindValue(name);
        qsq.exec();
        for(size_t i=0;i<blockVector.size();++i)
            for(size_t j=0;j<blockVector[i].size();++j)
                if(blockVector[i][j].updateFlag)
                {
                    qsq.prepare("UPDATE "+MAPBLOCKTABLE+" SET Crop=?,Number=? WHERE MapName=? AND [Row]=? AND [Column]=?");
                    qsq.addBindValue(blockVector[i][j].crop);
                    qsq.addBindValue(blockVector[i][j].number);
                    qsq.addBindValue(name);
                    qsq.addBindValue(i);
                    qsq.addBindValue(j);
                    qsq.exec();
                    blockVector[i][j].updateFlag=false;
                }
    }
    else
    {
        qsq.prepare("INSERT INTO "+MAPTABLE+" (Name,Mark) VALUES (?,?)");
        qsq.addBindValue(name);
        qsq.addBindValue(mark);
        qsq.exec();
        for(size_t i=0;i<blockVector.size();++i)
            for(size_t j=0;j<blockVector[i].size();qsq.exec())
            {
                qsq.prepare("INSERT INTO "+MAPBLOCKTABLE+" (MapName,[Row],[Column],Crop,Number) VALUES (?,?,?,?,?)");
                qsq.addBindValue(name);
                qsq.addBindValue(i);
                qsq.addBindValue(j);
                qsq.addBindValue(blockVector[i][j].crop);
                qsq.addBindValue(blockVector[i][j++].number);
            }
    }
    d.qsd.commit();
    d.close();
}

bool YieldMap::exportToXlsx(QString dir)
{
    QXlsx::Document d(dir+"/地图"+name+".xlsx");
    d.addSheet("信息");
    d.write(1,1,"类型");
    d.write(1,2,"测产");
    d.write(2,1,"创建时间");
    QXlsx::Format f;
    f.setPatternBackgroundColor("#99ff99");
    f.setBorderStyle(QXlsx::Format::BorderThin);
    f.setBorderColor("#d4d4d4");
    d.write(2,2,createTime,f);
    d.write(3,1,"修改时间");
    d.write(3,2,modifyTime,f);
    d.write(4,1,"备注");
    d.write(4,2,mark,f);
    d.write(5,1,"排");
    int rowCount=blockVector.size();
    d.write(5,2,rowCount);
    d.write(6,1,"列");
    int columnCount=blockVector[0].size();
    d.write(6,2,columnCount);
    d.addSheet("编号");
    d.selectSheet("编号");
    initSheet(d);
    for(int i=0;i<rowCount;i++)
        for(size_t j=0;j<blockVector[i].size();j++)
            d.write(i+2,j+2,blockVector[i][j].number,f);
    d.addSheet("作物");
    d.selectSheet("作物");
    initSheet(d);
    for(int j=0;j<rowCount;j++)
        for(size_t k=0;k<blockVector[j].size();k++)
            d.write(j+2,k+2,blockVector[j][k].crop,f);
    d.selectSheet("信息");
    return d.save();
}

void YieldMap::importFromXlsx(QString file,QString name)
{
    this->name=name;//=QFileInfo(file).fileName().section("地图",1,1).section(".",0,0);
    QXlsx::Document d(file);
    d.selectSheet("信息");
    QString type;
	for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="类型")
		{
            type=d.read(i,2).toString();
			if(type!="播种"&&type!="测产")
                return;
		}
    for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="创建时间")
        {
            createTime=d.read(i,2).toString();
            break;
        }
    for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="修改时间")
        {
            modifyTime=d.read(i,2).toString();
            break;
        }
    for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="备注")
        {
            mark=d.read(i,2).toString();
            break;
        }
    int rowCount=0,columnCount=0;
    for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="排")
        {
            rowCount=d.read(i,2).toInt();
            break;
        }
    for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
        if(d.read(i,1).toString()=="列")
        {
            columnCount=d.read(i,2).toInt();
            break;
        }
    d.selectSheet("编号");
    if(type=="播种")
    {
        std::vector<std::vector<Block>>().swap(Map::blockVector);
        for(int i=0;i<rowCount;i++)
        {
            std::vector<Block> bv;
            for(int j=0;j<columnCount;)
            {
                Block b;
                b.number=d.read(i+2,2+j++).toString();
                bv.push_back(b);
            }
            Map::blockVector.push_back(bv);
        }
    }
    else if(type=="测产")
    {
        std::vector<std::vector<YieldBlock>>().swap(blockVector);
        for(int i=0;i<rowCount;i++)
        {
            std::vector<YieldBlock> bv;
            for(int j=0;j<columnCount;)
            {
                YieldBlock b;
                b.number=d.read(i+2,2+j++).toString();
                bv.push_back(b);
            }
            blockVector.push_back(bv);
        }
        d.selectSheet("作物");
        for(int i=0;i<rowCount;i++)
            for(int j=0;j<columnCount;j++)
                blockVector[i][j].crop=d.read(i+2,j+2).toString();
	}
	save();
}

void YieldMap::saveNumber()
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Name From "+MAPTABLE+" WHERE Name=?");
	qsq.addBindValue(name);
	qsq.exec();
	if(qsq.next())
	{
		d.qsd.transaction();
		for(size_t i=0;i<blockVector.size();++i)
			for(size_t j=0;j<blockVector[i].size();++j)
                if(blockVector[i][j].updateFlag)
				{
					qsq.prepare("UPDATE "+MAPBLOCKTABLE+" SET Number=? WHERE MapName=? AND [Row]=? AND [Column]=?");
					qsq.addBindValue(blockVector[i][j].number);
					qsq.addBindValue(name);
					qsq.addBindValue(i);
					qsq.addBindValue(j);
					qsq.exec();
                    blockVector[i][j].updateFlag=false;
				}
		d.qsd.commit();
	}
	d.close();
}

void YieldMap::saveCrop()
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Name From "+MAPTABLE+" WHERE Name=?");
	qsq.addBindValue(name);
	qsq.exec();
	if(qsq.next())
	{
		d.qsd.transaction();
		for(size_t i=0;i<blockVector.size();++i)
			for(size_t j=0;j<blockVector[i].size();++j)
                if(blockVector[i][j].updateFlag)
                {
                    qsq.prepare("UPDATE "+MAPBLOCKTABLE+" SET Crop=? WHERE MapName=? AND [Row]=? AND [Column]=?");
                    qsq.addBindValue(blockVector[i][j].crop);
                    qsq.addBindValue(name);
                    qsq.addBindValue(i);
                    qsq.addBindValue(j);
                    qsq.exec();
                    blockVector[i][j].updateFlag=false;
                }
		d.qsd.commit();
	}
	d.close();
}

void YieldMap::initSheet(QXlsx::Document &d)
{
    int rowCount=blockVector.size();
    for(int i=0;i<rowCount;i++)
        d.write(i+2,1,QString::number(rowCount-i)+"排");
    for(size_t i=0;i<blockVector[0].size();i++)
        d.write(1,i+2,QString::number(i+1)+"列");
}
