#ifndef MAPTABLE_H
#define MAPTABLE_H

#include <QTableView>
#include "dialogs/dialogsinglemapblockinfo.h"

class MapTable:public QTableView
{
	Q_OBJECT
public:
	MapTable(QWidget *parent=nullptr);
	void setItemCrop(int row,int column,QString crop);
	void setItemBackground(int row,int column,int type,int direction,int state);
	void setItemIgnoreBackground(int row,int column,int direction,int incomeDirection);
	void clear(int row,int column);
	void showBlockDialog(int row,int column);
    void setBlock(YieldBlock *b);
	void setDialogReadOnly(bool b);
signals:
    void signalDataModified(int row,int column);

private:
	QString statePicture(QString picture,int state);

    DialogSingleMapBlockInfo *dsbi;
};

#endif // MAPTABLE_H
