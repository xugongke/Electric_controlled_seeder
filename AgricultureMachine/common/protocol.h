#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <QDebug>
#include <QDateTime>

typedef unsigned long long          u64;    /*!<u64*/
typedef unsigned int                u32;    /*!<u32*/
typedef unsigned short              u16;    /*!<u16*/
typedef unsigned char               u8;     /*!<u8*/

typedef signed long long            s64;    /*!<s64*/
typedef signed int                  s32;    /*!<s32*/
typedef signed short                s16;    /*!<s16*/
typedef signed char                 s8;     /*!<s8*/

typedef volatile unsigned int       vu32;   /*!<vu32*/
typedef volatile unsigned short     vu16;   /*!<vu16*/
typedef volatile unsigned char      vu8;    /*!<vu8*/

typedef volatile signed int         vs32;   /*!<vs32*/
typedef volatile signed short       vs16;   /*!<vs16*/
typedef volatile signed char        vs8;    /*!<vs8*/

typedef struct LXBZParaType_st
{
	u32 Density ;// 株/亩
	u32 CellLen; //行长 计算使用的行长, 应用层暂时可以定死为5米
	u16 Hju;      //行间距  单位cm
	u16 ZhuShu;  // 株数 单位cm 正常情况下由密度计算得到,增加该值的作用是预留以后上位机直接指定。
				//该值不为0时使用, 为0时自动计算
}LXBZParaType; //连续播种模式参数

typedef struct TerParaType_st
{
	s16 A;     //下种口距离 行程开关到下种口的距离cm   行程开关必须在下种口前方
	s16 B;      //种子落地距离  种子自由落体运动行走距离cm

	u16 EncodeNum;  /*编码器变送比, 1m距离对应的编码器脉冲计数个数*/
	u8 EncoderDir;  /*编码器方向 0:正向 1:反向  行进时编码器可能为反向计数*/
	u8 HoleNum;     /*播种盘孔数*/

	u16 GearRatio;   /*电机减速比       步进电机 播种盘减速比*/
	u16 MicroStepValue; /*步进电机细分值  步进电机转动一圈的细分值*/

	s16 X1;         //天线距离X1  北斗天线与北斗行程开关在行进方向距离 单位:cm 北斗天线在前则为正,反之为负
	s16 BDiroff;    /*反向距离修订 用于修订打点器和起始播种距离等 单位:cm*/
	s16 TappTrigOff; /*打点器到北斗行程开关距离 cm  打点器落点位置在北斗行程开关前方为正，反之为负*/
	u16 TapperTime; //打点时间  单位:ms
	u8 ZeroPosEn;//是否使能零位开关 0:不使用 1:使用
	u8 GZEn;//刮种是否使能 0:不使能 1:使能
    u8 PrePercent;//预充种百分比
	u8 U8Resv2=0;
	u32 U32Resv1=0;
	u32 U32Resv2=0;
	u32 U32Resv3=0;
	u32 CrcCheck;   /*参数CRC校验*/
//	friend QDebug operator<<(QDebug os,const TerParaType_st &c)
//	{
//		return os<<"A"<<c.A<<"B"<<c.B<<"EncodeNum"<<c.EncodeNum<<"EncoderDir"<<c.EncoderDir<<"HoleNum"<<c.HoleNum<<"GearRatio"<<c.GearRatio<<"MicroStepValue"<<c.MicroStepValue<<"X1"<<c.X1<<"BDiroff"<<c.BDiroff<<"TappTrigOff"<<c.TappTrigOff<<"TapperTime"<<c.TapperTime<<"";
//	}
}TerParaType;  /*厂家后台参数*/

typedef struct UserParaType_st{
	u16 DZTime;     //倒(投)种时间  单位ms
	s16 HJ;         /*行间距 单位:cm*/
    u32 Rpm;//步进电机转速,r/min
    u8 AntennaType;//0:单 1:双
    u8 U8Resv=0;
    s16 AntennaDistance;//天线间距 单位:cm
	u32 CrcCheck;   /*参数CRC校验*/
}UserParaType;      /*用户后台参数*/

/*北斗模式AB线数据参数*/
typedef struct BDParaType_st
{
	double StartN;      //触杆时的A点纬度值 保留8位小数
	double StartE;      //触杆时的A点经度值 保留8位小数
	double EndBN;      //B点的纬度值 保留8位小数
	double EndBE;      //B点时的经度值 保留8位小数
	float  StartDir;    /*触杆时的行进方向 角度值 北斗获取到的行进方向角度值*/
	float  CalcDir;     /*计算得到的行进方向, 起点和输入的终点方向*/
	u16    StartState;  //标识起始A点经纬度信息是否有效 0:无效  1:有效
	u16    CalcDirFlag; //计算得到的行进方向是否有效(即B点信息是否有效) 0:无效  1:有效
	u16    OffLen;      //起始偏移量cm, 记录的起始触发点为碰触发开关之前的最后获取到的位置信息，该位置到实际碰杆位置有一个位移差
	u16    BDOffTime;   /*北斗终端实际位置到传输到播种机延迟时间 ms*/
	u32    Resv=0;        //保留
	u32    CrcCheck;    /* CRC校验和 控制板计算用于检查参数是否完整*/
}BDParaType;

