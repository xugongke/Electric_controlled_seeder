/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          user_uart.c
*\Description   STM321XX系列UART驱动源文件
*\Note          1)利用HAL库封装应用层代码, 用于统一应用层代码编写风格
*\Note          2)增加新的串口时，需在HAL_UART_TxCpltCallback中增加对应UART的发送完成信号量释放函数
*\Log           2019.05.27    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "user_uart.h"
#include "stdlib.h"
#include "main.h"
pCallBack Uart1SentDoneFunc;
pCallBack Uart2SentDoneFunc;
pCallBack Uart3SentDoneFunc;
pCallBack Uart4SentDoneFunc;
pCallBack Uart5SentDoneFunc;
pCallBack Uart6SentDoneFunc;

void* Uart1SentDonePara;
void* Uart2SentDonePara;
void* Uart3SentDonePara;
void* Uart4SentDonePara;
void* Uart5SentDonePara;
void* Uart6SentDonePara;

#ifdef __UART3_ENABLE
extern UART_HandleTypeDef huart3;
#endif
#ifdef __UART4_ENABLE
extern UART_HandleTypeDef huart4;
#endif
#ifdef __UART5_ENABLE
extern UART_HandleTypeDef huart5;
#if RS485_CTRL_ENABLE
UartUserType UartUser5 = USER_UART_INIT(&huart5, DMA_DISABLE, 512, TRUE, RS485_CTRL2_GPIO_Port, RS485_CTRL2_Pin);
#else 
UartUserType UartUser5 = USER_UART_INIT(&huart5, DMA_DISABLE, 512);
#endif
#endif
#ifdef __UART1_ENABLE
extern UART_HandleTypeDef huart1;
#if RS485_CTRL_ENABLE
UartUserType UartUser1 = USER_UART_INIT(&huart1, DMA_DISABLE, 512, FALSE, NULL, GPIO_PIN_0);
#else
UartUserType UartUser1 = USER_UART_INIT(&huart1, DMA_DISABLE, 512);
#endif
#endif
#ifdef __UART2_ENABLE
extern UART_HandleTypeDef huart2;
#if RS485_CTRL_ENABLE
UartUserType UartUser2 = USER_UART_INIT(&huart2, DMA_DISABLE, 512, TRUE, RS485_CTR2_GPIO_Port, RS485_CTR2_Pin);
#else 
UartUserType UartUser2 = USER_UART_INIT(&huart2, DMA_DISABLE, 512);
#endif
#endif

#ifdef __UART3_ENABLE
extern UART_HandleTypeDef huart3;
#if RS485_CTRL_ENABLE
UartUserType UartUser3 = USER_UART_INIT(&huart3, DMA_DISABLE, 1500, TRUE, RS485_2_CTR_GPIO_Port, RS485_2_CTR_Pin);
#else
UartUserType UartUser3 = USER_UART_INIT(&huart3, DMA_DISABLE, 1500);
#endif
#endif

#ifdef __UART4_ENABLE
extern UART_HandleTypeDef huart4;
#if RS485_CTRL_ENABLE
UartUserType UartUser4 = USER_UART_INIT(&huart4, DMA_DISABLE, 1400, FALSE, NULL, GPIO_PIN_0);
#else 
UartUserType UartUser4 = USER_UART_INIT(&huart4, DMA_DISABLE, 1400);
#endif
#endif

#ifdef __UART6_ENABLE
extern UART_HandleTypeDef huart6;
#if RS485_CTRL_ENABLE
UartUserType UartUser6 = USER_UART_INIT(&huart6, DMA_DISABLE, 1400, TRUE, RS485_1_CTR_GPIO_Port, RS485_1_CTR_Pin);
#else 
UartUserType UartUser6 = USER_UART_INIT(&huart6, DMA_DISABLE, 1400);
#endif
#endif

