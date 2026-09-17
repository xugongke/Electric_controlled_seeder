#include "resultmodel.h"
#include <QDebug>

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

ResultModel::ResultModel(const std::vector<BlockResult> &dv,QObject *parent)
	: QAbstractTableModel(parent),dataV(dv)
{
}

QVariant ResultModel::headerData(int section, Qt::Orientation orientation, int role) const
{
	if(role==Qt::DisplayRole&&orientation==Qt::Horizontal)
		return header[section];
	return QAbstractTableModel::headerData(section,orientation,role);
}

int ResultModel::rowCount(const QModelIndex &parent) const
{
	if (parent.isValid())
		return 0;
	return dataV.size();
}

int ResultModel::columnCount(const QModelIndex &parent) const
{
	if (parent.isValid())
		return 0;
	return header.size();
}

QVariant ResultModel::data(const QModelIndex &index, int role) const
{
	if (!index.isValid())
		return QVariant();
	switch(role)
	{
	case Qt::DisplayRole:
    {
        int row=index.row();
        switch(index.column())
        {
        case BLOCKROWCOLUMN:
            return dataV[row].row;
        case BLOCKCOLUMNCOLUMN:
            return dataV[row].column;
        case STATECOLUMN:
            switch(dataV[row].state)
            {
            case 1:
                return "未完成";
            case 2:
                return "完成";
            case 3:
                return "失败";
            default:;
            }
        case SEED1COLUMN:
            return dataV[row].seedCount[0];
        case SEED2COLUMN:
            return dataV[row].seedCount[1];
        case SEED3COLUMN:
            return dataV[row].seedCount[2];
        case SEED4COLUMN:
            return dataV[row].seedCount[3];
        case SEED5COLUMN:
            return dataV[row].seedCount[4];
        case SEED6COLUMN:
            return dataV[row].seedCount[5];
        case FERTILIZER1COLUMN:
            return dataV[row].fertilizerCount[0];
        case FERTILIZER2COLUMN:
            return dataV[row].fertilizerCount[1];
        case FERTILIZER3COLUMN:
            return dataV[row].fertilizerCount[2];
        case FERTILIZER4COLUMN:
            return dataV[row].fertilizerCount[3];
        case FERTILIZER5COLUMN:
            return dataV[row].fertilizerCount[4];
        case FERTILIZER6COLUMN:
            return dataV[row].fertilizerCount[5];
        case STARTTIMECOLUMN:
            return dataV[row].startTime;
        case ENDTIMECOLUMN:
            return dataV[row].endTime;
        case MARKCOLUMN:
            return dataV[row].mark;
        case DELETEBUTTONCOLUMN:
            return QVariant();
        }
        break;
    }
	case Qt::EditRole:
		return index.data();
	}
	return QVariant();
}

bool ResultModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
	if (data(index, role)== value)
		return false;
	if(role==Qt::EditRole)
		switch(index.column())
		{
		case MARKCOLUMN:
			emit signalMarkChanged(index.row(),value.toString());
			break;
        default:;
		}
	emit dataChanged(index, index, {role});
	return true;
}

Qt::ItemFlags ResultModel::flags(const QModelIndex &index) const
{
	return index.isValid()?index.column()==MARKCOLUMN?QAbstractTableModel::flags(index)|Qt::ItemIsEditable:QAbstractTableModel::flags(index):Qt::NoItemFlags;
}

bool ResultModel::removeRows(int row, int count, const QModelIndex &parent)
{
	beginRemoveRows(parent, row, row + count - 1);
	// FIXME: Implement me!
	endRemoveRows();
	return true;
}

void ResultModel::updateAll()
{
	beginResetModel();
	endResetModel();
}

QStringList ResultModel::getHeader()
{
	return header;
}
