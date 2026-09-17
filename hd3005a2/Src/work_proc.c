/***************************************************************************************************
*                    (c) Copyright 1992-2022 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          work_proc.c
*\Description   系统新工作状态管理相关接口
*\Note          
*\Log           2022.12.07    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "work_proc.h"
#include "operation.h"
#include "para.h"
#include "math.h"
#include "motor.h"
#include "tlib_time.h"


#if ENABLE_BZP_PRE 
#define BZP_PRE_STEPS  ((u32)BZP_HOLE_NUM*(GlobalPara.PrePercent%101))       /*68 播种盘预充种动作孔数*10倍  如68表示6.8个孔位*/
#else
#define BZP_PRE_STEPS  (BZP_HOLE_NUM*70)  /*70 播种盘预充种动作孔数*100倍  如70表示0.7圈的孔位*/
#endif

#define GZ_EN  (GlobalPara.GZEn)   /*0:没有刮种  1:使能刮种结构*/

bool ShiFeiOnFlag; /*TRUE 启动施肥*/

u16 WorkMode; //当前工作模式
u8 BzpInState;  //播种盘输入状态 按位表示各个播种盘  0:零位开关未触发  1:零位开关触发

u32 LXBZCellLen;//用于连续播种计算的小区长度 单位:cm
u32 LXBZZhushu; //当前播种小区的株数
LXBZParaType LXBZPara; /*连续播种参数*/
s32 Zhuju[LINE_NUM]; /*当前小区的株距 cm*/

TestModeStateType TestStatus; //当前测试模式下所有外设状态
u16 CurrentCMDAna; /*当前解析到的命令 */
u32 TestModeCtrl; /*测试模式下控制命令*/

TestCMDType TestCMD; /*测试模式下上位机下发的控制命令*/
u8 DJCtrlState; /*按位表示电机启动状态  0~3播种电机 4:自动供种电机   0:表示电机停止  1:表示电机启动*/

BZCellParaType  BZCellPara; //播种起始参数 上位机下发参数
BZCellParaType  BZCellParaCurr; //播种起始参数 控制板内部备份
BZStatusType    BzStatus; //播种状态

bool GDTapDone; /*当前小区过道中间打点是否结束 FALSE:还未打点  TRUE:已打点*/
s32 GDTapOff;   /*过道中间打点的起始行程cm*/

bool QZTapDone; /*清种时刻打点结束*/
s32 QZTapOff;   /*清种打点的起始行程cm*/

s32 QZStartOff; /*清种开始时刻偏移cm*/

#define CURR_OFF_LEN   (s32)(BdCurrOffCoor.Y*100)   /*行进方向距离cm*/
#define CELL_OFF       (BZCellParaCurr.StartPOS)    /*当前小区起始行程 cm*/
#define CELL_L         (BZCellParaCurr.CellLen)     /*当前小区长度cm*/
#define CELL_S         (BZCellParaCurr.InS)         /*当前小区的过道cm*/

bool DZStartFlag;       /*是否倒种过程已经判断结束*/
bool RowNoUpdateFlag;   /*上位机是否更新了排号*/
bool StateChange;  /*状态变化 临时变量使用*/

#if BD_SIMU_TEST
s32 BdSimuSpeed = 1000;
s32 BDSimuVerticalOff = -481; // 垂直方向距离 cm
s32 BDSimuOff; /*模拟北斗的行程 cm*/
s32 BDSimuStartOff; /*模拟北斗的行程 cm*/
u32 BDSimuStartTime; /*模拟北斗起始时间 ms*/
#endif
/*获取播种盘当前脉冲个数最大值*/
uint32_t GetCurrPulseNum(void)
{
    u8 i;
    uint32_t  max_val = 0;
    for (i = 0; i < (LINE_NUM+1); i++){
        if (i != GZ_STEP_INDEX) {
            if (CurrRunPulseNum[i] > max_val){
                max_val = CurrRunPulseNum[i];
            }
        }
    }

    return max_val;
}

/*获取播种实时状态*/
void GetBzStatus(BZStatusType* st)
{
    u32 i;
    st->RunState = RunState|MoveOn;
    st->OffLen = CURR_OFF_LEN;
    st->Speed = BdCalcSpeed;
    st->VerticalOff = (s32)(BdCurrOffCoor.X*100);
   
    st->RowNum = BZCellParaCurr.RowNum;
    for (i = 0; i < LINE_NUM; i++){
        st->LoufeiCnt[i] = GetLoufeicnt(i);
        st->LouZHCnt[i] = GetLouZhongcnt(i);
    }
    st->BdState = 0;
    if ((CurrBDPos.ValidFlag == 1) && ((osTimeGet() - CurrBDPos.TimeStamp) < 500)){
        /*是否有北斗GPS信号*/
        st->BdState |= 1;
    }
}

/*获取播种盘零位状态 按位表示各个播种盘
bit:0~3 对应播种盘1~4
bit:4 保留
bit:5-6 播种盘5-6
*/
u8 GetBzpInState(void)
{
    /*获取播种盘输入状态*/
    u8 ins = 0;
    ins |= ZERO_IN_STATE(0);
    ins |= (ZERO_IN_STATE(1) << 1);
    ins |= (ZERO_IN_STATE(2) << 2);
    ins |= (ZERO_IN_STATE(3) << 3);

#if LINE_NUM > 4
    /*播种盘5及6*/
    ins |= (ZERO_IN_STATE(4) << 5);
    ins |= (ZERO_IN_STATE(5) << 6);
#endif
    
    return ins;
}

void GetTestStatus(TestModeStateType* tst_state)
{
    u32 i;
    tst_state->EncoderCnt = 0;//GetEncoderNum();
    tst_state->BdCnt = GetBdStartTrigerCnt();
    for (i = 0; i < LINE_NUM; i++){ 
        tst_state->LoufeiCnt[i] = GetLoufeicnt(i);
        tst_state->LouZHCnt[i]  = GetLouZhongcnt(i);
    }

    tst_state->WarningState = 0; //报警状态暂时负值为0
    tst_state->CtrlState = TestModeCtrl;

    /*同步输入状态*/
   /*按位表示输入阀门状态0:未触发 1:触发  0~3 零位开关1-4  4:自动供种接近开关 5:预留输入1   6:钢索1  7:钢索2  
                         8:压力  9:风机   10:脚踏板  11:一键初始化按钮   12北斗  13-14 零位开关5-6
                        */
    tst_state->InputState = 0;
    BzpInState = GetBzpInState();//播种盘零位开关
    tst_state->InputState |= BzpInState&0x0f;
    /*自动供种开关*/
    if (AUTOSEED_IN_STATE() != 0){
        tst_state->InputState |= (1 << 4);
    }
    if(YL_INPUT() != 0){
        tst_state->InputState |= (1 << 5);
    }
    /*钢索*/
    if(GS1_IN_STATE() != 0){
        tst_state->InputState |= (1 << 6);
    }
    if(GS2_IN_STATE() != 0){
        tst_state->InputState |= (1 << 7);
    }
    if(QLYL_INPUT_STATE() != 0){
        tst_state->InputState |= (1 << 8);
    }
    if(FJYL_INPUT_STATE() != 0){
        tst_state->InputState |= (1 << 9);
    }
    if(TBInputState != 0){//脚踏板
        tst_state->InputState |= (1 << 10);
    }
    if(INIT_KEY() != 0){//一键初始化
        tst_state->InputState |= (1 << 11);
    }

    if ((CurrBDPos.ValidFlag == 1) && ((osTimeGet() - CurrBDPos.TimeStamp) < 500)){
        /*是否有北斗GPS信号*/
        tst_state->InputState |= (1 << 12);
    }

    tst_state->InputState |= (BzpInState&0x60)<<8; //播种盘5及6零位开关 13及14位
}

