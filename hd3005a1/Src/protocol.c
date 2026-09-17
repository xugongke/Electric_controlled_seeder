/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          protocol.c
*\Description   
*\Note          
*\Log           2020.08.05    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "protocol.h"
#include "string.h"
#include "update.h"
#include "user_uart.h"
#include "tlib_crc.h"
#include "rx8025t.h"
#include "para.h"
#include "work_proc.h"
#include "operation.h"
extern u8 AppVersions[]; /*软件版本号*/
#define PRO_SUCESS 1
#define PRO_FAILED 0
bool SysReset; /*是否需要重启设备*/

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
u32 FrameConstruct(uint8_t* con_buf, u8 fnc, uint8_t* data, u16 data_len)
{
    u16 crc;
    /*
    1   1    2    0~N  2    1
    FS FUNC dlen data crc16 fe

    多字节时,低字节在前  小端
    */
    /*帧头*/
    con_buf[0] = FRAME_START;
    /*功能码*/
    con_buf[1] = fnc;
    /*长度域*/
    con_buf[2] = (u8)(data_len >> 0);
    con_buf[3] = (u8)(data_len >> 8);
    /*数据域*/
    memcpy(con_buf+4, data, data_len);
   
    /*crc校验 对数据帧中除CRC校验字段外进行校验*/
    crc = CRC16_CCITTCalc(con_buf, data_len + 4);

    con_buf[4+data_len] = (u8)(crc >> 0);
    con_buf[5+data_len] = (u8)(crc >> 8);
    con_buf[6+data_len] = FRAME_END;

    return data_len+7;
}

/***************************************************************************************************
*\Function      FrameAnalysis
*\Description   协议解析
*\Parameter     buf     
*\Parameter     len     
*\Parameter     data_node 数据域地址地址及长度
*\Parameter     fnc       解析到的功能码  
*\Parameter     *
*\Return        uint32_t    要删除或解析到的数据长度
*\Note          1)可重入函数,协议相同时所有通讯接口可以复用
*\Log           2020.08.06    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
uint32_t FrameAnalysis(u8* buf, u16 len, DataNode* data_node, u8* fnc)
{
    u16 off = 0;
    u32 i = 0;
    u16 data_len;
    u16 crc;
    u16 crc_check;

    data_node->Len = 0;
    *fnc = FNC_INVALID;

    for (i = 0; i < len; i++){
        if (buf[i] == FRAME_START){
            break;
        }
        else {
            off++;
        }
    }
    if ((off+7) > len){
        /*长度不足*/
        return len;
    }

    data_len = buf[off+2] | (buf[off+3] << 8);
    if (data_len > FRAME_MAX_DATA_LEN){
        /*长度域不合法*/
        return off+1;
    }

    if (len < (off+data_len+7)){
        /*长度不足*/
        return off+1;
    }
    crc = CRC16_CCITTCalc(buf+off, data_len + 4);
    crc_check = buf[off+data_len+4] | (buf[off+5+data_len] << 8);
    
    if (crc_check != crc){
        /*CRC校验错误*/
        return off+1;
    }
    if (buf[off+data_len+6] != FRAME_END){
        return off+1;
    }
    /*至此合法性检查通过*/
    *fnc = buf[off+1];
    data_node->Data = buf+off+4;
    data_node->Len = data_len;

    return off+data_len+7;
}

u16 CRC16_MODBUS(u8* buf, u32 length)
{
    u32 i;
    u32 j;
    u32 c;
    u32 crc = 0x00;//0xFFFF;
    u32 POLY16 = 0xA001;
    //byte *buf = Data;
    for (i=0; i<length; i++)
    {
        c = ((u32)buf[i]) 
            & ((u32)0x00FF);
        crc ^= c;
        for (j=0; j<8; j++){
            if ((crc & 0x0001) != 0x0000){
                crc >>= 1;
                crc ^= POLY16;
            }
            else{
                crc >>= 1;
            }
        }
    }
    return (u16)crc;
}


#if BD_SIMU_TEST
 double bd_test_d = 36.40;
#endif
u8 RS232AnalysisBuf[FRAME_MAX_DATA_LEN+7];
u8 RS232SendBuf[FRAME_MAX_DATA_LEN+7];
u8 RS232SendBuf2[FRAME_MAX_DATA_LEN+7];
u8 RS232Fnc;        /*解析到的功能码*/
DataNode RS232DataNode; /*解析到的数据域*/

u8 SoftVerBuf[100];