/***************************************************************************************************
*\Function      ErrProcess
*\Description   
*\Parameter     huart
*\Return        uint8_t 0:不需要处理  1:需要处理
*\Note          
***************************************************************************************************/
uint8_t ErrProcess(UART_HandleTypeDef *huart)
{
    bool dma_enable = FALSE;
    
    switch ((u32)(huart->Instance))
    {
#ifdef __UART1_ENABLE
    case USART1_BASE:
        if (UartUser1.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        break;
#endif
#ifdef __UART2_ENABLE
    case USART2_BASE:
        if (UartUser2.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        break;
#endif
#ifdef __UART3_ENABLE
    case USART3_BASE:
        if (UartUser3.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        break;
#endif
#ifdef __UART4_ENABLE
    case UART4_BASE:
        if (UartUser4.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        break;
#endif
#ifdef __UART5_ENABLE
    case UART5_BASE:
        if (UartUser5.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        break;
#endif
#ifdef __UART6_ENABLE
    case USART6_BASE:
        if (UartUser6.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        break;
#endif
    default:
        break;
    }
    if (dma_enable == TRUE){
         return 0;
    }
    else  {
        return 1;
    }
}

/**
  * @brief  UART error callbacks.
  * @param  huart: pointer to a UART_HandleTypeDef structure that contains
  *                the configuration information for the specified UART module.
  * @retval None
  */
  void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
  /* Prevent unused argument(s) compilation warning */
  UNUSED(huart); 
  __HAL_UART_CLEAR_PEFLAG(huart);
  /* NOTE: This function Should not be modified, when the callback is needed,
           the HAL_UART_ErrorCallback could be implemented in the user file
   */ 
  bool dma_enable = FALSE;
  u8* buf_addr = NULL;
  UartUserType* usr_uart = NULL;
  switch ((u32)(huart->Instance))
  {
#ifdef __UART1_ENABLE
  case USART1_BASE:
      if (UartUser1.DMAEnable == TRUE) {
          dma_enable = TRUE;
      }
      buf_addr = (u8*)(UartUser1.RecvBuf.Addr);
      usr_uart = &UartUser1;
      break;
#endif
#ifdef __UART2_ENABLE
  case USART2_BASE:
      if (UartUser2.DMAEnable == TRUE) {
          dma_enable = TRUE;
      }
      buf_addr = (u8*)(UartUser2.RecvBuf.Addr);
      usr_uart = &UartUser2;
      break;
#endif
#ifdef __UART3_ENABLE
  case USART3_BASE:
      if (UartUser3.DMAEnable == TRUE) {
          dma_enable = TRUE;
      }
      buf_addr = (u8*)(UartUser3.RecvBuf.Addr);
      usr_uart = &UartUser3;
      break;
#endif
#ifdef __UART4_ENABLE
  case UART4_BASE:
      if (UartUser4.DMAEnable == TRUE) {
          dma_enable = TRUE;
      }
      buf_addr = (u8*)(UartUser4.RecvBuf.Addr);
      usr_uart = &UartUser4;
      break;
#endif
#ifdef __UART5_ENABLE
  case UART5_BASE:
      if (UartUser5.DMAEnable == TRUE) {
          dma_enable = TRUE;
      }
      buf_addr = (u8*)(UartUser5.RecvBuf.Addr);
      usr_uart = &UartUser5;
      break;
#endif
#ifdef __UART6_ENABLE
  case USART6_BASE:
      if (UartUser6.DMAEnable == TRUE) {
          dma_enable = TRUE;
      }
      buf_addr = (u8*)(UartUser6.RecvBuf.Addr);
      usr_uart = &UartUser6;
      break;
#endif
  default:
      break;
  }
  if (buf_addr == NULL){
      return ;
  }
  /*缓冲区满后, 继续从头开始记录数据*/
  if (dma_enable == FALSE) {
      /*UART5 使用中断方式*/
      //HAL_UART_Receive_IT(huart, buf_addr, usr_uart->RecvBufSize);
      /* Enable the UART Parity Error Interrupt */
      __HAL_UART_ENABLE_IT(huart, UART_IT_PE);
      /* Enable the UART Error Interrupt: (Frame error, noise error, overrun error) */
      __HAL_UART_ENABLE_IT(huart, UART_IT_ERR);
      /* Enable the UART Data Register not empty Interrupt */
      __HAL_UART_ENABLE_IT(huart, UART_IT_RXNE);
      huart->ErrorCode = HAL_UART_ERROR_NONE;
      huart->RxState = HAL_UART_STATE_BUSY_RX;

  }
  else {
       /* Enable the DMA channel */
      huart->ErrorCode = HAL_UART_ERROR_NONE;
      huart->RxState = HAL_UART_STATE_BUSY_RX;
      usr_uart->RecvBuf.WPos = 0;
      usr_uart->RecvBuf.RPos = 0;
    //tmp = (uint32_t*)&pData;
    HAL_DMA_Start_IT(huart->hdmarx, (uint32_t)&huart->Instance->DR, (u32)(usr_uart->RecvBuf.Addr), usr_uart->RecvBufSize);
    /* Enable the UART Parity Error Interrupt */
    //SET_BIT(huart->Instance->CR1, USART_CR1_PEIE);

    /* Enable the UART Error Interrupt: (Frame error, noise error, overrun error) */
    //SET_BIT(huart->Instance->CR3, USART_CR3_EIE);

    /* Enable the DMA transfer for the receiver request by setting the DMAR bit 
    in the UART CR3 register */
    SET_BIT(huart->Instance->CR3, USART_CR3_DMAR);
    //  HAL_UART_Receive_DMA(huart, buf_addr, usr_uart->RecvBufSize);  /*DMA模式下pRxBuffPtr指针不会变化*/
  }
  // CLEAR_BIT(huart->Instance->CR3, USART_CR3_EIE);
}
/**
* @brief  Tx Transfer completed callbacks.
* @param  huart: pointer to a UART_HandleTypeDef structure that contains
*                the configuration information for the specified UART module.
* @retval None
重构HAL 发送完成函数   中断和DMA方式都会调用该接口
*/
void HAL_UART_TxCpltCallback(UART_HandleTypeDef *huart)
{
    UartUserType* uart_h = NULL;
    /* Prevent unused argument(s) compilation warning */
    UNUSED(huart);
    /* NOTE: This function Should not be modified, when the callback is needed,
    the HAL_UART_TxCpltCallback could be implemented in the user file
    */ 
    switch ((u32)huart->Instance)
    {
#ifdef __UART1_ENABLE
    case USART1_BASE:
        if (Uart1SentDoneFunc != NULL) {
            Uart1SentDoneFunc(Uart1SentDonePara);
        }
        uart_h = &UartUser1;
        break;
#endif
#ifdef __UART2_ENABLE
    case USART2_BASE:
        if (Uart2SentDoneFunc != NULL) {
            Uart2SentDoneFunc(Uart2SentDonePara);
        }
        uart_h = &UartUser2;
        break;
#endif
#ifdef __UART3_ENABLE
    case USART3_BASE:
        if (Uart3SentDoneFunc != NULL) {
            Uart3SentDoneFunc(Uart3SentDonePara);
        }
        uart_h = &UartUser3;
        break;
#endif
#ifdef __UART4_ENABLE
    case UART4_BASE:
        if (Uart4SentDoneFunc != NULL) {
            Uart4SentDoneFunc(Uart4SentDonePara);
        }
        uart_h = &UartUser4;
        break;
#endif
#ifdef __UART5_ENABLE
    case UART5_BASE:
        if (Uart5SentDoneFunc != NULL) {
            Uart5SentDoneFunc(Uart5SentDonePara);
        }
        uart_h = &UartUser5;
        break;
#endif // __UART5_ENABLE
#ifdef __UART6_ENABLE
    case USART6_BASE:
        if (Uart6SentDoneFunc != NULL) {
            Uart6SentDoneFunc(Uart6SentDonePara);
        }
        uart_h = &UartUser6;
        break;
#endif // __UART6_ENABLE
    default:
        break;
    }

    if (uart_h != NULL){
        if (uart_h->InitFlag){
            osSemaphoreRelease(uart_h->SendFlag);
#if RS485_CTRL_ENABLE  /*485控制引脚*/
            if (uart_h->CtrlEnable == TRUE){
                RS485_RECV(uart_h->CtrlPort, uart_h->CtrlPin);
            }
#endif
        }
    }
}

/**
* @brief  Rx Transfer completed callbacks.
* @param  huart: pointer to a UART_HandleTypeDef structure that contains
*                the configuration information for the specified UART module.
* @retval None
* 重构接收缓冲区满函数
*/
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    bool dma_enable = FALSE;
    u8* buf_addr = NULL;
    UartUserType* usr_uart = NULL;
    switch ((u32)(huart->Instance))
    {
#ifdef __UART1_ENABLE
    case USART1_BASE:
        if (UartUser1.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        buf_addr = (u8*)(UartUser1.RecvBuf.Addr);
        usr_uart = &UartUser1;
        break;
#endif
#ifdef __UART2_ENABLE
    case USART2_BASE:
        if (UartUser2.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        buf_addr = (u8*)(UartUser2.RecvBuf.Addr);
        usr_uart = &UartUser2;
        break;
#endif
#ifdef __UART3_ENABLE
    case USART3_BASE:
        if (UartUser3.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        buf_addr = (u8*)(UartUser3.RecvBuf.Addr);
        usr_uart = &UartUser3;
        break;
#endif
#ifdef __UART4_ENABLE
    case UART4_BASE:
        if (UartUser4.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        buf_addr = (u8*)(UartUser4.RecvBuf.Addr);
        usr_uart = &UartUser4;
        break;
#endif
#ifdef __UART5_ENABLE
    case UART5_BASE:
        if (UartUser5.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        buf_addr = (u8*)(UartUser5.RecvBuf.Addr);
        usr_uart = &UartUser5;
        break;
#endif
#ifdef __UART6_ENABLE
    case USART6_BASE:
        if (UartUser6.DMAEnable == TRUE) {
            dma_enable = TRUE;
        }
        buf_addr = (u8*)(UartUser6.RecvBuf.Addr);
        usr_uart = &UartUser6;
        break;
#endif
    default:
        break;
    }
    if (buf_addr == NULL){
        return ;
    }
    /*缓冲区满后, 继续从头开始记录数据*/
    if (dma_enable == FALSE) {
        /*UART5 使用中断方式*/
        HAL_UART_Receive_IT(huart, buf_addr, usr_uart->RecvBufSize);
    }
    else {
        HAL_UART_Receive_DMA(huart, buf_addr, usr_uart->RecvBufSize);  /*DMA模式下pRxBuffPtr指针不会变化*/
    }
  // CLEAR_BIT(huart->Instance->CR3, USART_CR3_EIE);
}

/***************************************************************************************************
*\Function      UartUserItInit
*\Description   当前UART发送和接收使用中断方式时, 使用该接口用于初始化中断
*\Parameter     uart
*\Return        u8
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static u8 UartUserItInit(UartUserType* uart)
{
    /*使能UART中断方式接收*/
    HAL_UART_Receive_IT(uart->huart, (u8*)(uart->RecvBuf.Addr), uart->RecvBufSize);
    //CLEAR_BIT(uart->huart->Instance->CR3, USART_CR3_EIE);
    return 1;
}

/***************************************************************************************************
*\Function      UartUserDMAInit
*\Description   当前UART发送和接收使用中断方式时, 使用该接口用于初始化中断
*\Parameter     uart
*\Return        u8
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static u8 UartUserDMAInit(UartUserType* uart)
{
    /*使能UART中断方式接收*/
    HAL_UART_Receive_DMA(uart->huart, (u8*)(uart->RecvBuf.Addr), uart->RecvBufSize);
   // CLEAR_BIT(uart->huart->Instance->CR3, USART_CR3_EIE);
    return 1;
}
//hdma_usart1_rx.Instance->NDTR

/***************************************************************************************************
*\Function      UartUserInit
*\Description   初始化串口
*\Parameter     
*\Return        u8  0:失败  1:成功
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u8 UartUserInit(DevTypeHandle h)
{
    UartUserType* uart = (UartUserType*)h;

    u8* buf;
    if (uart == NULL){
        return 0;
    }

    if (uart->InitFlag != 0) {
        /*已经初始化*/
        return PROC_SUCCESS;
    }

    /*初始化*/
    /*申请接收缓冲区*/
    buf = (u8*)malloc(sizeof(u8) * uart->RecvBufSize);
    if (buf == NULL) {
        while (1);
    }
    uart->RecvBuf = BufInit(buf, uart->RecvBufSize, BUF_MODE_CYCLE);
    /*申请互斥信号量*/
    uart->DevLock = osSemaphoreCreate(NULL, 1);
    /*申请数据发送完成标志信号量*/
    uart->SendFlag = osSemaphoreCreate(NULL, 1);
    if (uart->SendFlag == NULL) {
        while (1);
    }
    osSemaphoreWait(uart->SendFlag, 1);

    if (uart->DMAEnable == TRUE) {
        UartUserDMAInit(uart);
    }
    else {
        UartUserItInit(uart);
    }

#if RS485_CTRL_ENABLE
    if (uart->CtrlEnable == TRUE) {
        if (uart->CtrlPort == NULL){
            while (1);
        }
        RS485_RECV(uart->CtrlPort, uart->CtrlPin);
    }
#endif

    uart->InitFlag++;

    return PROC_SUCCESS;
}

static void GetRXWPos(UartUserType* uart_stm32)
{
    if (uart_stm32->DMAEnable == TRUE){
        /*接收数据时，需要根据DMA中的DMA_SxNDTR来计算实际接收的数据长度为多少*/
        uart_stm32->RecvBuf.WPos = uart_stm32->RecvBuf.Size - uart_stm32->huart->hdmarx->Instance->NDTR;
    }
    else {
        uart_stm32->RecvBuf.WPos = (u32)(uart_stm32->huart->pRxBuffPtr) - (u32)uart_stm32->RecvBuf.Addr;//uart_stm32->RecvBuf.Size - uart_stm32->huart->RxXferCount;
    }
}

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
u32 UartUserRecv(DevTypeHandle dev, u8* buf, u32 len, bool clear)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;
    u32 recv_len;
    //u32 i;
    if (uart_stm32->InitFlag == 0x00){
        return 0x00;
    }

    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
    GetRXWPos(uart_stm32);
    recv_len = BufGetData(&uart_stm32->RecvBuf, buf, 0, len);

    if (clear == TRUE) {
        BufDelHeadData(&uart_stm32->RecvBuf, recv_len);
    }

    /*@todo 处理7位数据位数据接收问题*/
    //     if ((uart_stm32->DMAEnable == TRUE) && (uart_stm32->DataMode == UART_7D)) {
    //         for (i = 0; i < recv_len; i++){
    //             buf[i] &= 0x7f;
    //         }
    //     }
    osSemaphoreRelease(uart_stm32->DevLock);

    return recv_len;
}

/***************************************************************************************************
*\Function      UartUserGetDataLen
*\Description   获取当前接收缓冲区中的数据长度
*\Parameter     dev UART配置信息结构体指针
*\Return        u32 接收缓冲区中的有效数据长度
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserGetDataLen(DevTypeHandle dev)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;
    u32 result;
    if (uart_stm32->InitFlag == 0x00) {
        return 0x00;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
    GetRXWPos(uart_stm32);
    result = BufGetDataLen(&uart_stm32->RecvBuf);
    osSemaphoreRelease(uart_stm32->DevLock);
    return result;
}

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
u32 UartUserDel(DevTypeHandle dev, u32 len)
{
    u32 result;
    UartUserType* uart_stm32 = (UartUserType*)dev;
    if (uart_stm32->InitFlag == 0x00){
        return 0x00;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
    GetRXWPos(uart_stm32);
    result = BufDelHeadData(&uart_stm32->RecvBuf, len);
    osSemaphoreRelease(uart_stm32->DevLock);
    return result;
}

/***************************************************************************************************
*\Function      UartUserClear
*\Description   清空接收缓冲区。
*\Parameter     uart_stm32  UART配置信息结构体指针
*\Return        u32         实际删除的数据长度
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u32 UartUserClear(DevTypeHandle dev)
{
    u32 result;
    UartUserType* uart_stm32 = (UartUserType*)dev;
    if (uart_stm32->InitFlag == 0x00) {
        return 0x00;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
    GetRXWPos(uart_stm32);
    result = BufClearData(&uart_stm32->RecvBuf);
    osSemaphoreRelease(uart_stm32->DevLock);

    return result;
}

/***************************************************************************************************
*\Function      GetSendTime
*\Description   获取UART发送完成需要时间
*\Parameter     uart
*\Parameter     data_len
*\Return        u32
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static u32 GetSendTime(UartUserType* uart, u16 data_len)
{
    u32 time = 0;       /*连续发送数据需要的时间*/

    time = ((data_len * 13) * 1000) / (uart->huart->Init.BaudRate);

    return (time + 30);
}

u32 UartUserSendIt(UartUserType* uart, u8* buf, u32 len)
{
    int32_t res;
    HAL_UART_Transmit_IT(uart->huart, buf, len);
    res = osSemaphoreWait(uart->SendFlag, GetSendTime(uart, len));
    if (res == osOK){
        return len;
    }

    return 0;
}

u32 UartUserSendDMA(UartUserType* uart, u8* buf, u32 len)
{
    int32_t res;
    HAL_UART_Transmit_DMA(uart->huart, buf, len);
    res = osSemaphoreWait(uart->SendFlag, GetSendTime(uart, len));
    if (res == osOK){
        return len;
    }

    return 0;
}

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
u32 UartUserSend(DevTypeHandle dev, u8* buf, u32 len)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;
    u32 result = 0;

    if (uart_stm32->InitFlag == 0x00) {
        return FALSE;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
#if RS485_CTRL_ENABLE
    if (uart_stm32->CtrlEnable == TRUE) {
        RS485_SEND(uart_stm32->CtrlPort, uart_stm32->CtrlPin);
    }
#endif
    if (uart_stm32->DMAEnable == TRUE) {
        result = UartUserSendDMA(uart_stm32, buf, len);
    }
    else {
        result = UartUserSendIt(uart_stm32, buf, len);
    }
#if RS485_CTRL_ENABLE
    if (uart_stm32->CtrlEnable == TRUE) {
        RS485_RECV(uart_stm32->CtrlPort, uart_stm32->CtrlPin);
    }
#endif
    osSemaphoreRelease(uart_stm32->DevLock);

    return result;
}

/***************************************************************************************************
*\Function      UartUserSendDoneHookCfg
*\Description   配置发送完成后需要进行的操作函数。
*\Parameter     uart_stm32  UART配置信息结构体
*\Parameter     handler     数据发送完成后要调用的函数接口
*\Parameter     para        数据发送完成后要调用的函数的参数
*\Return        void
*\Note
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
void UartUserSendDoneHookCfg(DevTypeHandle dev, pCallBack func, void* para)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;
    if (uart_stm32->InitFlag != 0) {
        osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
    }
    switch ((u32)(uart_stm32->huart->Instance))
    {
    case USART1_BASE:
        Uart1SentDoneFunc = func;
        Uart1SentDonePara = para;
        break;
    case USART2_BASE:
        Uart2SentDoneFunc = func;
        Uart2SentDonePara = para;
        break;
    case USART3_BASE:
        Uart3SentDoneFunc = func;
        Uart3SentDonePara = para;
        break;
    #ifdef __UART4_ENABLE
    case UART4_BASE:
        Uart4SentDoneFunc = func;
        Uart4SentDonePara = para;
        break;
    #endif
    #ifdef __UART5_ENABLE
    case UART5_BASE:
        Uart5SentDoneFunc = func;
        Uart5SentDonePara = para;
        break;
    #endif
    default:
        break;
    }

    if (uart_stm32->InitFlag != 0) {
        osSemaphoreRelease(uart_stm32->DevLock);
    }
}

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
u32 UartUserSetBaudRate(DevTypeHandle dev, u32 baudrate)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;

    if (baudrate == (uart_stm32->huart->Init.BaudRate)) {
        /*若波特率和原来的相同则不进行设置直接返回*/
        return baudrate;//TRUE;
    }
    uart_stm32->huart->Init.BaudRate = baudrate;
    HAL_UART_Init(uart_stm32->huart);
    if (uart_stm32->InitFlag == 0){
        return baudrate;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);
    if (uart_stm32->DMAEnable == TRUE) {
        UartUserDMAInit(uart_stm32);
    }
    else {
        UartUserItInit(uart_stm32);
    }
    GetRXWPos(uart_stm32);
    BufClearData(&uart_stm32->RecvBuf);

    osSemaphoreRelease(uart_stm32->DevLock);
    return baudrate;
}

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
void UartUserSetParity(DevTypeHandle dev, DRV_UART_PARITY new_parity)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;

    uint32_t hal_parity = UART_PARITY_NONE;

    if (new_parity == UART_USER_PARITY_NO){
        hal_parity = UART_PARITY_NONE;
    }
    else if (new_parity == UART_USER_PARITY_ODD){
        hal_parity = UART_PARITY_ODD;
    }
    else if (new_parity == UART_USER_PARITY_EVEN){
        hal_parity = UART_PARITY_EVEN;
    }

    if (hal_parity == (uart_stm32->huart->Init.Parity)) {
        /*若波特率和原来的相同则不进行设置直接返回*/
        return;// hal_parity;//TRUE;
    }
    if (hal_parity != UART_PARITY_NONE){
        uart_stm32->huart->Init.WordLength = UART_WORDLENGTH_9B;
    }
    else {
        uart_stm32->huart->Init.WordLength = UART_WORDLENGTH_8B;
    }
    uart_stm32->huart->Init.Parity = hal_parity;
    HAL_UART_Init(uart_stm32->huart);
    if (uart_stm32->InitFlag == 0){
        return ;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);

    if (uart_stm32->DMAEnable == TRUE) {
        UartUserDMAInit(uart_stm32);
    }
    else {
        UartUserItInit(uart_stm32);
    }
    GetRXWPos(uart_stm32);
    BufClearData(&uart_stm32->RecvBuf);

    osSemaphoreRelease(uart_stm32->DevLock);
    return ;
}

