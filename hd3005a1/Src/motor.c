/***************************************************************************************************
*                    (c) Copyright 1992-2022 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          motor.c
*\Description   
*\Note          
*\Log           2022.05.16    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "operation.h"
#include "motor.h"
#include "work_proc.h"

#define SPEED_LOW   50   /*最低步进电机启动速度mm/s*/
#define STEP_US_CNT (4) /*步进电机脉冲控制1US对应计算值*/

#define PWM_STEPS   (1)    /*一次输出的PWM个数*/
u8 ConvDoneFlag; //adc是否转换完成
#define SPEED_TEST 0 /*编码器模拟速度测试*/

extern TIM_HandleTypeDef htim10; /*pwm输出PF6供种开关*/
extern TIM_HandleTypeDef htim3; /*中断控制PE13引脚*/
extern TIM_HandleTypeDef htim4; /*中断控制PE14引脚*/
extern TIM_HandleTypeDef htim1; /*pwm输出PE11引脚*/
u8 PWM1Vol; /*1:表示当前高电平  0:表示当前低电平*/
u8 PWM3Vol; /*1:表示当前高电平  0:表示当前低电平*/
u8 PWM4Vol; /*1:表示当前高电平  0:表示当前低电平*/
u8 PWM5Vol; /*1:表示当前高电平  0:表示当前低电平*/
u32 CurrRunPulseNum[5]; //正在运行脉冲数  0:表示之前运行脉冲数已经结束  非0:表示有脉冲正在输出过程中
u32 TotalOutputPWMNums; //总的PWM计数

#define GZP_RATIO 20        /*变送比 20:1*/
#define GZP_STEPS_CYCLE  2560   /*电机转动一圈细分数*/
u32 GZPStepPwmNums = (u32)((double)49.1707*GZP_RATIO*GZP_STEPS_CYCLE/360); /*自动供种开关步进电机 每次步进脉冲数*/
u32 GZPSpeed = 5*GZP_RATIO*GZP_STEPS_CYCLE/60; /*转动速度 r/min 换算为脉冲数/s*/  

u32 SimuPWMGPIOArray2[PWM_STEPS*2+2]; //
extern DMA_HandleTypeDef hdma_tim8_up; //定时器
extern TIM_HandleTypeDef htim8; 
#define STEP_PWM_PORT  GPIOE
//#define STEP_PWM_PIN   (u32)(GPIO_PIN_11|GPIO_PIN_12|GPIO_PIN_13|GPIO_PIN_14|GPIO_PIN_15)
#define STEP_PWM_PIN   (u32)(GPIO_PIN_12)

#define STEP_PWM_LOW()   (STEP_PWM_PORT->BSRR = STEP_PWM_PIN)
#define STEP_PWM_HIGH()    (STEP_PWM_PORT->BSRR = (STEP_PWM_PIN << 16))


#define PWM1_LOW()  (STEP_PWM_PORT->BSRR = GPIO_PIN_11);PWM1Vol=0
#define PWM1_HIGH()   (STEP_PWM_PORT->BSRR = (GPIO_PIN_11 << 16));PWM1Vol=1

#define PWM3_LOW()  (STEP_PWM_PORT->BSRR = GPIO_PIN_13);PWM3Vol=0
#define PWM3_HIGH()   (STEP_PWM_PORT->BSRR = (GPIO_PIN_13 << 16));PWM3Vol=1

#define PWM4_LOW()  (STEP_PWM_PORT->BSRR = GPIO_PIN_14);PWM4Vol=0
#define PWM4_HIGH()   (STEP_PWM_PORT->BSRR = (GPIO_PIN_14 << 16));PWM4Vol=1

#define PWM5_LOW()  (STEP_PWM_PORT->BSRR = GPIO_PIN_15);PWM5Vol=0
#define PWM5_HIGH()   (STEP_PWM_PORT->BSRR = ((u32)GPIO_PIN_15 << 16));PWM5Vol=1

s16 Voltage = 121; //电源电压 单位0.1v
volatile bool BZStepMotorRunFlag[5]; //标记是否步进电机在运行, 该变量只在中断处理函数中变为FALSE

/*编码器计数*/
u32 curr_encoder;
int32_t LastEncoderCnt;   //上次获取到的编码器计数
int32_t EncoderNumPerSec; //编码器速度 脉冲个数/s
int32_t EncoderSpeed;     //编码器速度 mm/s

bool StopStepMotor; //停止步进电机

s32 LastStepCtrlSpeed; 
s32 StepCtrlSpeed; /*步进电机控制使用速度,负值表示倒车行驶  mm/s*/
u32 LastPulseTime[5]; //上次驱动的脉冲宽度 单位:us

