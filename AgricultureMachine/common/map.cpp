#include "map.h"
#include "../../common/database.h"
#include <QVariant>
#include <QDebug>
#include <QSqlError>
#include <QFileInfo>
#include <cmath>
#include <QSettings>
#include "../SowSystem/SowSystem/global.h"
#include <deque>

#define MAPINFOROWATTRIBUTESCOUNT 20

QStringList Block::viewType={
    "排列","编号","密度(株/亩)"
};

bool Map::isExist(QString name)
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

Map::Map()
{

}

void Map::load(QString qs)
{
	name=qs;
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT CreateTime,ModifyTime,Mark,BlockColumn,MachineColumn,SeedColumnGap,ABLineName FROM "+MAPTABLE+" WHERE Name=?");
	qsq.addBindValue(qs);
	qsq.exec();
	qsq.next();
	createTime=qsq.value("CreateTime").toString();
	modifyTime=qsq.value("ModifyTime").toString();
	mark=qsq.value("Mark").toString();
	blockColumn=qsq.value("BlockColumn").toInt();
    machineColumn=qsq.value("MachineColumn").toInt();
	seedColumnGap=qsq.value("SeedColumnGap").toInt();
    abLineName=qsq.value("ABLineName").toString();
	qsq.prepare("SELECT MAX([Row]),MAX([Column]) FROM "+MAPBLOCKTABLE+" WHERE MapName=?");
	qsq.addBindValue(qs);
	qsq.exec();
	qsq.next();
	int rowCount=qsq.value("MAX([Row])").toInt()+1,columnCount=qsq.value("MAX([Column])").toInt()+1;
	qsq.prepare("SELECT [Row],[Column],Number,Density,SowSeed FROM "+MAPBLOCKTABLE+" WHERE MapName=? ORDER BY [Row],[Column]");
	qsq.addBindValue(qs);
	qsq.exec();
	std::vector<std::vector<Block>>().swap(blockVector);
	for(int i=0;i++<rowCount;)
	{
		std::vector<Block> bv;
		std::deque<bool> bd;
		for(int j=0;j++<columnCount&&qsq.next();bd.push_back(false))
		{
			Block b;
			b.number=qsq.value("Number").toString();
			b.density=qsq.value("Density").toInt();
			b.sowSeed=qsq.value("SowSeed").toBool();
            b.updateFlag=false;
			bv.push_back(b);
		}
		blockVector.push_back(bv);
	}
	qsq.prepare("SELECT [Row],Length FROM "+ROWATTRIBUTESTABLE+" WHERE MapName=? ORDER BY [Row]");
	qsq.addBindValue(qs);
	std::vector<RowAttributes>().swap(rowAttributesVector);
	for(qsq.exec();qsq.next();)
	{
		RowAttributes ra;
		ra.length=qsq.value("Length").toInt();
		rowAttributesVector.push_back(ra);
	}
	qsq.prepare("SELECT [Index],Length FROM "+MAPAISLETABLE+" WHERE MapName=? ORDER BY [Index]");
	qsq.addBindValue(qs);
	std::vector<Aisle>().swap(aisleVector);
	for(qsq.exec();qsq.next();)
	{
		Aisle a;
		a.length=qsq.value("Length").toInt();
		aisleVector.push_back(a);
	}
	d.close();
}

