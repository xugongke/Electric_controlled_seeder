/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          para.c
*\Description   
*\Note          
*\Log           2020.08.13    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "para.h"
#include "ee_24cxx.h"
#include "tlib_crc.h"
#include "stdio.h"
#include "string.h"

UserParaType UserPara; /*用户后台参数*/
TerParaType GlobalPara;
TerParaType GlobalParaSet; /*上位机设置的参数*/

GPIO_TypeDef* ZeroInputPort[4]= {IN10_GPIO_Port,IN11_GPIO_Port,IN8_GPIO_Port,IN9_GPIO_Port};
u16 ZeroInputPin[4]= {IN10_Pin,IN11_Pin,IN8_Pin,IN9_Pin}; //零位输入GPIO PIN

/*预留控制输出*/
GPIO_TypeDef* YLCtrlPort[3]= {OUT12_GPIO_Port,OUT10_GPIO_Port,OUT11_GPIO_Port};
u16 YLCtrlPin[3]= {OUT12_Pin,OUT10_Pin,OUT11_Pin}; //零位输入GPIO PIN

u8 CtrlValveState[12];//阀门控制状态 

/*内部输入输出状态变量  开始*/
vu32 LouzhongCnt[4]; /*漏种计数 中断*/
vu32 LoufeiCnt[4];   /*漏肥计数 中断*/
vu32 BeidouStartTrigCnt; /*北斗起始触发开关*/
u32 BdTrigTime;  /*北斗触发时间*/

u32 LastGsStartTrig1Cnt; /*钢索触发开关1计数值 播种起始值*/
u32 LastGsStartTrig2Cnt; /*钢索触发开关2计数值 播种起始值*/
vu32 GsStartTrig1Cnt; /*钢索触发开关1计数值*/
vu32 GsStartTrig2Cnt; /*钢索触发开关2计数值*/
u32  GsTriggerTime[2]; /*钢索开关触发时间 ms*/

u32 LastLouzhongCnt[4]; /*漏种计数 中断  播种起始值*/
u32 LastLoufeiCnt[4];   /*漏肥计数 中断 播种起始值*/
u32 LastBeidouStartTrig; /*北斗起始触发开关 播种起始值*/

s32 LastPulseNum;   /*上次编码器计数*/

u8 TBInputState;    /*踏板输入*/

u8 DZKeyInputState;     /*倒种开关状态 0:未按下  1:按下*/
u8 LastDZKeyInputState; /*倒种开关状态,用于判断开关状态变化*/
u8 DZKeyFilter;         /*倒种开关滤波计数*/
u8 DZKeyValid;          /*记录一次有效的倒种开关按下*/

u32 DisLEDCnt[12]; /*显示板12个LED灯对应的计数状态值*/

//bool NewSpeedGetFlag;       /*是否新获取到北斗速度信息*/
BDSpeedDataType CurrBDSpeed;/*当前解析到的北斗速度和方向信息*/

bool NewPosGetFlag;         /*是否新获取到北斗位置信息*/
BDPosDataType   CurrBDPos;  /*当前解析到的北斗位置信息*/

BDParaType BDPara; /*北斗系统参数 AB线数据*/
BDParaType BDSpeedCalPara; /*北斗下计算速度参数用临时结构体*/
BDParaType BDSpeedShortCalPara; /*北斗下计算速度 瞬时参数用结构体*/
/*清除漏种漏肥, 北斗触发开关及钢索触发开关等统计计数*/
void ClearStaticCnts(void)
{
    /*清空所有计数值*/
    //ClearPulseNum();
    ClearGS1StartTrigCnt();
    ClearGS2StartTrigCnt();
    ClearBdStartTrigerCnt();
}

void ClearLzCnt(void)
{
    u8 i;
    //清除漏种计数
    for (i = 0; i < 4; i++){
        ClearLoufeiCnt(i);
        ClearLouzhongCnt(i);
        LZStartCnt[i] = GetLouZhongcnt(i);
    }
    LZStartLen = 0;
}

void GetInputState(void) /*获取所有非中断触发输入状态*/
{
    /*踏板输入*/
    TBInputState = (HAL_GPIO_ReadPin(IN18_GPIO_Port,  IN18_Pin)==GPIO_PIN_RESET)?1:0;
    
    InitKey = INIT_KEY();
}

