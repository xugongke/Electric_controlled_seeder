#ifndef GLOBAL_H
#define GLOBAL_H
#define CONFIGFILE "config.ini"
#define APPLICATIONGROUP "Application"
#define SEEDGAPFINETUNINGARRAY "SeedGapFineTuning"
#define DEVICEGROUP "Device"
#define TESTWARNINGGROUP "TestWarning"
#define CONTINUOUSSOWMODEGROUP "ContinuousSowMode"
#define MAPTABLE QString("Map")
#define MAPBLOCKTABLE QString("MapBlock")
#define ROWATTRIBUTESTABLE QString("RowAttributes")
#define MAPAISLETABLE QString("MapAisle")
#define TASKTABLE QString("Task")
#define TASKBLOCKTABLE QString("TaskBlock")
#define RESULTTABLE QString("Result")
#define ABLINETABLE QString("ABLine")

#include <QAbstractItemView>
#include "../../common/protocol.h"

struct Coordinate
{
	int row,column;
};

extern QMap<QString,QStringList> BlockColumnCountMap;
extern QList<int> SeedGapFineTuningDensityList;
extern int MaxMotorCount;

void setTouchable(QAbstractItemView *qaiv);
QString listString(QStringList qsl);
bool bit(long long number,int index);
UserParaType getUserParameterFromSetting();
TerParaType getManufacturerParameterFromSetting();
void writeLog(QString log);
bool densityIsSpecified(int value);
int specifiedDensity(int value);
QPixmap getTransparentPixmap(QString path);

#endif // GLOBAL_H
