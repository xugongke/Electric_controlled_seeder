/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          FSM.h
*\Description   播种机状态相关定义
*\Note          
*\Log           2020.11.27    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _FSM_H
#define _FSM_H
/*主控制板状态定义  开始*/
#define M_S_INITAL          0   /*刚上电初始状态*/
#define M_S_AUTO            1   /*自动模式*/
#define M_S_MANU            2   /*手动模式*/
#define M_S_BD              3   /*北斗模式*/
#define M_S_LXBZ            4   /*连续播种模式*/

#define M_S_PWCHECK         5   /*密码验证*/
#define M_S_VALVE_TEST      6   /*阀门测试*/
#define M_S_USER_PARA       8   /*用户参数设置*/
#define M_S_FAC_PARA        9    /*厂家参数设置*/
#define M_S_FAULT_DIS       10    /*故障处理*/

/*主控制板状态定义  结束*/

#endif /*_FSM_H*/