u8  DCStartEnable[2];   //使能对应的直流电机  0:连续播种电机 1:分种电机
u16 DcMotorSetDuty[2];  //直流电机要设置的占空比
u16 DcMotorCurrDuty[2]; //直流电机要当前的占空比 0.1%
u32 DCMotorChannelNum[2] = {TIM_CHANNEL_1, TIM_CHANNEL_2};

extern ADC_HandleTypeDef hadc1;


void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  /* Prevent unused argument(s) compilation warning */
  //UNUSED(htim);

  /* NOTE : This function should not be modified, when the callback is needed,
            the HAL_TIM_PeriodElapsedCallback could be implemented in the user file
   */
    if (htim == &htim1){
        /*反转电平状态*/
        if (PWM1Vol == 0){
            PWM1_HIGH();
            /*@TODO是否需要结束*/
            if ((StopStepMotor == TRUE)|| 
                ((DJCtrlState&0x01) == 0)){
                    __HAL_TIM_DISABLE(&htim1); 
                    BZStepMotorRunFlag[0] = FALSE;
            }
            CurrRunPulseNum[0]++;
        }
        else {
            PWM1_LOW();
        }
    }
  else 
  if (htim == &htim3){
      /*反转电平状态*/
      if (PWM3Vol == 0){
          PWM3_HIGH();
          /*@TODO是否需要结束*/
          if ((StopStepMotor == TRUE)|| 
              ((DJCtrlState&0x04) == 0)){
               __HAL_TIM_DISABLE(&htim3); 
               BZStepMotorRunFlag[2] = FALSE;
          }
          CurrRunPulseNum[2]++;
      }
      else {
          PWM3_LOW();
      }
  }
  else 
  if (htim == &htim4){
       /*反转电平状态*/
      if (PWM4Vol == 0){
          PWM4_HIGH();
          /*@TODO是否需要结束*/
           if ((StopStepMotor == TRUE)|| ((DJCtrlState&0x08) == 0)){
              __HAL_TIM_DISABLE(&htim4); 
              BZStepMotorRunFlag[3] = FALSE;
          }
          CurrRunPulseNum[3]++;
      }
      else {
          PWM4_LOW();
      }
  }
  else 
      if (htim == &htim10){
          /*自动供种开关 PWM输出*/
          if (PWM5Vol == 0){
              PWM5_HIGH();
              /*@TODO是否需要结束*/
              if ((DJCtrlState&0x10) == 0){
                  __HAL_TIM_DISABLE(&htim10); 
                  BZStepMotorRunFlag[4] = FALSE;
              }
              CurrRunPulseNum[4]++;
              if (CurrRunPulseNum[GZ_STEP_INDEX] >= GZPStepPwmNums){
                  DJCtrlState &= (~(1<<GZ_STEP_INDEX));
              }
          }
          else {
              PWM5_LOW();
          }
      }
}

void HAL_TIM_PWM_PulseFinishedCallback(TIM_HandleTypeDef *htim)
{
   // if (htim == &htim10){
        /*自动供种开关 PWM输出*/
        // __HAL_TIM_ENABLE(&htim10);
    //}
    if (htim == &htim1){
        CurrRunPulseNum[0]++;
        /*PE11 PWM输出*/
        if (((StopStepMotor == TRUE)|| (DJCtrlState&0x01) == 0)){
            HAL_TIM_PWM_Stop(&htim1, TIM_CHANNEL_2);//__HAL_TIM_DISABLE(&htim1);
            BZStepMotorRunFlag[0] = FALSE;
        }
    }
}

/***************************************************************************************************
*\Function      SimuPwmCallBack
*\Description   DMA中断回调函数
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void SimuPwmErrorCallBack(DMA_HandleTypeDef *_hdma)
{
//    u32 i;
//     u32 wr_val;
//     for (i=1; i < (PWM_STEPS*2+2); i+=2){
//         SimuPWMGPIOArray2[i] = (wr_val); //输出高电平
//     }
    HAL_DMA_Start_IT(&hdma_tim8_up, (u32)&SimuPWMGPIOArray2[0], (uint32_t)&(STEP_PWM_PORT->BSRR), PWM_STEPS*2); 

    __HAL_TIM_ENABLE(&htim8);
}

/***************************************************************************************************
*\Function      SimuPwmCallBack
*\Description   DMA中断回调函数
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void SimuPwmCallBack(DMA_HandleTypeDef *_hdma)
{
//    u32 i;
//    u32 wr_val;
    CurrRunPulseNum[1] += PWM_STEPS;
    if (((DJCtrlState&0x02) != 0) && (StopStepMotor == FALSE) && (CurrRunPulseNum[1] < TotalOutputPWMNums)){
//         wr_val = (STEP_PWM_PIN)&(DJCtrlState<<11); //各个电机的使能状态
//         if (Last_wr_val != wr_val){
//             Last_wr_val = wr_val;
//             for (i=0; i < (PWM_STEPS*2+2); i+=2){
//                 SimuPWMGPIOArray2[i] = (wr_val<<16); //输出低电平
//             }
//         }
        /*继续PWM输出*/
        HAL_DMA_Start_IT(&hdma_tim8_up, (u32)&SimuPWMGPIOArray2[0], (uint32_t)&(STEP_PWM_PORT->BSRR), PWM_STEPS*2); 
        //__HAL_TIM_ENABLE(&htim8);
    }
    else {
        __HAL_TIM_DISABLE(&htim8);
        STEP_PWM_HIGH(); //使驱动器处于低电平状态,保证空闲时不会误动作
        //StopStepMotor = FALSE;
        BZStepMotorRunFlag[1] = FALSE; //步进电机停止运行
    }
}

