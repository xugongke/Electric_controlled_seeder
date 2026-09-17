/***************************************************************************************************
*                    (c) Copyright 1992-2019 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          rx8025t.c
*\Description   
*\Note          
*\Log           2019.07.06    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "rx8025t.h"
#include "main.h"
#include "cmsis_os.h"
#include "string.h"
static osSemaphoreId DevLock;
osSemaphoreDef(DevLock);
uint8_t Rx8025InitFlag;
I2cSimuType Rx8025TI2c = I2C_SIMU_INIT(5, RX8025_SDA_GPIO_Port, RX8025_SCL_GPIO_Port, RX8025_SDA_Pin, RX8025_SCL_Pin);

#define I2C_DEV &Rx8025TI2c

 TIME TestTime;
 /*R8025T 寄存器地址*/
 typedef enum
 {
     RX8025T_REG_SEC = 0,
     RX8025T_REG_MIN,
     RX8025T_REG_HOUR,
     RX8025T_REG_WEEK_DAY,
     RX8025T_REG_MONTH_DAY,
     RX8025T_REG_MONTH,
     RX8025T_REG_YEAR,
     RX8025T_REG_RAM,
     RX8025T_REG_ALARM_MIN,
     RX8025T_REG_ALARM_HOUR,
     RX8025T_REG_ALARM_WEEKDAY,
     RX8025T_REG_TIMER_COUNT0,
     RX8025T_REG_TIMER_COUNT1,
     RX8025T_REG_EXTENSION,
     RX8025T_REG_FLAG,
     RX8025T_REG_CONTROL,
 }DRV_RX8025T_REG;

 typedef struct
 {
     uint8_t Seconds;     /*秒，00-59*/
     uint8_t Minutes;     /*分，00-59*/
     uint8_t Hours;       /*时，00-23*/
     uint8_t WeekDay;     /*周几*/
     uint8_t MonthDay;    /*日，01-31*/
     uint8_t Month;       /*月，01-12*/
     uint8_t Year;        /*年，00-99*/
 }DRV_RX8025T_TIME;   /*RX8025t所使用的时间类型*/

#define RX8025T_I2C_ADDR    0x64
 /*????*/
#define RX8025T_CSEL_HALF_SEC            0x00 //0.5s
#define RX8025T_CSEL_TWO_SEC             0x01 //2s
#define RX8025T_CSEL_TEN_SEC             0x02 //10s
#define RX8025T_CSEL_THIRTY_SEC          0x03 //30s

#define RX8025T_BIT_UIE             0x20 //???????
#define RX8025T_BIT_TIE             0x10 //???????
#define RX8025T_BIT_AIE             0x08 //???????
#define RX8025T_BIT_RESET           0x01 //??

#define RX8025T_BIT_VLF             0x02 //????????
#define RX8025T_BIT_VDET            0x01 //???????

#define RX8025T_BIT_32768HZ         0x00
#define RX8025T_BIT_USEL            0x20
#define RX8025T_BIT_UIE             0x20
 /***************************************************************************************************
 *\Function      RTCRx8025tGetTimeBCD
 *\Description   Rx8025T获取BCD格式时间
 *\Parameter     rx8025
 *\Parameter     time
 *\Return        bool
 *\Note
 *\Log           2012.03.22    Ver 1.0    张波
 *               创建函数。
 ***************************************************************************************************/
 static bool RTCRx8025tGetTimeBCD(TIME* time)
 {
     DRV_RX8025T_TIME rx8025_time = {0};
     uint8_t addr;

     addr = (uint8_t)(RX8025T_REG_SEC);

     /*读取rx8025t的内部寄存器的值*/
    I2CSimuRecvData(I2C_DEV, RX8025T_I2C_ADDR, &addr, 1, (uint8_t*)&rx8025_time, sizeof(rx8025_time));

     /*从RX8025T寄存器中读出的数据提取出时间*/
     time->TUn.TSt.Second = rx8025_time.Seconds & 0x7F;
     time->TUn.TSt.Minute = rx8025_time.Minutes & 0x7F;
     time->TUn.TSt.Hour   = rx8025_time.Hours & 0x3F;
     time->TUn.TSt.Day    = rx8025_time.MonthDay & 0x3F;
     time->TUn.TSt.Month  = rx8025_time.Month & 0x1F;
     time->TUn.TSt.Year   = rx8025_time.Year;

     /*检查时间的有效性*/
     if(TimeBCDCheck(time)){
         return TRUE;
     }
     else{
         return FALSE;
     }
 }
 
