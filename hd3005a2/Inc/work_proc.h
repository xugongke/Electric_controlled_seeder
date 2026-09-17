#ifndef _WORK_PROC_H
#define _WORK_PROC_H
#include "main.h"
#include "protocol.h"
#if LINE_NUM == 4
#define BZP_ZERO_MASK  0X0F     /*播种盘屏蔽*/
#else
 /*6通道*/
#define BZP_ZERO_MASK  0X6F     /*播种盘屏蔽 bit0~3 播种盘1~4 bit:4自动供种  bit:5,6 播种盘5,6*/
#endif
#define GZP_STEP_MASK  0x80    /*自动供种步进电机*/

#define BD_SPEED_INTERVAL 1000 /*单位:ms 北斗速度计算间隔*/


#define ENABLE_BZP_PRE  1 /*1使能播种盘可调比例 0:固定比例*/


#define WORK_MODE_IDLE   0  /*空闲模式*/
#define WORK_MODE_BD     1  /*正常北斗工作模式*/
#define WORK_MODE_LXBZ   2  /*连续播种模式*/
#define WORK_MODE_TEST   3  /*测试模式*/

extern bool ShiFeiOnFlag; /*TRUE 启动施肥*/
extern s32 Zhuju[LINE_NUM]; /*当前小区的株距d cm*/

extern u32 LXBZCellLen;     //用于连续播种计算的小区长度 单位:cm
extern u32 LXBZZhushu;      //当前小区单行的株数 单位:株

extern u8 DJCtrlState;      /*0~3播种电机 4:自动供种电机 5:6 播种盘5及6*/
extern u16 WorkMode;        //当前工作模式
#define MAX_CTRL_NUMS  23   /*最大控制编号*/
extern u16 CurrentCMDAna;   /*当前解析到的命令 */
extern TestCMDType TestCMD; /*测试模式下上位机下发的控制命令*/

extern TestModeStateType TestState; //当前测试模式下所有外设状态
/*获取播种盘零位状态 按位表示各个播种盘*/
u8 GetBzpInState(void);
/*获取播种实时状态*/
void GetBzStatus(BZStatusType* st);
/*清零播种盘累计脉冲*/
void ClearBZPPulseNum(void);
/*获取测试模式下所有设备状态*/
void GetTestStatus(TestModeStateType* tst_state);

/***************************************************************************************************
*\Function      WorkProcTask
*\Description   工作状态管理任务
*\Parameter     para
*\Return        void
*\Note          
***************************************************************************************************/
void WorkProcTask(void const* para);

/***************************************************************************************************
*\Function      LXBZParaCheck
*\Description   连续播种模式参数检查
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void LXBZParaCheck(void);

/***************************************************************************************************
*\Function      GetZhuShu
*\Description   
*\Parameter     density     密度:株/亩
*\Parameter     cell_len    小区长度   cm
*\Parameter     hju         行间距 单位cm
*\Return        u32
*\Note          1)株距=cell_len/(株数-1)
*\Log           2022.12.12    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 GetZhuShu(u32 density, u32 cell_len, u16 hju);

/***************************************************************************************************
*\Function      GetZhuJu
*\Description   计算株距
*\Parameter     cell_len  小区总长度 cm
*\Parameter     N         小区株数
*\Return        u32
***************************************************************************************************/
u32 GetZhuJu(u32 cell_len, u32 N);

#endif /*_WORK_PROC_H*/