/***************************************************************************************************
*\Function      SetStepMotorPulseTime
*\Description   设置步进电机驱动单个脉冲宽度
*\Parameter     0.1us
*\Return        void
***************************************************************************************************/
void SetStepMotorPulseTime(u8 index, u32 us)
{
//    TIM_OC_InitTypeDef sConfigOC = {0};
    LastPulseTime[index] = us;
    switch (index)
    {
    case 0:
//         if (us == 0){
//              HAL_TIM_PWM_Stop(&htim1, TIM_CHANNEL_2);//__HAL_TIM_DISABLE(&htim1);
//             return; //为0则停止脉冲输出
//         }
//         htim1.Init.CounterMode = TIM_COUNTERMODE_UP;
//         htim1.Init.Period = us-1; //500US一个周期 PWM输出周期1000us  
//         TIM1->ARR = htim1.Init.Period;
//         TIM1->PSC = (168/STEP_US_CNT)-1; //1/8US
// 
//         sConfigOC.OCMode = TIM_OCMODE_PWM1;
//         sConfigOC.Pulse = ((us+1)/2)-1;
//         sConfigOC.OCPolarity = TIM_OCNPOLARITY_HIGH;
//         sConfigOC.OCNPolarity = TIM_OCPOLARITY_LOW;
//         sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;
//         sConfigOC.OCIdleState = TIM_OCIDLESTATE_RESET;
//         sConfigOC.OCNIdleState = TIM_OCNIDLESTATE_RESET;
//         if (HAL_TIM_PWM_ConfigChannel(&htim1, &sConfigOC, TIM_CHANNEL_2) != HAL_OK)
//         {
//             Error_Handler();
//         }
        htim1.Init.Prescaler = (168/STEP_US_CNT)-1;
        htim1.Init.CounterMode = TIM_COUNTERMODE_UP;
        htim1.Init.Period = ((us+1)/2)-1; //500US一个周期 PWM输出周期1000us  
        if (HAL_TIM_Base_Init(&htim1) != HAL_OK){
            Error_Handler();
        }
        break;
    case 1:
        if (us == 0){
            __HAL_TIM_DISABLE(&htim8);
            return; //为0则停止脉冲输出
        }
        htim8.Init.Prescaler = 168-1; //1us时钟
        htim8.Init.CounterMode = TIM_COUNTERMODE_UP;
        htim8.Init.Period = ((us+1)/2)-1; //500US一个周期 PWM输出周期1000us  
        // htim8.Init.Period = 50-1; //50US一个周期 PWM输出周期100us   
        // htim8.Init.Period = 25-1; //25US一个周期 PWM输出周期50us
        TIM8->ARR = htim8.Init.Period;
        TIM8->PSC = (168/STEP_US_CNT)-1; //1/8US
        break;
    case 2:
        if (us == 0){
            osDelay(2); //等待中断结束
            __HAL_TIM_DISABLE(&htim3);
            return; //为0则停止脉冲输出
        }
        htim3.Init.Prescaler = (84/STEP_US_CNT)-1;
        htim3.Init.CounterMode = TIM_COUNTERMODE_UP;
        htim3.Init.Period = ((us+1)/2)-1; //500US一个周期 PWM输出周期1000us  
        if (HAL_TIM_Base_Init(&htim3) != HAL_OK){
            Error_Handler();
        }
        //TIM3->ARR = htim3.Init.Period;
        //TIM3->PSC = (168/STEP_US_CNT)-1; //1/8US
        break;
    case 3:
        if (us == 0){
            osDelay(2); //等待中断结束
            __HAL_TIM_DISABLE(&htim4);
            return; //为0则停止脉冲输出
        }

        htim4.Init.Prescaler = (84/STEP_US_CNT)-1;
        htim4.Init.CounterMode = TIM_COUNTERMODE_UP;
        htim4.Init.Period = ((us+1)/2)-1; //500US一个周期 PWM输出周期1000us  
        if (HAL_TIM_Base_Init(&htim4) != HAL_OK){
            Error_Handler();
        }
        //TIM4->ARR = htim4.Init.Period;
        //TIM4->PSC = (168/STEP_US_CNT)-1; //1/8US
        break;
    case 4:
        if (us == 0){
            osDelay(2); //等待中断结束
            __HAL_TIM_DISABLE(&htim10);
            return; //为0则停止脉冲输出
        }
        htim10.Init.Prescaler = (168/STEP_US_CNT)-1;
        htim10.Init.CounterMode = TIM_COUNTERMODE_UP;
        htim10.Init.Period = ((us+1)/2)-1; //500US一个周期 PWM输出周期1000us  
        if (HAL_TIM_Base_Init(&htim10) != HAL_OK)
        {
            Error_Handler();
        }
//         TIM10->ARR = htim10.Init.Period;
//         TIM10->PSC = (168/STEP_US_CNT)-1; //1/8US
        break;
    default:
        break;
    }
}

