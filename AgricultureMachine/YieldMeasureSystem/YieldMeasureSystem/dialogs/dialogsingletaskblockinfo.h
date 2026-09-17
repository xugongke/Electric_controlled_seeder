#ifndef DIALOGSINGLETASKBLOCKINFO_H
#define DIALOGSINGLETASKBLOCKINFO_H

#include <QDialog>
#include "dataStructs/taskblock.h"

namespace Ui {
class DialogSingleTaskBlockInfo;
}

class DialogSingleTaskBlockInfo : public QDialog
{
    Q_OBJECT

public:
    explicit DialogSingleTaskBlockInfo(QWidget *parent = nullptr);
    ~DialogSingleTaskBlockInfo();
    void setBlock(TaskBlock *b);
    void setCoordinate(int row,int column);
    int margin();
    void setReadOnly(bool b);
    bool measure();

protected:
    void changeEvent(QEvent *) override;

private:
    Ui::DialogSingleTaskBlockInfo *ui;

signals:
    void signalDataModified(int row,int column);
};

#endif // DIALOGSINGLETASKBLOCKINFO_H
