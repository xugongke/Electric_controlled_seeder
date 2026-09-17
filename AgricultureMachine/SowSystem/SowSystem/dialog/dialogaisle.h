#ifndef DIALOGAISLE_H
#define DIALOGAISLE_H

#include <QDialog>
#include "../../common/map.h"

namespace Ui {
class DialogAisle;
}

class DialogAisle : public QDialog
{
	Q_OBJECT

public:
	explicit DialogAisle(std::vector<Aisle> av,QWidget *parent = nullptr);
	~DialogAisle();
	std::vector<Aisle> value();

private:
	Ui::DialogAisle *ui;
	std::vector<Aisle> av;
};

#endif // DIALOGAISLE_H