/*pwm1 pe11 tim1_ch2*/
void  pwm1Init(void)
{
      TIM_OC_InitTypeDef sConfigOC = {0};
     //__HAL_TIM_DISABLE(&htim1);

    htim1.Instance = TIM1;
    htim1.Init.Prescaler = 168/STEP_US_CNT-1;
    htim1.Init.CounterMode = TIM_COUNTERMODE_UP;
    htim1.Init.Period = 500*STEP_US_CNT-1;
    htim1.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
    htim1.Init.RepetitionCounter = 0;
    htim1.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    if (HAL_TIM_Base_Init(&htim1) != HAL_OK){
        Error_Handler();
    }

//     sConfigOC.OCMode = TIM_OCMODE_PWM1;
//     sConfigOC.Pulse = STEP_US_CNT*250-1;
//     sConfigOC.OCPolarity = TIM_OCNPOLARITY_HIGH;
//     sConfigOC.OCNPolarity = TIM_OCPOLARITY_LOW;
//     sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;
//     sConfigOC.OCIdleState = TIM_OCIDLESTATE_RESET;
//     sConfigOC.OCNIdleState = TIM_OCNIDLESTATE_RESET;
//     if (HAL_TIM_PWM_ConfigChannel(&htim1, &sConfigOC, TIM_CHANNEL_2) != HAL_OK){
//         Error_Handler();
//     }

    /*@todo确保PE11空闲高电平*/
}
/*定时器3,4,10初始化 PE13 PE14 PE15*/
void pwm3to5Init(void)
{

    htim3.Instance = TIM3;
    htim3.Init.Prescaler = 168/STEP_US_CNT-1;
    htim3.Init.CounterMode = TIM_COUNTERMODE_UP;
    htim3.Init.Period = STEP_US_CNT*250-1;;
    htim3.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
    htim3.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    if (HAL_TIM_Base_Init(&htim3) != HAL_OK)
    {
        Error_Handler();
    }

    htim4.Instance = TIM4;
    htim4.Init.Prescaler = 168/STEP_US_CNT-1;
    htim4.Init.CounterMode = TIM_COUNTERMODE_UP;
    htim4.Init.Period = STEP_US_CNT*250-1;;
    htim4.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
    htim4.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    if (HAL_TIM_Base_Init(&htim4) != HAL_OK)
    {
        Error_Handler();
    }

    htim10.Instance = TIM10;
    htim10.Init.Prescaler = 168/STEP_US_CNT-1;
    htim10.Init.CounterMode = TIM_COUNTERMODE_UP;
    htim10.Init.Period = STEP_US_CNT*250-1;;
    htim10.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
    htim10.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    if (HAL_TIM_Base_Init(&htim10) != HAL_OK)
    {
        Error_Handler();
    }
}
/***************************************************************************************************
*\Function      StepMotorInit
*\Description   
*\Parameter     
*\Return        void
*\Note          1)pwm1 pe11 TIM1 PWM_CH2
                2)PWM2 pe12 TIM8 定时器DMA触发自动反转电平
                3)pwm3\4 pe13\pe14 定时器3 4 中断触发反转电平
                4)pwm5 PE15自动供种开关电机  TIM10中断触发反转电平
***************************************************************************************************/
void StepMotorInit(void)
{
    u16 i;
    __HAL_TIM_DISABLE(&htim1); //TIM1确认引脚空闲电平状态
    __HAL_TIM_DISABLE(&htim3);
    __HAL_TIM_DISABLE(&htim4);
    __HAL_TIM_DISABLE(&htim10);

    __HAL_TIM_DISABLE(&htim8);
    HAL_DMA_RegisterCallback(&hdma_tim8_up, HAL_DMA_XFER_CPLT_CB_ID, SimuPwmCallBack);
    HAL_DMA_RegisterCallback(&hdma_tim8_up, HAL_DMA_XFER_ERROR_CB_ID, SimuPwmErrorCallBack);
    htim8.Init.Prescaler = 168-1; //1us时钟
    htim8.Init.CounterMode = TIM_COUNTERMODE_UP;
    htim8.Init.Period = 500-1; //500US一个周期 PWM输出周期1000us 
    /*
    小区长度一般为3m~30m 行驶速度按照
    */
    htim8.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    if (HAL_TIM_Base_Init(&htim8) != HAL_OK){
        Error_Handler();
    }

    HAL_DMA_Start_IT(&hdma_tim8_up, (u32)&SimuPWMGPIOArray2[0], (uint32_t)(&STEP_PWM_PORT->BSRR), PWM_STEPS*2);
    /* Enable the TIM Output Capture/Compare 3 request */
    __HAL_TIM_ENABLE_DMA(&htim8, TIM_DMA_UPDATE);
    /*步进电机初始化
    PWM输出引脚空闲时输出高电平
    */
    for (i=0; i < (PWM_STEPS*2+2); i++){
        if ((i%2) == 0){
            SimuPWMGPIOArray2[i] = (STEP_PWM_PIN); //输出高电平
        }
        else {
            SimuPWMGPIOArray2[i] = (STEP_PWM_PIN << 16); //输出低电平; 
          
        }
    }

    pwm1Init();
    pwm3to5Init();
    STEP_PWM_HIGH();
    PWM1_HIGH();
    PWM3_HIGH();
    PWM4_HIGH();
    PWM5_HIGH();
}

