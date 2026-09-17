#ifndef TASK_H
#define TASK_H
#define TASKDIRECTORY QString("tasks")

#include <QString>
#include <vector>
#include "taskblock.h"
#include <QStringList>

struct PathNode
{
    int row,column;
    bool positive;//true正向,false反向，排从小到大为正

    bool operator==(PathNode &pn)
	{
        return row==pn.row&&column==pn.column&&positive==pn.positive;
    }
};

class Task
{
public:
	Task();
	void load(QString qs);
	void save();
	float completionDegree();
    bool columnDirection(int column);
    void saveInfo();
    void saveBlock(int row,int column);
    bool exportToXlsx(QString dir);
	void importFromXlsx(QString file,QString name);
    void initPathState();

	QString name,mapName,mark,createTime;
	QString lastWorkTime;//上次点开始任务按钮时间
	std::vector<std::vector<TaskBlock>> routeBlockVector;
	int pathType;//0-5
	int startRow,startColumn;//上次任务结束时保存的下一个区域，作为下次任务开始时的默认起点
	int lastRow,lastColumn;//上个测产结束的区域，每次测产结束后更新
    bool positive;//路径方向，程序以排从大到小为正，用户以排从小到大为正
	QStringList resultHeader={
        "排","列","开始时间","结束时间","湿度（%）","质量（kg）","容重（kg/L）","作物","状态","备注"
	};
};

#endif // TASK_H