struct TestModeStateType_st
{
	u32 EncoderCnt;  //编码器计数
	u32 BdCnt;       /*北斗开关状态 计数*/
    u32 LoufeiCnt[6]; //漏肥计数
    u32 LouZHCnt[6]; //漏种计数
	u32 InputState; /*按位表示输入阀门状态0:未触发 1:触发  0~3 零位开关  4:自动供种接近开关 5:预留输入1   6:钢索1  7:钢索2
                         8:压力  9:风机   10:脚踏板  11:一键初始化按钮  12:北斗 13-14:零位开关5-6 15~31保留
						*/
	u32 WarningState; /*按位表示输入阀门状态0:未触发 1:触发  0~3 零位开关  4:自动供种接近开关 5:预留输入1   6:钢索1  7:钢索2
                         8:压力  9:风机   10:脚踏板  11:一键初始化按钮  12:北斗 13~14:零位开关5-6 15保留  16~19播种盘电机 20自动供种电机
						*/
	u32 CtrlState;     /*按位表示阀门控制状态 0:不动作 1:动作状态  0:预落种 1:倒种  2:清种(转动阀门) 3刮种 4~5预留1~2  6:喇叭 7:打点器
                        8: 报警灯2  9:运行指示灯 10~15保留   16~19播种盘电机 20自动供种电机 21:播种盘5 22:播种盘6
						*/
};

struct TestCMDType_st
{
	u16 CtrlNo; /*要控制的控制单元序号*/
	u16 State;  /*阀门状态 0:打开  1:关闭*/
}; /*测试模式下控制命令*/

typedef struct BZCellParaType_st
{
	u8  TXFlag; // 播种方向与AB同向还是反向  0:反向  1:同向
    u8 FinalFlag;//0代表不是地图最后1排，1代表是最后一排（包括超出的排）,如果启用地图外播种，则恒为0
    u8 NextFinalFlag;
    u8 isAfterNextZoneSow;//当前小区排+2的小区是否播种
	s32  RowNum;      //当前小区所在排编号
	s32  InS;         /*小区间隔(过道长度) 单位:cm*/
    s32  Density[6];    //小区密度或者株数
	s32  CellLen;      //当前小区长度(不含过道) cm
	s32  StartPOS; // 当前小区沿行进方向的坐标 cm   A点所在小区第一粒种子位置为0点 沿AB线
    s32  DisplayRowNum;//调试信息中显示的当前排号

    s32  NextRowNum;      //下排小区编号
    s32  NextInS;         /*下排小区间隔(过道长度) 单位:cm*/
    s32  NextDensity[6];    //下排小区密度或者株数   若为0表示当前小区不需要播种或者禁用状态
    s32  NextCellLen;      //下排小区长度(不含过道) cm
    s32  NextStartPOS; //下排小区沿行进方向的坐标 cm   A点所在小区第一粒种子位置为0点 沿AB线
    s32  NextDisplayRowNum;//调试信息中显示的下排排号
	friend QDebug operator<<(QDebug os,const BZCellParaType_st &c)
	{
        return os<<"TXFlag"<<c.TXFlag<<"RowNum"<<c.RowNum<<"InS"<<c.InS<<"Density"<<c.Density[0]<<c.Density[1]<<c.Density[2]<<c.Density[3]<<c.Density[4]<<c.Density[5]<<"CellLen"<<c.CellLen<<"StartPOS"<<c.StartPOS<<"FinalFlag"<<c.FinalFlag<<"DisplayRowNum"<<c.DisplayRowNum<<"NextRowNum"<<c.NextRowNum<<"NextInS"<<c.NextInS<<"NextDensity"<<c.NextDensity[0]<<c.NextDensity[1]<<c.NextDensity[2]<<c.NextDensity[3]<<c.NextDensity[4]<<c.NextDensity[5]<<"NextCellLen"<<c.NextCellLen<<"NextStartPOS"<<c.NextStartPOS<<"NextFinalFlag"<<c.NextFinalFlag<<"isAfterNextZoneSow"<<c.isAfterNextZoneSow<<"NextDisplayRowNum"<<c.NextDisplayRowNum;
	}
    QString getString()
    {
        return "TXFlag "+QString::number(TXFlag)+" RowNum "+QString::number(RowNum)+" InS "+QString::number(InS)+" Density "+QString::number(Density[0])+" "+QString::number(Density[1])+" "+QString::number(Density[2])+" "+QString::number(Density[3])+" "+QString::number(Density[4])+" "+QString::number(Density[5])+" CellLen "+QString::number(CellLen)+" StartPOS "+QString::number(StartPOS)+" FinalFlag "+QString::number(FinalFlag)+" DisplayRowNum"+QString::number(DisplayRowNum)+" NextRowNum "+QString::number(NextRowNum)+" NextInS "+QString::number(NextInS)+" NextDensity "+QString::number(NextDensity[0])+" "+QString::number(NextDensity[1])+" "+QString::number(NextDensity[2])+" "+QString::number(NextDensity[3])+" "+QString::number(NextDensity[4])+" "+QString::number(NextDensity[5])+" NextCellLen "+QString::number(NextCellLen)+" NextStartPOS "+QString::number(NextStartPOS)+" NextFinalFlag "+QString::number(NextFinalFlag)+" isAfterNextZoneSow "+QString::number(isAfterNextZoneSow)+" NextDisplayRowNum"+QString::number(NextDisplayRowNum);
    }
}BZCellParaType;

typedef struct BZStatusType_st
{
	u8  RunState;   //是否在运行状态
	u8 BdState;//北斗信息是否正常 0:不正常 1:正常
	u8  Resv[2];
	s32 Speed;//mm/s 沿行进方向为正 给用户显示时单位用m/s,如1.30m/s
	s32 RowNum;     //当前正在进行的排编号
	s32 OffLen;      //农机距离A点沿AB线方向的行程 单位cm
	s32 VerticalOff; //农机距离A点垂直AB线方向的行程 单位cm
    u32 LoufeiCnt[6];//漏肥计数
    u32 LouZHCnt[6]; //漏种计数
	s32 Resv2[8];    //预留其他状态
}BZStatusType;

#endif // PROTOCOL_H