void TimeErrorProc(void)
{
    if ((htim1.Instance->CR1 & TIM_CR1_CEN) == 0){
        BZStepMotorRunFlag[0] = FALSE;
    }

    if ((htim8.Instance->CR1 & TIM_CR1_CEN) == 0){
        BZStepMotorRunFlag[1] = FALSE;
    }

    if ((htim3.Instance->CR1 & TIM_CR1_CEN) == 0){
        BZStepMotorRunFlag[2] = FALSE;
    }

    if ((htim4.Instance->CR1 & TIM_CR1_CEN) == 0){
        BZStepMotorRunFlag[3] = FALSE;
    }

    if ((htim10.Instance->CR1 & TIM_CR1_CEN) == 0){
        BZStepMotorRunFlag[4] = FALSE;
    }
}

/***************************************************************************************************
*\Function      StepMotorMove
*\Description   步进电机移动步数
*\Parameter     pulse_num
*\Return        void
*\Note          
***************************************************************************************************/
void StepMotorMove(u8 index, u32 pulse_num)
{
//    u32 i;
//    u32 wr_val;
    switch (index)
    {
    case 0:
       // __HAL_TIM_ENABLE(&htim1);
        BZStepMotorRunFlag[0] = TRUE;
         HAL_TIM_Base_Start_IT(&htim1);
        //HAL_TIM_Base_Start(&htim1);
        //HAL_TIM_PWM_Start_IT(&htim1, TIM_CHANNEL_2);
        break;
    case 1:
        __HAL_TIM_DISABLE(&htim8);
        BZStepMotorRunFlag[1] = TRUE;

        HAL_DMA_Start_IT(&hdma_tim8_up, (u32)&SimuPWMGPIOArray2[0], (uint32_t)(&STEP_PWM_PORT->BSRR), PWM_STEPS*2);
        /* Enable the TIM Output Capture/Compare 3 request */
        __HAL_TIM_ENABLE_DMA(&htim8, TIM_DMA_UPDATE);
        __HAL_TIM_ENABLE(&htim8);
        break;
    case 2:
        BZStepMotorRunFlag[2] = TRUE;
        //__HAL_TIM_ENABLE(&htim3);
        HAL_TIM_Base_Start_IT(&htim3);
        break;
    case 3:
        BZStepMotorRunFlag[3] = TRUE;
        //__HAL_TIM_ENABLE(&htim4);
        HAL_TIM_Base_Start_IT(&htim4);
        break;
    case 4:
        BZStepMotorRunFlag[4] = TRUE;
        //__HAL_TIM_ENABLE(&htim10);
        HAL_TIM_Base_Start_IT(&htim10);
        break;
    default:
        break;
    }
   
}

/*启动自动供种步进电机*/
void StartGZStepMotor(void)
{
    /*启动控制*/
    CurrRunPulseNum[GZ_STEP_INDEX] = 0; /*脉冲计数清0*/
    DJCtrlState |= (1 << GZ_STEP_INDEX);
    SetStepMotorPulseTime(GZ_STEP_INDEX, (STEP_US_CNT*1000*1000/GZPSpeed)); //单个脉冲对应clock值
    StepMotorMove(GZ_STEP_INDEX, 1);  //控制对应电机启动
}