void Map::save()
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
					qsq.prepare("UPDATE "+MAPBLOCKTABLE+" SET Number=?,Density=?,SowSeed=? WHERE MapName=? AND [Row]=? AND [Column]=?");
					qsq.addBindValue(blockVector[i][j].number);
					qsq.addBindValue(blockVector[i][j].density);
					qsq.addBindValue(blockVector[i][j].sowSeed);
					qsq.addBindValue(name);
					qsq.addBindValue(i);
					qsq.addBindValue(j);
					qsq.exec();
                    blockVector[i][j].updateFlag=false;
				}
		for(size_t i=0;i<rowAttributesVector.size();qsq.exec())
		{
			qsq.prepare("UPDATE "+ROWATTRIBUTESTABLE+" SET Length=? WHERE MapName=? AND [Row]=?");
			qsq.addBindValue(QString::number(rowAttributesVector[i].length));
			qsq.addBindValue(name);
			qsq.addBindValue(i++);
		}
        for(size_t i=0;i<aisleVector.size();qsq.exec())
		{
			qsq.prepare("UPDATE "+MAPAISLETABLE+" SET Length=? WHERE MapName=? AND [Index]=?");
			qsq.addBindValue(QString::number(aisleVector[i].length));
			qsq.addBindValue(name);
            qsq.addBindValue(i++);
		}
	}
	else
	{
		qsq.prepare("INSERT INTO "+MAPTABLE+" (Name,Mark,BlockColumn,MachineColumn,SeedColumnGap) VALUES (?,?,?,?,?)");
		qsq.addBindValue(name);
		qsq.addBindValue(mark);
		qsq.addBindValue(blockColumn);
		qsq.addBindValue(machineColumn);
		qsq.addBindValue(seedColumnGap);
		qsq.exec();
		for(size_t i=0;i<blockVector.size();++i)
			for(size_t j=0;j<blockVector[i].size();qsq.exec())
			{
				qsq.prepare("INSERT INTO "+MAPBLOCKTABLE+" (MapName,[Row],[Column],Number,Density,SowSeed) VALUES (?,?,?,?,?,?)");
				qsq.addBindValue(name);
				qsq.addBindValue(i);
				qsq.addBindValue(j);
				qsq.addBindValue(blockVector[i][j].number);
				qsq.addBindValue(blockVector[i][j].density);
				qsq.addBindValue(blockVector[i][j++].sowSeed);
			}
		for(size_t i=0;i<rowAttributesVector.size();qsq.exec())
		{
			qsq.prepare("INSERT INTO "+ROWATTRIBUTESTABLE+" (MapName,[Row],Length) VALUES (?,?,?)");
			qsq.addBindValue(name);
			qsq.addBindValue(i);
			qsq.addBindValue(QString::number(rowAttributesVector[i++].length,'f',2));
		}
		for(size_t i=0;i<aisleVector.size();qsq.exec())
		{
			qsq.prepare("INSERT INTO "+MAPAISLETABLE+" (MapName,[Index],Length) VALUES (?,?,?)");
			qsq.addBindValue(name);
			qsq.addBindValue(i);
			qsq.addBindValue(QString::number(aisleVector[i++].length,'f',2));
		}
	}
	d.qsd.commit();
	d.close();
}

bool Map::exportToXlsx(QString dir)
{
    QXlsx::Document d(dir+"/地图"+name+".xlsx");
	d.addSheet("信息");
	d.write(1,1,"类型");
	d.write(1,2,"播种");
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
    size_t rowCount=blockVector.size();
    d.write(5,2,rowCount);
	d.write(6,1,"列");
    size_t columnCount=blockVector[0].size();
    d.write(6,2,columnCount);
	d.write(7,1,"小区行数");
    d.write(7,2,blockColumn,f);
	d.write(8,1,"机器行数");
    d.write(8,2,machineColumn,f);
	d.write(9,1,"行间距(cm)");
    d.write(9,2,seedColumnGap,f);
	d.write(1,3,"排长(cm)");
    for(size_t i=0;i<rowCount;i++)
        d.write(i+2,3,rowAttributesVector[i].length,f);
	d.write(1,4,"过道长(cm)");
    for(size_t i=0;i<rowCount+1;i++)
        d.write(i+2,4,aisleVector[i].length,f);
	if(!abLineName.isEmpty())
	{
		d.addSheet("AB线");
		d.selectSheet("AB线");
		d.write(1,1,"StartN");
		d.write(1,2,abLine.StartN);
		d.write(2,1,"StartE");
		d.write(2,2,abLine.StartE);
		d.write(3,1,"EndBN");
		d.write(3,2,abLine.EndBN);
		d.write(4,1,"EndBE");
		d.write(4,2,abLine.EndBE);
		d.write(5,1,"StartDir");
		d.write(5,2,abLine.StartDir);
		d.write(6,1,"CalcDir");
		d.write(6,2,abLine.CalcDir);
		d.write(7,1,"StartState");
		d.write(7,2,abLine.StartState);
		d.write(8,1,"CalcDirFlag");
		d.write(8,2,abLine.CalcDirFlag);
		d.write(9,1,"OffLen");
		d.write(9,2,abLine.OffLen);
		d.write(10,1,"BDOffTime");
		d.write(10,2,abLine.BDOffTime);
		d.write(11,1,"Resv");
		d.write(11,2,abLine.Resv);
		d.write(12,1,"CrcCheck");
		d.write(12,2,abLine.CrcCheck);
		d.write(13,1,"A点排");
		d.write(13,2,aRow);
		d.write(14,1,"A点列");
		d.write(14,2,aColumn);
		d.write(15,1,"方向");
		d.write(15,2,abLineDirection);
        d.write(16,1,"名称");
        d.write(16,2,abLineName);
	}
	d.addSheet("编号");
	d.selectSheet("编号");
    initSheet(d);
	for(size_t i=0;i<blockVector.size();i++)
		for(size_t j=0;j<blockVector[i].size();j++)
            d.write(i+2,j+2,blockVector[i][j].number,f);
	d.addSheet("密度");
	d.selectSheet("密度");
    initSheet(d);
	for(size_t j=0;j<blockVector.size();j++)
		for(size_t k=0;k<blockVector[j].size();k++)
            d.write(j+2,k+2,blockVector[j][k].density,f);
	d.addSheet("是否播种");
	d.selectSheet("是否播种");
    initSheet(d);
	for(size_t j=0;j<blockVector.size();j++)
		for(size_t k=0;k<blockVector[j].size();k++)
			if(blockVector[j][k].sowSeed)
                d.write(j+2,k+2,"√",f);
	d.selectSheet("信息");
	return d.save();
}

