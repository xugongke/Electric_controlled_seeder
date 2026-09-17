/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          ee_24cxx.c
*\Description   支持AT24C01~AT24C16,通过TotalSize来限制最大大小
*\Note          1)1k 2k 页大小为8字节
                2)4k 8k 16k页大小为16字节  需要根据具体芯片型号修改页大小宏定义:AT24Cxx_PAGE_SIZE
                ATMLH144 2dc
*\Log           2019.07.07    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "ee_24cxx.h"
#include "main.h"
#include "cmsis_os.h"
#include "type.h"

#if (EE_24CXX_TOTAL_SIZE <= 256)
#define EE24Cxx_PAGE_SIZE 0x08 /*AT24Cxx一页的大小 1k 2k 页大小为8字节   4K 8K 16K大小为16字节*/
#elif (EE_24CXX_TOTAL_SIZE <= 2048)
#define EE24Cxx_PAGE_SIZE 0x10 
#else 
#error "EE_24CXX_TOTAL_SIZE error"
#endif

static osSemaphoreId EEDevLock;
osSemaphoreDef(EEDevLock);

uint8_t EE24cxxInitFlag;
I2cSimuType EE24cxxI2c = I2C_SIMU_INIT(5, EE_SDA_GPIO_Port, EE_SCL_GPIO_Port, EE_SDA_Pin, EE_SCL_Pin);

#define EE_I2C_DEV (&EE24cxxI2c)
#if FLASH_SIMU_EEPROM
#else 
/***************************************************************************************************
*\Function      GetDevWordAddr
*\Description   
*\Parameter     addr        字节地址
*\Parameter     dev_addr
*\Parameter     word_addr
*\Return        void
*\Note          
***************************************************************************************************/
static void GetDevWordAddr(uint16_t addr, uint8_t* dev_addr, uint8_t* word_addr)
{
    *dev_addr = EE24Cxx_ADDRESS| ((addr & 0x0700) >> 7);
    *word_addr = (addr&0xff);
}

/***************************************************************************************************
*\Function      At24c01PageWrite
*\Description   单页写数据
*\Parameter     at2c401 AT24C01设备配置信息结构体指针
*\Parameter     addr    要写的地址
*\Parameter     buf     写入数据首地址
*\Parameter     len     数据长度
*\Return        uint16_t     实际写入数据长度，若写入失败则返回0
*\Note          由于进行写操作时，写完当前页后，AT24C01内部的地址指针会回到当前页的第一个字节
*\Note          而不是下一页的第一个字节，所以最大的写操作不能超过页
*\Log           2011.05.23    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static uint16_t At24c01PageWrite(uint16_t addr, uint8_t* buf, uint16_t len)
{
    uint16_t result;
    uint8_t dev_addr = EE24Cxx_ADDRESS;
    uint8_t word_addr = 0;
    GetDevWordAddr(addr, &dev_addr, &word_addr);
    result = I2CSimuSendData(EE_I2C_DEV, dev_addr, &word_addr, 1, buf, len);
    /*等5MS,等待内部的写操作完成*/
    osDelay(6);
    return result;
}

/***************************************************************************************************
*\Function      At24c01Write
*\Description   AT24C01写数据
*\Parameter     at24c01 AT24C01设备配置信息结构体指针
*\Parameter     addr    要写的地址
*\Parameter     buf     写入数据首地址
*\Parameter     len     数据长度
*\Return        uint16_t     实际写入的数据长度
*\Note          该函数中实现分页写和参数的检查
*\Log           2011.05.23    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
static uint16_t At24c01Write(uint16_t addr, uint8_t* buf, uint16_t len)
{
    uint16_t i;   /*用于记录写入数据时剩余未写入的数据长度*/
    uint16_t temp;
    uint16_t result;

    i = len;
    /*写起始页的数据*/
    temp = addr % EE24Cxx_PAGE_SIZE;
    if (temp != 0x00)
    {
        /*要写的数据的长度可能写不满当前页*/
        temp = Min(EE24Cxx_PAGE_SIZE - temp, i);
        result = At24c01PageWrite(addr, buf, temp);
        if (result == 0x00){
            return 0x00;
        }
        addr += temp;
        buf += temp;
        i = len - temp;
    }

    /*写中间的页*/
    for (; i > EE24Cxx_PAGE_SIZE;){
        result = At24c01PageWrite(addr, buf, EE24Cxx_PAGE_SIZE);
        if (result == 0x00){
            return 0x00;
        }
        addr += EE24Cxx_PAGE_SIZE;
        buf += EE24Cxx_PAGE_SIZE;
        i -= EE24Cxx_PAGE_SIZE;
    }

    /*写剩余不足一页的数据*/
    if (i != 0x00){
        result = At24c01PageWrite(addr, buf, i);
        if (result == 0x00){
            return 0x00;
        }
    }

    return len;
}

