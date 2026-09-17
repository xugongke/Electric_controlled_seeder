#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QPropertyAnimation>
#include <QGraphicsOpacityEffect>
//#include <QTimer>

QT_BEGIN_NAMESPACE
namespace Ui { class MainWindow; }
QT_END_NAMESPACE

class MainWindow : public QMainWindow
{
	Q_OBJECT

public:
	MainWindow(QWidget *parent = nullptr);
	~MainWindow();

protected:
    void resizeEvent(QResizeEvent *event) override;
    void showEvent(QShowEvent *event) override;

private:
    void fadeInWidget(QWidget *widget, int duration = 280);

	Ui::MainWindow *ui;
    //QTimer qt;
signals:
    void signalValveStateChanged();
};
#endif // MAINWINDOW_H
