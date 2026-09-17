/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          para.h
*\Description   
*\Note          1)参数(网络 试验)信息及设备ID信息存储在EEPROM中
                2)离线数据存储在NAND区域
                3)各个通道校准数据存放在NAND区域
*\Log           2020.08.12    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _PARA_H
#define _PARA_H
#include "main.h"
#include "cmsis_os.h"
#include "type.h"

#define STEP_GEAR_RATIO   (GlobalPara.GearRatio)   /*5 步进电机与播种盘的减速比X:1*/
#define BZP_HOLE_NUM       (GlobalPara.HoleNum)   /*9 播种盘孔数*/

extern u8 AppVersions[]; /*软件版本号*/
extern u8 AppErrVersion[]; /*软件版本号*/
/*配置参数变量 开始*/
#define SEEDER_MODE_IDLE 0 /*无效播种机模式*/

#define SEEDER_MODE_BDA  3  /*北斗模式*/
#define SEEDER_MODE_LXBZ 5  /*连续播种模式*/
/*配置参数变量 结束*/

/*预留控制输出*/
extern GPIO_TypeDef* YLCtrlPort[3];
extern u16 YLCtrlPin[3];
extern GPIO_TypeDef* ZeroInputPort[4];
extern u16 ZeroInputPin[4];
extern u32 YLZStartTime; //预落种动作开始时间
extern u32 DzStartTime; //倒种阀门动作时间
extern u32 LXBZCnt; //连续播种电机测速计数
extern s16 Voltage; //电源电压 单位0.1v

/*内部输入输出状态变量  开始*/
extern vu32 LouzhongCnt[4]; /*漏种计数 中断*/
extern vu32 LoufeiCnt[4];   /*漏肥计数 中断*/
extern u32 BdTrigTime;  /*北斗触发时间*/

extern vu32 BeidouStartTrigCnt; /*北斗起始触发开关*/
extern u32 LastBeidouStartTrig; /*北斗起始触发开关 播种起始值*/
extern vu32 GsStartTrig1Cnt; /*钢索触发开关1*/
extern vu32 GsStartTrig2Cnt; /*钢索触发开关2*/

extern s32 LastPulseNum;   /*上次编码器计数*/

extern u32 LastLouzhongCnt[4]; /*漏种计数 中断  播种起始值*/
extern u32 LastLoufeiCnt[4];   /*漏肥计数 中断 播种起始值*/
extern u32 LastBeidouStartTrig; /*北斗起始触发开关 播种起始值*/

extern u32 LastGsStartTrig1Cnt; /*钢索触发开关1计数值 播种起始值*/
extern u32 LastGsStartTrig2Cnt; /*钢索触发开关2计数值 播种起始值*/
extern u32  GsTriggerTime[2];   /*钢索开关触发时间 ms*/

extern u8 QLPressInputState; //气路压力输入
extern u8 FJPressInputState;  //风机压力输入
 
extern u8 TBInputState;      /*踏板输入 0:未踏下 1:踏下*/

extern u8 InitKey;          /*一键初始化 0:未按下  1:按下*/
extern u8 LastInitKey;      /*一键初始化,用于判断开关状态变化*/
extern u8 InitKeyFilter;    /*一键初始化滤波计数*/
extern u8 InitKeyValid;     /*记录一次有效的一键初始化*/

extern u8 BzpInState;   /*播种盘输入状态 按位表示 bit0~3    1表示触发零位*/

extern u32 DisLEDCnt[12]; /*显示板12个LED灯对应的计数状态值*/
void GetInputState(void); /*获取所有非中断触发输入状态*/
#define GS1_IN_STATE()  ((HAL_GPIO_ReadPin(IN16_GPIO_Port, IN16_Pin)==GPIO_PIN_RESET)?1:0)
#define GS2_IN_STATE()  ((HAL_GPIO_ReadPin(IN17_GPIO_Port, IN17_Pin)==GPIO_PIN_RESET)?1:0)
/*气路及风机压力监测输入*/
#define FJYL_INPUT_STATE() ((HAL_GPIO_ReadPin(IN14_GPIO_Port, IN14_Pin)==GPIO_PIN_RESET)?1:0)
#define QLYL_INPUT_STATE() ((HAL_GPIO_ReadPin(IN3_GPIO_Port, IN3_Pin)==GPIO_PIN_RESET)?1:0)

