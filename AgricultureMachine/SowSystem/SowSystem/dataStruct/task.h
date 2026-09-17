#ifndef TASK_H
#define TASK_H

#include <QString>
#include <vector>
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

struct TaskBlock
{
	int state;//0123未播种 播种中 完成 失败
    bool sow;
};

class Task
{
public:
	Task();
	void load(QString qs);
	void save();
	float completionDegree();
	bool exportToXlsx(QString dir);
	void importFromXlsx(QString file,QString name);
	bool isSow(int row,int column,bool b);//b:是否启用地图外播种
	void initPathState();
	int density(int row,int column,bool b);
    bool columnDirection(int column);
    void saveInfo();
	void saveBlock(int row,int column);

	QString name,mapName,mark,createTime;
	QString lastWorkTime;//上次点开始任务按钮时间
	std::vector<std::vector<TaskBlock>> routeBlockVector;
	int pathType;//0-5，上次使用的路径
    bool positive;//是否为正向，排从小到大为正
	int outsetRow,outsetColumn;//起点排列
	int lastBlockRow,lastBlockColumn;//刚完成的一组区域的行列
	QStringList resultHeader={
        "排","列","开始时间","完成时间","状态","1行播种","2行播种","3行播种","4行播种","5行播种","6行播种","1行漏肥","2行漏肥","3行漏肥","4行漏肥","5行漏肥","6行漏肥","备注"
	};
};

#endif // TASK_H