/***************************************************************************************************
*\Function      UartUserSetStopBit
*\Description   配置UART的停止位。
*\Parameter     dev
*\Parameter     new_parity
*\Return        void
*\Note          
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static void UartUserSetStopBit(DevTypeHandle dev, DRV_UART_STB stopbit)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;

    u32 new_stopbit = UART_STOPBITS_1;

    switch (stopbit)
    {
    case UART_STB_1:
        new_stopbit = UART_STOPBITS_1;
        break;
    case UART_STB_1_5:
        new_stopbit = UART_STOPBITS_1;
        break;
    case UART_STB_2:
        new_stopbit = UART_STOPBITS_2;
        break;
    default:
        new_stopbit = UART_STOPBITS_1;
        break;
    }

    if (new_stopbit == (uart_stm32->huart->Init.StopBits)) {
        /*若波特率和原来的相同则不进行设置直接返回*/
        return;// hal_parity;//TRUE;
    }
    uart_stm32->huart->Init.StopBits = new_stopbit;
    HAL_UART_Init(uart_stm32->huart);
    if (uart_stm32->InitFlag == 0){
        return;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);

    if (uart_stm32->DMAEnable == TRUE) {
        UartUserDMAInit(uart_stm32);
    }
    else {
        UartUserItInit(uart_stm32);
    }
    GetRXWPos(uart_stm32);
    BufClearData(&uart_stm32->RecvBuf);

    osSemaphoreRelease(uart_stm32->DevLock);
    return ;
}