/***************************************************************************************************
*\Function      StopAllCtrl
*\Description   停止所有控制设备
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void StopAllCtrl(void)
{
    YLZ_OFF();
    QZ_OFF();
    DZ_OFF();
    GZ_OFF();       //所有阀门处于关闭状态
    RUN_LED1_OFF(); //运行指示灯关闭
    DJCtrlState = 0;//所有电机关闭状态
    TotalOutputPWMNums = 0;
    SF_MOTOR_OFF(); //施肥电机控制
    ShiFeiOnFlag = FALSE;
}

/***************************************************************************************************
*\Function      TestModeProc
*\Description   测试模式处理 
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void TestModeProc(void)
{
    u32 i;
    u32 ctrl_no;
    u32 state;

    switch (SeedMode)
    {
    case SEED_S_WAIT:
        StopAllCtrl();
        //清除一次按钮
        InitKeyValid = 0;
        
        SeedMode = SEED_S_WAIT_END;
        TotalOutputPWMNums = U32_MAX;
        break;
    case SEED_S_WAIT_END:
        if (InitKeyValid != 0) { //一键初始化按钮 4个播种盘自动恢复到零位
            InitKeyValid = 0;
            SeedMode = SEED_HALF_CYCLE;
            BzpInState = GetBzpInState();
            DJCtrlState = BZP_ZERO_MASK&(~BzpInState);
            ClearBZPPulseNum();
        }
        break;
    case SEED_HALF_CYCLE:
        if (GetCurrPulseNum() < ((GlobalPara.MicroStepValue*STEP_GEAR_RATIO)/2+20)){
             DJCtrlState = BZP_ZERO_MASK;
             sprintf((char*)DebugInfoBuf, "旋转半圈");
        }
        else {
            InitKeyValid = 0;
            SeedMode = SEED_WAIT_ZERO;
            BzpInState = GetBzpInState();
            DJCtrlState = BZP_ZERO_MASK&(~BzpInState);
            ClearBZPPulseNum(); //清零播种盘累计脉冲
            sprintf((char*)DebugInfoBuf, "旋转半圈结束,等待零位");
        }
        break;
    case SEED_WAIT_ZERO:
        if (GetCurrPulseNum() < (GlobalPara.MicroStepValue*STEP_GEAR_RATIO+20)){ //最多动作一圈
            BzpInState = GetBzpInState();
            DJCtrlState = BZP_ZERO_MASK&(~BzpInState);
            if (BZP_ZERO_MASK == BzpInState){
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "初始化成功");
                SeedMode = SEED_S_WAIT_END;
                ClearBZPPulseNum(); //清零播种盘累计脉冲
            }
        }
        else{
            /*超出一圈*/
            SeedMode = SEED_S_WAIT_END;
            DJCtrlState = 0;
            ClearBZPPulseNum(); //清零播种盘累计脉冲
            TotalOutputPWMNums = U32_MAX;
            memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
            sprintf((char*)DebugInfoBuf, "零位开关触发错误");
        }
        InitKeyValid = 0; 
        break;
    default:
        SeedMode = SEED_S_WAIT;
        break;
    }
    /*设备控制命令处理*/
    if (CurrentCMDAna == FNC_CMD_SVCTRL){
        CurrentCMDAna = FNC_CMD_NULL;
        state = TestCMD.State;
        ctrl_no = TestCMD.CtrlNo;
        if (ctrl_no < MAX_CTRL_NUMS){
            if (state == 0){
                TestModeCtrl &= ~(1 << ctrl_no);
            }
            else {
                TestModeCtrl |= 1 << ctrl_no;
            }
            switch (ctrl_no)
            {
            case 0://预落种
                if (state){
                    YLZ_ON(); 
                }
                else {
                    YLZ_OFF(); 
                }
                break;
            case 1://倒种
                if (state){
                    DZ_ON(); 
                }
                else {
                    DZ_OFF();
                }
                break;
            case 2://清种
                if (state){
                    QZ_ON(); 
                }
                else {
                    QZ_OFF();
                }
                break;
            case 3:
            case 4:
            case 5://预留3路
                if (state){
                    YL_CTRL_ON(ctrl_no-3);
                }
                else {
                    YL_CTRL_OFF(ctrl_no-3);
                }
                break;
            case 6://喇叭
                if (state){
                    LB_ON(); 
                }
                else {
                    LB_OFF();
                }
                break;
            case 7://打点器
                if (state){
                    TAPPER_ON();
                    TapperOnStartTime = osTimeGet(); 
                }
                else {
                    TAPPER_OFF();
                }
                break;
            case 8://报警灯2
                if (state){
                    WARNING_LED2_ON(); 
                }
                else {
                    WARNING_LED2_OFF();
                }
                break;
            case 9://运行指示灯
                if (state){
                    RUN_LED1_ON(); 
                }
                else {
                    RUN_LED1_OFF();
                }
                break;
            case 16://播种盘1
            case 17://播种盘2
            case 18://播种盘3
            case 19://播种盘4
            case 20://自动供种电机 
            case 21://播种盘5  
            case 22://播种盘6
                if (state){
                    DJCtrlState |= 1<<(ctrl_no-16);
                }
                else {
                    DJCtrlState &= ~(1<<(ctrl_no-16));
                }
                break;
            default:
                break;
            }
        }
    }
    state = 0;
    /*所有阀门控制状态*/
    for (i = 0; i < 12; i++){
        if (CtrlValveState[i]){
            state |= (1 << i);
        }
    }
    /*电机控制状态*/
    state |= (DJCtrlState << 16);
    TestModeCtrl = state;
    /*上位机状态切换命令响应*/
    if (CurrentCMDAna != FNC_CMD_NULL){
        switch (CurrentCMDAna)
        {
        case FNC_CMD_START_BZ:
            WorkMode = WORK_MODE_BD; //启动播种模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_LXBZ:
            WorkMode = WORK_MODE_LXBZ; //启动连续播种模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_STOP_TEST:
            WorkMode = WORK_MODE_IDLE; //停止测试模式
            sprintf((char*)DebugInfoBuf, "停止状态");
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_STOP;
            break;
        default:
            break;
        }
        CurrentCMDAna = FNC_CMD_NULL;
    }
}

void IdleModeProc(void)
{
    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
    sprintf((char*)DebugInfoBuf, "空闲模式");

    if (CurrentCMDAna != FNC_CMD_NULL){
        switch (CurrentCMDAna)
        {
        case FNC_CMD_START_BZ:
            WorkMode = WORK_MODE_BD; //进入播种模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_TEST:
            WorkMode = WORK_MODE_TEST; //开始测试模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_LXBZ:
            WorkMode = WORK_MODE_LXBZ; //进入连续播种模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        default:
            break;
        }
        CurrentCMDAna = FNC_CMD_NULL;
    }
}

/***************************************************************************************************
*\Function      GetZhuShu
*\Description   
*\Parameter     density     密度:株/亩     Q
*\Parameter     cell_len    小区长度   cm  L
*\Parameter     hju         行间距 单位cm  H
*\Return        u32
*\Note          1)株距=cell_len/(株数-1)
***************************************************************************************************/
u32 GetZhuShu(u32 density, u32 cell_len, u16 hju)
{
    u32 zhushu;  //单行株数
    if (cell_len < 20){
        cell_len = 20;
    }
    zhushu = ceil((density*1.0)*(hju*0.01)*(cell_len*0.01)/666.67); //上取整 如3.1取4

    if (zhushu < 2){
        zhushu = 2;
    }

    return zhushu;
}

/***************************************************************************************************
*\Function      GetZhuJu
*\Description   计算株距
*\Parameter     cell_len  小区总长度 cm
*\Parameter     N         小区株数
*\Return        u32
***************************************************************************************************/
u32 GetZhuJu(u32 cell_len, u32 N){
    return  (cell_len*10/(N-1) + 5)/10; //株距四舍五入
}

