#ifndef FRAMESINGLEBLOCKINFO_H
#define FRAMESINGLEBLOCKINFO_H
#define SHADOW_WIDTH 5 //窗口阴影宽度

#include <QFrame>
#include "../../common/map.h"

namespace Ui {
class FrameSingleBlockInfo;
}

class FrameSingleBlockInfo : public QFrame
{
	Q_OBJECT

public:
	explicit FrameSingleBlockInfo(QWidget *parent = nullptr);
	~FrameSingleBlockInfo();
	void setBlock(Block *b);
	void setReadOnly(bool b);
	void setCoordinate(int row,int column);
	int row();
	int column();
protected:
	void paintEvent(QPaintEvent *) override;
private slots:
	void slotCheckBoxSowSeedStateChanged(int state);
	void slotLineEditNumberTextChanged(const QString &text);
	void slotSpinBoxDensityValueChanged(int value);
private:
	Ui::FrameSingleBlockInfo *ui;
	Block *b;
signals:
	void signalSowSeedModified();
	void signalDataModified();
};

#endif // FRAMESINGLEBLOCKINFO_H