/***************************************************************************************************
*\Function      Rx8025tInit
*\Description   
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void Rx8025tInit(void)
{
    uint8_t rx8025t_reg,tmp_reg = 0;
    uint8_t addr =0;
    if (Rx8025InitFlag){
        return ;
    }
    I2cSimuInit(I2C_DEV);
   DevLock = osSemaphoreCreate(osSemaphore(DevLock), 1);
   if (DevLock == NULL){
       while (1);
   }
   RTCRx8025tGetTimeBCD(&TestTime);

   addr = (u8)(RX8025T_REG_FLAG);
   I2CSimuRecvData(I2C_DEV, RX8025T_I2C_ADDR, &addr, 1, &rx8025t_reg, 1);
   if (rx8025t_reg & RX8025T_BIT_VLF){
       //电池电压低,发出警告
       tmp_reg = (~RX8025T_BIT_VLF);
       I2CSimuSendData(I2C_DEV, RX8025T_I2C_ADDR, &addr, 1, &tmp_reg, 1);
   }
   if (rx8025t_reg & RX8025T_BIT_VDET)
   {
       //温补停止,发出警告
       tmp_reg = (~RX8025T_BIT_VDET);
       I2CSimuSendData(I2C_DEV, RX8025T_I2C_ADDR, &addr, 1, &tmp_reg, 1);
   }
   /*设置输出32.768KHz频率输出，FSEL0，1都为0即可,其他位一并设置为0，无影响*/
 
   Rx8025InitFlag++;
}

/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cGetBCD
*\Description   获取BCD格式时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tGetBCD(TIME* time)
{
    bool result;

    /*若未初始化返回FALSE*/
    if (Rx8025InitFlag == 0x00){
        return FALSE;
    }
    osSemaphoreWait(DevLock, osWaitForever);
    /*获取Rx8025的BCD格式的时间*/
    result = RTCRx8025tGetTimeBCD(time);
    osSemaphoreRelease(DevLock);
    return result;
}


