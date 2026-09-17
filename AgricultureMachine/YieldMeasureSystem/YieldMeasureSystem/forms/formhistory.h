#ifndef FORMHISTORY_H
#define FORMHISTORY_H

#include <QWidget>
#include "dataStructs/blockresult.h"

namespace Ui {
class FormHistory;
}

class FormHistory : public QWidget
{
	Q_OBJECT

public:
	explicit FormHistory(QWidget *parent = nullptr);
	~FormHistory();

protected:
    void showEvent(QShowEvent *event) override;

private:
	Ui::FormHistory *ui;
    std::vector<BlockResult> recordData;

public slots:
	void slotRefreshComboBoxTaskFilter();

signals:
    void signalResultDeleted(QString taskName);
};

#endif // FORMHISTORY_H
