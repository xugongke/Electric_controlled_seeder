#ifndef GLOBAL_H
#define GLOBAL_H
#define CONFIGFILE "config.ini"
#define APPLICATIONGROUP "application"
#define DEVICEGROUP "device"
#define QIHE 1//湿度递减标定
//#define JIYUAN 1//济源、公主岭机器
#define RESULTTABLE QString("Result")
#define MASSCALIBRATIONTABLE QString("MassCalibration")
#define MASSCALIBRATIONPOINTTABLE QString("MassCalibrationPoint")
#define MOISTURECALIBRATIONPOINTTABLE QString("MoistureCalibrationPoint")
#define MAPTABLE QString("Map")
#define MAPBLOCKTABLE QString("MapBlock")
#define TASKTABLE QString("Task")
#define TASKBLOCKTABLE QString("TaskBlock")
#define TASKPATHTABLE QString("TaskPath")
#define MAXCALIBRATIONCOUNT 30

#include <stdint.h>
#include <map>
#include <QAbstractItemView>
#include "tools/realtimedata.h"
#include <QDateTime>

//全局变量
class MainWidget;
//class ThreadAccept;
//class ThreadPC;
//class ThreadData;
class ThreadUart;

//操作缓存
struct  GlobalCache
{
    uint16_t    widget_index;   //当前界面索引
    uint16_t    flag_sensor_time: 1;    //传感器界面,是否启用时间查询
    uint16_t    flag_his_time   : 1;    //历史界面,是否启用时间查询
    uint16_t    flag_sys_pc     : 1;    //是否启动网络服务

    /*检测界面*/
    uint16_t    work_tick;      //同步时钟选择
    uint16_t    work_stack;     //视图模式

    /*传感器查询*/
    int64_t     sensor_start;
    int64_t     sensor_end;
    char        sensor_NO[24];
    uint32_t    sensor_reg;
    uint16_t    sensor_type;
    uint16_t    sensor_mode;

    /*历史查询*/
    int64_t  his_start;
    int64_t  his_end;

    /*系统设置*/
    char     sys_name[32];
};

int Cache_load();
int Cache_save();

//标定
struct CalibData
{
	CalibData():n(0),flag(0),zero(0)
	{
	}
	int     n;          //标定点数
	int     flag;       //bit0: 是否启用反向标定 bit1:灵敏度取反
	double   zero;       //清零点
    double   adc[2*MAXCALIBRATIONCOUNT];    //灵敏度
    double   val[2*MAXCALIBRATIONCOUNT];    //物理量
};

struct CalibMap
{
	CalibData   d;
    double  k[2*MAXCALIBRATIONCOUNT];  //斜率
    double  b[2*MAXCALIBRATIONCOUNT];  //截距
};

struct GlobalData
{
    MainWidget      *widget;    //主界面
//    ThreadAccept    *tAccept;   //套接字接收线程
//    ThreadPC        *tPC;       //上位机命令线程
//    ThreadData      *tData;     //采集板数据接收线程
    ThreadUart *tUart;
    int             m;          //最大采集板数量
    int             n;          //每个采集板最大通道    
	std::map<QString,CalibMap> massCmMap,moistureCmMap;
    uint32_t flag_pro_reload    : 1;    //项目界面是否重新加载
    uint32_t flag_sensor_reload : 1;    //传感器界面是否重新加载
    RealtimeData *rd;
    GlobalCache     cache;
    int valveState=-1;//阀门状态
	QString logFile=QDateTime::currentDateTime().toString("yyyy-MM-dd hh：mm：ss")+".txt";
};
extern GlobalData G;

