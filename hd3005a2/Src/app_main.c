#include "main.h"
#include "cmsis_os.h"
#include "type.h"
#include "stdlib.h"
#include "string.h"
#include "user_uart.h"
#include "rx8025t.h"
#include "ee_24cxx.h"
#include "update.h"
#include "ff_time.h"
#include "para.h"
#include "operation.h"
#include "motor.h"
#include "work_proc.h"
#define GS_FILTER_TIME 300 /*钢索触发滤波时间 单位:ms*/

void  IOProcessTask(void const* para);
extern osThreadId defaultTaskHandle;
u32 SysTime;    //系统时间
u32 SecMsTick;  /*每秒内毫秒计数*/
u32 LXBZCnt; //连续播种电机测速计数
#if BD_SIMU_TEST
u8 AppVersions[] = "hd3005a2_test v1.7 20260820";
#else 
u8 AppVersions[] = "hd3005a2 v1.7 20260820_2";
#endif
u8 AppErrVersion[] = "hd3005a1 err v1.0";

u32 DzStartTime;
u32 YLZStartTime;

u8 InitKey;          /*一键初始化 0:未按下  1:按下*/
u8 LastInitKey;      /*一键初始化,用于判断开关状态变化*/
u8 InitKeyFilter;    /*一键初始化滤波计数*/
u8 InitKeyValid;     /*记录一次有效的一键初始化*/

extern TIM_HandleTypeDef htim6;
// uint16_t usTimeGet(void){
//     return __HAL_TIM_GET_COUNTER(&htim6);
// }

int fputc(int ch, FILE *f)
{
    /* 将Printf内容发往串口 */
    UartUserSend(&UartUser5, (u8*)&ch, 1);
    return 0;
}

void AppMain(void const * para)
{
    UartUserInit(&UartUser1); //115200 8-N-1波特率
    UartUserInit(&UartUser4); //115200 8-N-1波特率
    UartUserInit(&UartUser5); //115200 8-N-1波特率
    UartUserInit(&UartUser6); //115200 8-N-1波特率

    EE24cxxInit();
    ParaInit();
    /*电机控制*/
    osThreadDef(motor_task, StepMotorCtrlTask, osPriorityNormal, 0, 256);
    defaultTaskHandle = osThreadCreate(osThread(motor_task), NULL);
    /*输入输出控制*/
    osThreadDef(iotask, IOProcessTask, osPriorityNormal, 0, 256);
    defaultTaskHandle = osThreadCreate(osThread(iotask), NULL);
    /*北斗模块协议解析*/
    osThreadDef(lcdtask, BdAnalysisTask, osPriorityNormal, 0, 256);
    defaultTaskHandle = osThreadCreate(osThread(lcdtask), NULL);
    /*播种机核心控制任务*/
    osThreadDef(mainstate, WorkProcTask, osPriorityNormal, 0, 256);
    defaultTaskHandle = osThreadCreate(osThread(mainstate), NULL);
    /*平板协议解析*/
    osThreadDef(uarttask, ProtocolAnalysisTask, osPriorityNormal, 0, 256);
    defaultTaskHandle = osThreadCreate(osThread(uarttask), NULL);
    while (1)
    {
        osDelay(20);
        if ((Updateing == TRUE) || (SysReset == TRUE)){
            osDelay(500);
            /*程序升级, 重启处理器*/
            HAL_NVIC_SystemReset();
        }
    }
}

time_t FreeRTOS_time( time_t *pxTime )
{
    time_t uxTime;
    uxTime = SysTime;
    if( pxTime != NULL )
    {
        *pxTime = uxTime;
    }
    return uxTime;
}
/**
* @brief  Get the value of the Kernel timer in ms
* @param  None
* @retval None
* @note   MUST REMAIN UNCHANGED: \b osKernelSysTick shall be consistent in every CMSIS-RTOS.
*/
uint32_t osTimeGet(void)
{
    //return osKernelSysTick()*(1000/configTICK_RATE_HZ);
    return uwTick*(1000/configTICK_RATE_HZ);
}

void HAL_Delay(uint32_t Delay)
{
    uint32_t tickstart = HAL_GetTick();
    uint32_t wait = Delay;

    /* Add a period to guaranty minimum wait */
    if (wait < HAL_MAX_DELAY){
        wait++;
    }

    while((HAL_GetTick() - tickstart) < wait){
        //feed_dog();
    }
}

#if 1
void HAL_IncTick(){
    uwTick += uwTickFreq;
    if (SecMsTick >= (configTICK_RATE_HZ-1)){
        SecMsTick = 0;
        SysTime++;/*系统秒时间戳加1*/
        EncoderSpeedCalc();
    }
    else {
        SecMsTick++;
        if ((SecMsTick % 200) == 0){
            EncoderSpeedCalc();
        }
    }
}
#endif

