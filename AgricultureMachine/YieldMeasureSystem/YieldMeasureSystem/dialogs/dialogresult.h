#ifndef DIALOGRESULT_H
#define DIALOGRESULT_H

#include <QDialog>
#include "dataStructs/blockresult.h"

namespace Ui {
class DialogResult;
}

class DialogResult : public QDialog
{
	Q_OBJECT

public:
	explicit DialogResult(QString taskName,QWidget *parent = nullptr);
	~DialogResult();

private:
	Ui::DialogResult *ui;
    std::vector<BlockResult> data;
};

#endif // DIALOGRESULT_H
