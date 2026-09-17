#ifndef DIALOGINPUTABLINENAME_H
#define DIALOGINPUTABLINENAME_H

#include <QDialog>

namespace Ui {
class DialogInputABLineName;
}

class DialogInputABLineName : public QDialog
{
	Q_OBJECT

public:
	explicit DialogInputABLineName(QWidget *parent = nullptr);
	~DialogInputABLineName();
	QString getName();
private:
	Ui::DialogInputABLineName *ui;
};

#endif // DIALOGINPUTABLINENAME_H
