#ifndef FORMHISTORY_H
#define FORMHISTORY_H

#include <QWidget>
#include "dataStruct/blockresult.h"

namespace Ui {
class FormHistory;
}

class FormHistory : public QWidget
{
	Q_OBJECT

public:
	explicit FormHistory(QWidget *parent = nullptr);
	~FormHistory();

private:
	Ui::FormHistory *ui;
    std::vector<BlockResult> data;
public slots:
	void slotRefreshComboBoxTaskFilter();
};

#endif // FORMHISTORY_H
