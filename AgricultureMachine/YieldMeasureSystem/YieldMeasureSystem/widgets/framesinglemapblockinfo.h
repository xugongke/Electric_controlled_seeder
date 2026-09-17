#ifndef FRAMESINGLEMAPBLOCKINFO_H
#define FRAMESINGLEMAPBLOCKINFO_H
#define SHADOW_WIDTH 5//窗口阴影宽度

#include <QFrame>
#include "dataStructs/Yieldblock.h"

namespace Ui {
class FrameSingleMapBlockInfo;
}

class FrameSingleMapBlockInfo : public QFrame
{
	Q_OBJECT

public:
    explicit FrameSingleMapBlockInfo(QWidget *parent = nullptr);
    ~FrameSingleMapBlockInfo();
    void setBlock(YieldBlock *b);
	void setReadOnly(bool b);
	QString crop();
	void setCoordinate(int row,int column);
	int row();
	int column();
protected:
	void paintEvent(QPaintEvent *) override;
private slots:
	void slotComboBoxCropCurrentTextChanged(const QString &text);
	void slotLineEditNumberTextChanged(const QString &text);
private:
    Ui::FrameSingleMapBlockInfo *ui;
    YieldBlock *b;
signals:
	void signalDataModified();
};

#endif // FRAMESINGLEMAPBLOCKINFO_H
