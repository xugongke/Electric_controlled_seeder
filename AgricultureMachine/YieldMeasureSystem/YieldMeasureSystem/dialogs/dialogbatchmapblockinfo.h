#ifndef DIALOGBATCHMAPBLOCKINFO_H
#define DIALOGBATCHMAPBLOCKINFO_H

#include <QDialog>
#include "dataStructs/yieldblock.h"

namespace Ui {
class DialogBatchMapBlockInfo;
}

class DialogBatchMapBlockInfo : public QDialog
{
	Q_OBJECT

public:
    explicit DialogBatchMapBlockInfo(QWidget *parent = nullptr);
    ~DialogBatchMapBlockInfo();
    YieldBlock value();
private:
    Ui::DialogBatchMapBlockInfo *ui;
};

#endif // DIALOGBATCHMAPBLOCKINFO_H
