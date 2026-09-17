#ifndef COMMUNICATION_H
#define COMMUNICATION_H

#include <QSerialPort>
#include <QTimer>
//#include <QList>
#include <QDebug>
#include "../../common/protocol.h"

enum MachineMode
{
	STOP,SOW,TEST,CONTINUOUSSOW
};

//class ResendUnit : public QObject
//{
//public:
//    QByteArray sendBuf,receiveBuf;
//    QTimer qt;
//    int retryTime;
//    int fnc;
//};

class Communication:public QObject
{
	Q_OBJECT

private:
	void addCrc(QByteArray &qba);
    bool checkCrc(QByteArray &qba);
	unsigned short CRC16_CCITTCalc(unsigned char* src, unsigned int length);

    QSerialPort qsp;
	MachineMode mode,preMode,debugInfoMode;//当前模式、预设模式（区分下发用户和厂家参数成功信号反馈给哪个功能）、调试信息模式（区分调试信息反馈给播种界面还是连续播种界面）
    QTimer connectionTimer;
    bool state;
    bool bdState;
    QString version;
    QByteArray buf;
    // bool runFlag;
    //QThread thread;
    //QList<ResendUnit*> pendingCmds;
    //void createResendUnit(int fnc,QByteArray qba,bool retry);
    //ResendUnit* findPending(int fnc);
public:
	Communication();
	void openPort();
    void closePort();
	void enterTestMode();
	void exitTestMode();
	void setValveState(u16 index,bool state);
	void setValveState(TestCMDType_st);
    //void getVersion();
	void getDebugInformation(MachineMode m);
	void startSow();
	void stopSow();
	void setSowParameters(BZCellParaType_st bzcpt);
	void getSowStatus();
	void getTestStatus();
	void getABLine();
	void setABLine(BDParaType);
	void setDotWhenClearSeed(bool b);
	void setManufacturerParameter(TerParaType);
	void setUserParameter(UserParaType,MachineMode);
	void startContinuousSow(LXBZParaType);
	void stopContinuousSow();
	void getManufacturerParameter();
	void getUserParameter();
	MachineMode getPreMode();
	MachineMode getMode();
	MachineMode getDebugInfoMode();
	void setEmptyABLine();
    bool getConnectionState();
    QString getVersion();
    void enableGapPoint(bool);
    // template <typename... T>
    // void sendCmd(int cmd,T... argList);
    bool getBdState() const;

signals:
	void signalGetTestStatus(TestModeStateType_st);
    //void signalGetVersion(QString);
	void signalGetDebugInformation(QString);
	void signalSetSowParameters(bool);
	void signalGetSowStatus(BZStatusType_st);
	void signalEnterTestMode();
	void signalExitTestMode();
	void signalStartSow();
	void signalStopSow();
	void signalGetABLine(BDParaType);
	void signalSetABLine(bool);
	void signalSetManufacturerParameter(bool);
	void signalSetUserParameter(bool);
	void signalStartContinuousSow();
	void signalStopContinuousSow();
	void signalGetManufacturerParameter(TerParaType);
	void signalGetUserParameter(UserParaType);
	void signalPortConnected();
	void signalPortDisconnected();
};

#endif // COMMUNICATION_H
