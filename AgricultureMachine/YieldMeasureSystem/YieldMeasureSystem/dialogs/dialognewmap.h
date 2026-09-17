#ifndef DIALOGNEWMAP_H
#define DIALOGNEWMAP_H

#include <QDialog>

namespace Ui {
class DialogNewMap;
}

class DialogNewMap : public QDialog
{
	Q_OBJECT

public:
	explicit DialogNewMap(QWidget *parent = nullptr);
	~DialogNewMap();
	QString newMapName();
private:
	Ui::DialogNewMap *ui;
	QString map;
};

#endif // DIALOGNEWMAP_H
