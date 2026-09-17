/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          ee_24cxx.h
*\Description   
*\Note          1) 需要根据具体芯片型号修改总大小宏定义:EE_24CXX_TOTAL_SIZE   
*\Log           2019.07.07    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _EE_24CXX_H
#define _EE_24CXX_H
#include "i2c_simu.h"

#define FLASH_SIMU_EEPROM  1 /*是否使用FLASH模拟EEPROM*/

#define EE24Cxx_ADDRESS 0xA0   /*默认A0,A1,A2脚全都连到GND   4kbit(512 byte)芯片A2用于内部页地址p0  
8K bit(1k byte)芯片 A2 A1用于内部页地址p1 p0  16kbit(2k byte)芯片 A2 A1 A0全部用于内部页地址p2 p1 p0*/
#define EE_24CXX_TOTAL_SIZE (2048) /*芯片总的容量大小:字节, 需要根据芯片调整*/

/***************************************************************************************************
*\Function      EE24cxxInit
*\Description   
*\Parameter     
*\Return        uint8_t 1:成功 0:失败
*\Note          
***************************************************************************************************/
uint8_t EE24cxxInit(void);

/***************************************************************************************************
*\Function      DeviceStorageAt24c01Write
*\Description   写一定长度的数据
*\Parameter     dev     AT24C01设备配置信息结构体指针
*\Parameter     addr    要写的地址
*\Parameter     buf     数据缓冲区首地址
*\Parameter     len     写入数据长度
*\Return        uint16_t     实际写入数据长度，若写入失败则返回0，否则返回len的值
*\Note
***************************************************************************************************/
uint16_t EE24cxxWrite(uint16_t addr, uint8_t* buf, uint16_t len);

/***************************************************************************************************
*\Function      EE24cxxRead
*\Description   读数据
*\Parameter     addr    起始地址
*\Parameter     buf     接收缓冲区首地址
*\Parameter     len     要读的数据长度
*\Return        uint16_t     实际读取的数据长度
*\Note          若所要读取的数据长度或地址超出了当前的总容量则返回0
***************************************************************************************************/
uint16_t EE24cxxRead(uint16_t addr,  uint8_t* buf, uint16_t len);

void TestEEPROM(void const* para);
#endif /*_EE_24CXX_H*/