/**
* @brief  EXTI line detection callbacks.
* @param  GPIO_Pin: Specifies the pins connected EXTI line
* @retval None
*/
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    uint32_t curr_time = osTimeGet();
    /* Prevent unused argument(s) compilation warning */
    UNUSED(GPIO_Pin);
    /* NOTE: This function Should not be modified, when the callback is needed,
    the HAL_GPIO_EXTI_Callback could be implemented in the user file
    */
    switch (GPIO_Pin)
    {
    case IN6_Pin:
        LouzhongCnt[0]++;
        break;
    case IN4_Pin:
        LouzhongCnt[1]++;
        break;
    case IN19_Pin:
        LouzhongCnt[2]++;
        break;
    case IN20_Pin:
        LouzhongCnt[3]++;
        break;
    case IN12_Pin:
        LoufeiCnt[0]++;
        break;
    case IN13_Pin:
        LoufeiCnt[1]++;
        break;
    case IN1_Pin:
        LoufeiCnt[2]++;
        break;
    case IN2_Pin:
        LoufeiCnt[3]++;
        break;
    case IN21_Pin:
        if ((curr_time - BdTrigTime) >= GS_FILTER_TIME){
            BeidouStartTrigCnt++;
            BdTrigTime = curr_time;
        }//
        break;
#if LINE_NUM > 4
    case IN24_Pin:
        LouzhongCnt[5]++;
        break;
    case IN23_Pin:
        LouzhongCnt[4]++;
        break;
    case IN16_Pin:
        LoufeiCnt[5]++;
        break;
    case IN22_Pin:
        LoufeiCnt[4]++;
        break;
#endif
    default:
        break;
    }
}

#define LED_COMM_DEV (&UartUser1)
u8 DisBoardBuf[64];
u32 LEDDelay = 15; //闪烁时间  单位ms
u32 LedTestCnt[12];
u32 DisBoardFlushTime; /*刷新显示板起始时间*/
void FlushLEDDisBoard(void)
{
    u32 len;
    u32 i;
#if 1
    /*@todo 将数据刷新到显示控制板*/
    for (i = 0; i < LINE_NUM; i++)
    {
        DisLEDCnt[0+i] = LouzhongCnt[i];//漏种计数
        DisLEDCnt[LINE_NUM+i] = LoufeiCnt[i];//漏肥计数
        //DisLEDCnt[8+i] = 0;
    }
#else
    u32 i;
    for (i = 0; i < 12; i++){
        LedTestCnt[i] += 1;
        DisLEDCnt[i] = LedTestCnt[i];
    }
#endif
    memcpy(DisBoardBuf+4, DisLEDCnt, 48);
    memcpy(DisBoardBuf+4+48, &LEDDelay, 4);
    /*漏种漏肥共8路u32数据, 还有4个灯直接控制状态*/
    len = FrameConstruct(DisBoardBuf, FNC_SET_LED_CNT, DisBoardBuf+4, 48+4);
    UartUserClear(LED_COMM_DEV);
    len = UartUserSend(LED_COMM_DEV, DisBoardBuf, len);
}

/***************************************************************************************************
*\Function      IOProcessTask
*\Description   输入输出定期处理
*\Parameter     para
*\Return        void
*\Note          
***************************************************************************************************/
void  IOProcessTask(void const* para)
{
    GetInputState();
    
    DEAD_LOOP{
        /*电瓶电压采集*/
        AdcProcFunc();
        GetInputState();
        /*一键初始化按钮*/
        if ((InitKey != 0) && (LastInitKey == 0)){
            if (InitKeyFilter < 240){
                InitKeyFilter++;
            }
        }
        else if (InitKey == 0){
            if ((InitKeyFilter >= 6)){ //释放按钮时响应 
                InitKeyValid = 1;
            }
            InitKeyFilter = 0;
            LastInitKey = InitKey; 
        }

        /*脚踏板处理 喇叭*/
        if (WorkMode != WORK_MODE_TEST){//非测试模式下同步脚踏板及喇叭状态
            if (TBInputState == 1){
                LB_ON();
            }
            else {
                LB_OFF();
            }
        }
       
        if ((osTimeGet() - DzStartTime) >= (UserPara.DZTime)){
            /*倒种开关时间到*/
            DZ_OFF();
        }
        /*预落种开关时间到*/
        if ((osTimeGet()-YLZStartTime) >= (UserPara.DZTime)){
            YLZ_OFF();
        }
        /*打点器动作时间*/
        if ((osTimeGet() - TapperOnStartTime) >= TAPPER_ON_TIME){
            TapperOnStartTime = osTimeGet();
            TAPPER_OFF();
        }
        /*刷新显示板*/
        if ((osTimeGet() - DisBoardFlushTime) > DIS_FLUSH_TIME){
            DisBoardFlushTime = osTimeGet();
            FlushLEDDisBoard(); /*刷新led显示板*/
        }
        else {
            osDelay(5);
        }
    }
}
