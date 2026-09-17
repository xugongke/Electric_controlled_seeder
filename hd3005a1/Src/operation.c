#include "operation.h"
#include "user_uart.h"
#include "protocol.h"
#include "FSM.h"
#include "string.h"
#include "para.h"
#include "math.h"
#include "stdlib.h"
#include "motor.h"
u32 BdErrorCnt; /*北斗定位信息错误计数*/

uint16_t SeedMode; //当前播种机的工作状态，播种的细节状态
uint16_t RunState;  /*运行状态*/
u8   MoveOn; /*0x80表示农机运行  0x00在准备阶段*/

bool QZDDEnable;        /*是否使能清种打点*/
bool GDDDEnable=FALSE;        /*是否使能过道打点*/

u32 ErrCode;            /*用于指示当前系统故障*/
u8 DebugInfoBuf[64];    /*调试信息状态输出缓冲区*/
u32 StateStartTime;     //切换到当前状态的时间戳 单位:ms  用于在播种模式下根据时间检查各种状态

u32 AvgSpeedTime;   //上次获取平均速度的时间 ms
s32 AvgSpeed;       /*统计出来的平均速度 mm/s*/

u32 LZStartCnt[4];  //漏种起始计数值, 专用于播种过程中漏种监测
s16 LZStartLen;     /*漏种监测起始行程*/

bool TapperOnFlag;   /*是否打点器工作  小区间隔中间时刻*/
u32 TapperOnStartTime;  /*打点器起始工作时间*/

CoordinateType BdSpeedCoor; //距离起始点坐标 计算速度专用
CoordinateType BdCurrCoor; //最近获取到的北斗信息距离起始点坐标 
CoordinateType BdCurrOffCoor; //经过修正后当前实际位置距离起始点坐标, 原点为北斗行程开关触发(A点)所在位置
CoordinateType BdLastOffCoor; //上次用于判断是否在倒车的坐标值

double startBdYlen; /*起始北斗行程开关的坐标 m*/

bool RowNumIncrease; //是否行号递增

bool BDTXFlag; /*是否与起始方向同方向 TRUE:同向  FALSE:反向*/
bool DirValid; /*是否方向判断有效 TRUE有效 FALSE无效   在农机一开始运动时判断一次行进方向, 是与AB线同向还是反向*/
double DirPDStartOff; /*单位:m 判断方向的起始偏移*/ 
u32 DirPDStartTime;  //ms 

double db_sub;
double DirPDEndOff;   /*单位:m 判断方向的结束偏移*/ 
u32 DirPDEndTime;     //ms 

CoordinateType CoorXYMid;   /*经纬度转换成正北正东方向的平面坐标, X轴为正东方向 Y轴为正北方向 */
CoordinateType CoorXYDir;   /*正北正东方向平面坐标转换成触发北斗行程开发时行进方向的平面坐标   Y轴为行进方向 X轴为垂直于行进方向*/
double RE = 6378137.0;      //经度圆的半径为地球的半径 单位:m
double RN = 0.0;            //纬度圆半径与所在纬度有关 单位:m
double pi = 3.1415926535898;

