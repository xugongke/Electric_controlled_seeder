#ifndef _OPERATION_H
#define _OPERATION_H
#include "main.h"
#include "para.h"
#include "user_uart.h"
#define BD_SIMU_TEST  1  /*北斗模拟测试代码*/
//#define SPEED_FILTER_EN  0 /*是否使能北斗计算速度滤波功能*/
//#define SIMU_CELL_DATA  1 /*是否自动生成模拟测试小区数据*/
extern bool RowNumIncrease; //是否行号递增
#if BD_SIMU_TEST
extern s32 BdSimuSpeed;
#define SIMU_SPEED  BdSimuSpeed /*模拟速度值1000mm/s*/

extern s32 BDSimuVerticalOff; // 垂直方向距离 cm
extern u32 BDSimuStartTime;
extern s32 BDSimuOff; /*模拟北斗的行程 cm*/
extern s32 BDSimuStartOff; /*模拟北斗的行程 cm*/

#endif

#define TAPPER_ON_TIME  (GlobalPara.TapperTime) /*打点器工作时间 ms*/
#define DIS_FLUSH_TIME  (200)   /*刷新显示板时间间隔ms*/

extern u8 DebugInfoBuf[64];     /*调试信息状态输出缓冲区*/


extern u32 BdErrorCnt; /*北斗定位信息错误计数*/

extern s32 BdCalcSpeed; //通过北斗位置计算的实时速度 行进方向一致为正值, 倒车为负值 mm/s
extern s32 AvgSpeed;    /*统计出来的北斗平均速度 mm/s*/
extern u32 AvgSpeedTime;// 上次获取平均速度的时间 ms
extern u32 TapperOnStartTime;   /*打点器起始工作时间*/

#define RUN_S_STOP      0 /*停止模式*/
#define RUN_S_START     1 /*开始模式*/

#define SEED_S_WAIT      0  /*等待播种开始*/
#define SEED_S_WAIT_QZ   1  /*等待清种模式*/
#define SEED_S_QZ        2  /*开始清种*/
//#define SEED_S_QZ_END    3  /*清种结束*/
#define SEED_S_WAIT_GZ   4  /*等待刮种时机到*/
#define SEED_S_GZ        5  /*刮种*/
#define SEED_S_WAIT_END  6  /*正在播种过程中，等待当前小区播种结束*/
#define SEED_WAIT_ZERO   7  /*等待所有零位开关到位*/
#define SEED_HALF_CYCLE  8  /*等待所有零位开关到位之前 固定旋转半圈*/

#define SEED_PRE_DZ     11  /*预充种-倒种*/
#define SEED_PRE_MOTOR  12  /*预充种-播种盘电机*/
#define SEED_S_START    13  /*等待开始播种 检查是否有AB线数据*/
#define SEED_WAIT_S_BZP 14  /*A点数据已有, 等待行驶到对应位置开始播种盘转动*/

#define SEED_ERR_WAIT   15   /*异常处理等待*/

extern uint16_t SeedMode; //当前播种机的工作状态，播种的细节状态
extern uint16_t RunState;  /*运行状态*/
extern u8 MoveOn; /*0x80表示农机运行  0x00在准备阶段*/

extern bool QZDDEnable; /*是否使能清种打点*/
extern bool GDDDEnable; /*是否使能清种打点*/

extern u32 StateStartTime;   //切换到当前状态的时间戳 单位:ms  用于在播种模式下根据时间检查各种状态

extern bool BDTXFlag; /*是否与起始方向同方向*/
extern bool DirValid; /*是否方向判断有效 TRUE表示有效 FALSE表示无效   在农机一开始运动时判断一次行进方向, 是与AB线同向还是反向*/
extern double DirPDStartOff; /*单位:m 判断方向的起始偏移*/ 
extern u32 DirPDStartTime;  //ms 
extern double db_sub;
extern double DirPDEndOff;   /*单位:m 判断方向的结束偏移*/ 
extern u32 DirPDEndTime;     //ms 

extern CoordinateType BdSpeedCoor; //距离起始点坐标 计算速度专用

extern CoordinateType BdCurrCoor; //最近获取到的北斗信息距离起始点坐标 
extern CoordinateType BdCurrOffCoor; //经过修正后当前实际位置距离起始点坐标, 原点为北斗行程开关触发所在位置
extern CoordinateType BdLastOffCoor; //上次用于判断是否在倒车的坐标值

/***************************************************************************************************
*\Function      BDTrigCoor
*\Description   将当前位置修正为以北斗行程开关触发位置为原点的坐标,便于统一计算
***************************************************************************************************/
void BDTrigCoor(void);

/***************************************************************************************************
*\Function      GetDirExchange
*\Description   根据碰杆的起始经纬度和传入的B点坐标计算行进方向,并记录在参数结构体中
*\Parameter     e   经度 直接从GPS获取到的值 B点经纬度
*\Parameter     n   纬度 
*\Parameter     bd_para 起点坐标结构体
*\Return        bool
*\Note          
***************************************************************************************************/
bool CalABDir(double e,double n, BDParaType* bd_para);

/***************************************************************************************************
*\Function      CoordinateExchange
*\Description   2个经纬度坐标之间沿行进方向之间的距离, 垂直方向距离计算
*\Parameter     e   经度 直接从GPS获取到的值 角度值
*\Parameter     n   纬度 
*\Parameter     xy_res 转换后的坐标值
*\Parameter     bd_para 起点坐标结构体
*\Return        bool
*\Note          1)纯2个坐标之间计算,未考虑北斗延迟等参数
***************************************************************************************************/
bool CoordinateExchange(double e,double n, CoordinateType* xy_res, BDParaType* bd_para);

#endif /*_OPERATION_H*/
