#ifndef DIALOGTASKRESULT_H
#define DIALOGTASKRESULT_H

#include <QDialog>
#include "dataStruct/blockresult.h"

namespace Ui {
class DialogTaskResult;
}

class DialogTaskResult : public QDialog
{
	Q_OBJECT

public:
	explicit DialogTaskResult(QString task,QWidget *parent = nullptr);
	~DialogTaskResult();

private:
	Ui::DialogTaskResult *ui;
    std::vector<BlockResult> data;
};

#endif // DIALOGTASKRESULT_H