/***************************************************************************************************
*\Function      GetPulseTimeFromRMP
*\Description   根据用户设置转速计算步进电机驱动脉冲宽度
*\Parameter     rmp   r/min  15~60
*\Return        u32  us*STEP_US_CNT
***************************************************************************************************/
u32 GetPulseTimeFromRMP(u32 rmp)
{
    u32 tmp_cnt;

    double time;
    if ((rmp < 10) | (rmp > 60)){
        return 0; //脉冲数为0，则表示需要处在停止状态
    }

    time = rmp*1.0;  /*转速R/MIN*/
    time /= 60;  //单位转为r/s

    time = (GlobalPara.MicroStepValue*STEP_GEAR_RATIO)*time; //脉冲数/s  电机与播种盘传动比为5:1
    if (time == 0){
        time = 1;
    }
    tmp_cnt = STEP_US_CNT*1000*1000/time; //单个脉冲对应clock值 
    return tmp_cnt;
}

/***************************************************************************************************
*\Function      GetPulseTime
*\Description   根据运行速度计算步进电机驱动脉冲宽度
*\Parameter     speed   mm/s
*\Return        u32  us*STEP_US_CNT
***************************************************************************************************/
u32 GetStepPulseTime(u8 index, s32 speed)
{
    u32 tmp_cnt;
    s32 N; //株数
    s32 cell_len;
    //u32 i;
    double time;
    if (speed < 200){  //速度低于0.2m/s
        return 0; //脉冲数为0，则表示需要处在停止状态
    }

    if (WorkMode == WORK_MODE_LXBZ){
        LXBZParaCheck();
        N = LXBZZhushu;
        if (N < 2){
            N = 2;
        }
        cell_len = LXBZPara.CellLen;
        if (cell_len == 0){
            cell_len = 100; 
        }
    }
    else {
        if (BZCellParaCurr.Density[index] == 0){
            //@TODO密度为0时，暂时采用一个固定的默认值,保证电机转动,不影响后续小区控制逻辑
            N = 25; //株数  
            cell_len = 500;
        }
        else {
            N = GetZhuShu(BZCellParaCurr.Density[index], BZCellParaCurr.CellLen, UserPara.HJ); //株数
            cell_len = BZCellParaCurr.CellLen;
        }
    }
    if (cell_len < 50){
        cell_len = 50;
    }
    //Zhuju = cell_len/(N-1);
    Zhuju[index] = GetZhuJu(cell_len, N); /*株距四舍五入*/
    /*转速r=V*N/(9*L)*60  R/MIN*/
    time = (speed*0.1)*N/(BZP_HOLE_NUM*cell_len); /*r/s*/

    time = (GlobalPara.MicroStepValue*STEP_GEAR_RATIO)*time; //脉冲数/s  电机与播种盘传动比为5:1
    if (time == 0){
        time = 1;
    }
    tmp_cnt = STEP_US_CNT*1000*1000/time; //单个脉冲对应clock值 
    return tmp_cnt;
}

/***************************************************************************************************
*\Function      DCMotorSpeedGet
*\Description   分种直流电机转速计算
*\Parameter     
*\Return        void  
*\Note          每隔1s调用一次该接口用于计算分种旋转电机转速
***************************************************************************************************/
void EncoderSpeedCalc(void)
{
    /*编码器转速*/
    curr_encoder = GetEncoderNumNoclear();
    EncoderNumPerSec = curr_encoder - LastEncoderCnt;
    LastEncoderCnt = curr_encoder;
#if SPEED_TEST
    EncoderSpeed = 1000;//mm/s
#else
    EncoderSpeed = EncoderNumPerSec*(1000*(1000/200))/(s32)(GlobalPara.EncodeNum); //mm/s;
#endif
    return;
}

/***************************************************************************************************
*\Function      PWMInit
*\Description   输出PWM初始化
*\Parameter     
*\Return        void
*\Note          1)PF6通道TIM10 CH1  2KHZ
2)PF6通道TIM10 CH1
***************************************************************************************************/
void PWMInit(void)
{
    TIM_OC_InitTypeDef sConfigOC = {0};
    sConfigOC.OCMode = TIM_OCMODE_PWM1;
    sConfigOC.Pulse = 0;
    sConfigOC.OCPolarity = TIM_OCPOLARITY_HIGH;
    sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;
    if (HAL_TIM_PWM_ConfigChannel(&htim10, &sConfigOC, TIM_CHANNEL_1) != HAL_OK){
        Error_Handler();
    }

    HAL_TIM_PWM_Stop(&htim10, TIM_CHANNEL_1);
}

