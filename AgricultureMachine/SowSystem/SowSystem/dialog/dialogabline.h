#ifndef DIALOGABLINE_H
#define DIALOGABLINE_H

#include <QDialog>

namespace Ui {
class DialogABLine;
}

class DialogABLine : public QDialog
{
    Q_OBJECT

public:
    explicit DialogABLine(QString name,QWidget *parent = nullptr);
    ~DialogABLine();
	void setGroupBox2Visible(bool b);
    void setPosition(int row,int column,bool direction);

private:
    Ui::DialogABLine *ui;
};

#endif // DIALOGABLINE_H
