#ifndef TASKBLOCK_H
#define TASKBLOCK_H

#include <QStringList>

struct TaskBlock
{
    static QStringList viewType;

    int state=0;//state:0123-未开始,测产中,已完成,失败
    bool measure;//是否测产
    bool updateFlag;//是否更新
};

#endif // TASKBLOCK_H
