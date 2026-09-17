#include "currentblocktablemodel.h"

#define SEEDCOUNT1COLUMN 0
#define SEEDCOUNT2COLUMN 1
#define SEEDCOUNT3COLUMN 2
#define SEEDCOUNT4COLUMN 3
#define SEEDCOUNT5COLUMN 4
#define SEEDCOUNT6COLUMN 5

CurrentBlockTableModel::CurrentBlockTableModel(std::vector<Data> &dataV,QObject *parent)
	: QAbstractTableModel(parent),dataV(dataV)
{
}

QVariant CurrentBlockTableModel::headerData(int section, Qt::Orientation orientation, int role) const
{
	if(role==Qt::DisplayRole&&orientation==Qt::Horizontal)
		return header[section];
	return QAbstractTableModel::headerData(section,orientation,role);
}

int CurrentBlockTableModel::rowCount(const QModelIndex &parent) const
{
	if (parent.isValid())
		return 0;
	return dataV.size();
}

int CurrentBlockTableModel::columnCount(const QModelIndex &parent) const
{
	if (parent.isValid())
		return 0;
	return header.size();
}

QVariant CurrentBlockTableModel::data(const QModelIndex &index, int role) const
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
			case SEEDCOUNT1COLUMN:
				return dataV[row].seedCount[0];
			case SEEDCOUNT2COLUMN:
				return dataV[row].seedCount[1];
			case SEEDCOUNT3COLUMN:
				return dataV[row].seedCount[2];
			case SEEDCOUNT4COLUMN:
				return dataV[row].seedCount[3];
            case SEEDCOUNT5COLUMN:
                return dataV[row].seedCount[4];
            case SEEDCOUNT6COLUMN:
                return dataV[row].seedCount[5];
			}
			break;
		}
	case Qt::EditRole:
		return index.data();
	}
	return QVariant();
}

void CurrentBlockTableModel::updateAll()
{
	beginResetModel();
	endResetModel();
}
