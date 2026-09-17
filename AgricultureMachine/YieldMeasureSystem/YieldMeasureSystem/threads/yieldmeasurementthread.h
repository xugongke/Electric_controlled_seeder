#ifndef YIELDMEASUREMENTTHREAD_H
#define YIELDMEASUREMENTTHREAD_H

#include <QObject>
#include <QThread>
#include <QTimer>

class YieldMeasurementThread : public QObject
{
	Q_OBJECT
public:
    enum YIELDMEASUREMENTSTATE
    {
        INITIALMASS1,TOTALMASS1,UNITWEIGHTBUCKETCROPMASS1,INITIALMASS2,TOTALMASS2,UNITWEIGHTBUCKETCROPMASS2
    };

	explicit YieldMeasurementThread(QObject *parent = nullptr);
	void start();
	void close();
	void stop();//中途停止
	void setCrop(QString crop);
    void setRunValve(int c);
    void clear();
    void setMeasureMoisture(bool b);
    void setMeasureUnitWeight(bool b);

public slots:
    void slotMeasureYield(float value0,float value1,float value2,float value3);

private:
    void exactMass(float seconds);

	QThread qt;
    YIELDMEASUREMENTSTATE state;
    float totalMass,unitWeightBucketCropMass,initialMass,initialUnitWeightMass;
    bool stopFlag,realtimeMassThresholdFlag;//暂停测产,实时质量达到阈值
    float bigBin1FlowTime;
    float bigBin2FlowTime;
    float bigBinFlowEndTime;
    float unitWeightBinFlowTime;
    float unitWeightBinFlowEndTime;
    float unitWeightBinDetachTime;
    float unitWeightBinRepositionTime;
    float dropTime;
    float dropEndTime;
    float cyclicMeasureYieldThreshold,unitWeightBucketVolumn;
    int valveState=0;
    QString crop;
    int runValve;//0:测阀门1 1:测阀门2
    bool measureUnitWeight;//测容重
    bool measureMoisture;//测水分

signals:
    void signalReadMoistureFinished(float f);
    void signalFinish();
    void signalReadTotalMassFinished(float f);
    void signalReadUnitWeightFinished(float f);
    void signalReadInitialMass();
    void signalInfo(QString);
    void signalReadUnitWeightBucketCropMass();
};

#endif // YIELDMEASUREMENTTHREAD_H
