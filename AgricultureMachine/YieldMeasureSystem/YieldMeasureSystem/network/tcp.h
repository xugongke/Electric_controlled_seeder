#ifndef TCP_H
#define TCP_H
#include <stdint.h>

//连接握手协议
struct DataInfo
{
    uint32_t m;         //插槽号
    uint32_t n;         //传感器序号
};

//数据帧帧头结构
struct DataHead
{
    int     len;        // >0 数据长度, 0-传输id, -1-标定模式
    int     adc;        //adc
    union {
        struct
        {
            uint64_t    sensorId;       //id
            uint64_t    cardId;         //id
        };
        struct {
            float   max;        //最大值
            float   min;        //最小值
            float   ave;        //平均值
            int     trigger;    //触发点位置 -1为没触发
        };
    };
};

//管道协议
struct PipeCmd
{
    int fd;     //套接字
    int index;  //索引    -1表示整个线程退出
};

//数据端口协议头结构
struct CmdHead
{
    uint8_t     h;      //消息头
    uint8_t     cmd;    //命令数
    uint16_t    len;    //数据长度 包括数据头
    uint32_t    res;
};
#define CMD_HEAD    0xA8

//---------------------------------------------------------------------------------
//命令端口数据结构
struct CmdID
{
    int         j;      //通道号
    int         flag;   //0-普通传感器 1-电压表
    uint64_t    id;     //传感器id
};
struct CmdInfo
{
    uint64_t    id;     //采集板id
    int         pid;    //大版本号
    int         vid;    //小版本号
    int64_t     utc;    //更新时间
};
struct CmdParam
{
    uint32_t pageSize;      //单个数据包大小
    uint32_t Hz;            //采样频率
    uint16_t triIndex;      //触发方式
    uint16_t tickIndex;     //同步时钟方式
    struct {
        uint32_t    enable  : 1;    //是否使能
        uint32_t    triIndex: 3;    //触发方式 0-不使能触发 1-高于阈值触发 2-低于阈值触发
        uint32_t    vout    : 4;    //供桥电压 0-5V 1-10V
        uint32_t    mul     : 8;    //放大倍数索引
        uint32_t    maxS    : 16;   //最大灵敏度 1000倍
        float       value;          //阈值
    } pass[16];
};
struct CmdSValue
{
    int j;      //通道号
    int val;    //dac值 放大倍数 供桥电压选择 最大灵敏度1000倍
};
struct CmdGMap
{
    int i;      //供桥电压索引 0 - 5V 1 - 10V
    int j;      //通道号
    int k;      //放大倍数索引
    int reg;    //保留
};
struct CmdDacMap
{
    int      i;
    uint16_t dac[16];
    float    V[16];
};
struct CmdCalibMap
{
    struct CmdGMap  index;  //数据索引
    float           T;      //温度
    int             n;      //校准点
    float           val[22];
    int             adc[22];
    int64_t         utc;    //校准时间
};

struct CmdMulMap
{
    uint16_t n;         //支持的放大倍数数量
    uint16_t mul[15];   //最多支持15个放大倍数
};

//-------------------------------------------------------------------------------
//      name            value       send        recv        description

#define CMD_ALIVE       0x00    //  ----        ----        判断连接是否存在
#define CMD_G_INFO      0x01    //  ----        CmdInfo     获得板卡参数
#define CMD_S_ID        0x02    //  CmdID       ----        设置id
#define CMD_S_PARAM     0x04    //  CmdParam    ----        设置通道参数
#define CMD_G_PARAM     0x05    //  ----        CmdParam    读取通道参数
#define CMD_S_GPA       0x06    //  CmdSValue   CmdSValue   单独设置放大倍数    val:放大倍数索引
#define CMD_S_DAC       0x07    //  CmdSValue   CmdSValue   单独设置dac输出   val:dac值
#define CMD_S_DACMAP    0x08    //  CmdDacMap   CmdDacMap   设置供桥输出校准表
#define CMD_G_DACMAP    0x09    //  int         CmdDacMap   读取供桥输出校准表
#define CMD_S_CALIBMAP  0x0A    //  CmdCalibMap CmdCalibMap 设置校准点
#define CMD_G_CALIBMAP  0x0B    //  CmdGMap     CmdCalibMap 读取校准点
#define CMD_S_TEMP      0x0C    //  float       ----        设置温度值
#define CMD_S_VOUT      0x0D    //  CmdSValue   CmdSValue   单独设置供桥电压    val:0-5V 1-10V
#define CMD_S_MAXS      0x0E    //  CmdSValue   CmdSValue   单独设置最大灵敏度   val:最大灵敏度的1000倍
#define CMD_G_PGA       0x0F    //  CmdSValue   CmdSValue   读取放大倍数
#define CMD_G_MULMAP    0x10    //  ----        CmdMulMap   读取放大倍数表


#define CMD_STOP        0x80    //  ----        ----        结束
#define CMD_START       0x81    //  ----        ----        常规模式(需要提前设参数)
#define CMD_CALIB       0x82    //  int         ----        标定模式
#define CMD_AUTO        0x83    //  int         ----        自动校准模式
#define CMD_HAND        0x84    //  int         ----        手动校准模式

#define CMD_C_ID        0x86    //  ----        ----        强制采集板上报id
#define CMD_C_DATA      0x87    //  ----        ----        数据连接复位
#define CMD_C_RESET     0x88    //  ----        ----        全复位

#define CMD_EX_R_REG    0xA0    //  ----        int         读寄存器
#define CMD_EX_W_REG    0xA1    //  int         int         写寄存器
#define CMD_EX_R_RH     0xA2    //  int         float       读取水分 模式 - 值

#define CMD_ERROR       0xff    //  ----        int         错误


union CmdBody
{
    struct CmdID        ID;
    struct CmdInfo      info;
    struct CmdParam     param;
    struct CmdSValue    sValue;
    struct CmdGMap      gMap;
    struct CmdDacMap    dacMap;
    struct CmdCalibMap  calibMap;
    struct CmdMulMap    mul;
    int                 i;
    float               f;
};

struct TcpFormat
{
    struct  CmdHead h;
    union   CmdBody b;
};



#endif