void Map::importFromXlsx(QString file,QString name)
{
    this->name=name;//QFileInfo(file).fileName().section("地图",1,1).section(".",0,0);
	QXlsx::Document d(file);
	d.selectSheet("信息");
	for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="类型")
		{
			if(d.read(i,2).toString()!="播种")
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
	for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="小区行数")
		{
			blockColumn=d.read(i,2).toInt();
			break;
		}
	for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="机器行数")
		{
			machineColumn=d.read(i,2).toInt();
			break;
		}
	for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
		if(d.read(i,1).toString()=="行间距(cm)")
		{
			seedColumnGap=d.read(i,2).toFloat();
			break;
		}
	std::vector<RowAttributes>().swap(rowAttributesVector);
	for(int i=2;;)
	{
		QVariant qv=d.read(i++,3);
		if(!qv.isValid())
			break;
		RowAttributes ra;
		ra.length=qv.toFloat();
		rowAttributesVector.push_back(ra);
	}
	std::vector<Aisle>().swap(aisleVector);
	for(int i=2;;)
	{
		QVariant qv=d.read(i++,4);
		if(!qv.isValid())
			break;
		Aisle a;
		a.length=qv.toFloat();
		aisleVector.push_back(a);
	}
	d.selectSheet("编号");
	std::vector<std::vector<Block>>().swap(blockVector);
    for(int i=0;i<rowCount;i++)
	{
		std::vector<Block> bv;
        for(int j=0;j<columnCount;)
		{
			Block b;
            b.number=d.read(i+2,2+j++).toString();
			bv.push_back(b);
		}
		blockVector.push_back(bv);
	}
	d.selectSheet("密度");
    for(int i=0;i<rowCount;i++)
    {
        for(int j=0;j<columnCount;j++)
            blockVector[i][j].density=d.read(i+2,j+2).toInt();
    }
	d.selectSheet("是否播种");
    for(int i=0;i<rowCount;i++)
    {
        for(int j=0;j<columnCount;j++)
            blockVector[i][j].sowSeed=d.read(i+2,j+2).toString()=="√";
    }
	bool hasABLine=d.selectSheet("AB线");
    if(hasABLine)
    {
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="StartN")
			{
				abLine.StartN=d.read(i,2).toDouble();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="StartE")
			{
				abLine.StartE=d.read(i,2).toDouble();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="EndBN")
			{
				abLine.EndBN=d.read(i,2).toDouble();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="EndBE")
			{
				abLine.EndBE=d.read(i,2).toDouble();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="StartDir")
			{
				abLine.StartDir=d.read(i,2).toFloat();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="CalcDir")
			{
				abLine.CalcDir=d.read(i,2).toFloat();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="StartState")
			{
				abLine.StartState=d.read(i,2).toUInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="CalcDirFlag")
			{
				abLine.CalcDirFlag=d.read(i,2).toUInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="OffLen")
			{
				abLine.OffLen=d.read(i,2).toUInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="BDOffTime")
			{
				abLine.BDOffTime=d.read(i,2).toUInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="Resv")
			{
				abLine.Resv=d.read(i,2).toULongLong();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="CrcCheck")
			{
				abLine.CrcCheck=d.read(i,2).toULongLong();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="A点排")
			{
				aRow=d.read(i,2).toInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="A点列")
			{
				aColumn=d.read(i,2).toInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="方向")
			{
				abLineDirection=d.read(i,2).toInt();
				break;
			}
		for(int i=1;i<MAPINFOROWATTRIBUTESCOUNT;i++)
			if(d.read(i,1).toString()=="名称")
			{
				abLineName=d.read(i,2).toString();
				break;
			}
	}
	d.selectSheet("信息");
	save();
	saveABLine(abLineName);
}