/***************************************************************************************************
*\Function      DCMotorDutyAdj
*\Description   
*\Parameter     duty_ths  占空比 高电平部分  单位:0.1%  0表示一直为低电平或者关闭   1000:表示一直为高电平
*\Return        u16
*\Note          
***************************************************************************************************/
void DCMotorDutyAdj(u16 duty_ths, u32 channel_num)
{
    TIM_OC_InitTypeDef sConfigOC = {0};
    sConfigOC.OCMode = TIM_OCMODE_PWM1;
    
    sConfigOC.OCPolarity = TIM_OCPOLARITY_HIGH;
    sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;

    if (duty_ths > 1000){
        duty_ths = 1000;
    }

    switch (channel_num)
    {
    case TIM_CHANNEL_1:
        //sConfigOC.Pulse = (duty_ths+1)/20;  //暂时为20KHZ
        sConfigOC.Pulse = (duty_ths+1)/2;  //暂时为20KHZ
        if (sConfigOC.Pulse == 0){
            TIM_CCxChannelCmd(htim10.Instance, channel_num, TIM_CCx_DISABLE);
        }
        else {
            TIM_CCxChannelCmd(htim10.Instance, channel_num, TIM_CCx_DISABLE);
            if (HAL_TIM_PWM_ConfigChannel(&htim10, &sConfigOC, channel_num) != HAL_OK){
                Error_Handler();
            }
            TIM_CCxChannelCmd(htim10.Instance, channel_num, TIM_CCx_ENABLE);
            __HAL_TIM_ENABLE(&htim10);
        }
        break;
    default:
        break;
    }
}

/***************************************************************************************************
*\Function      EncoderInit
*\Description   编码器初始化
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void  EncoderInit(void)
{
    HAL_TIM_Encoder_Start(&htim2, TIM_CHANNEL_ALL);
}

void StopAllPwm(void)
{
    __HAL_TIM_DISABLE(&htim1); //关闭所有PWM输出 异常处理
    __HAL_TIM_DISABLE(&htim8);
    __HAL_TIM_DISABLE(&htim3);
    __HAL_TIM_DISABLE(&htim4);
    __HAL_TIM_DISABLE(&htim10);
    memset(&BZStepMotorRunFlag, 0x00, sizeof(BZStepMotorRunFlag));
}

void StepMotorCtrlTask(const void* para)
{
    u32 i;
    StepMotorInit();
    EncoderInit(); //编码器初始化
    osDelay(1000);
    ParaLegalCheck();
    //SetStepMotorPulseTime(500*STEP_US_CNT);  //按照2KHZ输出频率输出
    DEAD_LOOP{
        if (RUN_S_STOP == RunState) {
            /*任何模式下,停止状态都不会让步进电机转动*/
            DJCtrlState = 0;
            StopStepMotor = TRUE;
            osDelay(10);
            StopAllPwm();
        }
        else {
            switch (WorkMode)
            {
            case WORK_MODE_TEST:
                /*测试模式*/
                StopStepMotor = FALSE;
                for (i = 0; i < 5; i++){
                    if ((DJCtrlState & (1<<i)) != 0){
                        if (BZStepMotorRunFlag[i] == FALSE) {
                            if (i != GZ_STEP_INDEX)
                            {
                                /*启动控制*/
                                SetStepMotorPulseTime(i, GetPulseTimeFromRMP(UserPara.RMP));  //按照用户设置转速转动
                                StepMotorMove(i, 1);  //控制对应电机启动
                            }
                            else {
                                StartGZStepMotor(); //启动自动供种步进电机
                            }
                        }
                    }
                }
                break;
            case WORK_MODE_BD:
            case WORK_MODE_LXBZ:
                if ((SEED_PRE_MOTOR == SeedMode) || (SeedMode == SEED_WAIT_ZERO)|| (SeedMode == SEED_HALF_CYCLE)){
                    StopStepMotor = FALSE;
                    AvgSpeed = BdCalcSpeed;
                    //osDelay(200); //等待阀门关闭
                    /*播种盘预充种过程*/
                    for (i = 0; i < 4; i++){
                        if ((DJCtrlState & (1<<i)) != 0){
                            if ((BZStepMotorRunFlag[i] == FALSE)&&(CurrRunPulseNum[i] < TotalOutputPWMNums)) {
                                /*启动控制*/
                                SetStepMotorPulseTime(i, GetPulseTimeFromRMP(UserPara.RMP));  //按照用户设置转速转动
                                StepMotorMove(i, 1);  //控制对应电机启动
                            }
                        }
                    }
                    break;
                }
#if BD_SIMU_TEST
                EncoderSpeed = SIMU_SPEED;
                BdCalcSpeed = EncoderSpeed;
#endif
                AvgSpeed = BdCalcSpeed;
                if ((DJCtrlState&BZP_ZERO_MASK) != 0){
                    /*运行速度异常处理  开始*/
                    /*速度都比较低时,才同步为低速*/
#if SPEED_FILTER_EN
                    if ((EncoderSpeed < SPEED_LOW) && (BdCalcSpeed < SPEED_LOW)){
                        AvgSpeed = BdCalcSpeed;
                        AvgSpeedTime = osTimeGet();
                    }
                    else {
                        /*正常速度下, 需要增加速率滤波防止北斗信号短时异常造成速度计算异常*/
                        if ((BdCalcSpeed > 250) && (BdCalcSpeed < 1000)){
                            /*速度在相对合理区间内, 考虑有选择采用北斗速度*/
                            change_per = BdCalcSpeed - EncoderSpeed;
                            if (change_per < 0){
                                change_per *= -1;
                            }
                            if ((change_per < (BdCalcSpeed*100/15)) && (change_per < (EncoderSpeed*100/15))){
                                /*速度偏差在15%以内*/
                                AvgSpeed = BdCalcSpeed;
                                AvgSpeedTime = osTimeGet();
                            }
                            else {
                                /*速度偏差过大, 则认为北斗异常*/
                            }
                            if ((osTimeGet() - AvgSpeedTime) > 6000){
                                /*长时间无法获取稳定平均速度则更新一次*/
                                AvgSpeed = BdCalcSpeed;
                            }
                        }
                        else {
                            /*采用编码器速度*/
                            AvgSpeed = EncoderSpeed;
                        }
                    }
#else 
                   // AvgSpeed = BdCalcSpeed;//直接使用北斗速度
#endif
                    StepCtrlSpeed = AvgSpeed;
                    /*运行速度异常处理  结束 */
                    if ((StepCtrlSpeed < SPEED_LOW) /*|| ((WORK_MODE_BD == WorkMode) && (BZCellParaCurr.Density == 0))*/){
                        /*速度过低  @TODO需要再斟酌一下,若是下一小区密度不为0是否会影响*/
                        StopStepMotor = TRUE; //停止步进电机转动
                    }
                    else {
                        StopStepMotor = FALSE;
                        /*需要重新计算步进电机脉冲输出速度*/
                        LastStepCtrlSpeed = StepCtrlSpeed;
                        TimeErrorProc();
                        for (i = 0; i < 4; i++){
                            if (GetStepPulseTime(i, StepCtrlSpeed) != LastPulseTime[i]){
                                SetStepMotorPulseTime(i, GetStepPulseTime(i, StepCtrlSpeed));
                            }
                            if(BZStepMotorRunFlag[i] == FALSE){
                                StepMotorMove(i, 100);
                            }
                        }
                    }
                }
                else {
                    //AvgSpeed = BdCalcSpeed;
                }

                /*施肥电机启停控制逻辑*/
                if ((RunState == RUN_S_START) && (AvgSpeed > (SPEED_LOW*2))/* && (ShiFeiOnFlag == TRUE)*/){
                    SF_MOTOR_ON();
                }
                else {
                    SF_MOTOR_OFF();
                }
                break;
            default:
                WorkMode = WORK_MODE_IDLE;
                break;
            }
        }
        osDelay(1);
    }
}

