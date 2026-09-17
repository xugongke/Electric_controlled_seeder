#include "realtimedata.h"
#include "global.h"
//#include "network/threaddata.h"
#include <QTimerEvent>
#include <QSettings>
//#include "network/tcp.h"
#include <QDebug>
#include <QMessageBox>
#include "uart/threaduart.h"
#include <QTextCodec>

#define MASSINTERVAL 200
#define MOISTUREINTERVAL 100

RealtimeData::RealtimeData(QObject *parent)
    : QObject{parent},dialogFlag(true),maxMoisture(0)
{
    connect(G.tUart,&ThreadUart::sig_uart,this,[=](int cmd,int len,void *args){
		QSettings qs(CONFIGFILE,QSettings::IniFormat);
        qs.setIniCodec(QTextCodec::codecForName("utf-8"));
        switch(cmd)
        {
		case CMD_EX_R_RH:
        {
			if(((CmdBody *)args)->fa[0]>10e-6)//排除读数错误干扰
            {
				qs.beginGroup(APPLICATIONGROUP);
                if(moistureValueDeque.size()==2000/MOISTUREINTERVAL)
                    moistureValueDeque.pop_front();
				qs.endGroup();
                moistureValueDeque.push_back(((CmdBody *)args)->fa[0]);
				//旧机器算法
//                MoistureCalibrationData mcd;
//                mcd.load(yieldMeasurementCrop);
//                //qDebug()<<tDeque.size()<<moistureValueDeque.size()<<mcd.isValid(tf.b.f)<<"ttt";
//                if(tDeque.size()<moistureValueDeque.size()&&mcd.isValid(((CmdBody *)args)->fa[0]))
//                {qDebug()<<"向后读";
//                    tDeque.push_back(((CmdBody *)args)->fa[0]);
//                }
//                float t=Calib_trans(&G.moistureCmMap[yieldMeasurementCrop],((CmdBody *)args)->fa[0]);
//                if(t>maxMoisture)
//                {
//                    maxMoisture=t;
//    #ifdef QIHE
//                    std::deque<float>().swap(tDeque);
//                    //齐河机器峰值后下降快，尽量向前取
//                    for(size_t i=0;i<moistureValueDeque.size();++i)
//                        if(mcd.isValid(moistureValueDeque[i]))
//                            tDeque.push_back(moistureValueDeque[i]);
//    #elif JIYUAN
//        //递增标定不需要排除标定范围外的点
//                    tDeque.assign(moistureValueDeque.begin()+moistureValueDeque.size()/2,moistureValueDeque.end());
//    #endif
//                    qDebug()<<tDeque.size()<<"tDeque"<<'[';
//                    for(size_t i=0;i<tDeque.size();qDebug()<<tDeque[i++]);
//                    qDebug()<<']'<<"未使用"<<maxMoisture<<((CmdBody *)args)->fa[0];
//				}
			}
            break;
        }
        case CMD_EX_VAL:
            realtimeMassMap["1"]=((CmdBody *)args)->fa[0];
            realtimeMassMap["2"]=((CmdBody *)args)->fa[1];
            realtimeMassMap["3"]=((CmdBody *)args)->fa[2];
            realtimeMassMap["4"]=((CmdBody *)args)->fa[3];
            // for(int i=0;i<4;i++)
            //     realtimeMassMap[i]=((CmdBody *)args)->fa[i];



                //float t=G.tData->currentVal(i);
//                if(dialogFlag&&tt==40)
//                {
//                    killTimer(massTimer);
//                    dialogFlag=false;
//                    TcpFormat tf;
//                    tf.h.h=CMD_HEAD;
//                    tf.h.cmd=CMD_STOP;
//                    tf.h.len=sizeof(CmdHead);
//                    G.tData->sendCmd(0,&tf);
//                    G.tData->detEnd();
//                    tf.h.h=CMD_HEAD;
//                    tf.h.cmd=CMD_START;
//                    tf.h.len=sizeof(CmdHead);
//                    G.tData->setAveWindow(10);
//                    G.tData->detStart();
//                    connect(&temp,&QTimer::timeout,this,&RealtimeData::slotTempTimeout);
//                    temp.start(100);
//                    QMessageBox::critical(nullptr,"错误","读取质量出错");
//                }
            break;
        default:;
        }
    },Qt::BlockingQueuedConnection);
}

void RealtimeData::clearMoistureHistory()
{
	//std::deque<float>().swap(tDeque);
	//maxMoisture=0;
}

void RealtimeData::setDialogFlag(bool newDialogFlag)
{
	dialogFlag = newDialogFlag;
}

void RealtimeData::slotTempTimeout()
{
	temp.stop();
	disconnect(&temp,&QTimer::timeout,this,&RealtimeData::slotTempTimeout);
	massTimer=startTimer(MASSINTERVAL);
}

