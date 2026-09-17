#ifndef REALTIMEDATA_H
#define REALTIMEDATA_H

#include <QObject>
#include <deque>
#include <QTimer>

class RealtimeData : public QObject
{
	Q_OBJECT

    std::map<QString,float> realtimeMassMap;
	std::deque<float> moistureValueDeque,tDeque;
	int massTimer,moistureTimer,tt;
	bool dialogFlag,transformMoistureFinishedFlag;
	float maxMoisture;//水分百分比最大值
	QString yieldMeasurementCrop;
	QTimer temp;
public:
	RealtimeData(QObject *parent = nullptr);
	float uniteMass();
    float unitWeightMass();
    float singleMass(QString channel);
	float averageMoisture();
	float newestMoisture();
	void start();
	void clearMoistureHistory();
	void setYieldMeasurementCrop(QString yieldMeasurementCrop);
	void setDialogFlag(bool newDialogFlag);
    float channelMass(QString channel);

//protected:
//	void timerEvent(QTimerEvent *event) override;

private slots:
	void slotTempTimeout();
};

#endif // REALTIMEDATA_H