extern const char *g_trigger_list[];
extern const char *g_threshold_list[];
extern const char *g_type_list[];
extern const int   g_Hz_list[];
extern const int   g_Vout_list[];
extern const char *units[][5];
extern QStringList channleList;
extern QStringList cropList;
extern std::map<QString,QStringList> moistureSensorModeMap;
//项目
struct ProjectHead
{
    uint32_t    h;      //文件头
    uint32_t    Hz;     //采样频率
    uint32_t    t;      //采集时间
    uint32_t    pt;     //预采集时间
    uint32_t    tri;    //触发方式
    uint32_t    n;      //传感器个数
    uint32_t    flag;   //bit[0]是否自动停止
    uint32_t    res;
};
struct ProjectBody
{
    uint64_t    id;         //传感器id
    double      trigger;    //触发阈值阈值
    uint32_t    triIndex;   //触发模式
    int         type;       //0-常规传感器 1-电压表 2-毫伏表
    char        text[40];   //备注
};
struct ProjectSave
{
    int64_t     utc;        //历史记录生成时间
    char        detName[36];//测试名称
    uint16_t    index[4];   //当天的历史记录数量
    char        pc[26];     //检测时上位机编号
    uint16_t    pcPort;     //联机时上位机分配的编号, 0-本地历史记录
    char        text[260];  //备注
    uint32_t    tick;       //同步时钟选择
};

struct CalibParam
{
    uint64_t    id;         //传感器id
    int64_t     utc;        //标定时间
    char        NO[24];     //传感器编号
    int         type;       //类型索引
    int         iV;         //供桥电压

    int         flag;
    int         maxS;       //最大灵敏度的1000倍
    char        unit[8];    //单位
    char        model[24];  //型号
    double      range;      //量程
    uint64_t    cid;        //标定时采集板id
    int         i;          //标定时采集板插槽
    int         j;          //标定时通道
    int         pid;        //传感器组ID
    int         pindex;     //解偶序号
    char        res[24];
};

//解耦合
struct DecouplingParam
{
    int     id;         //传感器组ID
    int     type;       //解偶方式
    int     count;      //传感器数量
    int     mapSize;    //解偶矩阵长度
    char    name[24];   //传感器组名称
    char    res[24];
};

int Calib_check_moisture(CalibData *calib);
int  Calib_check(CalibData *calib);
void Calib_init(CalibMap *map);   //根据 CalibData 计算 k,b
double Calib_trans(const CalibMap *map, float adc);     //灵敏度->物理量
double Calib_inv(const CalibMap *map, double val);      //物理量->灵敏度
void setValve(int valveFlag);
double *Decoupling_3f(double *out, const double *in, const double *matrix);
void initMassCalibMap();
void initMoistureCalibMap();
QString listString(QStringList qsl);
QPixmap getTransparentPixmap(QString path);
float setPrecision(float f,int precision);
void updateResultFailureState();
std::vector<int> getColumnNode(int column);
void writeLog(QString log);
QString transMoisture(const CalibMap *map,float adc,int precision);
QString transMoisture(float value,int precision);

//原始文件文件头
struct FileHead
{
    uint32_t    h;          //文件头
    uint32_t    hLen;       //文件头长度
    uint64_t    cardId;     //采集板id
    uint64_t    sensorId;   //传感器id
    int64_t     utf;        //采集时间
    int         i;          //采集板索引
    int         j;          //通道索引

    int         lenth;      //数据长度
    int         index;      //实际触发点索引
    int         Hz;         //采样频率
    int         preLen;     //理论预采集点数
    double      zero;       //清零点
    ProjectBody body;       //曲线设置参数
    CalibParam  param;      //标定参数
    CalibData   calib;      //标定点
    int         crc;        //文件校验
};

struct DataSocketSet
{
    int packSize;   //每帧数据数据包大小
    int Hz;         //采样频率
    int preLen;     //预采集点数
    int showLen;    //画布显示总点数
};

//清空文件夹
int c_clear_dir(const char *path);

//检查路径
int c_check_dir();
void setTouchable(QAbstractItemView *qaca);
//#define MAX_DATA_BUF

#define PROJECT_PATH    "./project/"
//#define HISTORY_PATH    "./history/"
#define HISTORY_PATH    "/media/hd/dataSsd/"
#define TEMP_PATH       "./temp/"

#define FILE_HEAD       0x8080
#define PROJECT_HEAD    0xA0A0

#endif // GLOBAL_H