int Map::blockEachTrip()
{
	return machineColumn/blockColumn;
}

std::vector<int> Map::getColumnNode(int column)
{
	int b=blockEachTrip();
	column=column/b*b;//获取该列所在组的第一列，每blockEachTrip()列为一组
	std::vector<int> columnNodeVector;
	for(int i=0;i<b;columnNodeVector.push_back(column+i++));
	return columnNodeVector;
}

/***************************************************************************************************
*\Function      GetZhuShu
*\Description
*\Parameter     density     密度:株/亩     Q
*\Parameter     cell_len    小区长度   cm  L
*\Parameter     hju         行间距 单位cm  H
*\Return        u32
*\Note          1)株距=cell_len/(株数-1)
***************************************************************************************************/
u32 Map::GetZhuShu(u32 density, u32 cell_len, u16 hju)
{
    u32 zhushu;  //单行株数
    if (cell_len < 20){
        cell_len = 20;
    }
    zhushu = ceil((density*1.0)*(hju*0.01)*(cell_len*0.01)/666.7); //上取整 如3.1取4

    if (zhushu < 2){
        zhushu = 2;
    }

    return zhushu;
}

u32 Map::GetZhuShu(int row,int column)
{
	u32 zhushu;  //单行株数
	zhushu = ceil((blockVector[row][column].density*1.0)*(seedColumnGap*0.01)*(rowAttributesVector[row].length<20?20:rowAttributesVector[row].length*0.01)/666.7); //上取整 如3.1取4
	return zhushu<2?2:zhushu;
}

float Map::seedGap(int row,int column)
{
	return rowAttributesVector[row].length*1.0/(GetZhuShu(row,column)-1)/100.0;
}

void Map::loadABLine()
{
    if(abLineName.isEmpty())
		return;
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
    qsq.prepare("SELECT StartN,StartE,EndBN,EndBE,StartDir,CalcDir,StartState,CalcDirFlag,OffLen,BDOffTime,Resv,CrcCheck FROM "+ABLINETABLE+" WHERE Name=?");
    qsq.addBindValue(abLineName);
	qsq.exec();
	qsq.next();
	abLine.StartN=qsq.value("StartN").toDouble();
	abLine.StartE=qsq.value("StartE").toDouble();
	abLine.EndBN=qsq.value("EndBN").toDouble();
	abLine.EndBE=qsq.value("EndBE").toDouble();
	abLine.StartDir=qsq.value("StartDir").toDouble();
	abLine.CalcDir=qsq.value("CalcDir").toDouble();
	abLine.StartState=qsq.value("StartState").toFloat();
	abLine.CalcDirFlag=qsq.value("CalcDirFlag").toFloat();
	abLine.OffLen=qsq.value("OffLen").toInt();
	abLine.BDOffTime=qsq.value("BDOffTime").toInt();
	abLine.Resv=qsq.value("Resv").toInt();
	abLine.CrcCheck=qsq.value("CrcCheck").toInt();
	qsq.prepare("SELECT ARow,AColumn,ABLineDirection FROM "+MAPTABLE+" WHERE Name=?");
    qsq.addBindValue(name);
	qsq.exec();
	qsq.next();
	aRow=qsq.value("ARow").toInt();
	aColumn=qsq.value("AColumn").toInt();
	abLineDirection=qsq.value("ABLineDirection").toInt();
	d.qsd.close();
}

