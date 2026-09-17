#ifndef FRAMESINGLETASKBLOCKINFO_H
#define FRAMESINGLETASKBLOCKINFO_H
#define SHADOW_WIDTH 5//窗口阴影宽度

#include <QFrame>
#include "dataStructs/taskblock.h"

namespace Ui {
class FrameSingleTaskBlockInfo;
}

class FrameSingleTaskBlockInfo : public QFrame
{
    Q_OBJECT

public:
    explicit FrameSingleTaskBlockInfo(QWidget *parent = nullptr);
    ~FrameSingleTaskBlockInfo();
    void setBlock(TaskBlock *b);
    void setReadOnly(bool b);
    bool measure();
    void setCoordinate(int row,int column);
    int row();
    int column();

protected:
    void paintEvent(QPaintEvent *) override;

private slots:
    void slotCheckBoxMeasureStateChanged(int state);

private:
    Ui::FrameSingleTaskBlockInfo *ui;
    TaskBlock *b;

signals:
    void signalDataModified();
};

#endif // FRAMESINGLETASKBLOCKINFO_H
