#ifndef DIALOGBATCHTASKBLOCKINFO_H
#define DIALOGBATCHTASKBLOCKINFO_H

#include <QDialog>
#include "dataStructs/taskblock.h"

namespace Ui {
class DialogBatchTaskBlockInfo;
}

class DialogBatchTaskBlockInfo : public QDialog
{
    Q_OBJECT

public:
    explicit DialogBatchTaskBlockInfo(QWidget *parent = nullptr);
    ~DialogBatchTaskBlockInfo();
    TaskBlock value();

private:
    Ui::DialogBatchTaskBlockInfo *ui;
};

#endif // DIALOGBATCHTASKBLOCKINFO_H
