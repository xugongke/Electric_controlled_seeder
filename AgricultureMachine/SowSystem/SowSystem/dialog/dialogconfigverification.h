#ifndef DIALOGCONFIGVERIFICATION_H
#define DIALOGCONFIGVERIFICATION_H

#include <QDialog>

namespace Ui {
class DialogConfigVerification;
}

class DialogConfigVerification : public QDialog
{
	Q_OBJECT

public:
	explicit DialogConfigVerification(QWidget *parent = nullptr);
	~DialogConfigVerification();
	QString password();

private:
	Ui::DialogConfigVerification *ui;
};

#endif // DIALOGCONFIGVERIFICATION_H
