#ifndef FORMMAP_H
#define FORMMAP_H

#include <QWidget>
#include "../../common/map.h"
#include "dialog/dialogsingleblockinfo.h"
#include <deque>

namespace Ui {
class FormMap;
}

class FormMap : public QWidget
{
	Q_OBJECT

public:
	explicit FormMap(QWidget *parent = nullptr);
	~FormMap();

private:
	void loadCurrentMap(QString mapName);
	void setBlockCheckedState(int row,int column,bool b);
	void refreshList();

	Ui::FormMap *ui;
	Map currentMap;
    DialogSingleBlockInfo *dsbi;
	std::vector<std::deque<bool>> checkedDv;
	QStringList checkedMapList();
private slots:
	void slotVerticalSectionClicked(int logicalIndex);
	void slotHorizontalSectionClicked(int logicalIndex);
	void slotCheckBoxCheckAllBlockStateChanged(int state);
	void slotComboBoxViewCurrentTextChanged(const QString &);
public slots:
	void slotABLineStateUpdated(QString mapName);
signals:
	void signalMapListUpdated();
};
#endif // FORMMAP_H