/***************************************************************************************************
*\Function      CalABDir
*\Description   根据碰杆的起始经纬度和传入的B点坐标计算行进方向,并记录在参数结构体中
*\Parameter     e   经度 直接从GPS获取到的值 (B点)
*\Parameter     n   纬度 
*\Parameter     bd_para 起点(A点)坐标结构体 
*\Return        bool
*\Note          
***************************************************************************************************/
bool CalABDir(double e,double n, BDParaType* bd_para)
{
    double e_sub;
    double n_sub;
    double angle; //行进方向角度
    /*首先转换成正北和正东方向平面坐标, 坐标原点为触发行程开关之前获取到的经纬度坐标
    X轴为正东方向 Y轴为正北方向
    X为同一纬度方向  Y轴为经度方向
    */
    double r;

    if (RN == 0.0){
        RN = 6371393.0*cos(pi/180*bd_para->StartN); //纬度圆半径与所在纬度有关 单位:m
    }
    /*2与起始点A经纬度差值*/
    e_sub = e - bd_para->StartE;
    n_sub = n - bd_para->StartN;

    e_sub = e_sub*pi/180; //角度变为弧度
    n_sub = n_sub*pi/180; //角度变为弧度

    CoorXYMid.X = e_sub*RN;  //纬度方向的距离  不同纬度 纬度圆的半径不同
    CoorXYMid.Y = n_sub*RE;  //经度方向的距离 经度圆的半径是固定的地球半径

    r = (CoorXYMid.X*CoorXYMid.X+CoorXYMid.Y*CoorXYMid.Y);
    r = sqrt(r);

    angle = acos(CoorXYMid.Y/r);
    angle = angle / pi * 180;
    if(CoorXYMid.X < 0)
    {
        angle = 360 - angle;
    }
    bd_para->CalcDir = angle;
    bd_para->CalcDirFlag = 1; //计算角度值有效
    bd_para->EndBN = n;
    bd_para->EndBE = e; /*记录终点的经纬度信息*/

    return TRUE;
}

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
bool CoordinateExchange(double e,double n, CoordinateType* xy_res, BDParaType* bd_para)
{
    double e_sub;
    double n_sub;
    double angle; //行进方向角度
    /*首先转换成正北和正东方向平面坐标, 坐标原点为触发行程开关之前获取到的经纬度坐标
    X轴为正东方向 Y轴为正北方向
    X为同一纬度方向  Y轴为经度方向
    */
    if (bd_para->StartState != 1){
        /*是否有效起始经纬度值*/
        return FALSE;
    }
    if (RN == 0.0){
        RN = 6371393.0*cos(pi/180*bd_para->StartN); //纬度圆半径与所在纬度有关 单位:m
    }
    /*2与起始点经纬度差值*/
    e_sub = e - bd_para->StartE;
    n_sub = n - bd_para->StartN;

    e_sub = e_sub*pi/180; //角度变为弧度
    n_sub = n_sub*pi/180; //角度变为弧度

    CoorXYMid.X = e_sub*RN;  //纬度方向的距离  不同纬度 纬度圆的半径不同
    CoorXYMid.Y = n_sub*RE;  //经度方向的距离 经度圆的半径是固定的地球半径

    //转换为行进方向坐标
    if (bd_para->CalcDirFlag != 1){
        angle = -bd_para->StartDir; //计算结果无效时，先采用触发碰杆时的行进方向
    }
    else {
        angle = -bd_para->CalcDir;
    }

    angle = angle*pi/180;  //角度变弧度
    /*@TODO 可能需要角度取相反数*/
    CoorXYDir.X = CoorXYMid.X*cos(angle)+CoorXYMid.Y*sin(angle);//垂直行进方向距离
    CoorXYDir.Y = CoorXYMid.Y*cos(angle)-CoorXYMid.X*sin(angle);//行进方向
    CoorXYDir.Line = (CoorXYDir.X*CoorXYDir.X+CoorXYDir.Y*CoorXYDir.Y);
    CoorXYDir.Line = sqrt(CoorXYDir.Line);

    xy_res->X    = CoorXYDir.X;
    xy_res->Y    = CoorXYDir.Y; //行进方向距离
    xy_res->Line = CoorXYDir.Line;

    return TRUE;
}
s32 OffSpeed;
/*
1)点击开始按钮之前，请确保农机方向已经调整好,速度行驶到正常播种水平
2)A线触发时（北斗行程开关触发位置为坐标原点）,方向相同时An线位置为N(L+S) 
与A线触发方向相反时B, 线触发位置为2Q+L*(N+1)+(N)S  N为小区编号 
3)为了保证播种结果的准确性，若有播种机重新上电的情况，增加一次北斗触发开关的操作，重新修正A线
4)需要记录A线及触发方向(坐标原点为北斗行程开关, 与触发方向一致的前方为正值, 北斗行程开关后方为负值)
*/
/***************************************************************************************************
*\Function      BDTrigCoor
*\Description   将当前位置修正为以北斗行程开关触发位置为原点的坐标,便于统一计算
***************************************************************************************************/
void BDTrigCoor(void)
{
    u32 time_sub;
    
#if BD_SIMU_TEST
    CurrBDPos.ValidFlag = 1;
    CurrBDPos.TimeStamp = osTimeGet();
    if (RunState == RUN_S_STOP){
        BdCurrOffCoor.Y = 0;
        BdCurrOffCoor.X = 0;
        BdCurrOffCoor.Line = 0;
        BDSimuStartTime = osTimeGet();
        return ;
    }
    else {
        /*模拟计算行程*/
        time_sub = osTimeGet() - BDSimuStartTime;
        if (BDTXFlag == TRUE){ //AB线同向

                if(time_sub > 100){
                    BDSimuOff += (s32)(time_sub*SIMU_SPEED/10000);
                    BDSimuStartTime = osTimeGet();
                    time_sub = 0;
                }
                else {
                    //BdCurrOffCoor.Y = (BDSimuOff + BDSimuStartOff + (s32)(time_sub*SIMU_SPEED/10000))*0.01;
                }
                BdCurrOffCoor.Y = (BDSimuOff + BDSimuStartOff + (s32)(time_sub*SIMU_SPEED/10000))*0.01;
            
           // BdCurrOffCoor.Y = (BDSimuOff + (s32)(time_sub*SIMU_SPEED/10000))*0.01;
           // if(time_sub > 100){
            //    BDSimuOff  += BdCurrOffCoor.Y;
            //    BDSimuStartTime = osTimeGet();
            //}
        }
        else {
            if(time_sub > 100){
                BDSimuOff -= (s32)(time_sub*SIMU_SPEED/10000);
                BDSimuStartTime = osTimeGet();
                time_sub = 0;
            }
            else {
                //BdCurrOffCoor.Y = (BDSimuOff + BDSimuStartOff + (s32)(time_sub*SIMU_SPEED/10000))*0.01;
            }
            BdCurrOffCoor.Y = (BDSimuOff + BDSimuStartOff - (s32)(time_sub*SIMU_SPEED/10000))*0.01;

           // BdCurrOffCoor.Y = (BDSimuStartOff - (s32)(time_sub*SIMU_SPEED/10000))*0.01;
          //  if(time_sub > 100){
          //      BDSimuOff  += BdCurrOffCoor.Y;
          //      BDSimuStartTime = osTimeGet();
          //  }
        }
        BdCurrOffCoor.Line = BdCurrCoor.Y;
        BdCurrOffCoor.X = BDSimuVerticalOff*0.01;
    }
#else 
    /*检查行进方向*/
    time_sub = osTimeGet()-CurrBDPos.TimeStamp;

    if (NewPosGetFlag == TRUE){
        /*坐标系转换*/
        NewPosGetFlag = FALSE;
        if (BDPara.StartState == 1){
            CoordinateExchange(CurrBDPos.E, CurrBDPos.N, &BdCurrCoor, &BDPara); //2个北斗坐标之间的距离计算, 未考虑延迟
            if (BDPara.CalcDirFlag != 1){
                /*AB线还未划完, 没有准确的行进角度, 直线距离作为行进方向的距离*/
                BdCurrCoor.Y = BdCurrCoor.Line;
                BdCurrCoor.X = 0; //垂直方向距离先定为0
            }
        }
        else {
            /*还没有A点数据无法计算距离A点距离*/
            BdCurrCoor.Y = 0;
            BdCurrCoor.X = 0;
            BdCurrOffCoor.Line = 0;
            return ;
        }
    }
    
    if ((CurrBDPos.ValidFlag == 0) || (BDPara.StartState == 0)){
        /*当前位置信息没有或者没有A点坐标则不刷新行程*/
        BdCurrOffCoor.Y = 0;
        BdCurrOffCoor.X = 0;
        BdCurrOffCoor.Line = 0;
        return;
    }
    BdCurrOffCoor.X = BdCurrCoor.X; //垂直行进方向不修正
    
    if ((AvgSpeed > -2000) && (AvgSpeed < 2000)){
        OffSpeed = AvgSpeed;
    }
    if (OffSpeed < 0){
        OffSpeed *= -1;
    }
    /*行进方向距离修正延迟, 根据行驶速度及延迟时间*/
    if (BDTXFlag == TRUE){ //AB线同向
        startBdYlen = (BDPara.OffLen*0.01);
        BdCurrOffCoor.Y = BdCurrCoor.Y + 
            ((time_sub+BDPara.BDOffTime)*OffSpeed/10000)*0.01 /*北斗传输延迟+累积间隔*/
            - startBdYlen; // 修正为当前北斗行程开关距离碰杆时北斗行程开关的实际距离
    }
    else { //AB线反向
        startBdYlen = (BDPara.OffLen*0.01)-(GlobalPara.X1*0.01*2); /*北斗行程开关行进方向坐标以碰杆前最后一次获取的北斗位置为原点*/
        BdCurrOffCoor.Y = BdCurrCoor.Y - 
            ((time_sub+BDPara.BDOffTime)*OffSpeed/10000)*0.01 /*北斗传输延迟+累积间隔*/
            - startBdYlen; // 修正为当前北斗行程开关距离碰杆时北斗行程开关的实际距离
    }

    BdCurrOffCoor.Line = sqrt(BdCurrOffCoor.X*BdCurrOffCoor.X+BdCurrOffCoor.Y*BdCurrOffCoor.Y); //直线距离

    if (BDPara.CalcDirFlag != 0){
        /*有AB线情况下 对反向行驶时垂直方向距离进行修订*/
        if (BDTXFlag == FALSE){
            if (UserPara.AntennaType != 0){
                /*双天线版本需要修订垂直方向距离*/
                BdCurrOffCoor.X -= (UserPara.AntennaDistance*0.01);
            }
        }
    }
#endif
}