/***************************************************************************************************
*\Function      RTCRx8025tSetTimeBCD
*\Description   Rx8025T设置BCD格式时间
*\Parameter     rx8025
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
static bool RTCRx8025tSetTimeBCD(TIME* time)
{
    DRV_RX8025T_TIME  rx8025_time = {0};
    uint8_t weekday = 0;
    u32 result;
    uint8_t addr = 0;

    if(!(TimeBCDCheck(time)))
    {   /*所设置的时间不合法，退出*/
        return FALSE;
    }
    /*检查时间合法*/
    rx8025_time.Seconds  = time->TUn.TSt.Second;
    rx8025_time.Minutes  = time->TUn.TSt.Minute;
    rx8025_time.Hours    = time->TUn.TSt.Hour;
    rx8025_time.MonthDay = time->TUn.TSt.Day;
    rx8025_time.Month    = time->TUn.TSt.Month;
    rx8025_time.Year     = time->TUn.TSt.Year;
    /*计算星期*/
    weekday = TimeBCDWeekDay(*time);
    if (weekday != 7){
        rx8025_time.WeekDay = 0x01 << weekday;
    }
    else{
        return FALSE;
    }

    addr = (uint8_t)(RX8025T_REG_SEC);

    result = I2CSimuSendData(I2C_DEV, RX8025T_I2C_ADDR, &addr, 1, (uint8_t*)&rx8025_time, sizeof(rx8025_time));
    if (result == 0x00){
        return FALSE;
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cSetBCD
*\Description   以BCD格式设置时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tSetBCD(TIME* time)
{
    bool result;
    /*若未初始化返回FALSE*/
    if (Rx8025InitFlag == 0x00){
        return FALSE;
    }
    osSemaphoreWait(DevLock, osWaitForever);
    result =  RTCRx8025tSetTimeBCD(time);
    osSemaphoreRelease(DevLock);

    return result;
}
/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cSetBCD
*\Description   以DEC格式设置时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tSetDEC(TIME* time)
{
    bool result;
    TIME tmp;
    memcpy(&tmp, time, sizeof(TIME));
    TimeDECToBCD(&tmp);
    /*若未初始化返回FALSE*/
    if (Rx8025InitFlag == 0x00){
        return FALSE;
    }
    osSemaphoreWait(DevLock, osWaitForever);
    result =  RTCRx8025tSetTimeBCD(&tmp);
    osSemaphoreRelease(DevLock);

    return result;
}
/***************************************************************************************************
*\Function      DeviceRTCRx8025tI2cSetBCD
*\Description   以DEC格式设置时间
*\Parameter     dev
*\Parameter     time
*\Return        bool
*\Note
***************************************************************************************************/
bool Rx8025tGetDEC(TIME* time)
{
    bool result;
    /*若未初始化返回FALSE*/
    if (Rx8025InitFlag == 0x00){
        return FALSE;
    }
    osSemaphoreWait(DevLock, osWaitForever);
    /*获取Rx8025的BCD格式的时间*/
    result = RTCRx8025tGetTimeBCD(time);
    result = TimeBCDToDEC(time);
    osSemaphoreRelease(DevLock);
    return result;
}

u32 RTCErr;
TIME RdTime;
TIME WrTime = {0x20, 0x08, 0x13, 0x14, 0x12, 0x00};
bool SetFlag;
TIME ConTime = {0x20, 0x08, 0x12, 0x17, 0x20, 0x55};
u32  TestStamp;
#include "ff_time.h"
time_t test_time;
FF_TimeStruct_t   systmtime;
#include "time.h"
struct  tm set_time;
/*初始化系统时钟*/
void InitSysTime(void)
{
    Rx8025tGetDEC(&ConTime);
    systmtime.tm_year = ConTime.TUn.TSt.Year+100;/*1900年开始时间*/
    systmtime.tm_mon  = ConTime.TUn.TSt.Month-1;  /*month 0~11*/
    systmtime.tm_mday = ConTime.TUn.TSt.Day;
    systmtime.tm_hour = ConTime.TUn.TSt.Hour;
    systmtime.tm_min  = ConTime.TUn.TSt.Minute;
    systmtime.tm_sec  = ConTime.TUn.TSt.Second;

    TestStamp = FreeRTOS_mktime(&systmtime);
    portENTER_CRITICAL();
    SysTime = TestStamp - (8*3600); //北京时间加8小时
    SecMsTick = 0;
    portEXIT_CRITICAL();
}

void SetSysTime(u32 sys_time)
{
    portENTER_CRITICAL();
    SysTime = sys_time;
    SecMsTick = 0;
    portEXIT_CRITICAL();
    test_time = sys_time + (8*3600);
    FreeRTOS_gmtime_r(&test_time, &systmtime);
    ConTime.TUn.TSt.Year = systmtime.tm_year - 100; /*1900年开始时间*/
    ConTime.TUn.TSt.Month = systmtime.tm_mon +1;    /*month 0~11*/
    ConTime.TUn.TSt.Day = systmtime.tm_mday;
    ConTime.TUn.TSt.Hour = systmtime.tm_hour;
    ConTime.TUn.TSt.Minute = systmtime.tm_min;
    ConTime.TUn.TSt.Second = systmtime.tm_sec ;
    Rx8025tSetDEC(&ConTime);
}
void Rx8025tTest(void)
{
    if (SetFlag != FALSE)
    {
        if (Rx8025tSetBCD(&WrTime) == FALSE) RTCErr++;
        SetFlag = FALSE;
    }

    if (Rx8025tGetBCD(&RdTime) == FALSE) RTCErr++;
    set_time.tm_sec = 55;
    set_time.tm_min = 20;
    set_time.tm_hour = 17;
    set_time.tm_mday = 12;
    set_time.tm_mon = 8-1;
    set_time.tm_year = 2020-1900;

    TestStamp = mktime(&set_time) - 8*3600;
    TimeBCDToDEC(&ConTime);
    systmtime.tm_year = ConTime.TUn.TSt.Year+100;/*1900年开始时间*/
    systmtime.tm_mon  = ConTime.TUn.TSt.Month-1;  /*month 0~11*/
    systmtime.tm_mday = ConTime.TUn.TSt.Day;
    systmtime.tm_hour = ConTime.TUn.TSt.Hour;
    systmtime.tm_min  = ConTime.TUn.TSt.Minute;
    systmtime.tm_sec  = ConTime.TUn.TSt.Second;

    TestStamp = FreeRTOS_mktime(&systmtime);
    SysTime = TestStamp - (8*3600); //北京时间加8小时
    test_time = SysTime + (8*3600);
    FreeRTOS_gmtime_r(&test_time, &systmtime);
    ConTime.TUn.TSt.Year = systmtime.tm_year - 100; /*1900年开始时间*/
    ConTime.TUn.TSt.Month = systmtime.tm_mon +1;    /*month 0~11*/
    ConTime.TUn.TSt.Day = systmtime.tm_mday;
    ConTime.TUn.TSt.Hour = systmtime.tm_hour;
    ConTime.TUn.TSt.Minute = systmtime.tm_min;
    ConTime.TUn.TSt.Second = systmtime.tm_sec ;
    Rx8025tSetDEC(&ConTime);
}