void Map::saveABLine(QString ablName)
{
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	qsq.prepare("SELECT Name FROM "+ABLINETABLE+" WHERE Name=?");
	qsq.addBindValue(ablName);
	qsq.exec();
	if(!ablName.isEmpty())
		abLineName=ablName;
	d.qsd.transaction();
	if(qsq.next())
	{
		qsq.prepare("UPDATE "+ABLINETABLE+" SET StartN=?,StartE=?,EndBN=?,EndBE=?,StartDir=?,CalcDir=?,StartState=?,CalcDirFlag=?,OffLen=?,BDOffTime=?,Resv=?,CrcCheck=? WHERE Name=?");
        qsq.addBindValue(QString::number(abLine.StartN,'f',8));
        qsq.addBindValue(QString::number(abLine.StartE,'f',8));
        qsq.addBindValue(QString::number(abLine.EndBN,'f',8));
        qsq.addBindValue(QString::number(abLine.EndBE,'f',8));
        qsq.addBindValue(QString::number(abLine.StartDir,'f',6));
        qsq.addBindValue(QString::number(abLine.CalcDir,'f',6));
		qsq.addBindValue(abLine.StartState);
		qsq.addBindValue(abLine.CalcDirFlag);
		qsq.addBindValue(abLine.OffLen);
		qsq.addBindValue(abLine.BDOffTime);
		qsq.addBindValue(abLine.Resv);
		qsq.addBindValue(abLine.CrcCheck);
		qsq.addBindValue(abLineName);
		qsq.exec();
	}
	else
	{
		qsq.prepare("INSERT INTO "+ABLINETABLE+" (Name,StartN,StartE,EndBN,EndBE,StartDir,CalcDir,StartState,CalcDirFlag,OffLen,BDOffTime,Resv,CrcCheck) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)");
		qsq.addBindValue(ablName);
        qsq.addBindValue(QString::number(abLine.StartN,'f',8));
        qsq.addBindValue(QString::number(abLine.StartE,'f',8));
        qsq.addBindValue(QString::number(abLine.EndBN,'f',8));
        qsq.addBindValue(QString::number(abLine.EndBE,'f',8));
        qsq.addBindValue(QString::number(abLine.StartDir,'f',6));
        qsq.addBindValue(QString::number(abLine.CalcDir,'f',6));
		qsq.addBindValue(abLine.StartState);
		qsq.addBindValue(abLine.CalcDirFlag);
		qsq.addBindValue(abLine.OffLen);
		qsq.addBindValue(abLine.BDOffTime);
		qsq.addBindValue(abLine.Resv);
		qsq.addBindValue(abLine.CrcCheck);
		qsq.exec();
	}
	qsq.prepare("UPDATE "+MAPTABLE+" SET ARow=?,AColumn=?,ABLineDirection=?,ABLineName=? WHERE Name=?");
	qsq.addBindValue(aRow);
	qsq.addBindValue(aColumn);
	qsq.addBindValue(abLineDirection);
	qsq.addBindValue(abLineName);
	qsq.addBindValue(name);
	qsq.exec();
	d.qsd.commit();
	d.close();
}

void Map::clearABLine()
{
	Database d;
	d.open();
    QSqlQuery qsq(d.qsd);
    //待修改delete
    qsq.prepare("UPDATE "+MAPTABLE+" SET ARow=NULL,AColumn=NULL,ABLineDirection=NULL,ABLineName=NULL WHERE Name=?");
    qsq.addBindValue(name);
    qsq.exec();
	d.close();
    abLineName.clear();
}

int Map::columnWidth()
{
	return blockColumn*seedColumnGap;
}

int Map::columnOffset(int column,bool b)
{
    return b?column*columnWidth():(column+1)*columnWidth();
}

int Map::rowToOffset(int row)
{
    //排相对于AB线的偏移
	int offset=0;
	if(abLineDirection)
        for(int i=0;i<row;i++)
            offset+=rowAttributesVector[i].length+aisleVector[i+1].length;
	else
        for(int i=rowAttributesVector.size()-1;i>row;i--)
            offset+=rowAttributesVector[i].length+aisleVector[i].length;
	return offset;
}