/***************************************************************************************************
*\Function      DeviceUartStm32F1SetDataMode
*\Description   配置uart的数据格式
*\Parameter     dev
*\Parameter     data_mode
*\Return        void
*\Note          
*\Log           2017.09.14    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static void UartUserSetDataMode(DevTypeHandle dev, DRV_UART_DM data_mode)
{
    UartUserType* uart_stm32 = (UartUserType*)dev;

    u32 new_data_mode = UART_WORDLENGTH_8B;

    switch (data_mode)
    {
    case UART_7D:
        new_data_mode = UART_WORDLENGTH_8B;  /*不支持7位数据模式, 若是可以灵活变通为8位数据位, 无校验 1位停止位, 应用层将每个字节的最高位置为0*/
        break;
    case UART_8D:
        new_data_mode = UART_WORDLENGTH_8B;
        break;
    case UART_9D:
        new_data_mode = UART_WORDLENGTH_9B;
        break;
    default:
        break;
    }

    if (new_data_mode == (uart_stm32->huart->Init.WordLength)) {
        /*若波特率和原来的相同则不进行设置直接返回*/
        return;// hal_parity;//TRUE;
    }
    uart_stm32->huart->Init.WordLength = new_data_mode;
    HAL_UART_Init(uart_stm32->huart);
    if (uart_stm32->InitFlag == 0){
        return ;
    }
    osSemaphoreWait(uart_stm32->DevLock, osWaitForever);

    if (uart_stm32->DMAEnable == TRUE) {
        UartUserDMAInit(uart_stm32);
    }
    else {
        UartUserItInit(uart_stm32);
    }
    GetRXWPos(uart_stm32);
    BufClearData(&uart_stm32->RecvBuf);

    osSemaphoreRelease(uart_stm32->DevLock);
    return ;
}