#define AUTOSEED_IN_STATE() ((HAL_GPIO_ReadPin(IN5_GPIO_Port, IN5_Pin)==GPIO_PIN_RESET)?1:0)            /*自动供种开关*/
#define ZERO_IN_STATE(i)    ((HAL_GPIO_ReadPin(ZeroInputPort[i%4], ZeroInputPin[i%4])==GPIO_PIN_RESET)?1:0)  /*零位开关*/

#define YL_INPUT() ((HAL_GPIO_ReadPin(IN7_GPIO_Port, IN7_Pin)==GPIO_PIN_RESET)?1:0)         /*预留输入1*/

#define INIT_KEY()  ((HAL_GPIO_ReadPin(IN15_GPIO_Port, IN15_Pin)==GPIO_PIN_RESET)?1:0)      /*一键初始化按钮*/

/*预留3路输出控制*/
#define YL_CTRL_ON(i)   CtrlValveState[(i)+3]=1;HAL_GPIO_WritePin(YLCtrlPort[(i)%3], YLCtrlPin[(i)%3], GPIO_PIN_SET)
#define YL_CTRL_OFF(i)  CtrlValveState[(i)+3]=0;HAL_GPIO_WritePin(YLCtrlPort[(i)%3], YLCtrlPin[(i)%3], GPIO_PIN_RESET)


/*获取当前编码器计数及清除编码器计数接口*/
extern TIM_HandleTypeDef htim2;
#define GetEncoderNum() ((GlobalPara.EncoderDir == 0)?(__HAL_TIM_GET_COUNTER(&htim2) - LastPulseNum):(LastPulseNum-__HAL_TIM_GET_COUNTER(&htim2)))    /*编码器脉冲计数*/
/*专门用于计算速度,防止清零后影响速度计算*/
#define GetEncoderNumNoclear() ((GlobalPara.EncoderDir == 0)?(__HAL_TIM_GET_COUNTER(&htim2) - 0):(0-__HAL_TIM_GET_COUNTER(&htim2)))    /*编码器脉冲计数*/
#define ClearEncoderNum() (LastPulseNum = __HAL_TIM_GET_COUNTER(&htim2))

#define GetLoufeicnt(i)     (LoufeiCnt[i]-LastLoufeiCnt[i])     /*漏肥计数*/
#define GetLouZhongcnt(i)   (LouzhongCnt[i]-LastLouzhongCnt[i]) /*漏种计数*/
#define ClearLoufeiCnt(i)   (LastLoufeiCnt[i] = LoufeiCnt[i]) 
#define ClearLouzhongCnt(i) (LastLouzhongCnt[i] = LouzhongCnt[i])

#define ClearBdStartTrigerCnt() (LastBeidouStartTrig=BeidouStartTrigCnt)    /*北斗触发行程开关*/
#define GetBdStartTrigerCnt()   (BeidouStartTrigCnt-LastBeidouStartTrig)

#define ClearGS1StartTrigCnt()  {LastGsStartTrig1Cnt = GsStartTrig1Cnt; GsTriggerTime[0] = osTimeGet();}     /*钢索1*/
#define ClearGS2StartTrigCnt()  {LastGsStartTrig2Cnt = GsStartTrig2Cnt; GsTriggerTime[1] = osTimeGet();}     /*钢索2*/
#define GetGS1StartTrigCnt()    (GsStartTrig1Cnt-LastGsStartTrig1Cnt)
#define GetGS2StartTrigCnt()    (GsStartTrig2Cnt-LastGsStartTrig2Cnt)

extern u8 CtrlValveState[12];//阀门控制状态
/*运行指示灯*/
#define RUN_LED1_ON()   CtrlValveState[9]=1;HAL_GPIO_WritePin(OUT2_GPIO_Port, OUT2_Pin, GPIO_PIN_SET)
#define RUN_LED1_OFF()  CtrlValveState[9]=0;HAL_GPIO_WritePin(OUT2_GPIO_Port, OUT2_Pin, GPIO_PIN_RESET)
/*报警灯 */
#define WARNING_LED2_ON()   CtrlValveState[8]=1;HAL_GPIO_WritePin(OUT4_GPIO_Port, OUT4_Pin, GPIO_PIN_SET)
#define WARNING_LED2_OFF()  CtrlValveState[8]=0;HAL_GPIO_WritePin(OUT4_GPIO_Port, OUT4_Pin, GPIO_PIN_RESET)