/***************************************************************************************************
*\Function      LXBZParaCheck
*\Description   连续播种模式参数检查
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void LXBZParaCheck(void)
{
    if (LXBZPara.Density < 100){
        LXBZPara.Density = 1000;
    }
    if (LXBZPara.Hju < 5){
        LXBZPara.Hju = 60; //默认行距60cm
    }
    if (LXBZPara.CellLen < 10){
        LXBZPara.CellLen = 500; //默认5米行长
    }
}

void LXBZProc(void)
{
    if (RunState == RUN_S_START){
        //运行模式
        switch (SeedMode)
        {
        case SEED_S_WAIT:
#if BD_SIMU_TEST
            BDSimuOff = 0;
            BDSimuStartTime = osTimeGet();
            StateStartTime = osTimeGet();
#else 
            if ((CurrBDPos.ValidFlag == 0) || ((osTimeGet() - CurrBDPos.TimeStamp) > 500)){
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "无法获取定位信息");
                break;
            }

            /*更新A点信息*/
            BDPara.StartE     = CurrBDPos.E;
            BDPara.StartN     = CurrBDPos.N; /*起始A点经纬度*/
            BDPara.StartState = 1;  //A点经纬度有效
            BDPara.StartDir   = 0;  /*起始行进方向 在锁定AB线之前不使用方向信号, 只关注直线距离*/
            BDPara.CalcDirFlag = 0;//AB线方向还无效
            BDPara.BDOffTime = 100;//北斗延迟100ms
            BDPara.OffLen = 0; //cm 偏移值  
            NewPosGetFlag = TRUE; //强制触发一次坐标计算,保证尽快更新到A点距离
            /*同向*/
            BDTXFlag = TRUE;
#endif
            BZCellParaCurr.RowNum = 0;
            SeedMode = SEED_S_WAIT_END;
            MoveOn = 0x80;
            ClearBZPPulseNum(); //清零播种盘累计脉冲
            TotalOutputPWMNums = UINT32_MAX;
            ClearLzCnt();
            LXBZParaCheck();
            LXBZCellLen = LXBZPara.CellLen; //连续播种下,暂定参与计算的小区长度为5米
            if (LXBZPara.ZhuShu > 2){
                LXBZZhushu = LXBZPara.ZhuShu;
            }
            else{
                /*计算株距*/
                LXBZZhushu = GetZhuShu(LXBZPara.Density, LXBZCellLen, LXBZPara.Hju);
            }
            break;
        case SEED_S_WAIT_END:
            ShiFeiOnFlag = TRUE;
            sprintf((char*)DebugInfoBuf, "连续播种模式 株距:%dcm", GetZhuJu(LXBZCellLen, LXBZZhushu));
            /*连续播种时：倒种、预落种常开，清种、刮种常闭*/
            DZ_ON();YLZ_ON();QZ_OFF();GZ_OFF();
            DJCtrlState = BZP_ZERO_MASK; //使能4个步进电机
            break;
        default:
            SeedMode = SEED_S_WAIT;
            break;
        }
    }
    else {
        MoveOn = 0;
        //停止模式
        StopAllCtrl();
        memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
        sprintf((char*)DebugInfoBuf, "停止模式");
        ShiFeiOnFlag = FALSE;
    }

    /*命令响应*/
    if (CurrentCMDAna != FNC_CMD_NULL){
        switch (CurrentCMDAna)
        {
        case FNC_CMD_START_BZ:
            WorkMode = WORK_MODE_BD; //进入播种模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_TEST:
            WorkMode = WORK_MODE_TEST; //开始测试模式
            sprintf((char*)DebugInfoBuf, "测试模式");
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_LXBZ:
            WorkMode = WORK_MODE_LXBZ; //进入连续播种模式
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
            //  case FNC_CMD_STOP_BZ:   //停止播种模式
            //      break;
            //  case FNC_CMD_STOP_TEST:
            //      TestMode = WORK_MODE_IDLE; //停止测试模式
            //      break;
        case FNC_CMD_STOP_LXBZ:   //停止连续播种模式
            sprintf((char*)DebugInfoBuf, "停止状态");
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_STOP;
            break;
        default:
            break;
        }
        CurrentCMDAna = FNC_CMD_NULL;
    }
}

/***************************************************************************************************
*\Function      UpdateRowNum
*\Description   更新下一个小区
*\Parameter     
*\Return        bool
*\Note          
*\Log           2023.01.09    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateRowNumCheck(void)
{
    RowNoUpdateFlag = FALSE;
    
    if (BZCellParaCurr.RowNum != BZCellParaCurr.NextRowNum){
        /*当前NEXT区域还未使用,继续使用NEXT区域*/
        if (BZCellParaCurr.NextDensity[0] >= 0){
            /*密度小于0表示最后一个区域*/
            RowNoUpdateFlag = TRUE;
        }
    }
    else {
        /*当前所有小区信息已经使用,检查是否有上位机新下发小区信息*/
        if ((BZCellPara.RowNum == BZCellParaCurr.RowNum) && (BZCellPara.NextRowNum != BZCellParaCurr.RowNum)){
            RowNoUpdateFlag = TRUE;
            BZCellParaCurr.NextRowNum       = BZCellPara.NextRowNum;
            BZCellParaCurr.NextInS          = BZCellPara.NextInS;
            memcpy(BZCellParaCurr.NextDensity, BZCellPara.NextDensity, sizeof(BZCellParaCurr.NextDensity));
            BZCellParaCurr.NextCellLen      = BZCellPara.NextCellLen;
            BZCellParaCurr.NextCellStartPOS = BZCellPara.NextCellStartPOS;
            BZCellParaCurr.NextFinalFlag    = BZCellPara.NextFinalFlag;
            BZCellParaCurr.DisplayRowNum = BZCellPara.DisplayRowNum;
            BZCellParaCurr.NextDisplayRowNum = BZCellPara.NextDisplayRowNum;
        }
    }
    
    //  if (RowNoUpdateFlag == TRUE){
        BZCellParaCurr.FinalFlag = BZCellParaCurr.NextFinalFlag;//最后一个小区指示

        BZCellParaCurr.RowNum   = BZCellParaCurr.NextRowNum;
        BZCellParaCurr.DisplayRowNum = BZCellParaCurr.NextDisplayRowNum;

        BZCellParaCurr.InS      = BZCellParaCurr.NextInS;

        memcpy(BZCellParaCurr.Density, BZCellParaCurr.NextDensity, sizeof(BZCellParaCurr.Density));
        BZCellParaCurr.CellLen  = BZCellParaCurr.NextCellLen;
        BZCellParaCurr.StartPOS = BZCellParaCurr.NextCellStartPOS;
   // }
    if (BZCellParaCurr.NextDensity[0] < 0){
        RowNoUpdateFlag = FALSE;
    }
    
    return RowNoUpdateFlag;
}

/***************************************************************************************************
*\Function      GetQzStartOff
*\Description   获取清种时刻所在行程坐标 cm 
*\Parameter     
*\Return        s32
*\Note          
***************************************************************************************************/
s32 GetQzStartOff(void)
{
    s32 res;
    //s32 cell_len = BZCellParaCurr.CellLen;
   // s32 seed_num;
    if (BDTXFlag == TRUE){//同向
        res = CELL_OFF+CELL_L+(s32)GlobalPara.A-GlobalPara.B-(BZP_PRE_STEPS*Zhuju[0]/100);
    }
    else { //反向
        res = CELL_OFF-(CELL_L+(s32)GlobalPara.A-GlobalPara.B-(BZP_PRE_STEPS*Zhuju[0]/100));
    }
    QZStartOff = res;
   
    return res;
}

/*计算清种打点的起始坐标*/
void GetQZTapOff(void)
{
    QZTapOff = GetQzStartOff();
    /*清种时刻行程开关所在位置   */
    if (BDTXFlag == TRUE){//同向    
        QZTapOff = QZTapOff - (s32)GlobalPara.TappTrigOff;
    }
    else { //反向
        QZTapOff = QZTapOff+(s32)GlobalPara.TappTrigOff;
    }
}

/***************************************************************************************************
*\Function      QZTapProc
*\Description   清种打点逻辑控制
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void QZTapProc(void)
{
    if (QZTapDone == FALSE){
        //当前小区过道中间打点还未开始 判断是否满足起始打点条件
        if (BDTXFlag == TRUE){/*同向*/
            /*行程位置已经到达过道中间打点位置*/
            if ((CURR_OFF_LEN+3) >= QZTapOff){
                QZTapDone = TRUE;
                if (QZDDEnable){
                    TAPPER_ON();
                }
            }
        }
        else {/*反向*/
            if ((CURR_OFF_LEN-3) <= QZTapOff){
                QZTapDone = TRUE;
                if (QZDDEnable){
                    TAPPER_ON();
                }
            }
        }
    }
}

