#ifndef WIDGETMAPINFO_H
#define WIDGETMAPINFO_H

#include <QWidget>
#include "dataStructs/yieldmap.h"

namespace Ui {
class WidgetMapInfo;
}

class WidgetMapInfo : public QWidget
{
	Q_OBJECT

public:
	explicit WidgetMapInfo(QWidget *parent = nullptr);
	~WidgetMapInfo();
	void setMap(QString m);
	void clear();
private:
	Ui::WidgetMapInfo *ui;
};

#endif // WIDGETMAPINFO_H