/*打点器*/
#define TAPPER_ON()         CtrlValveState[7]=1;TapperOnStartTime = osTimeGet();HAL_GPIO_WritePin(OUT3_GPIO_Port, OUT3_Pin, GPIO_PIN_SET)
#define TAPPER_OFF()        CtrlValveState[7]=0;                                HAL_GPIO_WritePin(OUT3_GPIO_Port, OUT3_Pin, GPIO_PIN_RESET)
/*喇叭*/
#define LB_ON()             CtrlValveState[6]=1;HAL_GPIO_WritePin(OUT5_GPIO_Port, OUT5_Pin, GPIO_PIN_SET)
#define LB_OFF()            CtrlValveState[6]=0;HAL_GPIO_WritePin(OUT5_GPIO_Port, OUT5_Pin, GPIO_PIN_RESET)

/*预落种阀门*/
#define YLZ_ON()        YLZStartTime=osTimeGet();CtrlValveState[0]=1;HAL_GPIO_WritePin(OUT7_GPIO_Port, OUT7_Pin, GPIO_PIN_SET)     
#define YLZ_OFF()       YLZStartTime=osTimeGet();CtrlValveState[0]=0;HAL_GPIO_WritePin(OUT7_GPIO_Port, OUT7_Pin, GPIO_PIN_RESET)    
/*倒种阀门(投种)*/
#define DZ_ON()             DzStartTime = osTimeGet();CtrlValveState[1]=1;HAL_GPIO_WritePin(OUT8_GPIO_Port, OUT8_Pin, GPIO_PIN_SET)
#define DZ_OFF()            DzStartTime = osTimeGet();CtrlValveState[1]=0;HAL_GPIO_WritePin(OUT8_GPIO_Port, OUT8_Pin, GPIO_PIN_RESET)
/*刮种*/
#define GZ_ON()          YL_CTRL_ON(0) 
#define GZ_OFF()         YL_CTRL_OFF(0)  

/*施肥电机控制*/
#define SF_MOTOR_ON()   YL_CTRL_ON(2);YL_CTRL_ON(1)  
#define SF_MOTOR_OFF()  YL_CTRL_OFF(2);YL_CTRL_OFF(1) 

/*清种阀门 转动阀门复用*/
#define QZ_ON()             CtrlValveState[2]=1;HAL_GPIO_WritePin(OUT6_GPIO_Port, OUT6_Pin, GPIO_PIN_SET)
#define QZ_OFF()            CtrlValveState[2]=0;HAL_GPIO_WritePin(OUT6_GPIO_Port, OUT6_Pin, GPIO_PIN_RESET)

/*内部输入输出状态变量  结束*/
typedef struct TerParaType_st
{
    s16 A;     //下种口距离 行程开关到下种口的距离cm   行程开关必须在下种口前方
    s16 B;      //种子落地距离  种子自由落体运动行走距离cm  

    u16 EncodeNum;  /*编码器变送比, 1m距离对应的编码器脉冲计数个数*/
    u8 EncoderDir;  /*编码器方向 0:正向 1:反向  行进时编码器可能为反向计数*/
    u8 HoleNum;     /*播种盘孔数*/

    u16 GearRatio;      /*电机减速比       步进电机 播种盘减速比X:1 */
    u16 MicroStepValue; /*步进电机细分值  步进电机转动一圈的细分值*/

    s16 X1;         //天线距离X1  北斗天线与北斗行程开关在行进方向距离 单位:cm 北斗天线在前则为正,反之为负
    s16 BDiroff;    /*反向距离修订 用于修订打点器和起始播种距离等 单位:cm*/
    s16 TappTrigOff;/*打点器到北斗行程开关距离 cm  打点器落点位置在北斗行程开关前方为正，反之为负*/
    u16 TapperTime; //打点时间  单位:ms
    u8  ZeroPosEn;   /*是否使能零位开关 0:不使用零位开关 1:使用零位开关*/
    u8  GZEn;        /*是否有刮种结构 1:有   0:没有*/
    u8 PrePercent;    /*预充种百分比 单位%1 0~100*/
    u8  Resv1[1];//u8  Resv1[2];
    s32 Resv[3];    //保留

    u32 CrcCheck;   /*参数CRC校验*/
}TerParaType;  /*厂家后台参数*/

