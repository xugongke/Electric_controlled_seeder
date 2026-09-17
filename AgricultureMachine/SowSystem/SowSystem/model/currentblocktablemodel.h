#ifndef CURRENTBLOCKTABLEMODEL_H
#define CURRENTBLOCKTABLEMODEL_H

#include <QAbstractTableModel>

class CurrentBlockTableModel : public QAbstractTableModel
{
	Q_OBJECT

public:
	struct Data
	{
		std::vector<int> seedCount;
	};

	explicit CurrentBlockTableModel(std::vector<Data> &dataV,QObject *parent = nullptr);
	void updateAll();
	// Header:
	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override;

	// Basic functionality:
	int rowCount(const QModelIndex &parent = QModelIndex()) const override;
	int columnCount(const QModelIndex &parent = QModelIndex()) const override;

	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

private:
	QStringList header={
        "1","2","3","4","5","6"
	};
	const std::vector<Data> &dataV;
};

#endif // CURRENTBLOCKTABLEMODEL_H