/*计算过道中间打点的起始坐标*/
void GetGDTapOff(void)
{
    if (BDTXFlag == TRUE){/*同向*/
        GDTapOff = BZCellParaCurr.StartPOS+(BZCellParaCurr.CellLen+
            BZCellParaCurr.InS/2-(s32)GlobalPara.TappTrigOff); //过道中间位置 提前一点距离(打点器到行程开关距离)
    }
    else {
        /*反向*/
        GDTapOff = BZCellParaCurr.StartPOS-(BZCellParaCurr.CellLen+
            BZCellParaCurr.InS/2-(s32)GlobalPara.TappTrigOff); //过道中间位置 提前一点距离(打点器到行程开关距离)
    }
}

/***************************************************************************************************
*\Function      GDTapProc
*\Description   过道中间打点逻辑控制
*\Parameter     
*\Return        void
*\Note          
*\Log           2023.01.10    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
void GDTapProc(void)
{
    if (GDTapDone == FALSE){
        //当前小区过道中间打点还未开始 判断是否满足起始打点条件
        if (BDTXFlag == TRUE){/*同向*/
            /*行程位置已经到达过道中间打点位置*/
            if ((CURR_OFF_LEN+3) >= GDTapOff){
                GDTapDone = TRUE;
                if (GDDDEnable == TRUE){
                    TAPPER_ON();
                }

            }
        }
        else {/*反向*/
            if ((CURR_OFF_LEN-3) <= GDTapOff){
                GDTapDone = TRUE;
               if (GDDDEnable == TRUE){
                    TAPPER_ON();
               }
            }
        }
    }
}
bool NextYLZOn = FALSE; //下一个小区预落种是否打开
/*清零播种盘累计脉冲*/
void ClearBZPPulseNum(void)
{
    memset(&CurrRunPulseNum[0], 0x00, 16); //清零播种盘累计脉冲
#if LINE_NUM > 4
    memset(&CurrRunPulseNum[5], 0x00, 8);
#endif
}
/***************************************************************************************************
*\Function      BZModeProc
*\Description   播种模式
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void BZModeProc(void)
{
    u32 i;
    u32 row_num;
    if (RunState == RUN_S_STOP){
        MoveOn = 0;
        ShiFeiOnFlag = FALSE; //停止施肥
        memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
        sprintf((char*)DebugInfoBuf, "停止模式");
        StopAllCtrl(); //停止模式
       // return;
    }
    else {//运行模式
        switch (SeedMode)
        {
        case SEED_S_WAIT:
            StopAllCtrl();
            ShiFeiOnFlag = FALSE;
            BZCellParaCurr.RowNum = -10000000;//暂时标记当前播种排号为无效值,防止播种中断情况下，还未实质播种但是上位机记录当前小区为已播种状态
#if BD_SIMU_TEST
            osDelay(600); //让上位机有时间获取无效行号
            if (BZCellPara.TXFlag == 1){
                BDTXFlag = TRUE;
                /*同向*/
                BDSimuStartOff = BZCellPara.StartPOS - 800;
            }
            else {
                /*反向*/
                BDTXFlag = FALSE;
                BDSimuStartOff = BZCellPara.StartPOS + 800;
            }
            BDSimuOff = 0;
            BDSimuStartTime = osTimeGet();
            //osDelay(600); //让上位机有时间获取无效行号
#else
            osDelay(600); //让上位机有时间获取无效行号
            if ((CurrBDPos.ValidFlag == 0) || ((osTimeGet() - CurrBDPos.TimeStamp) > 500)){
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "无法获取定位信息");
                break;
            }
#endif
            memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
#if BD_SIMU_TEST
            BDSimuVerticalOff += 240;
#endif
           /*判断序号递增关系*/
           if (BZCellPara.DisplayRowNum < BZCellPara.NextDisplayRowNum){
               RowNumIncrease = TRUE;
           }
           else {
               RowNumIncrease = FALSE;
           }
            SeedMode = SEED_WAIT_ZERO;  //等待所有播种盘零位开关触发
             memcpy(&BZCellParaCurr, &BZCellPara, sizeof(BZCellParaType)); //同步当前播种小区参数
            if (GlobalPara.ZeroPosEn != 0){ //使用零位开关同步各个播种盘
                SeedMode = SEED_HALF_CYCLE;  //固定旋转半圈
                sprintf((char*)DebugInfoBuf, "等待零位");
                BzpInState = GetBzpInState();
                DJCtrlState = BZP_ZERO_MASK&(~BzpInState);
                ClearBZPPulseNum(); //清零播种盘累计脉冲
                TotalOutputPWMNums = (GlobalPara.MicroStepValue*STEP_GEAR_RATIO+20); //最大转动一周即可,若是一周还未触发,说明有故障
            }
            else {
                DJCtrlState = 0; //若是没有零位开关不需要同步电机
                ClearBZPPulseNum(); //清零播种盘累计脉冲
                TotalOutputPWMNums = 0;
                sprintf((char*)DebugInfoBuf, "预充种");
            }
#if BD_SIMU_TEST
            BDTXFlag = BZCellPara.TXFlag==0?FALSE:TRUE;
            SeedMode = SEED_PRE_DZ;
            //SeedMode = SEED_WAIT_ZERO;  //农机上可以增加零位开关功能
            ClearBZPPulseNum(); //清零播种盘累计脉冲
            SeedMode = SEED_HALF_CYCLE;
            StateStartTime = osTimeGet();
            BzpInState = GetBzpInState();
             TotalOutputPWMNums = (GlobalPara.MicroStepValue*STEP_GEAR_RATIO+20);
#endif
            break;
        case SEED_HALF_CYCLE:
            /*播种盘固定旋转半圈*/
            if (GetCurrPulseNum() < (GlobalPara.MicroStepValue*STEP_GEAR_RATIO/2)){ //最多动作一圈
                DJCtrlState = BZP_ZERO_MASK;
                //TotalOutputPWMNums = U32_MAX;
                sprintf((char*)DebugInfoBuf, "旋转半圈");
            }
            else {
                sprintf((char*)DebugInfoBuf, "等待零位");
                BzpInState = GetBzpInState();
                DJCtrlState = BZP_ZERO_MASK&(~BzpInState);
                ClearBZPPulseNum(); //清零播种盘累计脉冲
                SeedMode = SEED_WAIT_ZERO;  //等待所有播种盘零位开关触发
            }
            break;
        case SEED_WAIT_ZERO:
            //等待所有零位开关触发
#if BD_SIMU_TEST
            GlobalPara.ZeroPosEn = 0;
