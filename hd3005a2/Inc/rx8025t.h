/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          rx8025t.h
*\Description   RX8025T驱动源文件
*\Note          
*\Log           2019.07.06    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _RX8025T_H
#define _RX8025T_H
#include "i2c_simu.h"
#include "tlib_time.h"

/***************************************************************************************************
*\Function      Rx8025tInit
*\Description   
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void Rx8025tInit(void);

/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cGetBCD
*\Description   获取BCD格式时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tGetBCD(TIME* time);

/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cSetBCD
*\Description   以BCD格式设置时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tSetBCD(TIME* time);
/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cSetBCD
*\Description   以DEC格式设置时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tGetDEC(TIME* time);

/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cSetBCD
*\Description   以DEC格式设置时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tSetDEC(TIME* time);
/*初始化系统时钟*/
void InitSysTime(void);
void SetSysTime(u32 sys_time);
#endif /*_RX8025T_H*/