int Map::offsetToRow(int offset)
{
	size_t rowCount=blockVector.size();
    if(!abLineName.isEmpty()&&!abLineDirection)
    {
        //若AB线为反向
        if(offset<-aisleVector[aisleVector.size()-1].length)
        {
            int t=rowCount-1;
            for(int t2=offset;t2<0;t++)
                t2+=aisleVector[0].length+rowAttributesVector[0].length;
            return t;
        }
        if(offset<0)
            return -999999;
        for(int i=rowCount-1;i>=0;i--)
        {
            offset-=rowAttributesVector[i].length;
            if(offset<0)
                return i;
            offset-=aisleVector[i].length;
            if(offset<0)
                return -999999;
        }
        int t=0;
        for(;offset>0;t--)
            offset-=aisleVector[0].length+rowAttributesVector[0].length;
        return t;
	}
    if(offset<-aisleVector[0].length)
    {
        offset+=aisleVector[0].length;
        int d=aisleVector[0].length+rowAttributesVector[0].length,t=offset/d;
        if(offset%d<0)
            t--;
        return t;
    }
    if(offset<0)
        return -999999;
    int o=0;
    for(size_t i=0;i<rowCount;i++)
    {
        o+=rowAttributesVector[i].length;
        if(offset<o)
            return i;
        o+=aisleVector[i+1].length;
        if(offset<o)
            return -999999;
    }
    if(offset>o)
    {
        int t=rowCount-1;
        for(;offset>o;t++)
            offset-=aisleVector[rowCount].length+rowAttributesVector[rowCount-1].length;
        return t;
    }
    return -3;
}

UserParaType Map::getUserParameter()
{
	UserParaType upt;
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	upt.DZTime=iniFile.value("DropSeedTime").toInt();
	upt.HJ=seedColumnGap;
	upt.Rpm=iniFile.value("Rpm").toInt();
    iniFile.endGroup();
	return upt;
}

int Map::forwardSowStartPosition(int row)
{
	int d=0;
	if(row<0)
        for(int i=row;i++<0;d-=rowAttributesVector[0].length+aisleVector[0].length);
	else
	{
		int rowCount=rowAttributesVector.size();
		for(int i=0;i<row;i++)
            d+=i<rowCount?rowAttributesVector[i].length+aisleVector[i+1].length:rowAttributesVector[rowCount-1].length+aisleVector[rowCount].length;
	}
	return d;
}

int Map::backwardSowStartPosition(int row)
{
    if(row<0)
        return forwardSowStartPosition(row)+rowAttributesVector[0].length;
    int s=rowAttributesVector.size();
    return forwardSowStartPosition(row)+rowAttributesVector[row<s?row:s-1].length;
}

int Map::startPosition(int row,bool tractorDirection)
{
    if(tractorDirection)
    {
        if(abLineName.isEmpty()||abLineDirection)
            return forwardSowStartPosition(row)-forwardSowStartPosition(aRow);
        return backwardSowStartPosition(aRow)-forwardSowStartPosition(row);
    }
    if(abLineName.isEmpty()||!abLineDirection)
        return backwardSowStartPosition(aRow)-backwardSowStartPosition(row);
    return backwardSowStartPosition(row)-forwardSowStartPosition(aRow);
}

int Map::centralOffset(int column)
{
	return (columnOffset(column,true)+columnOffset(column+blockEachTrip()-1,false))/2;
}

void Map::saveNumber()
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

void Map::saveDensity()
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
					qsq.prepare("UPDATE "+MAPBLOCKTABLE+" SET Density=? WHERE MapName=? AND [Row]=? AND [Column]=?");
					qsq.addBindValue(blockVector[i][j].density);
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

void Map::initSheet(QXlsx::Document &d)
{
    int rowCount=blockVector.size();
    for(int i=0;i<rowCount;i++)
        d.write(i+2,1,QString::number(rowCount-i)+"排");
    for(size_t i=0;i<blockVector[0].size();i++)
        d.write(1,i+2,QString::number(i+1)+"列");
}
