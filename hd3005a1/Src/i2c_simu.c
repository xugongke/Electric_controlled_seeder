/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          i2c_simu.c
*\Description   
*\Note          
*\Log           2019.07.06    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "i2c_simu.h"

#define SCL_LOW()    HAL_GPIO_WritePin(i2c->SclPort, i2c->SclPin, GPIO_PIN_RESET)
#define SCL_HIGH()   HAL_GPIO_WritePin(i2c->SclPort, i2c->SclPin, GPIO_PIN_SET)

#define SDA_LOW()    HAL_GPIO_WritePin(i2c->SdaPort, i2c->SdaPin, GPIO_PIN_RESET)
#define SDA_HIGH()   HAL_GPIO_WritePin(i2c->SdaPort, i2c->SdaPin, GPIO_PIN_SET)

static uint8_t ReadSDAPin(I2cSimuType* i2c)
{
    if(HAL_GPIO_ReadPin(i2c->SdaPort, i2c->SdaPin) == GPIO_PIN_RESET) {
        return 0;
    }
    else {
        return 1;
    }
}
 //uint16_t usTimeGet(void);
static void I2cDelayUs(uint16_t us)
{
   uint16_t i;
   uint16_t cur;
   i = usTimeGet();
   do 
   {
       cur = usTimeGet();
       cur = cur - i;
   } while ((cur) < us);
}
/***************************************************************************************************
*\Function      I2cSimuInit
*\Description   I2C初始化
*\Parameter     i2c
*\Return        uint8_t
*\Note          
***************************************************************************************************/
uint8_t I2cSimuInit(I2cSimuType* i2c)
{
    if (i2c == NULL){
        return 0;
    }
    if (i2c->InitFlag != 0) {
        return 0;
    }

    SDA_HIGH();
    SCL_HIGH();
    if (i2c->delay_us == 0){
        i2c->delay_us = 5; /*5us*2 默认100K*/
    }
    i2c->InitFlag++;

    return 0;
}


/* ********************************************************
**名称：I2C_Start
**功能：启动I2C
**输入：无
**返回：无
******************************************************* */
void I2C_Start(I2cSimuType* i2c)
{
    /*起始条件: SCL为高电平时,SDA由高变为低
    正常收发数据时, SCL为低电平时SDA数据变化
    */
    SDA_HIGH();
    I2cDelayUs(i2c->delay_us);
    SCL_HIGH();  /*保证SCL和SDA都为高电平*/
    I2cDelayUs(i2c->delay_us);
    SDA_LOW();
    I2cDelayUs(i2c->delay_us); /*延迟*/
    SCL_LOW();//钳位I2C总线，准备发送数据
}

/**********************************************************
**名称：I2C_Stop
**功能：停止I2C
**输入：无
**返回：无
**********************************************************/
void I2C_Stop(I2cSimuType* i2c)
{
    /*停止条件 SCL为高电平时, SDA由低变高*/
    SDA_LOW();
    I2cDelayUs(i2c->delay_us);
    SCL_HIGH();
    I2cDelayUs(i2c->delay_us);
    SDA_HIGH();
}

/********************************************************
**名称：Test_Ack()
**功能：检测应答位
1:表示检测成功   0:表示检测失败
*********************************************************/
uint8_t Test_Ack(I2cSimuType* i2c)
{ 
#if 0
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    GPIO_InitStruct.Pin = i2c->SdaPin;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    //HAL_GPIO_Init(i2c->SdaPort, &GPIO_InitStruct);
#endif
    uint8_t flag = 0;
    SCL_LOW();//时钟线变低, 从机开始准备应答数据    SCL=0;
    SDA_HIGH(); //读入数据

    I2cDelayUs(i2c->delay_us);
    if(ReadSDAPin(i2c)==0)
        flag = 1;
    else flag=0;
    SCL_HIGH();
    I2cDelayUs(i2c->delay_us);
    SCL_LOW();//
       // GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_OD;
      //  HAL_GPIO_Init(i2c->SdaPort, &GPIO_InitStruct);
    return (flag);
}

/********************************************************
**名称：SendData()  
**功能：发送一字节数据
**输入：buffer
**返回：
*******************************************************/
void I2CSendDataInter(I2cSimuType* i2c, uint8_t buffer)
{
    uint8_t i=0;//一字节8位
    uint8_t temp=0;
    temp=buffer;
    for (i = 0; i < 8; i++){
        SCL_LOW();
        if((temp&0x80) == 0){ //判断最高位是0还是1
            SDA_LOW();
        }
        else {
            SDA_HIGH();
        }
        I2cDelayUs(i2c->delay_us);
        SCL_HIGH();
        I2cDelayUs(i2c->delay_us);
        temp = temp << 1;
    }

    SCL_LOW(); /*准备接收应答数据*/
}

