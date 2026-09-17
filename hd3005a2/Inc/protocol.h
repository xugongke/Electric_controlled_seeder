/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          protocol.h
*\Description   
*\Note          
*\Log           2020.08.05    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _PROTOCOL_H
#define _PROTOCOL_H
#include "main.h"
#include "type.h"
#include "para.h"
#define COMM_DEV_BD (&UartUser6) /*北斗通讯串口*/
#define COMM_DEV_UP (&UartUser4) /*平板通讯串口,原串口屏通讯接口*/

#define FRAME_START  0x68
#define FRAME_END    0x0d

#define FNC_INVALID 0
#define FRAME_MAX_DATA_LEN   1400  /*数据域最大长度*/ 
#define FNC_SET_LED_CNT      0x5C  /*下发12个LED的信息*/
//#define FNC_GET_CUR_VALUE    0x01  /*获取实时温湿度数据*/
//#define FNC_GET_STORAGE      0x02  /*获取离线数据*/
//#define FNC_GET_STATUS       0x03  /*获取当前运行状态*/
#define FNC_GET__RTC         0x04  /*获取系统时间*/
#define FNC_SET_RTC          0x05  /*设置系统时间*/

#define FNC_GET_TEST_STATUS  0x08   /*获取测试模式下的所有外设状态 TestModeStateType*/
#define FNC_CMD_SVCTRL       0x09   /*下发测试模式下控制命令 数据域为TestCMDType*/     

#define FNC_CMD_START_BZ     0X0A   /*启动播种 数据域为空   回复数据域为1个字节 0:*/
#define FNC_CMD_STOP_BZ      0X0B   /*停止播种 数据域为空   回复数据域为1个字节 0:*/

#define FNC_CMD_START_TEST   0X0E   /*进入测试模式 数据域为空    回复数据域为1个字节 0:*/
#define FNC_CMD_STOP_TEST    0X0F   /*退出测试模式 数据域为空  回复数据域为1个字节 0:*/

#define FNC_CMD_START_LXBZ   0X11   /*启动连续播种模式  数据域为 LXBZParaType*/
#define FNC_CMD_STOP_LXBZ    0X12   /*停止连续播种模式  数据域为空*/

#define FNC_SET_BZ_PARA      0X20   /*设置播种参数 BZCellParaType   回复数据域为1个字节 0:失败*/
#define FNC_GET_BZ_STATUS    0X21   /*当前播种状态 */

#define FNC_RD_DEBUG_INFO    0X22   /*读取调试信息   回复数据域为最大200字节字符串*/

#define FNC_STORE_AB         0x23   /*存储AB线 数据域为空 回复数据为AB线数据 BDParaType*/
#define FNC_SET_AB           0X24   /*设置AB线数据 数据域为BDParaType 用于在开始时播种前设置AB线数据用*/

#define FNC_SET_TER_PARA     0x25  /*设置厂家后台参数 数据域为TerParaType, 只在用户改变设置参数时设置*/
#define FNC_GET_TER_PARA     0x26  /*读取厂家后台参数 回复数据域为TerParaType*/

#define FNC_SET_USER_PARA    0x27  /*设置用户后台参数 数据域为UserParaType  只在用户改变设置参数时设置*/
#define FNC_GET_USER_PARA    0x28  /*读取用户后台参数 回复数据域为UserParaType*/

#define FNC_QZDD_ENABLE     0X29   /*设置是否清种时刻打点    数据域为1个字节  0:表示不打点 1:表示打点  用户操作按钮时下发*/
#define FNC_GET_QZDD_STATE  0X30   /*获取清种时刻打点状态 数据域为空   回复数据域为1字节*/


#define FNC_GDDD_ENABLE     0X31   /*设置是否过道中间时刻打点    数据域为1个字节  0:表示不打点 1:表示打点*/
#define FNC_GET_GDDD_STATE  0X32   /*获取清种时刻打点状态 数据域为空   回复数据域为1字节*/

