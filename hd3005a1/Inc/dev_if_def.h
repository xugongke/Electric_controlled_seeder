/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          dev_if_def.h
*\Description   设备通讯接口定义
*\Note          1)用于统一不同类型设备接口。
                2)针对无法统一设备定义特殊接口
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _DEV_IF_DEF_H
#define _DEV_IF_DEF_H
#include "type.h"


typedef void(*pCallBack)(void* para);   /*回调函数指针类型定义*/

/*设备通用接口 开始*/
typedef void* DevTypeHandle;

#define DEVICE_IF \
    u8* Name; /*设备名称*/\
    u8 (*Init)(DevTypeHandle dev);\
    void (*Close)(DevTypeHandle dev);\
    u32  InitFlag

typedef struct DeviceType_st
{
    DEVICE_IF;
}DeviceType;
#define DEVICE_IF_INIT NULL, NULL, NULL, 0x00

/*设备通用接口 结束*/

/*通讯接口抽象接口定义 开始*/
/*网络通讯  串口通讯都基于该抽象层*/
#define DEVICE_COMM_IF \
    DEVICE_IF;\
    u32 (*Send)(DevTypeHandle, u8* buf, u32 len);\
    u32  (*Recv)(DevTypeHandle, u8* buf, u32 len, bool clear);\
    u32  (*GetRecvLen)(DevTypeHandle);\
    u32  (*Del)(DevTypeHandle, u32 len);\
    u32  (*Clear)(DevTypeHandle)

typedef struct DeviceCommType_st
{
    DEVICE_COMM_IF;
}DeviceCommType;

#define DEVICE_COMM_IF_INIT DEVICE_IF_INIT,NULL,NULL,NULL,NULL,NULL
/*通讯接口抽象接口定义 结束*/


/*串口通讯接口定义   开始*/
typedef enum
{
    SOCKET_INVALID,
    SOCKET_CLIENT,
    SOCKET_SERVER
}SocketType;

typedef enum
{
    UART_USER_PARITY_NO,     /*无校验*/
    UART_USER_PARITY_ODD,    /*奇校验*/
    UART_USER_PARITY_EVEN,   /*偶校验*/
    UART_USER_PARITY_MARK,   /*!<MARK校验*/
    UART_USER_PARITY_SPACE   /*!<SPACE校验*/
}DRV_UART_PARITY;       /*UART的校验方式，具体值与平台有关*/

typedef enum
{
    UART_STB_1,    /*1停止位*/
    UART_STB_1_5,  /*1.5停止位*/
    UART_STB_2     /*2停止位*/
}DRV_UART_STB;  /*UART的停止位方式，具体值与平台有关*/

typedef enum
{
    UART_7D,
    UART_8D,            /*8位数据位*/
    UART_9D             /*9位数据位,不支持*/
}DRV_UART_DM;/*UART数据格式，具体值与平台有关*/

/*在本次实现中不提供UART的动态调整流控功能*/
#define DEVICE_COMM_UART_IF \
    DEVICE_COMM_IF;\
    u32  (*SetBaudRate)(DevTypeHandle, u32 baudrate);\
    void (*SetParity)(DevTypeHandle, DRV_UART_PARITY parity);\
    void (*SetStopBits)(DevTypeHandle, DRV_UART_STB stop_bit);\
    void (*SetDataBits)(DevTypeHandle, DRV_UART_DM data_bit);\
    void (*SendDoneHookCfg)(DevTypeHandle, void (*func)(void* para), void* para)

typedef struct DeviceCommUartType_st
{
    DEVICE_COMM_UART_IF;
}DeviceCommUartType;

#define DEVICE_COMM_UART_IF_INIT DEVICE_COMM_IF_INIT,NULL,NULL,NULL,NULL,NULL
/*串口通讯接口定义  结束*/

#endif /*_DEV_IF_DEF_H*/
