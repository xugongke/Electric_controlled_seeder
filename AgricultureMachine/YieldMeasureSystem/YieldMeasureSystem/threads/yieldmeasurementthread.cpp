#include "yieldmeasurementthread.h"
#include <QSettings>
//#include "network/threaddata.h"
#include <windows.h>
#include <QTimerEvent>
#include "global.h"
#include <QDebug>
#include "uart/threaduart.h"
#include "global.h"

#define COLLECTIONFREQUENCY 2000
#define MOISTUREVALUEINTERVAL 500
#define REALTIMEMASSVALUEINTERVAL 200
#define READINITIALMASSSECOND 2

YieldMeasurementThread::YieldMeasurementThread(QObject *parent)
	: QObject{parent}
{
    moveToThread(&qt);
    runValve=0;
    clear();
	connect(&qt,&QThread::started,this,[=]{
        emit signalInfo("初始化参数");
		QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
		iniFile.beginGroup(APPLICATIONGROUP);
        bigBin1FlowTime=iniFile.value("BigBin1FlowTime").toFloat();
        bigBin2FlowTime=iniFile.value("BigBin2FlowTime").toFloat();
        bigBinFlowEndTime=iniFile.value("BigBinFlowEndTime").toFloat();
        unitWeightBinFlowTime=iniFile.value("UnitWeightBinFlowTime").toFloat();
        unitWeightBinFlowEndTime=iniFile.value("UnitWeightBinFlowEndTime").toFloat();
        unitWeightBinDetachTime=iniFile.value("UnitWeightBinDetachTime").toFloat();
        unitWeightBinRepositionTime=iniFile.value("UnitWeightBinRepositionTime").toFloat();
        dropTime=iniFile.value("DropTime").toFloat();
        dropEndTime=iniFile.value("DropEndTime").toFloat();
		cyclicMeasureYieldThreshold=iniFile.value("CyclicMeasureYieldThreshold").toFloat();
        unitWeightBucketVolumn=iniFile.value("UnitWeightBucketVolumn").toFloat();
		iniFile.endGroup();
        emit signalInfo("读初始质量");
        switch(runValve)
        {
        case 0:
            state=INITIALMASS1;
            exactMass(READINITIALMASSSECOND);
            break;
        case 1:
            state=INITIALMASS2;
            exactMass(dropEndTime*1000);
            break;
        default:;
        }
    });
}

void YieldMeasurementThread::start()
{
	emit signalInfo("开始测产");
    valveState=0;
    setValve(valveState);
	stopFlag=false;
	qt.start();
}

void YieldMeasurementThread::close()
{
	qt.quit();
	qt.wait();
	emit signalInfo("测产结束");
}

void YieldMeasurementThread::exactMass(float seconds)
{

    CmdBody cb;
    cb.ia[0]=seconds*COLLECTIONFREQUENCY;//点数
    G.tUart->sendCmd(CMD_EX_ANA,sizeof(int),&cb);
//	float f[3];
//    G.tData->getAnalyseData(f,seconds*COLLECTIONFREQUENCY);
//	float mass=Calib_trans(&G.massCmMap["1"],f[0]);
//	mass+=Calib_trans(&G.massCmMap["2"],f[1]);
//	mass+=Calib_trans(&G.massCmMap["3"],f[2]);
//	return Calib_trans(&G.massCmMap["三通道"],mass);
}

void YieldMeasurementThread::stop()
{
	stopFlag=true;
}

