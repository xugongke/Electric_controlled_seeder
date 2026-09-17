/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          update.h
*\Description   程序升级头文件
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _UPDATE_H
#define _UPDATE_H
#include "main.h"
#include "cmsis_os.h"
#include "stm32f4xx_hal_flash.h"
#include "type.h"
#include "protocol.h"
#define UP_CRC32_SEED    0xFFFFFFFF

#define UPDATA_TOTAL_SIZE (128*1024)   /*升级允许最大的应用程序大小*/
#define UPDATA_MIN_SIZE   (3*1024)   /*升级允许最小的应用程序大小*/

#define STM32_FLASH_START_ADDR (0x8000000)

#define UP_FLAG_START_ADDR      (0x8000000 + 32*1024)   //设置升级标志  UpDataFileHeader  一共两个每个地址占用256字节
#define UP_COPY_FLAG_START_ADDR (0x8000000 + 48*1024)   //设置升级标志  UpDataFileHeader  一共两个每个地址占用256字节

#define PARA_START_ADDR    (0x8000000 + 64*1024)        //设置FLASH 保存地址(必须为偶数)（stm32f207IGT6页3）

#define NOR_APP_START_ADDR      (0x8000000 + 128*1024)          //正常APP的起始地址 BOOTLOADER占用48K的空间
#define UP_APP_START_ADDR       (NOR_APP_START_ADDR + 128*1024) //升级APP的起始地址
#define UP_COPY_APP_START_ADDR  (UP_APP_START_ADDR  + 128*1024) //APP备份的起始地址   stm32f2 FLASH大小 0~3 16K; 4 64k; 5~ 128k

#define MAX_UPDATE_FILE_LEN (128*1024)

#define MAX_PARA_LEN   512 /*最大的用户参数存储*/

typedef struct UpDataFileStartHeader_st
{
    u32 Len;    //升级文件总的长度
    u32 CrcNum;  //升级文件校验和，若是长度不相等则认为是不合理的参数
}UpDataFileStartHeader;  //0xcd 设置升级文件头


typedef struct UpDataFileEndHeader_st
{
    u32 Len;        //升级文件总的长度  与开始帧中的应该相等。若是不相等，则以结束帧的为准
    u32 CrcNum;     //升级文件的CRC校验
}UpDataFileEndHeader; //传输升级文件结束标志

typedef struct
{
    u32 FileHeaderChk;  //对升级信息本身的crc32校验（从UpdateFlag至filechk部分），多项式X32+X26
    u32 UpdateFlag;     //升级标志  对于应用程序和BIT的该字段不需要置升级标志  对于升级文件的应用程序和BIT文件需要将对应的标志正确置位
    u32 FileAttr;       //文件属性  
    u32 FileLen;        //升级文件的大小
    u32 FileChk;        //升级文件的CRC32校验,多项式X32+X26
}UpDataFileHeader;      //在每个程序区域或BIT区域都以该结构体作为开始

/*UpdateFlag相关宏定义*/
#define NO_NEED_UPDATE  0x00000000      /*不需要进行升级，直接跳转到应用*/
#define NEED_UPDATE     0xF3F6F7F7      /*备份当前应用程序，并升级新的应用程序，
升级成功将升级标志置为0x12341234，升级失败将升级标志置为0x56781234；
跳转到新的应用程序后要求应用程序在重启前将升级标志置为0x00000000，
否则再次重启时Bootloader会将备份的旧程序重新替换掉新的程序。*/
#define UPDATE_SUCESS  0xF1F2F3F4
#define UPDATE_FAILED  0xF3F6F7F6
#define UPDATE_EXCEPT  UPDATE_SUCESS   /*应用程序没有将升级成功标记清零，则需要将备份的旧程序恢复到内部FLASH中*/
extern bool Updateing;         //是否正在升级过程中
extern u8 AppVersion[]; //版本信息
/***************************************************************************************************
*\Function      UpdateInit
*\Description   初始化程序升级相关变量
*\Parameter     
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateInit(void);

/***************************************************************************************************
*\Function      UpdateBinFunc
*\Description   更新升级程序文件
*\Parameter     data 升级数据帧数据域内容
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateBinFunc(DataNode* data);

/***************************************************************************************************
*\Function      UpdateStartFunc
*\Description   启动升级过程
*\Parameter     data 升级数据帧数据域内容
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateStartFunc(DataNode* data);

/***************************************************************************************************
*\Function      UpdateEndFunc
*\Description   升级过程结束，进行最终合法性检查
*\Parameter     data 升级数据帧数据域内容
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateEndFunc(DataNode* data);

/***************************************************************************************************
*\Function      WriteFlashPara
*\Description   写参数到FLASH空间
*\Parameter     addr  0~MAX_PARA_LEN-1
*\Parameter     buf
*\Parameter     len
*\Return        bool
*\Note          
*\Log           2022.10.21    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool WriteFlashPara(u32 addr, u8* buf, u32 len);

/***************************************************************************************************
*\Function      ReadFlashPara
*\Description   读取FLASH空间中的用户参数
*\Parameter     addr 0~MAX_PARA_LEN-1
*\Parameter     buf
*\Parameter     len
*\Return        u32
*\Note          
*\Log           2022.10.21    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 ReadFlashPara(u32 addr, u8* buf, u32 len);

#endif /*_UPDATE_H*/
