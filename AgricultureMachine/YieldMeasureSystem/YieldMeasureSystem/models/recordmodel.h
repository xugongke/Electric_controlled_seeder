#ifndef RECORDMODEL_H
#define RECORDMODEL_H

#include <QAbstractTableModel>
#include "dataStructs/blockresult.h"

class RecordModel : public QAbstractTableModel
{
	Q_OBJECT

public:
    explicit RecordModel(const std::vector<BlockResult> &data,QObject *parent = nullptr);
	void updateAll();
	// Header:
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;
	// Basic functionality:
	int rowCount(const QModelIndex &parent = QModelIndex()) const override;
	int columnCount(const QModelIndex &parent = QModelIndex()) const override;
	QStringList getHeader();
	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

	// Editable:
	bool setData(const QModelIndex &index, const QVariant &value,
				 int role = Qt::EditRole) override;

	Qt::ItemFlags flags(const QModelIndex& index) const override;

	// Add data:
	bool insertRows(int row, int count, const QModelIndex &parent = QModelIndex()) override;
	// Remove data:
	bool removeRows(int row, int count, const QModelIndex &parent = QModelIndex()) override;
signals:
    void signalMarkChanged(int i,QString mark);
private:
	QStringList header={
        "排","列","水分","质量","容重","作物","开始时间","完成时间","状态","备注",""
	};
    const std::vector<BlockResult> &brv;
};

#endif // RECORDMODEL_H