#endif
            BzpInState = GetBzpInState();
            if (GlobalPara.ZeroPosEn == 0){/*若是不使用零位开关, 则认为零位开关都到位置*/
                BzpInState = BZP_ZERO_MASK;
            }
            if (GetCurrPulseNum() < (GlobalPara.MicroStepValue*STEP_GEAR_RATIO+20)){ //最多动作一圈
                DJCtrlState = BZP_ZERO_MASK&(~BzpInState);
                if (BZP_ZERO_MASK == BzpInState){
                    osDelay(2);//等待电机控制停止
                    ClearBZPPulseNum();//清零播种盘累计脉冲零位作为未来脉冲计数的零点
                    TotalOutputPWMNums = 0;
                    /*所有播种盘都已到位*/
                    SeedMode = SEED_PRE_DZ;
                    if (BZCellParaCurr.Density[0] > 0){
                        NextYLZOn = TRUE;
                    }
                    else {
                        NextYLZOn = FALSE;
                    }
                    StateStartTime = osTimeGet();
                    if (NextYLZOn == TRUE){
                        YLZ_ON(); //预落种
                    }
                    else {
                        YLZ_OFF();
                    }
                    
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    if (GZ_EN != 0){
                        //if (BZCellParaCurr.Density[0] > 0){
                             QZ_ON();  //清种
                             sprintf((char*)DebugInfoBuf, "预充种-清种[%d]", BZCellParaCurr.DisplayRowNum/*RowNum+1*/);
                      //  }
                       // else {
                             //QZ_OFF();  //清种
                            // sprintf((char*)DebugInfoBuf, "跳过预充种-清种[%d]", BZCellParaCurr.RowNum+1);
                      //  }
                        //DZ_ON();  //倒种
                    }
                    else {
                        if (NextYLZOn == TRUE){
                            sprintf((char*)DebugInfoBuf, "预充种-预落种[%d]", BZCellParaCurr.DisplayRowNum/*RowNum+1*/);
                        }
                        else {
                            sprintf((char*)DebugInfoBuf, "跳过预充种-预落种[%d]", BZCellParaCurr.DisplayRowNum/*RowNum+1*/);
                        }
                    }
                }
            }
            else {
                /*电机控制超过一圈但是一直未能触发零位开关*/
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "零位开关触发错误");
                DJCtrlState = 0;//停止电机转动
                ShiFeiOnFlag = FALSE;
                SeedMode = SEED_ERR_WAIT;
                //break;
            }
            break;
        case SEED_PRE_DZ:
            //预充种-倒(投)种
            if ((osTimeGet() - StateStartTime) >= (UserPara.DZTime)){
                QZ_OFF();  //清种
                YLZ_OFF(); //预落种
                if ((BZCellPara.FinalFlag == 0) && (BZCellPara.NextDensity[0] > 0)){
                    DZ_ON();   //倒(投)种 当前小区不是最后一个小区
                    StartGZStepMotor();
                    NextYLZOn = TRUE;
                }
                else{
                    DZ_OFF();
                    NextYLZOn = FALSE;
                }
                if (GZ_EN != 0){
                    GZ_ON();  //开始刮种
                }
                
                if (RowNumIncrease == TRUE){
                    row_num = BZCellPara.DisplayRowNum+1;//BZCellPara.RowNum+2;
                }
                else {
                    row_num = BZCellPara.DisplayRowNum-1;
                }
                if (NextYLZOn == TRUE){
                     sprintf((char*)DebugInfoBuf, "预充种-播种盘调整[%d] 倒种[%d]", BZCellPara.DisplayRowNum/*RowNum+1*/, row_num);
                }
                else {
                    /*下个小区是最后一个则跳过倒种*/
                    sprintf((char*)DebugInfoBuf, "预充种-播种盘调整[%d] 跳过倒种[%d]", BZCellPara.DisplayRowNum/*RowNum+1*/, row_num);
                }
               
                StateStartTime = osTimeGet();
                SeedMode = SEED_PRE_MOTOR;
                DJCtrlState = BZP_ZERO_MASK; //所有电机转动
                ClearBZPPulseNum(); //清零播种盘累计脉冲 零位作为未来脉冲计数的零点
                TotalOutputPWMNums  = (BZP_PRE_STEPS*GlobalPara.MicroStepValue*STEP_GEAR_RATIO)/(BZP_HOLE_NUM*100); //提前动作6.8个孔位
            }
            break;
        case SEED_PRE_MOTOR:
            RowNoUpdateFlag = TRUE; //刚开始默认上位机已经更新小区信息
            //预充种-播种盘调整
            if (GetCurrPulseNum() >= TotalOutputPWMNums){
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "等待开始播种[%d]",BZCellPara.DisplayRowNum);
                DJCtrlState = 0;        //播种盘已到位,等待农机开始行走
                ClearBZPPulseNum(); //清零播种盘累计脉冲
                TotalOutputPWMNums = 0; //等待触发条件满足再开始播种盘转动
                StateStartTime = osTimeGet();
                SeedMode = SEED_S_START;
                DirValid = FALSE;       //方向判断无效
                DirPDStartOff = 0.0;    //判断行进方向起始距离变量
                DirPDEndOff = 0.0;
                ClearLzCnt(); //清除漏种数
                ClearBdStartTrigerCnt();//清除行程开关计数,等待触发行程开关
                RUN_LED1_ON();          // 运行指示灯点亮,提示用户可以开始农机行驶过程
            }
            else {
                /*播种盘动作未到位*/
            }
            break;
        case SEED_S_START: //判断AB线数据,若无AB线等待行程开关触发, 若有则判断行进方向
#if BD_SIMU_TEST
            BDTXFlag = BZCellPara.TXFlag==0?FALSE:TRUE;;
            memcpy(&BZCellParaCurr, &BZCellPara, sizeof(BZCellParaType)); //同步当前播种小区参数

            SeedMode = SEED_WAIT_S_BZP; //切换到等待播种盘动作阶段
            StateStartTime = osTimeGet();
            DirValid = TRUE;//方向有效
            break;
