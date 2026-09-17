#include "recordmodel.h"

#define BLOCKROWCOLUMN 0
#define BLOCKCOLUMNCOLUMN 1
#define MOISTURECOLUMN 2
#define MASSCOLUMN 3
#define UNITWEIGHTCOLUMN 4
#define CROPCOLUMN 5
#define STARTTIMECOLUMN 6
#define ENDTIMECOLUMN 7
#define STATECOLUMN 8
#define MARKCOLUMN 9
#define DELETEBUTTONCOLUMN 10

RecordModel::RecordModel(const std::vector<BlockResult> &data,QObject *parent)
    : QAbstractTableModel(parent),brv(data)
{
}

QVariant RecordModel::headerData(int section, Qt::Orientation orientation, int role) const
{
	if(role==Qt::DisplayRole&&orientation==Qt::Horizontal)
		return header[section];
	return QAbstractTableModel::headerData(section,orientation,role);
}

int RecordModel::rowCount(const QModelIndex &parent) const
{
	if (parent.isValid())
		return 0;
	return brv.size();
}

int RecordModel::columnCount(const QModelIndex &parent) const
{
	if (parent.isValid())
		return 0;
	return header.size();
}

QVariant RecordModel::data(const QModelIndex &index, int role) const
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
            return brv[row].row;
        case BLOCKCOLUMNCOLUMN:
            return brv[row].column;
        case MOISTURECOLUMN:
            return QString::number(brv[row].moisture)+'%';
        case MASSCOLUMN:
            return QString::number(brv[row].mass)+"kg";
        case UNITWEIGHTCOLUMN:
            return QString::number(brv[row].unitWeight)+"kg/L";
        case CROPCOLUMN:
            return brv[row].crop;
        case STARTTIMECOLUMN:
            return brv[row].startTime;
        case ENDTIMECOLUMN:
            return brv[row].endTime;
        case STATECOLUMN:
            switch(brv[row].state)
            {
            case 1:
                return "未完成";
            case 2:
                return "完成";
            case 3:
                return "失败";
            default:;
            }
        case MARKCOLUMN:
            return brv[row].mark;
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

bool RecordModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
	if (data(index, role)== value)
		return false;
	if(role==Qt::EditRole)
		switch(index.column())
		{
		case MARKCOLUMN:
            emit signalMarkChanged(index.row(),value.toString());
        default:;
		}
	emit dataChanged(index, index, {role});
	return true;
}

Qt::ItemFlags RecordModel::flags(const QModelIndex &index) const
{
	return index.isValid()?index.column()==MARKCOLUMN?QAbstractTableModel::flags(index)|Qt::ItemIsEditable:QAbstractTableModel::flags(index):Qt::NoItemFlags;
}

bool RecordModel::insertRows(int row, int count, const QModelIndex &parent)
{
	beginInsertRows(parent, row, row + count - 1);
	endInsertRows();
	return true;
}

bool RecordModel::removeRows(int row, int count, const QModelIndex &parent)
{
	beginRemoveRows(parent, row, row + count - 1);
	// FIXME: Implement me!
	endRemoveRows();
	return true;
}

void RecordModel::updateAll()
{
	beginResetModel();
	endResetModel();
}

QStringList RecordModel::getHeader()
{
	return header;
}
