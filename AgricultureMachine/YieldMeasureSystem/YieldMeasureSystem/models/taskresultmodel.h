#ifndef TASKRESULTMODEL_H
#define TASKRESULTMODEL_H

#include <QAbstractTableModel>
#include "dataStructs/blockresult.h"

extern QStringList header;

class TaskResultModel : public QAbstractTableModel
{
	Q_OBJECT
    const std::vector<BlockResult> &brv;
public:
    explicit TaskResultModel(const std::vector<BlockResult> &data,QObject *parent = nullptr);
	void updateRow(const QModelIndex &index);
	// Header:
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
	Qt::ItemFlags flags(const QModelIndex &index) const override;
	// Basic functionality:
	int rowCount(const QModelIndex &parent = QModelIndex()) const override;
	int columnCount(const QModelIndex &parent = QModelIndex()) const override;
	bool setData(const QModelIndex &index, const QVariant &value, int role = Qt::EditRole) override;
	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

	// Add data:
	bool insertRows(int row, int count, const QModelIndex &parent = QModelIndex()) override;

signals:
	void signalMarkChanged(int index,QString mark);
};

#endif // TASKRESULTMODEL_H
