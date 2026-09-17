/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          user_uart.h
*\Description   STM321XX系列UART驱动头文件
*\Note          1)利用HAL库封装应用层代码, 用于统一应用层代码编写风格
*\Log           2019.05.27    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _USER_UART_H
#define _USER_UART_H 
#include "cmsis_os.h"
#include "buf.h"
#include "main.h"
#include "dev_if_def.h"
#define PROC_SUCCESS 1
#define PROC_FAILED  0

#define RS485_CTRL_ENABLE 0  /*485电路控制引脚控制功能使能*/

/*各个串口使能*/
#define __UART1_ENABLE 
//#define __UART2_ENABLE 
//#define __UART3_ENABLE 
#define __UART4_ENABLE 
#define __UART5_ENABLE 
#define __UART6_ENABLE 

#define  DMA_ENABLE  1 /*DMA方式*/
#define  DMA_DISABLE 0 /*中断方式*/

#define RS485_RECV(port, pin) HAL_GPIO_WritePin(port, pin, GPIO_PIN_RESET)    /*低电平接收*/
#define RS485_SEND(port, pin) HAL_GPIO_WritePin(port, pin, GPIO_PIN_SET)    /*高电平发送*/

typedef struct UartUserType_st
{
    DEVICE_COMM_UART_IF;
    pCallBack SentDoneFunc; /*发送完成回调函数*/
    void* SentDonePara;     /*发送完成回调函数的参数*/
    UART_HandleTypeDef* huart;
    u8 DMAEnable;         /*0:中断  1:使用DMA   使用DMA时,须确保cube中配置对应的DMA*/
    u8 CtrlEnable;   /*485电路控制*/
    u16 RecvBufSize;   /*接收缓冲区大小*/
#if RS485_CTRL_ENABLE
    GPIO_TypeDef* CtrlPort;
    u16 CtrlPin;
#endif
    osSemaphoreId DevLock;   /*设备互斥信号量*/

    osSemaphoreId SendFlag; /*发送完成信号量*/

    BufType RecvBuf;        /*接收缓冲区*/
}UartUserType;

#if RS485_CTRL_ENABLE
#define USER_UART_INIT(huart, dma_use, rx_buf_size, CTRL_ENABLE, CTRL_PORT, CTRL_PIN) {DEVICE_COMM_UART_IF_INIT, NULL, NULL, huart, dma_use, CTRL_ENABLE, rx_buf_size, CTRL_PORT, CTRL_PIN, NULL, NULL}
#else 
#define USER_UART_INIT(huart, dma_use, rx_buf_size) {DEVICE_COMM_UART_IF_INIT, NULL, NULL, huart, dma_use, 0, rx_buf_size, NULL, NULL}
#endif


#ifdef __UART1_ENABLE
extern UartUserType UartUser1;
#endif
#ifdef __UART2_ENABLE
extern UartUserType UartUser2;
#endif
#ifdef __UART3_ENABLE
extern UartUserType UartUser3;
#endif
#ifdef __UART4_ENABLE
extern UartUserType UartUser4;
#endif
#ifdef __UART5_ENABLE
extern UartUserType UartUser5;
#endif
#ifdef __UART6_ENABLE
extern UartUserType UartUser6;
#endif
void UartTestTask(void const* para);

/***************************************************************************************************
*\Function      UartUserPtrInit
*\Description   初始化变量中的函数指针
*\Parameter     
*\Return        u8
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u8 UartUserPtrInit(DevTypeHandle h, u8* name);

/***************************************************************************************************
*\Function      UartUserInit
*\Description   初始化串口
*\Parameter     
*\Return        u8
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u8 UartUserInit(DevTypeHandle h);

/***************************************************************************************************
*\Function      DeviceUartStm32F1SetBaudRate
*\Description   设置UART的波特率。
*\Parameter     uart_stm32  标准UART模式的配置信息数据块的指针
*\Parameter     baud_rate   新的波特率
*\Return        u32         原来的波特率
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserSetBaudRate(DevTypeHandle dev, u32 baudrate);

/***************************************************************************************************
*\Function      DeviceUartStm32F1SendAdapter
*\Description   
*\Parameter     dev     URAT配置信息结构体指针
*\Parameter     buf     要发送的数据目的地址
*\Parameter     len     要发送的数据的长度
*\Return        bool    是否发生完成
*\Note
*\Log            2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserSend(DevTypeHandle dev, u8* buf, u32 len);

/***************************************************************************************************
*\Function      DeviceUartStm32F1Recv
*\Description   从接收缓冲区中获取数据。
*\Parameter     uart_stm32  UART配置信息结构体
*\Parameter     buf         获取数据的缓冲区的首地址
*\Parameter     len         要获取的数据长度
*\Parameter     clear       是否在读出数据后在缓冲区中将数据删除
*\Return        u32         实际获取的数据长度
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserRecv(DevTypeHandle dev, u8* buf, u32 len, bool clear);

/***************************************************************************************************
*\Function      UartUserGetDataLen
*\Description   获取当前接收缓冲区中的数据长度
*\Parameter     dev UART配置信息结构体指针
*\Return        u32 接收缓冲区中的有效数据长度
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserGetDataLen(DevTypeHandle dev);

/***************************************************************************************************
*\Function      UartUserDel
*\Description   删除缓冲区中的数据。
*\Parameter     uart_stm32  UART配置信息结构体指针
*\Parameter     len         要删除的数据长度
*\Return        u32         实际删除的数据长度
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserDel(DevTypeHandle dev, u32 len);

/***************************************************************************************************
*\Function      UartUserClear
*\Description   清空接收缓冲区。
*\Parameter     uart_stm32  UART配置信息结构体指针
*\Return        u32         实际删除的数据长度
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserClear(DevTypeHandle dev);

/***************************************************************************************************
*\Function      UartUserSetParity
*\Description   配置UART的校验方式。
*\Parameter     dev
*\Parameter     new_parity
*\Return        void
*\Note          
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
void UartUserSetParity(DevTypeHandle dev, DRV_UART_PARITY new_parity);


#endif /*_USER_UART_H*/