void FrameProcess(u8 fnc, DataNode* data, void (*sendfunc)(u8*buf, u16 len), u8* construct_buf, u16 buf_len)
{
    u32 tempu32;
    u8 ack;
//    u8* ptr;
    u16 send_len = 0;
    switch (fnc)
    {
    case FNC_GET__RTC:
        if (data->Len == 0){
            /*获取系统时间*/
            send_len = FrameConstruct(construct_buf, fnc, (u8*)&SysTime, 4);
        }
        break;
    case FNC_SET_RTC:
        if (data->Len == 4){
            /*设置系统时间*/
            memcpy(&tempu32, data->Data, 4);
            //SetSysTime(tempu32);
            ack = PRO_SUCESS;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_RESTART_TER:
        /*重启设备*/
        if (data->Len == 0){
            ack = PRO_SUCESS;
            SysReset = TRUE;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_UPDATE_START:
        /*开始升级过程*/
        if (UpdateStartFunc(data) == TRUE){
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_UPDATE_BIN:
        /*传输升级BIN文件*/
        if (UpdateBinFunc(data) == TRUE){
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_UPDATE_END:
        /*升级文件传输完成*/
        if (UpdateEndFunc(data) == TRUE){
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_GET_SOFT_VER:
        if (data->Len == 0){
            /*获取软件版本号*/
            if (EEError){
                 send_len = FrameConstruct(construct_buf, fnc, AppErrVersion, strlen((const char*)AppErrVersion)+1);
            }
            else {
                 /**/
                 sprintf((char*)SoftVerBuf, "%s,vol:%d.%d", AppVersions, Voltage/10, Voltage%10);
                 send_len = FrameConstruct(construct_buf, fnc, SoftVerBuf, strlen((const char*)SoftVerBuf)+1);
                 //send_len = FrameConstruct(construct_buf, fnc, AppVersions, strlen((const char*)AppVersions)+1);
            }
        }
        break;
    case FNC_GET_BZ_STATUS:
        /*获取测试状态*/
        if (data->Len == 0){
            /*测试模式下所有设备状态*/
            GetBzStatus(&BzStatus);
            send_len = FrameConstruct(construct_buf, fnc, (u8*)&BzStatus, sizeof(BzStatus));
        }
        break;
    case FNC_SET_BZ_PARA:
        if (data->Len == sizeof(BZCellParaType)){
            //CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
            memcpy(&BZCellPara, data->Data, data->Len);
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_STORE_AB:
        /*存储AB线数据*/
        if (data->Len == 0){
            /*确认存储AB线数据*/
            if ((CurrBDPos.ValidFlag != 0) && (BDPara.StartState == 1)){ //当前经纬度信息有效,且A点坐标有效
                BDPara.EndBE     = CurrBDPos.E;
                BDPara.EndBN     = CurrBDPos.N;      /*起始点经纬度*/

                CalABDir(BDPara.EndBE, BDPara.EndBN, &BDPara);//计算AB线行进方向
            }
#if BD_SIMU_TEST
                BDPara.StartN = bd_test_d+0.10; 
#endif
            send_len = FrameConstruct(construct_buf, fnc, (u8*)&BDPara, sizeof(BDParaType));
        }
        else {
            ack = PRO_FAILED;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_SET_AB:/*设置AB线数据*/
        if (data->Len == sizeof(BDParaType)){
            memcpy(&BDPara, data->Data, sizeof(BDParaType));  //复制到本地
            if (BDPara.StartState != 1){
                memset(&BDPara, 0x00, sizeof(BDPara));
            }
            ack = PRO_SUCESS;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        else {
            ack = PRO_FAILED;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_SET_TER_PARA: //设置厂家后台参数
        if (data->Len == sizeof(TerParaType)){
            memcpy(&GlobalParaSet, data->Data, sizeof(TerParaType));  //复制到本地
            if (memcmp(&GlobalParaSet, &GlobalPara, sizeof(TerParaType) - 4) != 0){
                /*下发参数与之前不同*/
                memcpy(&GlobalPara, data->Data, sizeof(TerParaType));  //复制到本地
                ParaLegalCheck();
                WriteTerPara(&GlobalPara);// 存储到本地
            }
            ack = PRO_SUCESS;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        else {
            ack = PRO_FAILED;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_GET_TER_PARA:
        /*获取厂家后台参数*/
        if (data->Len == 0){
            /*测试模式下所有设备状态*/
            send_len = FrameConstruct(construct_buf, fnc, (u8*)&GlobalPara, sizeof(TerParaType));
        }
        break;
    case FNC_QZDD_ENABLE:
        if (data->Len == 1){
            if (((u8*)data->Data)[0] == 0){
                QZDDEnable = FALSE;
            }
            else {
                QZDDEnable = TRUE; //使能清种时刻打点
            }
            ack = PRO_SUCESS;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        else {
            ack = PRO_FAILED;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_GDDD_ENABLE:
        if (data->Len == 1){
            if (((u8*)data->Data)[0] == 0){
                GDDDEnable = FALSE;
            }
            else {
                GDDDEnable = TRUE; //使能过道中间时刻打点
            }
            ack = PRO_SUCESS;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        else {
            ack = PRO_FAILED;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_SET_USER_PARA: //设置用户后台参数
        if (data->Len == sizeof(UserParaType)){
            memcpy(&UserPara, data->Data, sizeof(UserParaType));  //复制到本地
            ParaLegalCheck();
            ack = PRO_SUCESS;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        else {
            ack = PRO_FAILED;
            send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        }
        break;
    case FNC_GET_USER_PARA:
        /*获取厂家后台参数*/
        if (data->Len == 0){
            /*测试模式下所有设备状态*/
            send_len = FrameConstruct(construct_buf, fnc, (u8*)&UserPara, sizeof(UserParaType));
        }
        break;
    case FNC_GET_TEST_STATUS:
        /*获取测试状态*/
        if (data->Len == 0){
            /*测试模式下所有设备状态*/
            GetTestStatus(&TestStatus);
            send_len = FrameConstruct(construct_buf, fnc, (u8*)&TestStatus, sizeof(TestStatus));
        }
        break;
    case FNC_RD_DEBUG_INFO:
        if (data->Len == 0){
            /*测试模式下所有设备状态*/
            send_len = FrameConstruct(construct_buf, fnc, (u8*)DebugInfoBuf, strlen((char*)DebugInfoBuf));
        }
        break;
    case FNC_CMD_SVCTRL: //阀门测试界面 单个阀门控制
        if (data->Len == sizeof(TestCMDType)){
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
            memcpy(&TestCMD, data->Data, data->Len);
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_CMD_START_BZ: //启动播种
        if (data->Len == 0){
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_CMD_STOP_BZ: //停止播种
        if (data->Len == 0){
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_CMD_START_LXBZ: //开始连续播种
        if (data->Len == sizeof(LXBZParaType)){
            memcpy(&LXBZPara, data->Data, sizeof(LXBZParaType));
            LXBZParaCheck();
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_CMD_STOP_LXBZ: //停止连续播种
        if (data->Len == 0){
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_CMD_START_TEST: //进入测试模式
        if (data->Len == 0){
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    case FNC_CMD_STOP_TEST: //停止测试
        if (data->Len == 0){
            CurrentCMDAna = fnc;
            ack = PRO_SUCESS;
        }
        else {
            ack = PRO_FAILED;
        }
        send_len = FrameConstruct(construct_buf, fnc, &ack, 1);
        break;
    default:
        break;
    }
    /*发送应答帧*/
    if (send_len != 0){
        sendfunc(construct_buf, send_len);
    }
}

void Rs232Send(u8* buf, u16 len)
{
	UartUserSend(COMM_DEV_BD, buf, len);
    return;
}

void Rs232SendUp(u8* buf, u16 len)
{
    UartUserSend(COMM_DEV_UP, buf, len);
    return;
}
void GPSAnalysis(char *buf);

/***************************************************************************************************
*\Function      BdAnalysisTask
*\Description   北斗解析任务
*\Parameter     para
*\Return        void
*\Note          
***************************************************************************************************/
void BdAnalysisTask(void const* para)
{
    u32 len;
    u32 del_len;
    UartUserInit(COMM_DEV_BD); //115200 8-N-1波特率
    osDelay(1000);
    while (1){
        len = UartUserGetDataLen(COMM_DEV_BD);
        if (len != 0){
            osDelay(5);
            if (UartUserGetDataLen(COMM_DEV_BD) == len){
                /*接收到完整数据包*/
                memset(RS232AnalysisBuf, 0x00, sizeof(RS232AnalysisBuf));
                len = UartUserRecv(COMM_DEV_BD, RS232AnalysisBuf, sizeof(RS232AnalysisBuf), TRUE);
                /*北斗协议解析*/
                GPSAnalysis((char*)RS232AnalysisBuf);
                /*串口复用上位机参数配置及程序升级*/
                del_len = 0;
                do 
                {
                    del_len += FrameAnalysis(RS232AnalysisBuf+del_len, len-del_len, &RS232DataNode, &RS232Fnc);
                    FrameProcess(RS232Fnc, &RS232DataNode, Rs232Send, RS232SendBuf2, sizeof(RS232SendBuf2));
                    if (del_len >= len){
                        break;
                    }
                } while (1);
            }
        }
        osDelay(1);
    }
}

/***************************************************************************************************
*\Function      Rs232ProtocolAnalysisTask
*\Description   串口协议解析程序
*\Parameter     para
*\Return        void
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
void ProtocolAnalysisTask(void const* para)
{
    u32 len;
    u32 del_len;
    UartUserInit(COMM_DEV_UP); //115200 8-N-1波特率
    osDelay(1000);
    UpdateInit();//初始化升级相关操作
    while (1){
        len = UartUserGetDataLen(COMM_DEV_UP);
        if (len != 0){
            osDelay(5);
            if (UartUserGetDataLen(COMM_DEV_UP) == len){
                /*接收到完整数据包*/
                memset(RS232AnalysisBuf, 0x00, sizeof(RS232AnalysisBuf));
                len = UartUserRecv(COMM_DEV_UP, RS232AnalysisBuf, sizeof(RS232AnalysisBuf), TRUE);
                /*串口复用上位机参数配置及程序升级*/
                del_len = 0;
                do 
                {
                    del_len += FrameAnalysis(RS232AnalysisBuf+del_len, len-del_len, &RS232DataNode, &RS232Fnc);
                    FrameProcess(RS232Fnc, &RS232DataNode, Rs232SendUp, RS232SendBuf, sizeof(RS232SendBuf));
                    if (del_len >= len){
                        break;
                    }
                } while (1);
            }
        }
        osDelay(1);
    }
}

BDSpeedDataType TmpBDSpeed; /*当前解析到的北斗速度和方向信息*/
BDPosDataType   TmpBDPos;   /*当前解析到的北斗位置信息*/
//北斗数据解析
void GPSAnalysis(char *buf)
{
    u32 time;
    char *str;
    float  f;
    double lf;
    BDPosDataType* p = &TmpBDPos;

    time = osTimeGet();
    str = strstr(buf, "$GPGGA");
    if (str == NULL){
        str = strstr(buf, "$GBGGA");
    }
    if (str == NULL){
        str = strstr(buf, "$GNGGA");
    }
    if (str)
    {
        str = strchr(str, '.');
        if (str == NULL) return;
        //纬度
        str = strchr(str, ',');
        if (str == NULL) return;
        sscanf(str + 3, "%lf", &lf);
        p->N = lf / 60 + (str[1] * 10 + str[2] - 480 - 48);  //单位转换为°
        //经度
        str = strchr(str + 1, ',');
        if (str == NULL) return;
        str = strchr(str + 1, ',');
        if (str == NULL) return;
        sscanf(str + 4, "%lf", &lf);
        p->E = lf / 60 + (str[1] * 100 + str[2] * 10 + str[3] - 4800 - 480 - 48);//单位转换为°

        /*经纬度合法性检查*/
        if (((p->N > 0) && (p->N < 90.0)) && /*纬度*/
            ((p->E > 0) && (p->E < 180.0))  /*经度*/
        ){
          CurrBDPos.N = p->N; 
          CurrBDPos.E = p->E;
          CurrBDPos.ValidFlag = 1;
          CurrBDPos.TimeStamp = time;
          NewPosGetFlag = TRUE;
        }
    }
    str = strstr(buf, "$GPRMC");
    if (str)
    {
        str = strchr(str, '.');
        if (str == NULL) return;
        str = strchr(str, 'A');
        if (str == NULL) return;
        //纬度
        str = strchr(str, ',');
        if (str == NULL) return;
        sscanf(str + 3, "%lf", &lf);
        p->N = lf / 60 + (str[1] * 10 + str[2] - 480 - 48);  //单位转换为°
        //经度
        str = strchr(str + 1, ',');
        if (str == NULL) return;
        str = strchr(str + 1, 'N');
        if (str == NULL) return;
        str = strchr(str + 1, ',');
        if (str == NULL) return;
        sscanf(str + 4, "%lf", &lf);
        p->E = lf / 60 + (str[1] * 100 + str[2] * 10 + str[3] - 4800 - 480 - 48);//单位转换为°

        /*经纬度合法性检查*/
        if (((p->N > 0) && (p->N < 90.0)) && /*纬度*/
            ((p->E > 0) && (p->E < 180.0))  /*经度*/
            ){
                CurrBDPos.N = p->N; 
                CurrBDPos.E = p->E;
                CurrBDPos.ValidFlag = 1;
                CurrBDPos.TimeStamp = time;
                NewPosGetFlag = TRUE;
        }
    }
#if 1
    str = strstr(buf, "$GPVTG");
    if (str)
    {
        //角度
        str = strchr(str, ',');
        if (str == NULL) return;
        sscanf(str + 1, "%lf", &lf);
        TmpBDSpeed.Dir = lf;
        str = strchr(str, 'N');
        sscanf(str + 2, "%f", &f);
        str = strchr(str, 'K');  //单位
        if (str == NULL){
            return ;
        }
        TmpBDSpeed.Speed = (u16)(f*2500/9);/*@TODO km/h 单位换算 mm/s*/
        if (((double)TmpBDSpeed.Dir >= 0.0) && ((double)TmpBDSpeed.Dir <= 359.0)){
            CurrBDSpeed.Dir = TmpBDSpeed.Dir;
            CurrBDSpeed.TimeStamp = time;
           // NewSpeedGetFlag = TRUE;
        }
    }
#endif
}
