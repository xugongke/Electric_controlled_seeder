#ifndef RESULTMODEL_H
#define RESULTMODEL_H

#include <QAbstractTableModel>
#include "dataStruct/blockresult.h"

class ResultModel : public QAbstractTableModel
{
	Q_OBJECT

public:
    explicit ResultModel(const std::vector<BlockResult> &dv,QObject *parent = nullptr);
	void updateAll();
	// Header:
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;

	// Basic functionality:
	int rowCount(const QModelIndex &parent = QModelIndex()) const override;
	int columnCount(const QModelIndex &parent = QModelIndex()) const override;

	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
	bool setData(const QModelIndex &index, const QVariant &value, int role) override;
	Qt::ItemFlags flags(const QModelIndex &index) const override;
	bool removeRows(int row, int count, const QModelIndex &parent) override;
	QStringList getHeader();
signals:
	void signalMarkChanged(int row,QString mark);
private:
	QStringList header={
        "排","列","状态","播种1","播种2","播种3","播种4","播种5","播种6","漏肥1","漏肥2","漏肥3","漏肥4","漏肥5","漏肥6","开始时间","结束时间","备注",""
	};
    const std::vector<BlockResult> &dataV;
};

#endif // RESULTMODEL_H