/**
* @brief  Conversion complete callback in non blocking mode 
* @param  hadc: ADC handle
* @retval None
*/
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc)
{
    /* Prevent unused argument(s) compilation warning */
    UNUSED(hadc);
    /* NOTE : This function should not be modified. When the callback is needed,
    function HAL_ADC_ConvCpltCallback must be implemented in the user file.
    */
    ConvDoneFlag = 1;
}
#define ADC_CH_NUMS 2
u32 adc_start_time;
u8 ConvCnt;
u16 AdcDMABuf[ADC_CH_NUMS];
u32 AdcAccuBuf[ADC_CH_NUMS];      //累积值
u32 AdcAvgBuf[ADC_CH_NUMS];       //ADC平均转换值
u32 AdcVolBuf[ADC_CH_NUMS];       //ADC转换后的电压 0.001v
/*电瓶电压采集*/
void AdcProcFunc(void)
{
    u32 i;
    if ((osTimeGet() - adc_start_time) > 10){
        ConvCnt=0;
        memset(AdcAccuBuf, 0x00, sizeof(AdcAccuBuf));
        HAL_ADC_Start_DMA(&hadc1, (u32*)&AdcDMABuf[0], ADC_CH_NUMS);
    }
    if (ConvDoneFlag){
        for (i = 0; i < ADC_CH_NUMS; i++){
            AdcAccuBuf[i] += AdcDMABuf[i];
        }
        ConvCnt++;
        if (ConvCnt >= 64){
            ConvCnt = 0;
            for (i = 0; i < ADC_CH_NUMS; i++){
                AdcAvgBuf[i] = AdcAccuBuf[i]>>6;
                AdcAccuBuf[i] = 0;
                //AdcVolBuf[i] = AdcAvgBuf[i]*3300/4096;  //电压值0.0001v
                AdcVolBuf[i] = (AdcAvgBuf[i]*825/1024)*6;  //电压值0.001v
            }
        }
        Voltage = AdcVolBuf[1]/100; //电源电压
        ConvDoneFlag  = 0;
        adc_start_time = osTimeGet();
        HAL_ADC_Start_DMA(&hadc1, (u32*)&AdcDMABuf[0], ADC_CH_NUMS);
    }
}