#endif
            if ((CurrBDPos.ValidFlag == 0) || ((osTimeGet() - CurrBDPos.TimeStamp) > 500)){
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "无法获取定位信息");
                break;
            }
            MoveOn = 0x80;
            if (BDPara.StartState == 0){/*还没有起始点,等待北斗行程开关触发*/
                BDTXFlag = TRUE;  /*方向判断确定为同向*/
                if (GetBdStartTrigerCnt() != 0){
                    /*存储A点信息*/
                    BDPara.StartE     = CurrBDPos.E;
                    BDPara.StartN     = CurrBDPos.N; /*起始A点经纬度*/
                    BDPara.StartState = 1;  //A点经纬度有效
                    BDPara.StartDir   = 0;  /*起始行进方向 在锁定AB线之前不使用方向信号, 只关注直线距离*/
                    BDPara.CalcDirFlag = 0;//AB线方向还无效
                    BDPara.BDOffTime = 100;//北斗延迟100ms
                    BDPara.OffLen = (BDPara.BDOffTime+osTimeGet()-CurrBDPos.TimeStamp)*AvgSpeed/*GlobalPara.SpeedV1*//10000; //cm 偏移值  

                    memcpy(&BZCellParaCurr, &BZCellPara, sizeof(BZCellParaType)); //同步当前播种小区参数
                    SeedMode = SEED_WAIT_S_BZP; //切换到等待播种盘动作阶段
                    StateStartTime = osTimeGet();
                    DirValid = TRUE;//方向有效
                    NewPosGetFlag = TRUE; //强制触发一次坐标计算,保证尽快更新到A点距离
                    WriteBDPara(&BDPara);
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "等待播种盘动作[%d]", BZCellParaCurr.DisplayRowNum);
                }
                else{
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "等待行程开关触发");
                }
            }
            else  {//A点经纬度已有 进行方向判断, 判断完成后切换到下一阶段
                if (DirValid == FALSE){
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "判断速度及方向");
                    /*方向判断还无效需要判断方向*/
                    if (DirPDStartOff==0.0){
                        /*还未获取起始偏移*/
                        DirPDStartOff   = BdCurrOffCoor.Y;
                        DirPDEndOff     = BdCurrOffCoor.Y;
                        DirPDStartTime  = osTimeGet();
                    }
                    else {
                        DirPDEndTime = osTimeGet();
                        DirPDEndOff = BdCurrOffCoor.Y;
                        db_sub = (DirPDEndOff-DirPDStartOff);
                        if (db_sub < 0){
                            db_sub = -1*db_sub;
                        }
                        if (((DirPDEndTime-DirPDStartTime) >= 2000) || (db_sub > 0.3)){
                            if (db_sub >= 0.20){
                                /*2秒内行走距离在0.2米以上*/
                                if (DirPDEndOff > DirPDStartOff) {//距离A点行程在变大,同向
                                    BDTXFlag = TRUE;
                                }
                                else {/*距离在变小，说明反向*/
                                    BDTXFlag = FALSE;
                                }
                                memcpy(&BZCellParaCurr, &BZCellPara, sizeof(BZCellParaType)); //同步当前播种小区参数
                                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                                sprintf((char*)DebugInfoBuf, "等待播种盘动作[%d]", BZCellParaCurr.DisplayRowNum);

                                SeedMode = SEED_WAIT_S_BZP; //切换到等待播种盘动作阶段
                                StateStartTime = osTimeGet();
                                DirValid = TRUE;            //方向有效
                                NewPosGetFlag = TRUE;       //强制触发一次坐标计算,保证尽快更新到A点距离
                                break;
                            }
                            else {
                                /*行走距离太短,重新获取起始偏移*/
                                DirPDStartOff = BdCurrOffCoor.Y;
                                DirPDEndOff = BdCurrOffCoor.Y;
                                DirPDStartTime = osTimeGet();
                            }
                        }
                    }
                    break;
                }
            }
            break;
        case SEED_WAIT_S_BZP: //等待农机到触发播种盘开始转动的位置
            /*判断行进方向与上位机下发是否一致,若是不一致则报错*/
            if (BZCellParaCurr.TXFlag != (u8)BDTXFlag){
                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "下发方向与实际行驶方向不符");
                DJCtrlState = 0;//停止电机转动
                ShiFeiOnFlag = FALSE;
                SeedMode = SEED_ERR_WAIT;
                break;
            }

            StateChange = FALSE;
            if (BDTXFlag == TRUE){ //同向
                if ((CURR_OFF_LEN+3+20) >= (CELL_OFF + (s32)GlobalPara.A-(s32)GlobalPara.B)){
                    //等待满足启动播种盘条件
                    StateChange = TRUE;
                }
            }
            else {//反向
                if ((CURR_OFF_LEN-3-20) <= (CELL_OFF - ((s32)GlobalPara.A-(s32)GlobalPara.B))){
                    //等待满足启动播种盘条件
                    StateChange = TRUE;
                }
            }
            if (StateChange == TRUE){
                for (i = 0; i < (LINE_NUM+1); i++){
                    if (i != GZ_STEP_INDEX){
                    GetStepPulseTime(i, 1000);
                    }
                }
                //GetStepPulseTime(1000); //触发一次计算株距操作
                ShiFeiOnFlag = TRUE;    /*施肥电机可以开始动作*/
                QZTapDone = FALSE;      //第一个小区清种打点不需要
                GDTapDone = FALSE;      //当前小区过道中间打点还未开始
                GetGDTapOff();          //计算小区过道打点坐标
                GetQzStartOff();        //计算清种开始时刻偏移
                ClearBZPPulseNum(); //清零播种盘累计脉冲
                TotalOutputPWMNums  = UINT32_MAX;//播种电机开始动作
                DJCtrlState = BZP_ZERO_MASK;
                GZ_OFF();  //结束刮种
                SeedMode = SEED_S_WAIT_QZ; //切换到等待下一小区清种
                StateStartTime = osTimeGet();

                memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                sprintf((char*)DebugInfoBuf, "等待清种[%d]", BZCellParaCurr.DisplayRowNum);
            }
            break;
        case SEED_S_WAIT_QZ:
            QZTapProc();    //清种时刻打点控制逻辑
            GDTapProc();    //过道中间打点控制逻辑
            if (GDTapDone == TRUE){
                //上一小区的过道中间打点已经完成 更新下一个打点坐标
                GDTapDone = FALSE;
                GetGDTapOff(); //计算小区过道打点坐标
            }
            /*等待触发清种操作*/
            StateChange = FALSE;
            //清种开始时刻距离当前小区起点:(L+S+A)-(B+ (S+6.8d))=L-B-6.8d
            if (BDTXFlag == TRUE){//同向
                if ((CURR_OFF_LEN+3) >= (QZStartOff)){
                    StateChange = TRUE;
                }
            }
            else { //反向  @TODO反向时起始位置需要修订反向修订距离
                if ((CURR_OFF_LEN-3+GlobalPara.BDiroff) <= (QZStartOff)){
                    StateChange = TRUE;
                }
            }

            if (StateChange == TRUE){
                /*已满足清种触发条件*/
                if (BZCellParaCurr.Density[0] > 0){
                    QZ_ON();
                }
                if (GZ_EN != 0){ //有刮种结构
                     if (NextYLZOn == TRUE){
                         YLZ_ON(); //当前不是最后一个小区
                     }
                }
                else {
                    /*没有刮种功能 不能同时开启预落种阀门*/
                }
                DZStartFlag = FALSE; //倒种判断未开始
                SeedMode = SEED_S_WAIT_GZ; //等待刮种
                StateStartTime = osTimeGet();
                //GetStepPulseTime(1000); //触发一次计算株距操作
                if (GZ_EN != 0){
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "等待刮种[%d]", BZCellParaCurr.DisplayRowNum);
                }
                else {
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    if (BZCellParaCurr.Density[0] > 0){
                         sprintf((char*)DebugInfoBuf, "开始清种[%d]", BZCellParaCurr.DisplayRowNum);
                    }
                    else {
                         sprintf((char*)DebugInfoBuf, "跳过清种[%d]", BZCellParaCurr.DisplayRowNum);
                    }
                   
                    SeedMode = SEED_S_GZ; //跳过刮种开始
                }
            }
            break;
        case SEED_S_WAIT_GZ:
            GDTapProc();//过道中间打点控制逻辑
            StateChange = FALSE;
            /*判断清种停止时刻到,停止清种*/
            if (BDTXFlag == TRUE){//同向
                if ((CURR_OFF_LEN+3) >= (QZStartOff+(CELL_S-1*Zhuju[0]))){
                    StateChange = TRUE;
                }
            }
            else { //反向
                if ((CURR_OFF_LEN-3+GlobalPara.BDiroff) <= (QZStartOff-(CELL_S-1*Zhuju[0]))){
                    StateChange = TRUE;
                }
            }
            /*满足清种结束条件*/
            if (StateChange == TRUE){
                QZ_OFF(); //关闭清种阀门
                if (GZ_EN != 0){ //有刮种结构
                    YLZ_OFF();
                }
                else {
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                   
                    /*没有刮种功能 清种关闭后开启预落种阀门*/
                    if (BZCellParaCurr.FinalFlag == 0){
                        if (RowNumIncrease == TRUE){
                            row_num = BZCellParaCurr.DisplayRowNum+1;//BZCellParaCurr.RowNum+2;
                        }
                        else {
                            row_num = BZCellParaCurr.DisplayRowNum-1;
                        }
                        if (NextYLZOn == TRUE){
                            YLZ_ON();
                            sprintf((char*)DebugInfoBuf, "开始预落种[%d]", row_num);
                        }
                        else {
                            //YLZ_OFF();
                            sprintf((char*)DebugInfoBuf, "跳过预落种[%d]", row_num);
                        }
                    }
                    else{
                        sprintf((char*)DebugInfoBuf, "等待当前小区完成[%d]", BZCellParaCurr.DisplayRowNum/*RowNum+1*/);
                    }
                }

                if (DZStartFlag == FALSE){ //清种结束后开始倒种 @TODO是否需要延迟一会，让阀门关闭后再开始倒种
                    DZStartFlag = TRUE;
                    /*不是最后一个小区,说明需要倒种操作*/
                    if (GZ_EN != 0){ //有刮种结构 打开倒种开关
                        if (RowNumIncrease == TRUE){
                            row_num = BZCellParaCurr.DisplayRowNum+1;
                        }
                        else {
                            row_num = BZCellParaCurr.DisplayRowNum-1;
                        }
                        if (BZCellParaCurr.FinalFlag == 0){
                            if (BZCellPara.isAfterNextZoneSow == 1){
                                DZ_ON(); //下个小区还要继续播种
                                StartGZStepMotor();
                                NextYLZOn = TRUE;
                                sprintf((char*)DebugInfoBuf, "开始倒种[%d]", row_num);
                            }
                            else {
                                NextYLZOn = FALSE;
                                DZ_OFF();
                                sprintf((char*)DebugInfoBuf, "跳过倒种[%d]", row_num);
                            }
                        }
                        else{
                            NextYLZOn = FALSE;
                            /*最后一个小区当前已经是最后一个小区则跳过下一个小区倒种*/
                            sprintf((char*)DebugInfoBuf, "跳过倒种[%d] 等待当前小区结束[%d]", row_num, BZCellParaCurr.DisplayRowNum);
                        }
                    }
                    else {
                    }
                }
            }
            /*判断刮种开始时刻到*/
            StateChange = FALSE;
            if (BDTXFlag == TRUE){//同向
                if ((CURR_OFF_LEN+3) >= (CELL_OFF+CELL_L+(s32)GlobalPara.A-GlobalPara.B)){
                    StateChange = TRUE;
                }
            }
            else { //反向
                if ((CURR_OFF_LEN-3+GlobalPara.BDiroff) <= (CELL_OFF-(CELL_L+(s32)GlobalPara.A-GlobalPara.B))){
                    StateChange = TRUE;
                }
            }
            if (StateChange == TRUE){
                if (GZ_EN != 0){
                    /*刮种时刻到*/
                    GZ_ON();
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "开始刮种[%d]", BZCellParaCurr.DisplayRowNum);
                }
                SeedMode = SEED_S_GZ; //等待刮种过程结束
                StateStartTime = osTimeGet();
            }
            break;
        case SEED_S_GZ: /*等待刮种结束 切换到下一小区号*/
            GDTapProc();//过道中间打点控制逻辑
            /*判断清种结束时刻到,停止清种*/
            StateChange = FALSE;
            if (BDTXFlag == TRUE){//同向
                if ((CURR_OFF_LEN+3) >= (QZStartOff+(CELL_S-1*Zhuju[0]))){
                    StateChange = TRUE;
                }
            }
            else { //反向
                if ((CURR_OFF_LEN-3+GlobalPara.BDiroff) <= (QZStartOff-(CELL_S-1*Zhuju[0]))){
                    StateChange = TRUE;
                }
            }
            /*满足清种结束条件*/
            if (StateChange == TRUE){
                QZ_OFF(); //关闭清种阀门
                if (GZ_EN != 0){ //有刮种结构
                    YLZ_OFF();
                }
                else {
                    /*没有刮种功能 清种关闭后开启预落种阀门*/
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    if (BZCellParaCurr.FinalFlag == 0) {
                        if (RowNumIncrease == TRUE){
                             row_num = BZCellParaCurr.DisplayRowNum+1;
                        }
                        else {
                            row_num = BZCellParaCurr.DisplayRowNum-1;
                        }
                        if (NextYLZOn == TRUE){
                            YLZ_ON();
                            sprintf((char*)DebugInfoBuf, "开始预落种[%d]", row_num);
                        }
                        else {
                            //YLZ_OFF();
                            sprintf((char*)DebugInfoBuf, "跳过预落种[%d]", row_num);
                        }
                    }
                    else {
                         sprintf((char*)DebugInfoBuf, "等待当前小区完成[%d]", BZCellParaCurr.DisplayRowNum);
                    }
                }
                if (DZStartFlag == FALSE){ //清种结束后开始倒种
                    DZStartFlag = TRUE;
                    /*不是最后一个小区,说明需要倒种操作*/
                    if (GZ_EN != 0){ //有刮种结构 打开倒种开关
                        if (RowNumIncrease == TRUE){
                            row_num = BZCellParaCurr.DisplayRowNum+1;
                        }
                        else {
                            row_num = BZCellParaCurr.DisplayRowNum-1;
                        }
                        if (BZCellParaCurr.FinalFlag == 0){
                            if (BZCellPara.isAfterNextZoneSow == 1){
                                DZ_ON(); //下个小区还要继续播种
                                StartGZStepMotor();
                                NextYLZOn = TRUE;
                                sprintf((char*)DebugInfoBuf, "开始倒种[%d]", row_num);
                            }
                            else {
                                NextYLZOn = FALSE;
                                DZ_OFF();
                                sprintf((char*)DebugInfoBuf, "跳过倒种[%d]", row_num);
                            }
                        }
                        else{
                            NextYLZOn = FALSE;
                            /*最后一个小区当前已经是最后一个小区则跳过下一个小区倒种*/
                            sprintf((char*)DebugInfoBuf, "跳过倒种[%d] 等待当前小区结束[%d]", row_num, BZCellParaCurr.DisplayRowNum);
                        }
                    }
                    else {
                    }
                }
            }

            /*判断刮种停止时刻到*/
            StateChange = FALSE;
            if (BDTXFlag == TRUE){//同向
                if ((CURR_OFF_LEN+3) >= (CELL_OFF+CELL_L+CELL_S+(s32)GlobalPara.A-GlobalPara.B)){
                    StateChange = TRUE;
                }
            }
            else { //反向
                if ((CURR_OFF_LEN-3+GlobalPara.BDiroff) <= (CELL_OFF-(CELL_L+CELL_S+(s32)GlobalPara.A-GlobalPara.B))){
                    StateChange = TRUE;
                }
            }

            if (StateChange == TRUE){
                GZ_OFF();
                YLZ_OFF();
                UpdateRowNumCheck(); //检查上位机是否已更新下一小区内容
                if (RowNoUpdateFlag == FALSE){
                    /*若是上位机一直没有更新下一个小区播种的信息则需要报错*/
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "播种结束[%d]", BZCellPara.DisplayRowNum);
                    DJCtrlState = 0;//停止电机转动
                    ShiFeiOnFlag = FALSE;
                    SeedMode = SEED_ERR_WAIT;
                    break;
                }
                else {
                    ShiFeiOnFlag = TRUE;
                    /*刮种结束 此时上一小区种子已经落完, 可以开始切换小区号*/
                    ClearLzCnt(); //清除漏种数

                    SeedMode = SEED_S_WAIT_QZ; //等待清种 开始下一个循环
                    QZTapDone = FALSE;
                    //GetStepPulseTime(1000); //触发一次计算株距操作
                    for (i = 0; i < (LINE_NUM+1); i++){
                        if (i != GZ_STEP_INDEX){
                        GetStepPulseTime(i, 1000);
                        }
                    }
                    GetQzStartOff();        //计算清种开始时刻偏移
                    GetQZTapOff();          //计算清种打点行程点
                    StateStartTime = osTimeGet();
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    sprintf((char*)DebugInfoBuf, "等待清种[%d]", BZCellParaCurr.DisplayRowNum);
                }

                /*不是最后一个小区,说明需要倒种操作*/
                if (GZ_EN != 0){ //有刮种结构 打开倒种开关
                }
                else {
                    memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
                    if (RowNumIncrease == TRUE){
                        row_num = BZCellParaCurr.DisplayRowNum+1;
                    }
                    else {
                        row_num = BZCellParaCurr.DisplayRowNum-1;
                    }
                    if (BZCellParaCurr.FinalFlag == 0){
                        if (BZCellPara.isAfterNextZoneSow == 1){
                            DZ_ON(); //下个小区还要继续播种
                            StartGZStepMotor();
                            NextYLZOn = TRUE;
                            sprintf((char*)DebugInfoBuf, "开始倒种[%d]", row_num);
                        }
                        else {
                            NextYLZOn = FALSE;
                            DZ_OFF();
                            sprintf((char*)DebugInfoBuf, "跳过倒种[%d]", row_num);
                        }
                    }
                    else {
                        sprintf((char*)DebugInfoBuf, "等待播种结束[%d]", BZCellParaCurr.DisplayRowNum);
                       // sprintf((char*)DebugInfoBuf, "跳过倒种[%d]", row_num);
                    }
                }
            }
            break;
        case SEED_ERR_WAIT:
            /*等待操作停止*/
            StopAllCtrl();
            break;
        default:
            SeedMode = SEED_S_WAIT;
            memset(DebugInfoBuf, 0x00, sizeof(DebugInfoBuf));
            sprintf((char*)DebugInfoBuf, "等待开始[%d]", BZCellParaCurr.DisplayRowNum);
            break;
        }
    }//if (RunState == RUN_S_START)

    /*命令响应*/
    if (CurrentCMDAna != FNC_CMD_NULL){
        switch (CurrentCMDAna)
        {
        case FNC_CMD_START_BZ:
            WorkMode = WORK_MODE_BD; //进入播种模式
            sprintf((char*)DebugInfoBuf, "播种模式");
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_TEST:
            WorkMode = WORK_MODE_TEST; //开始测试模式
            sprintf((char*)DebugInfoBuf, "测试模式");
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_START_LXBZ:
            WorkMode = WORK_MODE_LXBZ; //进入连续播种模式
            sprintf((char*)DebugInfoBuf, "连续播种");
            SeedMode = SEED_S_WAIT;
            RunState = RUN_S_START;
            break;
        case FNC_CMD_STOP_BZ:   //停止播种模式
            sprintf((char*)DebugInfoBuf, "停止状态");
            RunState = RUN_S_STOP;
            SeedMode = SEED_S_WAIT;
            break;
            //  case FNC_CMD_STOP_TEST:
            //      TestMode = WORK_MODE_IDLE; //停止测试模式
            //      break;
            //case FNC_CMD_STOP_LXBZ:   //停止连续播种模式
            //     SeedMode = SEED_S_WAIT;
            //    RunState = RUN_S_STOP;
            //     break;
        default:
            break;
        }
        CurrentCMDAna = FNC_CMD_NULL;
    }
}