#define FNC_UPDATE_START    0xa0  /*开始升级过程*/
#define FNC_UPDATE_BIN      0xa1  /*升级bin传输*/
#define FNC_UPDATE_END      0xa2  /*BIN文件升级结束*/
#define FNC_GET_SOFT_VER    0xa3  /*获取软件版本号*/

#define FNC_RESTART_TER     0x10 /*重启设备*/
#define FNC_INVALID 0
#define FNC_CMD_NULL        0x0000  //数据处理完成

typedef struct BZCellParaType_st
{
    u8  TXFlag;         //播种方向与AB同向还是反向  0:反向  1:同向
    u8  FinalFlag;      /*0:不是最后一个小区  1:最后一个小区*/
    u8  NextFinalFlag;  /*0:不是最后一个小区  1:最后一个小区*/
    u8  isAfterNextZoneSow;//当前小区排+2的小区是否播种;
    s32  RowNum;    //当前小区所在排编号     
    s32  InS;       /*小区间隔(过道长度) 单位:cm*/
    s32  Density[LINE_NUM];   //小区密度或者株数  若是小于0,表示当前区域停止播种
    s32  CellLen;   //当前小区长度(不含过道) cm
    s32  StartPOS;  // 当前小区沿行进方向的坐标 cm   A点所在小区第一粒种子位置为0点 沿AB线
    s32  DisplayRowNum;//调试信息中显示的当前排号

    s32  NextRowNum;        //当前小区所在排编号     
    s32  NextInS;           /*小区间隔(过道长度) 单位:cm*/
    s32  NextDensity[LINE_NUM];       //小区密度或者株数   若为0表示当前小区不需要播种或者禁用状态 若是小于0,表示当前区域停止播种
    s32  NextCellLen;       //当前小区长度(不含过道) cm  
    s32  NextCellStartPOS;  // 当前小区沿行进方向的坐标 cm   A点所在小区第一粒种子位置为0点 沿AB线
    s32  NextDisplayRowNum;//调试信息中显示的下排排号
}BZCellParaType;

typedef struct BZStatusType_st
{
    u8  RunState;   //是否在运行状态
    u8  BdState;    //北斗信息是否正常 0:不正常 1:正常
    u8  Resv[2];    //
    s32 Speed;      //单位:mm/s  沿行进方向为正   给用户显示时单位用m/s,如1.30m/s
    s32 RowNum;     //当前正在进行的排编号
    s32 OffLen;      //农机距离A点沿AB线方向的行程 单位cm
    s32 VerticalOff; //农机距离A点垂直AB线方向的行程 单位cm
    u32 LoufeiCnt[LINE_NUM];//漏肥计数
    u32 LouZHCnt[LINE_NUM]; //漏种计数
    s32 Resv2[8-(LINE_NUM-4)*2];    //预留其他状态
}BZStatusType;

typedef struct LXBZParaType_st
{
    s32 Density ;// 株/亩
    s32 CellLen; //行长 计算使用的行长, 应用层暂时可以定死为5米
    s16 Hju;     //行间距  单位cm
    u16 ZhuShu;  // 株数 单位cm 正常情况下由密度计算得到,增加该值的作用是预留以后上位机直接指定。
                 //该值不为0时使用, 为0时自动计算
}LXBZParaType;   //连续播种模式参数


