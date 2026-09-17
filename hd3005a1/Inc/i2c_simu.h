/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          i2c_simu.h
*\Description   通用模拟I2C接口头文件定义
*\Note          1)需要将I2C的SCL SDA引脚初始化为开漏模式
*\Log           2019.07.06    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _I2C_SIMU_H
#define _I2C_SIMU_H
#include "main.h"
typedef struct i2c_simu_type_st{
    uint16_t       InitFlag;
    uint16_t       delay_us;  /*模拟I2C间隔*/

    GPIO_TypeDef*  SdaPort;
    GPIO_TypeDef*  SclPort;
    uint16_t       SdaPin;
    uint16_t       SclPin;
    //osSemaphoreId DevLock;   /*设备互斥信号量*/
}I2cSimuType;

#define I2C_SIMU_INIT(delay, sda_port, scl_port, sda_pin, scl_pin) {0, delay, sda_port, scl_port, sda_pin, scl_pin}


/***************************************************************************************************
*\Function      I2cSimuInit
*\Description   I2C初始化
*\Parameter     i2c
*\Return        u8
*\Note          
***************************************************************************************************/
uint8_t I2cSimuInit(I2cSimuType* i2c);

/***************************************************************************************************
*\Function      I2CSimuSendData
*\Description   
*\Parameter     i2c
*\Parameter     addr
*\Parameter     inter_addr
*\Parameter     inter_addr_len
*\Parameter     buf
*\Parameter     n
*\Return        uint8_t 1:发送成功  0:发送失败
*\Note          
***************************************************************************************************/
uint8_t I2CSimuSendData(I2cSimuType* i2c, uint8_t addr, uint8_t* inter_addr, uint8_t inter_addr_len, uint8_t* buf, uint16_t n);

/***************************************************************************************************
*\Function      I2CSimuRecvData
*\Description   
*\Parameter     i2c
*\Parameter     addr
*\Parameter     inter_addr
*\Parameter     inter_addr_len
*\Parameter     buf
*\Parameter     n
*\Return        uint8_t  1:成功  0:失败
*\Note          
***************************************************************************************************/
uint8_t I2CSimuRecvData(I2cSimuType* i2c, uint8_t addr, uint8_t* inter_addr, uint8_t inter_addr_len, uint8_t* buf, uint16_t n);

/*以下接口为内部使用接口, 针对非标准I2C设备可以自定义使用*/

/* ********************************************************
**名称：I2C_Start
**功能：启动I2C
**输入：无
**返回：无
******************************************************* */
void I2C_Start(I2cSimuType* i2c);

/**********************************************************
**名称：I2C_Stop
**功能：停止I2C
**输入：无
**返回：无
**********************************************************/
void I2C_Stop(I2cSimuType* i2c);

/********************************************************
**名称：SendData()  
**功能：发送一字节数据
**输入：buffer
**返回：
*******************************************************/
void I2CSendDataInter(I2cSimuType* i2c, uint8_t buffer);

/***************************************************************************************************
*\Function      SendAck
*\Description   
*\Parameter     i2c
*\Parameter     ack  0: ack  1:nack
*\Return        void
*\Note          
***************************************************************************************************/
void SendAck(I2cSimuType* i2c, uint8_t ack);


#endif /*_I2C_SIMU_H*/
