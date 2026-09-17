#ifndef FORMMAP_H
#define FORMMAP_H

#include <QWidget>
#include "dataStructs/yieldmap.h"
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
	void loadCurrentMap(QString map);
	void setBlockCheckedState(int row,int column,bool b);
	void refreshList();
    QStringList checkedMapList();

	Ui::FormMap *ui;
    YieldMap currentMap;
    std::vector<std::deque<bool>> checkedDv;

private slots:
	void slotVerticalSectionClicked(int logicalIndex);
	void slotHorizontalSectionClicked(int logicalIndex);
	void slotCheckBoxCheckAllBlockStateChanged(int state);
    void slotComboBoxViewCurrentTextChanged(const QString &);
};

#endif // FORMMAP_H
