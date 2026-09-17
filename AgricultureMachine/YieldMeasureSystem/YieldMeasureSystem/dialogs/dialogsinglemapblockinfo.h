#ifndef DIALOGSINGLEMAPBLOCKINFO_H
#define DIALOGSINGLEMAPBLOCKINFO_H

#include <QDialog>
#include "dataStructs/yieldblock.h"

namespace Ui {
class DialogSingleMapBlockInfo;
}

class DialogSingleMapBlockInfo : public QDialog
{
	Q_OBJECT

public:
    explicit DialogSingleMapBlockInfo(QWidget *parent = nullptr);
    ~DialogSingleMapBlockInfo();
    void setBlock(YieldBlock *b);
	void setCoordinate(int row,int column);
	int margin();
	void setReadOnly(bool b);
	QString crop();
protected:
	void changeEvent(QEvent *) override;
private:
    Ui::DialogSingleMapBlockInfo *ui;
signals:
	void signalDataModified(int row,int column);
};

#endif // DIALOGSINGLEMAPBLOCKINFO_H