void UartUserClose(DevTypeHandle dev)
{

}

/***************************************************************************************************
*\Function      UartUserPtrInit
*\Description   初始化变量中的函数指针
*\Parameter     
*\Return        u8
*\Note          
*\Log           2019.05.28    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
u8 UartUserPtrInit(DevTypeHandle h, u8* name)
{
    UartUserType* uart_stm32 = (UartUserType*)h;
    uart_stm32->Name             = name;
    uart_stm32->Init             = UartUserInit;
    uart_stm32->Send             = UartUserSend;
    uart_stm32->Recv             = UartUserRecv;
    uart_stm32->GetRecvLen       = UartUserGetDataLen;
    uart_stm32->Del              = UartUserDel;
    uart_stm32->Clear            = UartUserClear;
    uart_stm32->SetBaudRate      = UartUserSetBaudRate;
    uart_stm32->SetParity        = UartUserSetParity;
    uart_stm32->SetStopBits      = UartUserSetStopBit;
    uart_stm32->SetDataBits      = UartUserSetDataMode;
    uart_stm32->SendDoneHookCfg  = UartUserSendDoneHookCfg;
    uart_stm32->Close            = UartUserClose;

    return 1;
}
u8 Uart6RecvBuf[512];
u8 Uart5SendBuf[100];
u8 Uart1RecvBuf[512];
u8 Uart2RecvBuf[512];
u8 Uart3RecvBuf[512];
u8 Uart4RecvBuf[512];

/*485接口时，发送完成后，切换为接收状态*/

void UartIrqSimuTask(void* para);
void __aeabi_assert(const char* str, const char* str1, int l)
{
  while(1);
}
u8 Uart1RecvBuf[512];
#define TEST_COM_DEV (&UartUser4)
void UartTestTask(void const* para)
{
    u32 len;
#if 1
    UartUserInit(TEST_COM_DEV);
    //UartUserInit(&UartUser2);
    //UartUserInit(&UartUser3);

    //UartUserSendDoneHookCfg(&UartUser5, Uart5SentDone, NULL);
    //UartUserSetParity(&UartUser5, UART_USER_PARITY_NO);
    //UartUserSetBaudRate(&UartUser2, 9600);
#endif

    osDelay(100);
    while (1)
    {
#if 1
        len = UartUserGetDataLen(TEST_COM_DEV);
        osDelay(5);
        if ((len == UartUserGetDataLen(TEST_COM_DEV)) && (len != 0)) {
                len = UartUserRecv(TEST_COM_DEV, Uart1RecvBuf, sizeof(Uart1RecvBuf), TRUE);
               UartUserSend(TEST_COM_DEV, Uart1RecvBuf, len);
        }
        //UartUserSend(&UartUser3, "hello world", 11);
#endif
        osThreadYield();
    }
}
