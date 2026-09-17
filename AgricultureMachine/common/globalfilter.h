#ifndef GLOBALFILTER_H
#define GLOBALFILTER_H

#include <QObject>

class GlobalFilter : public QObject
{
	Q_OBJECT
public:
	explicit GlobalFilter(QObject *parent = nullptr);
	bool eventFilter(QObject *watched, QEvent *event) override;

private:
	void toggleKeyboardShowState();
	bool keyboardIsShow();

	QObject *lastWatchedObject;
};

#endif // GLOBALFILTER_H