u8 LastAValid;          //A点坐标是否有效
u32 BDSpeedStartTime;   /*计算北斗速度的起始时间*/
u32 BDSpeedStartTimeShort;   /*计算北斗速度的起始时间 用于判断启停变化时使用*/
u32 BDSpeedEndTime;     /*计算北斗速度的运行时间*/
s32 BdCalcSpeed;        //通过北斗位置计算的实时速度 行进方向一致为正值, 倒车为负值 mm/s
bool BDDCFlag;          //是否正在倒车

/***************************************************************************************************
*\Function      BdSpeedCalc
*\Description   通过获取的北斗定位信息计算行驶速度
*\Parameter     
*\Return        void
*\Note          1)距离计算的是2次定位之间的直线距离
2)若是未划A点则不进行倒车的判断,如果发生倒车时不会显示负的速度值
***************************************************************************************************/
void BdSpeedCalc(void)
{
#if BD_SIMU_TEST
    BdCalcSpeed = SIMU_SPEED;
#else
    s32 speed_calc = 0;
    u8 speed_flag = 0;
    if (CurrBDPos.ValidFlag == 0){
        /*无法获取位置信息, 则无法计算速度*/
        BdCalcSpeed = 0;
        BDSpeedStartTime = osTimeGet();
        BDSpeedStartTimeShort = BDSpeedStartTime;
        return;
    }
    else {
        if (BDSpeedCalPara.StartState == 0){
            BDSpeedCalPara.StartState = 1;
            BDSpeedCalPara.StartE = CurrBDPos.E;
            BDSpeedCalPara.StartN = CurrBDPos.N;
            BDSpeedShortCalPara.StartE = CurrBDPos.E;
            BDSpeedShortCalPara.StartN = CurrBDPos.N;
            BDSpeedStartTime = CurrBDPos.TimeStamp;
            BDSpeedStartTimeShort = BDSpeedStartTime;
            BdCalcSpeed = 0;
        }
        BDSpeedEndTime = CurrBDPos.TimeStamp - BDSpeedStartTimeShort;
        if (BDSpeedEndTime >= 300){
            /*时间到计算起始时间值*/
            CoordinateExchange(CurrBDPos.E, CurrBDPos.N, &BdSpeedCoor, &BDSpeedShortCalPara);
            BDSpeedStartTimeShort = CurrBDPos.TimeStamp;
            BDSpeedShortCalPara.StartE = CurrBDPos.E;
            BDSpeedShortCalPara.StartN = CurrBDPos.N;

            speed_calc = (s32)((BdSpeedCoor.Line*1000*1000)/(BDSpeedEndTime*1.0)); //mm/s
            if (speed_calc > 700){//速度很高之后 不再使用滤波功能
                speed_calc = BdCalcSpeed;
            }
            if ((BdCalcSpeed >= 0) && (BdCalcSpeed < 150)){
                /*在静止阶段, 且速度变化快过一定程度则及时切换速度*/
                 speed_calc = BdCalcSpeed - speed_calc;
                 if (speed_calc < -200){
                     speed_flag = 1;
                     BdCalcSpeed = BdCalcSpeed - speed_calc;
                 }
            }
            else if (BdCalcSpeed > 350){
                /*在正常运行阶段*/
                speed_calc = BdCalcSpeed - speed_calc;
                if (speed_calc > 300){
                    /*在高速运行阶段,且速度在降低*/
                    speed_flag = 1;
                    BdCalcSpeed = BdCalcSpeed - speed_calc;
                }
            }
        }
        BDSpeedEndTime = CurrBDPos.TimeStamp - BDSpeedStartTime;
        if ((BDSpeedEndTime >= BD_SPEED_INTERVAL) || (speed_flag == 1)){
            /*时间到计算起始时间值*/
            CoordinateExchange(CurrBDPos.E, CurrBDPos.N, &BdSpeedCoor, &BDSpeedCalPara);
            speed_calc = (s32)((BdSpeedCoor.Line*1000*1000)/(BDSpeedEndTime*1.0)); //mm/s
            if ((speed_calc > -1500) && (speed_calc < 1500)){
                if (speed_flag == 0){
                    BdCalcSpeed = speed_calc;
                }
            }
            else {
                BdErrorCnt++; /*北斗速度计算有问题，则很可能定位信息有问题*/
                return;
            }
            /*重新获取起始点坐标,同步为当前获取到的经纬度*/
            BDSpeedCalPara.StartState = 1;
            BDSpeedCalPara.StartE = CurrBDPos.E;
            BDSpeedCalPara.StartN = CurrBDPos.N;
            BDSpeedStartTime = CurrBDPos.TimeStamp;
            if ((LastAValid == 1) && (BDPara.StartState != 0)){//在已画A点情况下才判断是否倒车
                if (BDTXFlag == TRUE){
                    /*当前行进方向为AB线同向,则Y轴距离A点位置应该越来越大*/
                    if (BdCurrOffCoor.Y >= (BdLastOffCoor.Y)){
                        //正向行车
                        BDDCFlag = FALSE;
                    }
                    else {
                        //反向行车
                        BDDCFlag = TRUE;
                    }
                }
                else {
                    /*当前行进方向为AB线反向,则Y轴距离A点位置应该越来越小*/
                    if (BdCurrOffCoor.Y <= (BdLastOffCoor.Y)){
                        //正向行车
                        BDDCFlag = FALSE;
                    }
                    else {
                        //反向行车
                        BDDCFlag = TRUE;
                    }
                }
            }
            else {
                BDDCFlag = FALSE; //未划A点,不判断倒车
            }

            if (BDPara.StartState == 1){//A点坐标还没有的情况下,不进行倒车判断
                LastAValid = 1;
                memcpy(&BdLastOffCoor, &BdCurrOffCoor, sizeof(CoordinateType));
            }
            else {
                LastAValid = 0;
            }
            /*判断行进方向*/
            if (BDDCFlag == TRUE){
                BdCalcSpeed *= -1; //正在倒车,负值
            }
#if 1
            /*停止模式下实时判断方向功能*/
            if (RunState == RUN_S_STOP){
                /*速度为负的,可能为倒车状态,也可能是和AB线方向相反*/
                if (BdCalcSpeed < -150){
                    LastAValid = 0; //触发重新计算速度
                    if (BDTXFlag == TRUE){//反转行进方向
                        BDTXFlag = FALSE;
                    }
                    else {
                        BDTXFlag = TRUE;
                    }
                }
            }
#endif
        }
    }
#endif
}

/***************************************************************************************************
*\Function      WorkProcTask
*\Description   工作状态管理任务
*\Parameter     para
*\Return        void
*\Note          
*\Log           2022.12.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
void WorkProcTask(void const* para)
{
    DEAD_LOOP{
        BDTrigCoor();   //根据北斗信息计算到A点行进方向及垂直方向距离
        BdSpeedCalc();  //根据北斗信息计算速度及判断倒车
        switch (WorkMode)
        {
        case WORK_MODE_IDLE:
            IdleModeProc();
            break;
        case WORK_MODE_TEST:
            /*测试模式*/
            TestModeProc();
            break;
        case WORK_MODE_BD:
            BZModeProc();
            break;
        case WORK_MODE_LXBZ:
            LXBZProc();
            break;
        default:
            WorkMode = WORK_MODE_IDLE;
            break;
        }

        osDelay(1);
    }
}
