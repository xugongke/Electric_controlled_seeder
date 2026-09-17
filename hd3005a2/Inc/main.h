/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
  ******************************************************************************
  * @attention
  *
  * <h2><center>&copy; Copyright (c) 2020 STMicroelectronics.
  * All rights reserved.</center></h2>
  *
  * This software component is licensed by ST under Ultimate Liberty license
  * SLA0044, the "License"; You may not use this file except in compliance with
  * the License. You may obtain a copy of the License at:
  *                             www.st.com/SLA0044
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32f4xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */
#define WDG_ENABLE 1 /*是否使能看门狗*/
extern unsigned int SysTime; //系统时间
extern unsigned int SecMsTick;  /*每秒内毫秒计数*/
/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */
extern void AppMain(void const* para);
/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/
#define OUT7_Pin GPIO_PIN_2
#define OUT7_GPIO_Port GPIOE
#define OUT6_Pin GPIO_PIN_3
#define OUT6_GPIO_Port GPIOE
#define OUT5_Pin GPIO_PIN_4
#define OUT5_GPIO_Port GPIOE
#define OUT4_Pin GPIO_PIN_5
#define OUT4_GPIO_Port GPIOE
#define OUT3_Pin GPIO_PIN_6
#define OUT3_GPIO_Port GPIOE
#define OUT2_Pin GPIO_PIN_0
#define OUT2_GPIO_Port GPIOF
#define OUT1_Pin GPIO_PIN_1
#define OUT1_GPIO_Port GPIOF
#define PWM_O7_Pin GPIO_PIN_7
#define PWM_O7_GPIO_Port GPIOF
#define PWM_O6_Pin GPIO_PIN_8
#define PWM_O6_GPIO_Port GPIOF
#define IN24_Pin GPIO_PIN_0
#define IN24_GPIO_Port GPIOA
#define IN24_EXTI_IRQn EXTI0_IRQn
#define IN23_Pin GPIO_PIN_1
#define IN23_GPIO_Port GPIOA
#define IN23_EXTI_IRQn EXTI1_IRQn
#define IN22_Pin GPIO_PIN_2
#define IN22_GPIO_Port GPIOA
#define IN22_EXTI_IRQn EXTI2_IRQn
#define IN21_Pin GPIO_PIN_3
#define IN21_GPIO_Port GPIOA
#define IN21_EXTI_IRQn EXTI3_IRQn
#define SPI_CS_Pin GPIO_PIN_6
#define SPI_CS_GPIO_Port GPIOA
#define OUT10_Pin GPIO_PIN_7
#define OUT10_GPIO_Port GPIOA
#define OUT11_Pin GPIO_PIN_4
#define OUT11_GPIO_Port GPIOC
#define OUT12_Pin GPIO_PIN_5
#define OUT12_GPIO_Port GPIOC
#define OUT9_Pin GPIO_PIN_0
#define OUT9_GPIO_Port GPIOB
#define PWM_O1_Pin GPIO_PIN_11
#define PWM_O1_GPIO_Port GPIOE
#define PWM_O2_Pin GPIO_PIN_12
#define PWM_O2_GPIO_Port GPIOE
#define PWM_O3_Pin GPIO_PIN_13
#define PWM_O3_GPIO_Port GPIOE
#define PWM_O4_Pin GPIO_PIN_14
#define PWM_O4_GPIO_Port GPIOE
#define PWM_O5_Pin GPIO_PIN_15
#define PWM_O5_GPIO_Port GPIOE
#define EE_WP_Pin GPIO_PIN_11
#define EE_WP_GPIO_Port GPIOB
#define EE_SCL_Pin GPIO_PIN_12
#define EE_SCL_GPIO_Port GPIOB
#define EE_SDA_Pin GPIO_PIN_13
#define EE_SDA_GPIO_Port GPIOB
#define IN1_Pin GPIO_PIN_14
#define IN1_GPIO_Port GPIOB
#define IN1_EXTI_IRQn EXTI15_10_IRQn
#define IN2_Pin GPIO_PIN_15
#define IN2_GPIO_Port GPIOB
#define IN2_EXTI_IRQn EXTI15_10_IRQn
#define IN3_Pin GPIO_PIN_8
#define IN3_GPIO_Port GPIOD
#define IN4_Pin GPIO_PIN_9
#define IN4_GPIO_Port GPIOD
#define IN4_EXTI_IRQn EXTI9_5_IRQn
#define IN5_Pin GPIO_PIN_10
#define IN5_GPIO_Port GPIOD
#define IN25_Pin GPIO_PIN_11
#define IN25_GPIO_Port GPIOD
#define IN6_Pin GPIO_PIN_13
#define IN6_GPIO_Port GPIOD
#define IN6_EXTI_IRQn EXTI15_10_IRQn
#define IN7_Pin GPIO_PIN_2
#define IN7_GPIO_Port GPIOG
#define IN8_Pin GPIO_PIN_3
#define IN8_GPIO_Port GPIOG
#define IN9_Pin GPIO_PIN_4
#define IN9_GPIO_Port GPIOG
#define IN10_Pin GPIO_PIN_5
#define IN10_GPIO_Port GPIOG
#define IN11_Pin GPIO_PIN_8
#define IN11_GPIO_Port GPIOG
#define IN12_Pin GPIO_PIN_6
#define IN12_GPIO_Port GPIOC
#define IN12_EXTI_IRQn EXTI9_5_IRQn
#define IN13_Pin GPIO_PIN_7
#define IN13_GPIO_Port GPIOC
#define IN13_EXTI_IRQn EXTI9_5_IRQn
#define IN14_Pin GPIO_PIN_8
#define IN14_GPIO_Port GPIOC
#define IN15_Pin GPIO_PIN_9
#define IN15_GPIO_Port GPIOC
#define IN16_Pin GPIO_PIN_8
#define IN16_GPIO_Port GPIOA
#define IN16_EXTI_IRQn EXTI9_5_IRQn
#define IN17_Pin GPIO_PIN_9
#define IN17_GPIO_Port GPIOA
#define IN18_Pin GPIO_PIN_10
#define IN18_GPIO_Port GPIOA
#define IN19_Pin GPIO_PIN_11
#define IN19_GPIO_Port GPIOA
#define IN19_EXTI_IRQn EXTI15_10_IRQn
#define IN20_Pin GPIO_PIN_12
#define IN20_GPIO_Port GPIOA
#define IN20_EXTI_IRQn EXTI15_10_IRQn
#define RX8025_SCL_Pin GPIO_PIN_11
#define RX8025_SCL_GPIO_Port GPIOG
#define RX8025_SDA_Pin GPIO_PIN_12
#define RX8025_SDA_GPIO_Port GPIOG
#define OUT8_Pin GPIO_PIN_1
#define OUT8_GPIO_Port GPIOE

/* USER CODE BEGIN Private defines */
//uint16_t usTimeGet(void);
#define  usTimeGet()  (uint16_t)(TIM6->CNT)
uint32_t osTimeGet(void);
void UartTestTask(void const* para);

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