/***************************************************************************************************
*\Function      At24c01Read
*\Description   读数据
*\Parameter     at24c01  AT24C01设备配置信息结构体指针
*\Parameter     addr    要读的地址
*\Parameter     buf     接收缓冲区首地址
*\Parameter     len     数据长度
*\Return        uint16_t     实际读取数据长度，若读失败则返回0
*\Note          读取数据时是可以进行连续的进行读的所以不用分页
***************************************************************************************************/
static uint16_t At24c01Read(uint16_t addr, uint8_t* buf, uint16_t len)
{
    uint16_t result = 0;
    uint8_t dev_addr = EE24Cxx_ADDRESS;
    uint8_t word_addr = 0;

    GetDevWordAddr(addr, &dev_addr, &word_addr);
    result =  I2CSimuRecvData(EE_I2C_DEV, dev_addr, &word_addr, 1, buf, len);
    if (result == 1){
        result = len;
    }
    return result;
}
#endif
/***************************************************************************************************
*\Function      EE24cxxInit
*\Description   
*\Parameter     
*\Return        uint8_t 1:成功 0:失败
*\Note          
***************************************************************************************************/
uint8_t EE24cxxInit(void)
{
    if (EE24cxxInitFlag != 0x00){
        return 1;
    }

    /*初始化用到的I2C设备*/
    I2cSimuInit(EE_I2C_DEV);
    /*申请设备互斥信号量*/
    EEDevLock = osSemaphoreCreate(osSemaphore(EEDevLock), 1);
    if (EEDevLock == NULL){
        DEAD_LOOP;
    }

    EE24cxxInitFlag++;
    return 1;
}

#if FLASH_SIMU_EEPROM
extern bool WriteFlashPara(u32 addr, u8* buf, u32 len);
extern u32 ReadFlashPara(u32 addr, u8* buf, u32 len);
#endif

/***************************************************************************************************
*\Function      EE24cxxWrite
*\Description   写一定长度的数据
*\Parameter     dev     AT24C01设备配置信息结构体指针
*\Parameter     addr    要写的地址
*\Parameter     buf     数据缓冲区首地址
*\Parameter     len     写入数据长度
*\Return        uint16_t     实际写入数据长度，若写入失败则返回0，否则返回len的值
*\Note
***************************************************************************************************/
uint16_t  EE24cxxWrite(uint16_t addr, uint8_t* buf, uint16_t len)
{
    uint16_t temp = 0x00;
    uint16_t time_out = 0x00;

    if ((EE24cxxInitFlag == 0x00) ||
        (len == 0x00)               ||
        (addr >= EE_24CXX_TOTAL_SIZE)  ||
        (len > EE_24CXX_TOTAL_SIZE)  ||
        ((addr + len) > EE_24CXX_TOTAL_SIZE)){
        return 0x00;
    }
    osSemaphoreWait(EEDevLock, osWaitForever);
#if FLASH_SIMU_EEPROM
     if (WriteFlashPara(addr, buf, len) == TRUE){
         temp = len;
     }
#else 
    do
    {
        /*失败重试*/
        time_out++;
        temp = At24c01Write(addr, buf, len);
    } while ((temp == 0x00) && (time_out < 2));
#endif
    osSemaphoreRelease(EEDevLock);
    return temp;
}


/***************************************************************************************************
*\Function      EE24cxxRead
*\Description   读数据
*\Parameter     addr    起始地址
*\Parameter     buf     接收缓冲区首地址
*\Parameter     len     要读的数据长度
*\Return        uint16_t     实际读取的数据长度
*\Note          若所要读取的数据长度或地址超出了当前的总容量则返回0
***************************************************************************************************/
uint16_t EE24cxxRead(uint16_t addr,  uint8_t* buf, uint16_t len)
{
    uint16_t temp = 0x00;
    uint16_t time_out = 0x00;
    if ((EE24cxxInitFlag == 0x00) ||
        (len == 0x00)               ||
        addr >= EE_24CXX_TOTAL_SIZE  ||
        (len > EE_24CXX_TOTAL_SIZE)  ||
        ((addr + len) > EE_24CXX_TOTAL_SIZE)){
            return 0x00;
    }

    osSemaphoreWait(EEDevLock, osWaitForever);
#if FLASH_SIMU_EEPROM
    temp = ReadFlashPara(addr, buf, len);
#else 
    do
    {
        time_out++;
        temp = At24c01Read(addr, buf, len);
    } while ((temp == 0x00) && (time_out < 2));
#endif
    osSemaphoreRelease(EEDevLock);

    return temp;
}


#if FLASH_SIMU_EEPROM

#else
uint8_t EEBuf[EE_24CXX_TOTAL_SIZE];
uint8_t EEReadBuf[EE_24CXX_TOTAL_SIZE];
void SPI_Flash_Init(void);
u16  SPI_Flash_ReadID(void);  	    //读取FLASH ID
u16 flash_id;
u32 EEErr;
void TestEEPROM(void const* para)
{
    uint16_t i;
    uint16_t cnt = 0;
    uint16_t len;
    uint16_t write_len;
    EE24cxxInit();
    while (1)
    {
        write_len = EE_24CXX_TOTAL_SIZE-3;
        for (i = 0; i < write_len; i++){
            EEBuf[i] = (u8)(i+cnt);
        }
        len = EE24cxxWrite(3, EEBuf+3, write_len);
        if (len != write_len){
            EEErr++;
        }
        len = EE24cxxRead(0, EEReadBuf, EE_24CXX_TOTAL_SIZE);
        for (i = 3; i < write_len; i++){
            if (EEReadBuf[i] != EEBuf[i]){
                EEErr++;
            }
        }
        cnt++;
        osDelay(1*1000);
    }
}
#endif