//void RealtimeData::timerEvent(QTimerEvent *event)
//{
//	int id=event->timerId();
//	if(id==massTimer)
//		for(size_t i=0;i<realtimeMassVector.size();++i)
//		{
//			float t=G.tData->currentVal(i);
//			if(realtimeMassVector.size()>0&&realtimeMassVector[i]==t)
//				++tt;
//			else
//			{
//				dialogFlag=true;
//				tt=0;
//			}
//			realtimeMassVector[i]=t;
//			if(dialogFlag&&tt==40)
//			{
//				killTimer(massTimer);
//				dialogFlag=false;
//				TcpFormat tf;
//				tf.h.h=CMD_HEAD;
//				tf.h.cmd=CMD_STOP;
//				tf.h.len=sizeof(CmdHead);
//				G.tData->sendCmd(0,&tf);
//				G.tData->detEnd();
//				tf.h.h=CMD_HEAD;
//				tf.h.cmd=CMD_START;
//				tf.h.len=sizeof(CmdHead);
//				G.tData->setAveWindow(10);
//				G.tData->detStart();
//				connect(&temp,&QTimer::timeout,this,&RealtimeData::slotTempTimeout);
//				temp.start(100);
//				QMessageBox::critical(nullptr,"错误","读取质量出错");
//			}
//		}
//	else if(id==moistureTimer)
//	{
//        TcpFormat tf;
//        tf.h.h=CMD_HEAD;
//        tf.h.cmd=CMD_EX_R_RH;
//        tf.h.len=sizeof(CmdHead)+sizeof(int);
//        QSettings qs(CONFIGFILE,QSettings::IniFormat);
//        qs.beginGroup(APPLICATIONGROUP);
//        tf.b.i=qs.value("MoistureValueMode").toString().at(0).toLatin1();
//        G.tData->sendCmd(0,&tf);
//        if(tf.b.f>0.000001)//排除读数错误干扰
//        {
//            if(moistureValueDeque.size()==qs.value("ReadMoistureValueTime").toFloat()*1000/MOISTUREINTERVAL)
//                moistureValueDeque.pop_front();
//            moistureValueDeque.push_back(tf.b.f);
//            MoistureCalibrationData mcd;
//            mcd.load(yieldMeasurementCrop);
//            //qDebug()<<tDeque.size()<<moistureValueDeque.size()<<mcd.isValid(tf.b.f)<<"ttt";
//            if(tDeque.size()<moistureValueDeque.size()&&mcd.isValid(tf.b.f))
//            {qDebug()<<"向后读";
//                tDeque.push_back(tf.b.f);
//            }
//            float t=Calib_trans(&G.moistureCmMap[yieldMeasurementCrop],tf.b.f);
//            if(t>maxMoisture)
//            {
//                maxMoisture=t;
//#ifdef QIHE
//                std::deque<float>().swap(tDeque);
//                //齐河机器峰值后下降快，尽量向前取
//                for(size_t i=0;i<moistureValueDeque.size();++i)
//                    if(mcd.isValid(moistureValueDeque[i]))
//                        tDeque.push_back(moistureValueDeque[i]);
//#elif JIYUAN
//                //递增标定不需要排除标定范围外的点
//                tDeque.assign(moistureValueDeque.begin()+moistureValueDeque.size()/2,moistureValueDeque.end());
//#endif
//                qDebug()<<tDeque.size()<<"tDeque"<<'[';
//                for(size_t i=0;i<tDeque.size();qDebug()<<tDeque[i++]);
//                qDebug()<<']'<<"未使用"<<maxMoisture<<tf.b.f;
//            }
//        }
//		qs.endGroup();
//	}
//}

float RealtimeData::uniteMass()
{
    float f=Calib_trans(&G.massCmMap["1"],realtimeMassMap["1"]);
    f+=Calib_trans(&G.massCmMap["2"],realtimeMassMap["2"]);
    f+=Calib_trans(&G.massCmMap["3"],realtimeMassMap["3"]);
	return f;
}

float RealtimeData::unitWeightMass()
{
    return Calib_trans(&G.massCmMap["4"],realtimeMassMap["4"]);
}

float RealtimeData::singleMass(QString channel)
{
    return realtimeMassMap[channel];
}
#include <QFile>
#include <QTextStream>
//#define TEMP
float RealtimeData::averageMoisture()
{
	//旧机器算法
////f模式
//	float f=0;
//	foreach(float v,tDeque)
//		f+=v;
//	f/=tDeque.size();
//#ifdef TEMP
//	std::vector<float> tt;
//	for(size_t i=0;i<tDeque.size();++i)
//		if(std::abs(tDeque[i]-f)<=3)
//			tt.push_back(tDeque[i]);
//	if(tt.size()>=tDeque.size()/2)
//	{
//		f=0;
//		foreach(float v,tt)
//			f+=v;
//		f/=tt.size();
//		//qDebug()<<tDeque.size()<<"tDeque"<<'[';
//		//for(size_t i=0;i<tDeque.size();qDebug()<<tDeque[i++]);
//		//qDebug()<<']'<<f<<"最终计算1";
//		return f;
//	}
//#endif
//	//tt内点不足一半则用原平均值
//	//qDebug()<<tDeque.size()<<"tDeque"<<'[';
//	for(size_t i=0;i<tDeque.size();qDebug()<<tDeque[i++]);
//	//qDebug()<<']'<<f<<"最终计算2";
//	return f;
	//新机器直接取平均
	QFile qf("原始值.txt");
	qf.open(QIODevice::WriteOnly|QIODevice::Append|QIODevice::Text);
	QTextStream out(&qf);
	out<<QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
	QString qs="[";
	float f=0;
	foreach(float v,moistureValueDeque)
	{
		f+=v;
		qs+=QString::number(v)+" ";
	}
	qs+="]";
	f/=moistureValueDeque.size();
	out<<qs;
	qf.close();
	return f;
}

float RealtimeData::newestMoisture()
{
	size_t s=moistureValueDeque.size();
	return s>0?moistureValueDeque[s-1]:0;
}

void RealtimeData::start()
{
	massTimer=startTimer(MASSINTERVAL);
	moistureTimer=startTimer(MOISTUREINTERVAL);
}

void RealtimeData::setYieldMeasurementCrop(QString yieldMeasurementCrop)
{
	this->yieldMeasurementCrop=yieldMeasurementCrop;
}

float RealtimeData::channelMass(QString channel)
{
    return Calib_trans(&G.massCmMap[channel],realtimeMassMap[channel]);
}