typedef struct UserParaType_st{
    u16 DZTime;     //倒(投)种时间  单位ms
    s16 HJ;         /*行间距 单位:cm*/
    u32 RMP;        /*播种盘步进电机转速 r/min*/
    u8 AntennaType;//0:单 1:双
    u8 U8Resv;
    s16 AntennaDistance;//天线间距 单位:cm
    u32 CrcCheck;   /*参数CRC校验*/
}UserParaType;      /*用户后台参数*/

/*北斗模式AB线数据参数*/
typedef struct BDParaType_st
{
    double StartN;      //触杆时的A点纬度值 
    double StartE;      //触杆时的A点经度值
    double EndBN;      //B点的纬度值 
    double EndBE;      //B点时的经度值
    float  StartDir;    /*触杆时的行进方向 角度值 北斗获取到的行进方向角度值*/
    float  CalcDir;     /*计算得到的行进方向, 起点和输入的终点方向*/
    u16    StartState;  //标识起始A点经纬度信息是否有效 0:无效  1:有效
    u16    CalcDirFlag; //计算得到的行进方向是否有效(即B点信息是否有效) 0:无效  1:有效
    u16    OffLen;      //起始偏移量cm, 记录的起始触发点为碰触发开关之前的最后获取到的位置信息，该位置到实际碰杆位置有一个位移差
    u16    BDOffTime;   /*北斗终端实际位置到传输到播种机延迟时间 ms*/
    u32    Resv;        //保留
    u32    CrcCheck;    /* CRC校验和 控制板计算用于检查参数是否完整*/
}BDParaType;

typedef struct BDPosDataType_st
{
    double N;  //纬度值 单位:°
    double E;  //经度值 单位:°
    u8    ValidFlag;//标识经纬度信息是否有效 0:无效
    u8    Res; //保留
    u16   Res2; //保留
    u32   TimeStamp; //时间戳
}BDPosDataType;  /*北斗实时解析到的定位信息*/

typedef struct BDSpeedDataType_st
{
    float   Dir; /*行进方向*/
    s16     Speed;//行进速度 单位:mm/s
    u16     ValidFlag;//标识信息是否有效 0:无效
    u32     Resr;
    u32     TimeStamp; //时间戳
}BDSpeedDataType;  /*北斗实时解析到的速度信息*/

typedef struct CoordinateType_st
{
    double X;       //单位 m 垂直行进方向距离
    double Y;       //行进方向距离 m 
    double Line;    /*直线距离, 测试模式下使用 m*/
    double Res;     /*保留*/
}CoordinateType;

//extern bool NewSpeedGetFlag;        /*是否新获取到北斗速度信息*/
extern BDSpeedDataType  CurrBDSpeed;/*当前解析到的北斗速度和方向信息*/

extern bool NewPosGetFlag;          /*是否新获取到北斗位置信息*/
extern BDPosDataType    CurrBDPos;  /*当前解析到的北斗位置信息*/

extern BDParaType BDPara; /*北斗系统参数 AB线数据*/
extern BDParaType BDSpeedCalPara; /*北斗下计算速度参数用结构体*/
extern BDParaType BDSpeedShortCalPara; /*北斗下计算速度 瞬时参数用结构体*/

#define TER_INFO_STORE_ADDR    0    /*设备地址信息存储位置*/
//#define TYGS_INFO_STORE_ADDR  128   /*通用钢索模式参数信息存储位置*/
#define BD_INFO_STORE_ADDR    192   /*北斗模式参数信息存储位置*/

extern UserParaType UserPara; /*用户后台参数*/
extern TerParaType GlobalPara; /*系统参数*/
extern TerParaType GlobalParaSet; /*上位机设置的参数*/

extern u32 LZStartCnt[4];  //漏种起始计数值, 专用于播种过程中漏种监测
extern s16 LZStartLen;     /*漏种监测起始行程*/

extern u32 EEError; //eePROM 操作错误指示
/*清除漏种漏肥, 北斗触发开关及钢索触发开关等统计计数*/
void  ClearStaticCnts(void);
void ClearLzCnt(void);
bool  ParaInit(void);
void  WriteTerPara(TerParaType* para);

void  WriteBDPara(BDParaType* para);
void  ParaLegalCheck(void);//检查参数是否合法

#define PARA_CRC_SEED 0xffffffff 
#endif /*_PARA_H*/
