#ifndef YIELDBLOCK_H
#define YIELDBLOCK_H

#include "../../common/map.h"

struct YieldBlock:public Block
{
    QString crop;
    bool updateFlag;
	static QStringList viewType;
};

#endif // YIELDBLOCK_H
