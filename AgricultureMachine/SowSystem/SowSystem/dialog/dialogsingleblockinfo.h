#ifndef DIALOGSINGLEBLOCKINFO_H
#define DIALOGSINGLEBLOCKINFO_H

#include <QDialog>
#include "../../common/map.h"

namespace Ui {
class DialogSingleBlockInfo;
}

class DialogSingleBlockInfo : public QDialog
{
	Q_OBJECT

public:
	explicit DialogSingleBlockInfo(QWidget *parent = nullptr);
	~DialogSingleBlockInfo();
	void setBlock(Block *b);
	void setCoordinate(int row,int column);
	int margin();
	void setReadOnly(bool b);
	QString crop();
protected:
	void changeEvent(QEvent *) override;
private:
	Ui::DialogSingleBlockInfo *ui;
signals:
	void signalSowSeedModified(int row,int column);
	void signalDataModified(int row,int column);
};

#endif // DIALOGSINGLEBLOCKINFO_H