typedef struct TestModeStateType_st
{
    u32 EncoderCnt;  //编码器计数 后期固定为0 编码器取消
    u32 BdCnt;       /*北斗开关状态 计数*/
    u32 LoufeiCnt[LINE_NUM]; //漏肥计数
    u32 LouZHCnt[LINE_NUM];    //漏种计数
#if LINE_NUM==4
    u32 InputState;     /*按位表示输入阀门状态0:未触发 1:触发  0~3 零位开关  4:自动供种接近开关 5:预留输入1   6:钢索1  7:钢索2  
                         8:压力  9:风机   10:脚踏板  11:一键初始化按钮   12北斗  13 ~31保留
                        */
    u32 WarningState; /*
                        */
   u32 CtrlState;     /*按位表示阀门控制状态 0:不动作 1:动作状态  0:预落种 1:倒种  2:清种(转动阀门) 3刮种 4~5预留1~2  6:喇叭 7:打点器 
                        8: 报警灯2  9:运行指示灯 10~15保留   16~19播种盘电机 20自动供种电机
                        */
#else 
    /*6路配置*/
     u32 InputState;     /*按位表示输入阀门状态0:未触发 1:触发  0~3 零位开关1-4  4:自动供种接近开关 5:预留输入1   6:钢索1  7:钢索2  
                         8:压力  9:风机   10:脚踏板  11:一键初始化按钮   12北斗  13-14 零位开关5-6
                        */
    u32 WarningState; /*
                        */
   u32 CtrlState;     /*按位表示阀门控制状态 0:不动作 1:动作状态  
                        0:预落种 1:倒种  2:清种(转动阀门) 3刮种 4~5预留1~2  6:喇叭 7:打点器 
                        8: 报警灯2  9:运行指示灯 10~15保留   16~19播种盘电机 20自动供种电机 21播种盘5 22:播种盘6
                        */
#endif
}TestModeStateType;

typedef struct TestCMDType_st
{
    u16 CtrlNo; /*要控制的控制单元序号*/
    u16 State;  /*阀门状态 0:打开  1:关闭*/
}TestCMDType; /*测试模式下控制命令*/

extern BZCellParaType   BZCellPara; //播种起始参数
extern BZCellParaType   BZCellParaCurr; //播种起始参数 控制板内部备份
extern BZStatusType     BzStatus; //播种状态
extern LXBZParaType     LXBZPara; /*连续播种参数*/
extern TestModeStateType TestStatus; //测试模式下所有状态
extern bool SysReset; /*是否需要重启设备*/
#include "stm32f4xx_hal_flash.h"
u16 CRC16_MODBUS(u8* buf, u32 length);
/***************************************************************************************************
*\Struct        DataNode
*\Description   数据节点
***************************************************************************************************/
typedef struct
{
    void*   Data;   /*!<数据指针*/
    u32     Len;    /*!<数据长度*/
}DataNode;

/***************************************************************************************************
*\Function      FrameAnalysis
*\Description   协议解析
*\Parameter     buf     
*\Parameter     len     
*\Parameter     data_node 数据域地址地址及长度
*\Parameter     fnc       解析到的功能码
*\Return        uint32_t    要删除或解析到的数据长度
*\Note          1)可重入函数,协议相同时所有通讯接口可以复用
*\Log           2020.08.06    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
uint32_t FrameAnalysis(u8* buf, u16 len, DataNode* data_node, u8* fnc);
void FrameProcess(u8 fnc, DataNode* data, void (*sendfunc)(u8*buf, u16 len), u8* construct_buf, u16 buf_len);
/***************************************************************************************************
*\Function      FrameConstruct
*\Description   构造协议帧
*\Parameter     con_buf 构造缓冲区
*\Parameter     fnc     命令字
*\Parameter     data    数据域指针
*\Parameter     data_len  数据域长度
*\Return        u32       构造数据帧总长度
*\Note          1)可重入函数,协议相同时所有通讯接口可以复用
***************************************************************************************************/
u32 FrameConstruct(uint8_t* con_buf, u8 fnc, uint8_t* data, u16 data_len);

/***************************************************************************************************
*\Function      BdAnalysisTask
*\Description   北斗解析任务
*\Parameter     para
*\Return        void
*\Note          
***************************************************************************************************/
void BdAnalysisTask(void const* para);

/***************************************************************************************************
*\Function      Rs232ProtocolAnalysisTask
*\Description   串口协议解析程序
*\Parameter     para
*\Return        void
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
void ProtocolAnalysisTask(void const* para);

#endif /*_PROTOCOL_H*/
