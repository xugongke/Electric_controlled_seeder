#ifndef DIALOGROWATTRIBUTE_H
#define DIALOGROWATTRIBUTE_H

#include <QDialog>
#include "../../common/map.h"

namespace Ui {
class DialogRowAttribute;
}

class DialogRowAttribute : public QDialog
{
	Q_OBJECT

public:
	explicit DialogRowAttribute(std::vector<RowAttributes> rav,QWidget *parent = nullptr);
	~DialogRowAttribute();
	std::vector<RowAttributes> value();

private:
	Ui::DialogRowAttribute *ui;
	std::vector<RowAttributes> rav;
};

#endif // DIALOGROWATTRIBUTE_H
