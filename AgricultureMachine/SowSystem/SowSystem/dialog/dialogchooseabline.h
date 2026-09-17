#ifndef DIALOGCHOOSEABLINE_H
#define DIALOGCHOOSEABLINE_H

#include <QDialog>

namespace Ui {
class DialogChooseABLine;
}

class DialogChooseABLine : public QDialog
{
    Q_OBJECT

public:
    explicit DialogChooseABLine(QString mapName,QWidget *parent = nullptr);
    ~DialogChooseABLine();
    QString getABLineName();
    bool getDirection();
    int getColumn();

private:
    Ui::DialogChooseABLine *ui;
    QString abLineName;
    bool direction;
    int column;
};

#endif // DIALOGCHOOSEABLINE_H