u32 EEError; //eePROM 操作错误指示
/***************************************************************************************************
*\Function      ParaInit
*\Description   系统参数初始化
*\Parameter     
*\Return        bool
*\Note          
***************************************************************************************************/
bool ParaInit(void)
{
    bool res = FALSE;
    u32 crc_check;
    if (EE24cxxRead(TER_INFO_STORE_ADDR, (u8*)&GlobalPara, sizeof(TerParaType)) != (sizeof(TerParaType))){
        printf("eeprom read error\r\n");
        //EEError = 1;
    }
    crc_check = CRC32Calc(PARA_CRC_SEED, (u8*)&GlobalPara, sizeof(TerParaType)-4);
    if (crc_check != GlobalPara.CrcCheck){
        //EEError += 8;
        printf("init terminal paras\r\n");
        memset(&GlobalPara, 0x00, sizeof(GlobalPara));
        
        GlobalPara.MicroStepValue = 800;    //步进电机细分值
        GlobalPara.TapperTime = 60;         //打点器吸合时间60ms
        GlobalPara.EncodeNum = 600;         /*编码器变送比, 1m距离对应的编码器脉冲计数个数*/
        GlobalPara.X1 = 244;
        GlobalPara.HoleNum = 9; //播种盘孔数为暂时固定为9

        GlobalPara.CrcCheck = CRC32Calc(PARA_CRC_SEED, (u8*)&GlobalPara, sizeof(TerParaType)-4);
        //EE24cxxWrite(TER_INFO_STORE_ADDR, (u8*)&GlobalPara, sizeof(TerParaType));
    }
    else {
        printf("terminal para read success\r\n");
        res = TRUE;
    }

#if 0
    /*北斗模式参数 暂时改为上位机存储*/
    if (EE24cxxRead(BD_INFO_STORE_ADDR, (u8*)&BDPara, sizeof(BDParaType)) != (sizeof(BDParaType))){
        printf("eeprom read error\r\n");
    }
    crc_check = CRC32Calc(PARA_CRC_SEED, (u8*)&BDPara, sizeof(BDParaType)-4);
    if (crc_check != BDPara.CrcCheck){
        memset(&BDPara, 0x00, sizeof(BDPara));
        BDPara.BDOffTime = 100;//北斗延迟100ms
        BDPara.StartState = 0;
        BDPara.CalcDirFlag = 0; //行进方向无效
    }
#endif

    ParaLegalCheck();

    return res;
}

void  WriteTerPara(TerParaType* para)
{
    ParaLegalCheck();
    para->CrcCheck = CRC32Calc(PARA_CRC_SEED, (u8*)para, sizeof(TerParaType)-4);
    //EE24cxxWrite(TER_INFO_STORE_ADDR, (u8*)para, sizeof(TerParaType));
}

void  WriteBDPara(BDParaType* para)
{
    para->CrcCheck = CRC32Calc(PARA_CRC_SEED, (u8*)para, sizeof(BDParaType)-4);
#if 0
    EE24cxxWrite(BD_INFO_STORE_ADDR, (u8*)para, sizeof(BDParaType));
#endif 
}

void  ParaLegalCheck(void)//检查参数是否合法
{
    if (GlobalPara.GearRatio < 2){
        GlobalPara.GearRatio = 10;
    }
    if (GlobalPara.HoleNum == 0){
         GlobalPara.HoleNum = 9; //播种盘孔数
    }
    if ((UserPara.HJ < 10) || (UserPara.HJ > 5000)){
        UserPara.HJ = 60;
    }
    if ((UserPara.DZTime < 100) || (UserPara.DZTime > 10000)){
        UserPara.DZTime = 1500; /*倒种时间*/
    }
    if ((UserPara.RMP < 5) || (UserPara.RMP > 70)){
        UserPara.RMP = 20; /*播种盘转速R/MIN*/
    }
    if (GlobalPara.TapperTime > 1000){
        /*打点时间过大*/
        GlobalPara.TapperTime = 60;
    }
    if (GlobalPara.MicroStepValue > 6400){ //步进电机细分值
        GlobalPara.MicroStepValue = 800; 
    }

    if (GlobalPara.EncodeNum == 0){
        GlobalPara.EncodeNum = 700; //编码器变送比
    }
}
