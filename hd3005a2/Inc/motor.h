/***************************************************************************************************
*                    (c) Copyright 1992-2022 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          motor.h
*\Description   电机控制相关操作
*\Note          
*\Log           2022.05.16    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _MOTOR_H
#define _MOTOR_H
#include "main.h"
#include "para.h"
#define LXBZ_INDEX 0 /*连续播种电机*/
#define FZ_INDEX   1   /*分种电机*/
#define GZ_STEP_INDEX 4 /*自动供种开关步进电机参数0~3播种机 4 自动供种 5,6播种机*/

extern u32 CurrRunPulseNum[LINE_NUM+1]; //正在运行脉冲数  0:表示之前运行脉冲数已经结束  非0:表示有脉冲正在输出过程中
extern u32 TotalOutputPWMNums; //总的PWM计数
extern u16 LXBZSpeed;   //连续播种电机 脉冲数/s
extern int32_t EncoderSpeed;    //编码器速度 mm/s
extern s16 DCMotorSpeed; //直流分种电机每秒的转速
extern u32 DCMotorRMP;   // 分种电机每分钟转速
extern u32 DCMotorRMPDis; //分种电机显示每分钟转速  用于滤波显示转速提升用户体验
extern u8 DCStartEnable[2]; //使能对应的直流电机  0:连续播种电机 1:分种电机
extern u16 DcMotorCurrDuty[2]; //直流电机要当前的占空比 0.1%
/*电瓶电压采集*/
void AdcProcFunc(void);
/*启动自动供种步进电机*/
void StartGZStepMotor(void);

/***************************************************************************************************
*\Function      GetPulseTimeFromRMP
*\Description   根据用户设置转速计算步进电机驱动脉冲宽度.主要用于测试模式及预充种阶段
*\Parameter     rmp   r/min
*\Return        u32  us*STEP_US_CNT
***************************************************************************************************/
u32 GetPulseTimeFromRMP(u32 rmp);

/***************************************************************************************************
*\Function      GetPulseTime
*\Description   根据运行速度计算步进电机驱动脉冲宽度
                该接口中会根据小区密度自动计算株数、株距等参数
*\Parameter     speed   mm/s
*\Return        u32  us*STEP_US_CNT
***************************************************************************************************/
u32 GetStepPulseTime(u8 index, s32 speed);

/***************************************************************************************************
*\Function      StepMotorCtrlTask
*\Description   步进电机控制任务
*\Parameter     para
*\Return        void
*\Note          
***************************************************************************************************/
void StepMotorCtrlTask(const void* para);

/***************************************************************************************************
*\Function      PWMInit
*\Description   输出PWM初始化
*\Parameter     
*\Return        void
*\Note          1)PE5 PE6两个通道TIM9 采用同一频率,不同占空比
***************************************************************************************************/
void PWMInit(void);

/***************************************************************************************************
*\Function      DCMotorSpeedGet
*\Description   分种直流电机转速计算
*\Parameter     
*\Return        u16  每秒的脉冲计数
*\Note          每隔1s调用一次该接口用于计算分种旋转电机转速
***************************************************************************************************/
void EncoderSpeedCalc(void);

/***************************************************************************************************
*\Function      DCMotorDutyAdj
*\Description   
*\Parameter     duty_ths  占空比 高电平部分  单位:0.1%  0表示一直为低电平或者关闭   1000:表示一直为高电平
*\Return        u16
*\Note          
***************************************************************************************************/
void DCMotorDutyAdj(u16 duty_ths, u32 channel_num);

/***************************************************************************************************
*\Function      EncoderInit
*\Description   编码器初始化
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void  EncoderInit(void);
//#define ENCODE_CNT()    (TIM2->CNT)

//#define ENCODER_DIR()  __HAL_TIM_IS_TIM_COUNTING_DOWN(&htim2)

#endif /*_MOTOR_H*/
