#ifndef DIALOGBATCHBLOCKINFO_H
#define DIALOGBATCHBLOCKINFO_H

#include <QDialog>
#include "../../common/map.h"

namespace Ui {
class DialogBatchBlockInfo;
}

class DialogBatchBlockInfo : public QDialog
{
	Q_OBJECT

public:
	explicit DialogBatchBlockInfo(QWidget *parent = nullptr);
	~DialogBatchBlockInfo();
	Block value();
private:
	Ui::DialogBatchBlockInfo *ui;
};

#endif // DIALOGBATCHBLOCKINFO_H