void YieldMeasurementThread::slotMeasureYield(float value0,float value1,float value2,float value3)
{
    float a;
    float b;
    float c;
    float d;
    float moisture;
    float m;
	switch(state)
	{
    case INITIALMASS1:
        a=Calib_trans(&G.massCmMap["1"],value0);
        emit signalInfo("通道1原始值="+QString::number(setPrecision(value0,3))+"mV/V，转换值="+QString::number(setPrecision(a,3))+"kg");
        b=Calib_trans(&G.massCmMap["2"],value1);
        emit signalInfo("通道2原始值="+QString::number(setPrecision(value1,3))+"mV/V，转换值="+QString::number(setPrecision(b,3))+"kg");
        c=Calib_trans(&G.massCmMap["3"],value2);
        emit signalInfo("通道3原始值="+QString::number(setPrecision(value2,3))+"mV/V，转换值="+QString::number(setPrecision(c,3))+"kg");
        d=Calib_trans(&G.massCmMap["4"],value3);
        emit signalInfo("通道4原始值="+QString::number(setPrecision(value3,3))+"mV/V，转换值="+QString::number(setPrecision(d,3))+"kg");
        initialMass=Calib_trans(&G.massCmMap["三通道"],a+b+c);
        emit signalInfo("大桶初始质量="+QString::number(setPrecision(initialMass,3))+"kg");
        if(measureUnitWeight)
        {
            initialUnitWeightMass=Calib_trans(&G.massCmMap["容重"],d);
            emit signalInfo("容重桶初始原始值="+QString::number(setPrecision(d,3))+"mV/V，转换值="+QString::number(setPrecision(initialUnitWeightMass,3))+"kg");
        }
        emit signalInfo("开阀门1");
        valveState|=1;
        setValve(valveState);
        emit signalInfo("等待落种");
        Sleep(bigBin1FlowTime*1000);
        emit signalInfo("关阀门1");
        valveState&=~1;
        setValve(valveState);
		emit signalInfo("等待稳定");
        Sleep(bigBinFlowEndTime*1000);
        state=TOTALMASS1;
        exactMass(bigBinFlowEndTime);
		break;
    case TOTALMASS1:
        a=Calib_trans(&G.massCmMap["1"],value0);
        emit signalInfo("通道1原始值="+QString::number(setPrecision(value0,3))+"mV/V，转换值="+QString::number(setPrecision(a,3))+"kg");
        b=Calib_trans(&G.massCmMap["2"],value1);
        emit signalInfo("通道2原始值="+QString::number(setPrecision(value1,3))+"mV/V，转换值="+QString::number(setPrecision(b,3))+"kg");
        c=Calib_trans(&G.massCmMap["3"],value2);
        emit signalInfo("通道3原始值="+QString::number(setPrecision(value2,3))+"mV/V，转换值="+QString::number(setPrecision(c,3))+"kg");
        totalMass=Calib_trans(&G.massCmMap["三通道"],a+b+c);
        emit signalInfo("大桶结束质量="+QString::number(setPrecision(totalMass,3))+"kg");
        emit signalInfo("大桶净质量="+QString::number(totalMass-initialMass)+"kg");
        emit signalReadTotalMassFinished(setPrecision(totalMass-initialMass,3));
        emit signalInfo("开阀门4");
        valveState|=0b1000;
        setValve(valveState);
		emit signalInfo("等待落种");
        Sleep(unitWeightBinFlowTime*1000);
        emit signalInfo("关阀门4");
        valveState&=~0b1000;
        setValve(valveState);
        Sleep(unitWeightBinFlowEndTime*1000);
        emit signalInfo("伸气缸");
        valveState|=0b10000;
        setValve(valveState);
        Sleep(unitWeightBinDetachTime*1000);
        if(measureMoisture)
        {
            moisture=G.rd->newestMoisture();
            m=setPrecision(Calib_trans(&G.moistureCmMap[crop],moisture),2);
            emit signalInfo("水分读数="+QString::number(setPrecision(moisture,2)));
            emit signalInfo("湿度="+transMoisture(m,2));
            emit signalReadMoistureFinished(m);
        }
        state=UNITWEIGHTBUCKETCROPMASS1;
        exactMass(unitWeightBinDetachTime);
		break;
    case UNITWEIGHTBUCKETCROPMASS1:
        if(measureUnitWeight)
        {
            d=Calib_trans(&G.massCmMap["4"],value3);
            emit signalInfo("通道4原始值="+QString::number(setPrecision(value3,3))+"mV/V，转换值="+QString::number(setPrecision(d,3))+"kg");
            unitWeightBucketCropMass=Calib_trans(&G.massCmMap["容重"],d);
            emit signalInfo("容重桶结束质量="+QString::number(unitWeightBucketCropMass)+"kg");
            emit signalInfo("容重桶净质量="+QString::number(unitWeightBucketCropMass-initialUnitWeightMass)+"kg");
            emit signalInfo("容重="+QString::number((unitWeightBucketCropMass-initialUnitWeightMass)/unitWeightBucketVolumn)+"kg/L");
            emit signalReadUnitWeightFinished(setPrecision((unitWeightBucketCropMass-initialUnitWeightMass)/unitWeightBucketVolumn,2));
        }
        emit signalInfo("开阀门346");
        valveState|=0b1100;
        setValve(valveState);
        Sleep(dropTime*1000);
        emit signalInfo("关阀门346");
        valveState&=~0b1100;
        setValve(valveState);
        Sleep(dropEndTime*1000);
        emit signalInfo("缩气缸");
        valveState&=~0b10000;
        setValve(valveState);
        state=INITIALMASS2;
        Sleep(unitWeightBinRepositionTime*1000);
        emit signalFinish();
		break;
    case INITIALMASS2:
        // a=Calib_trans(&G.massCmMap["1"],value[0]);
        // emit signalInfo("通道1原始值="+QString::number(setPrecision(value[0],3))+"mV/V，转换值="+QString::number(setPrecision(a,3))+"kg");
        // b=Calib_trans(&G.massCmMap["2"],value[1]);
        // emit signalInfo("通道2原始值="+QString::number(setPrecision(value[1],3))+"mV/V，转换值="+QString::number(setPrecision(b,3))+"kg");
        // c=Calib_trans(&G.massCmMap["3"],value[2]);
        // emit signalInfo("通道3原始值="+QString::number(setPrecision(value[2],3))+"mV/V，转换值="+QString::number(setPrecision(c,3))+"kg");
        // initialMass=Calib_trans(&G.massCmMap["三通道"],a+b+c);
        // emit signalInfo("大桶初始质量="+QString::number(setPrecision(initialMass,3))+"kg");
        emit signalInfo("开阀门2");
        valveState|=2;
        setValve(valveState);
        emit signalInfo("等待落种");
        Sleep(bigBin2FlowTime*1000);
        emit signalInfo("关阀门2");
        valveState&=~2;
        setValve(valveState);
        emit signalInfo("等待稳定");
        Sleep(bigBinFlowEndTime*1000);
        state=TOTALMASS2;
        exactMass(bigBinFlowEndTime);
        break;
    case TOTALMASS2:
        a=Calib_trans(&G.massCmMap["1"],value0);
        emit signalInfo("通道1原始值="+QString::number(setPrecision(value0,3))+"mV/V，转换值="+QString::number(setPrecision(a,3))+"kg");
        b=Calib_trans(&G.massCmMap["2"],value1);
        emit signalInfo("通道2原始值="+QString::number(setPrecision(value1,3))+"mV/V，转换值="+QString::number(setPrecision(b,3))+"kg");
        c=Calib_trans(&G.massCmMap["3"],value2);
        emit signalInfo("通道3原始值="+QString::number(setPrecision(value2,3))+"mV/V，转换值="+QString::number(setPrecision(c,3))+"kg");
        totalMass=Calib_trans(&G.massCmMap["三通道"],a+b+c);
        emit signalInfo("大桶结束质量="+QString::number(setPrecision(totalMass,3))+"kg");
        emit signalInfo("大桶净质量="+QString::number(totalMass-initialMass)+"kg");
        emit signalReadTotalMassFinished(setPrecision(totalMass-initialMass,3));
        emit signalInfo("开阀门4");
        valveState|=0b1000;
        setValve(valveState);
        emit signalInfo("等待落种");
        Sleep(unitWeightBinFlowTime*1000);
        emit signalInfo("关阀门4");
        valveState&=~0b1000;
        setValve(valveState);
        Sleep(unitWeightBinFlowEndTime*1000);
        emit signalInfo("伸气缸");
        valveState|=0b10000;
        setValve(valveState);
        Sleep(unitWeightBinDetachTime*1000);
        // if(measureMoisture)
        // {
        //     moisture=G.rd->newestMoisture();
        //     m=setPrecision(Calib_trans(&G.moistureCmMap[crop],moisture),2);
        //     emit signalInfo("水分读数="+QString::number(setPrecision(moisture,2)));
        //     emit signalInfo("湿度="+transMoisture(m,2));
        //     emit signalReadMoistureFinished(m);
        // }
        if(measureMoisture)
        {
            moisture=G.rd->newestMoisture();
            m=setPrecision(Calib_trans(&G.moistureCmMap[crop],moisture),2);
            emit signalInfo("水分读数="+QString::number(setPrecision(moisture,2)));
            emit signalInfo("湿度="+transMoisture(m,2));
            emit signalReadMoistureFinished(m);
        }
        state=UNITWEIGHTBUCKETCROPMASS2;
        exactMass(unitWeightBinDetachTime);
        break;
    case UNITWEIGHTBUCKETCROPMASS2:
        if(measureUnitWeight)
        {
            d=Calib_trans(&G.massCmMap["4"],value3);
            emit signalInfo("通道4原始值="+QString::number(setPrecision(value3,3))+"mV/V，转换值="+QString::number(setPrecision(d,3))+"kg");
            unitWeightBucketCropMass=Calib_trans(&G.massCmMap["容重"],d);
            emit signalInfo("容重桶结束质量="+QString::number(unitWeightBucketCropMass)+"kg");
            emit signalInfo("容重桶净质量="+QString::number(unitWeightBucketCropMass-initialUnitWeightMass)+"kg");
            emit signalInfo("容重="+QString::number((unitWeightBucketCropMass-initialUnitWeightMass)/unitWeightBucketVolumn)+"kg/L");
            emit signalReadUnitWeightFinished(setPrecision((unitWeightBucketCropMass-initialUnitWeightMass)/unitWeightBucketVolumn,2));
        }
        emit signalInfo("开阀门346");
        valveState|=0b1100;
        setValve(valveState);
        Sleep(dropTime*1000);
        emit signalInfo("关阀门346");
        valveState&=~0b1100;
        setValve(valveState);
        Sleep(dropEndTime*1000);
        emit signalInfo("缩气缸");
        valveState&=~0b10000;
        setValve(valveState);
        emit signalFinish();
        break;
    default:;
	}
}

void YieldMeasurementThread::setCrop(QString crop)
{
    this->crop=crop;
}

void YieldMeasurementThread::setRunValve(int c)
{
    runValve=c;
}

void YieldMeasurementThread::clear()
{
    totalMass=0;
    unitWeightBucketCropMass=0;
    initialMass=0;
    initialUnitWeightMass=0;
}

void YieldMeasurementThread::setMeasureMoisture(bool b)
{
    measureMoisture=b;
}

void YieldMeasurementThread::setMeasureUnitWeight(bool b)
{
    measureUnitWeight=b;
}