/***************************************************************************************************
*\Function      SendAck
*\Description   
*\Parameter     i2c
*\Parameter     ack  0: ack  1:nack
*\Return        void
*\Note          
***************************************************************************************************/
void SendAck(I2cSimuType* i2c, uint8_t ack)
{
    SCL_LOW(); /*准备发送应答数据*/
    if (ack == 0){
        /*发送ACK信号 低电平*/
        SDA_LOW();
    }
    else {
        /*发送NACK信号 高电平*/
        SDA_HIGH();
    }
    I2cDelayUs(i2c->delay_us);
    SCL_HIGH();
    I2cDelayUs(i2c->delay_us);
    SCL_LOW();
}

/********************************************************
**名称：RecvData()  
**功能：接收一字节数据
**输入：buffer
**返回：
*******************************************************/
static uint8_t RecvData(I2cSimuType* i2c)
{
    uint8_t BitCnt=8;//一字节8位
    uint8_t data = 0;
    for (BitCnt = 0; BitCnt < 8; BitCnt++){
        SCL_LOW();    /*MSB first*/
        SDA_HIGH();
        I2cDelayUs(i2c->delay_us);
        SCL_HIGH();
        data <<= 1;
        if (ReadSDAPin(i2c) == 1){
            data |= 1;
        }
        I2cDelayUs(i2c->delay_us);
    }

    SCL_LOW(); /*准备发送应答数据*/

    return data;
}

/***************************************************************************************************
*\Function      I2CSimuSendData
*\Description   
*\Parameter     i2c
*\Parameter     addr
*\Parameter     buf
*\Parameter     n
*\Return        uint8_t 1:发送成功  0:发送失败
*\Note          
***************************************************************************************************/
uint8_t I2CSimuSendData(I2cSimuType* i2c, uint8_t addr, uint8_t* inter_addr, uint8_t inter_addr_len, uint8_t* buf, uint16_t n)
{
    uint8_t i;
    if (i2c == NULL){
        return 0;
    }
    I2C_Start(i2c);//启动I2C
    I2CSendDataInter(i2c, addr & 0xFE);//先发送从地址+write
    if(Test_Ack(i2c) == 0) {
        I2C_Stop(i2c);
        return(0);
    }
    if (inter_addr_len != 0x00){
        /*发送内部寄存器地址*/
        for (i = 0; i < inter_addr_len; i++){
            I2CSendDataInter(i2c, inter_addr[i]);
            if(Test_Ack(i2c) == 0) {
                I2C_Stop(i2c);
                return (0);
            }
        }
    }
    /*发送有效数据*/
    for(i=0; i<n; i++) {
        I2CSendDataInter(i2c, buf[i]);
        if( Test_Ack(i2c) == 0) {
            I2C_Stop(i2c);
            return(0);
        }
    }

    I2C_Stop(i2c);
    return (1);
}

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
uint8_t I2CSimuRecvData(I2cSimuType* i2c, uint8_t addr, uint8_t* inter_addr, uint8_t inter_addr_len, uint8_t* buf, uint16_t n)
{
    uint32_t i;
    if (i2c == NULL){
        return 0;
    }

    if (inter_addr_len != 0x00)
    {
        I2C_Start(i2c);//启动I2C
        I2CSendDataInter(i2c, addr & 0xFE);//先发送从地址+write
        if(Test_Ack(i2c) == 0) {
            I2C_Stop(i2c);
            return(0);
        }
        /*发送内部寄存器地址*/
        for (i = 0; i < inter_addr_len; i++){
            I2CSendDataInter(i2c, inter_addr[i]);
            if(Test_Ack(i2c) == 0) {
                I2C_Stop(i2c);
                return (0);
            }
        }
    }

    I2C_Start(i2c);//启动I2C
    I2CSendDataInter(i2c, addr | 0x01);//发送器件地址 读
    if(Test_Ack(i2c) == 0) {
        I2C_Stop(i2c);
        return (0);
    }

    for(i=0; i<n; i++) {
        buf[i] = RecvData(i2c);
        if (i == (n-1)){
            /*最后一个字节发送NACK*/
            SendAck(i2c, 1);
        }
        else {
            SendAck(i2c, 0);
        }
    }

    I2C_Stop(i2c);
    return (1);
}
