#include "communication.h"
#include <QDebug>
#include <QTextCodec>
#include "global.h"
#include <QSettings>
#include <QThread>

#define FNC_GET_TEST_STATUS  0x08  /*获取测试模式下的所有外设状态 回复数据域为TestModeStateType_st，发送数据域为空*/
#define FNC_TEST_CMD     0x09      /*下发测试模式下控制命令 发送数据域为TestCMDType_st，回复数据域为1个字节*/
#define FNC_CMD_START_LXBZ   0X11    /*启动连续播种模式  数据域为 LXBZParaType*/
#define FNC_CMD_STOP_LXBZ    0X12    /*停止连续播种模式  数据域为空*/
#define FNC_CMD_START_BZ     0X0A  /*启动播种 数据域为空   回复数据域为1个字节 0:*/
#define FNC_CMD_STOP_BZ      0X0B  /*停止播种 数据域为空   回复数据域为1个字节 0:*/
#define FNC_START_TEST     0X0E  /*进入测试模式 数据域为空    回复数据域为1个字节 0失败，1成功:*/
#define FNC_STOP_TEST      0X0F  /*退出测试模式 数据域为空  回复数据域为1个字节 0失败，1成功:*/
#define FNC_SET_BZ_PARA      0X20  /*设置播种参数 发送数据域为BZCellParaType_st  回复数据域为1个字节 0:失败 1成功*/
#define FNC_GET_BZ_STATUS    0X21   /*当前播种状态 回复数据域为BZStatusType_st*/
#define FNC_RD_DEBUG_INFO    0X22  /*读取调试信息   回复数据域为最大200字节字符串*/
#define FNC_STORE_AB         0x23   /*获取AB线 数据域为空 回复数据为AB线数据 BDParaType*/
#define FNC_SET_AB           0X24   /*设置AB线数据 数据域为BDParaType 用于在开始时播种前设置AB线数据用*/
#define FNC_SET_TER_PARA     0x25  /*设置厂家后台参数 数据域为TerParaType, 只在用户改变设置参数时设置*/
#define FNC_GET_TER_PARA     0x26  /*读取厂家后台参数 回复数据域为TerParaType*/
#define FNC_SET_USER_PARA    0x27  /*设置用户后台参数 数据域为UserParaType  只在用户改变设置参数时设置*/
#define FNC_GET_USER_PARA    0x28  /*读取用户后台参数 回复数据域为UserParaType*/
#define FNC_QZDD_ENABLE     0X29   /*设置是否清种时刻打点    数据域为1个字节  0:表示不打点 1:表示打点  用户操作按钮时下发*/
#define FNC_GET_QZDD_STATE  0X30   /*获取清种时刻打点状态 数据域为空   回复数据域为1字节*/
#define FNC_GDDD_ENABLE 0x31//设置是否过道中间时刻打点 数据域为1个字节  0:表示不打点 1:表示打点
#define FNC_GET_SOFT_VER    0xa3  /*获取控制板软件版本号*/
#define INTERVAL 500
#define TIMEOUTTIME 2000
#define DATASTARTINDEX 4//数据部分起始索引
#define RETRYTIME 3//命令重试次数

Communication::Communication():mode(STOP),state(false)
{
    qsp.setBaudRate(QSerialPort::Baud115200);
	qsp.setParity(QSerialPort::NoParity);
	qsp.setDataBits(QSerialPort::Data8);
    qsp.setStopBits(QSerialPort::OneStop);
    bdState=false;
    //runFlag=false;
    connect(&qsp,&QSerialPort::readyRead,this,[=]{
        for(buf.append(qsp.readAll());buf.size()>DATASTARTINDEX;)
        {
            int i=buf.indexOf(0x68);
            if(i>=0)
                buf.remove(0,i);
            else
                buf.clear();
            if(buf.size()<=DATASTARTINDEX)
                return;
            int l=(unsigned char)buf[2]+((unsigned char)buf[3]<<8)+7;
            if(buf.size()<l)
                return;
            QByteArray q=buf.left(l);
            if(checkCrc(q))
            {
                //ResendUnit *ru=findPending((unsigned char)q[1]);
                //if(ru){ru->receiveBuf=q;ru->qt.stop();pendingCmds.removeOne(ru);}
                //QByteArray &frame=ru?ru->receiveBuf:q;
                char *recv=q.data();
                TestModeStateType_st tmst;
                BZStatusType_st bzst;
                BDParaType bdpt;
                TerParaType tpt;
                UserParaType upt;
                switch((unsigned char)q[1])
                {
                case FNC_GET_TEST_STATUS:
                    memcpy(&tmst,recv+DATASTARTINDEX,sizeof(TestModeStateType_st));
                    emit signalGetTestStatus(tmst);
                    break;
                case FNC_TEST_CMD:
                    break;
                case FNC_CMD_START_LXBZ:
                    if((unsigned char)q[DATASTARTINDEX]==1)
                    {
                        mode=preMode;
                        emit signalStartContinuousSow();
                    }
                    break;
                case FNC_CMD_STOP_LXBZ:
                    if((unsigned char)q[DATASTARTINDEX]==1)
                    {
                        mode=STOP;
                        emit signalStopContinuousSow();
                    }
                    break;
                case FNC_START_TEST:
                    if((unsigned char)q[DATASTARTINDEX]==1)
                    {
                        mode=preMode;
                        emit signalEnterTestMode();
                    }
                    break;
                case FNC_STOP_TEST:
                    if((unsigned char)q[DATASTARTINDEX]==1)
                    {
                        mode=STOP;
                        emit signalExitTestMode();
                    }
                    break;
                case FNC_CMD_START_BZ:
                    if((unsigned char)q[DATASTARTINDEX]==1)
                    {
                        mode=preMode;
                        emit signalStartSow();
                    }
                    break;
                case FNC_CMD_STOP_BZ:
                    if((unsigned char)q[DATASTARTINDEX]==1)
                    {
                        mode=STOP;
                        emit signalStopSow();
                    }
                    break;
                case FNC_SET_BZ_PARA:
                    emit signalSetSowParameters((unsigned char)q[DATASTARTINDEX]==1);
                    break;
                case FNC_GET_BZ_STATUS:
                    memcpy(&bzst,recv+DATASTARTINDEX,sizeof(BZStatusType_st));
                    bdState=bzst.BdState>0;
                    emit signalGetSowStatus(bzst);
                    break;
                case FNC_RD_DEBUG_INFO:
                    emit signalGetDebugInformation(QTextCodec::codecForName("GB2312")->toUnicode(q.mid(DATASTARTINDEX,(unsigned char)q[2]+((unsigned char)q[3]<<8))));
                    break;
                case FNC_STORE_AB:
                    memcpy(&bdpt,recv+DATASTARTINDEX,sizeof(BDParaType));
                    emit signalGetABLine(bdpt);
                    break;
                case FNC_SET_AB:
                    emit signalSetABLine((unsigned char)q[DATASTARTINDEX]==1);
                    break;
                case FNC_SET_TER_PARA:
                    emit signalSetManufacturerParameter((unsigned char)q[DATASTARTINDEX]==1);
                    break;
                case FNC_GET_TER_PARA:
                    memcpy(&tpt,recv+DATASTARTINDEX,sizeof(TerParaType_st));
                    emit signalGetManufacturerParameter(tpt);
                    break;
                case FNC_SET_USER_PARA:
                    emit signalSetUserParameter((unsigned char)q[DATASTARTINDEX]==1);
                    break;
                case FNC_GET_USER_PARA:
                    memcpy(&upt,recv+DATASTARTINDEX,sizeof(UserParaType_st));
                    emit signalGetUserParameter(upt);
                    break;
                case FNC_GET_SOFT_VER:
                    version=q.mid(DATASTARTINDEX,(unsigned char)q[2]+((unsigned char)q[3]<<8));
                    state=true;
                    emit signalPortConnected();
                    break;
                default:;
                }
                //if(ru) ru->deleteLater();
                buf.remove(0,l);
            }
            else
                buf.remove(0,1);
        }
    });
    connect(&qsp,&QSerialPort::errorOccurred,this,[=](QSerialPort::SerialPortError error){
        if(error==QSerialPort::ResourceError)
        {
            emit signalPortDisconnected();
            state=false;
            version.clear();
            qsp.close();
        }
    });
    connect(&connectionTimer,&QTimer::timeout,this,[=]{
        if(!qsp.isOpen())
            openPort();
        QByteArray qba;
        qba.append(0x68);
        qba.append(FNC_GET_SOFT_VER);
        short len=0;
        qba.append((char *)&len,sizeof(short));
        addCrc(qba);
        qba.append(0xd);
        qsp.write(qba);
    });
    connectionTimer.start(INTERVAL);
    connect(&qsp,&QSerialPort::aboutToClose,this,[=]{
        writeLog("串口关闭"+QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss"));
    });
}

void Communication::enterTestMode()
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_START_TEST);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_START_TEST,qba,true);
}

void Communication::exitTestMode()
{
	QByteArray qba;
	qba.append(0x68);
    qba.append(FNC_STOP_TEST);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_STOP_TEST,qba,true);
}

void Communication::setValveState(u16 index,bool state)
{
	QByteArray qba;
	qba.append(0x68);
    qba.append(FNC_TEST_CMD);
	short len=sizeof(TestCMDType_st);
	qba.append((char *)&len,sizeof(short));
    TestCMDType_st tct;
    tct.CtrlNo=index;
    tct.State=state?1:0;
    qba.append((char *)&tct,len);
	addCrc(qba);
	qba.append(0xd);
    qsp.write(qba);
    //createResendUnit(FNC_TEST_CMD,qba,true);
}

void Communication::setValveState(TestCMDType_st tct)
{
	QByteArray qba;
	qba.append(0x68);
    qba.append(FNC_TEST_CMD);
	short len=sizeof(TestCMDType_st);
	qba.append((char *)&len,sizeof(short));
	qba.append((char *)&tct,len);
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_TEST_CMD,qba,true);
}

unsigned short Communication::CRC16_CCITTCalc(unsigned char* src, unsigned int length)
{
	unsigned short r = 0;
	const unsigned short CrctableCCITTRefl[256] ={
		0x0000, 0x1189, 0x2312, 0x329B, 0x4624, 0x57AD, 0x6536, 0x74BF,
		0x8C48, 0x9DC1, 0xAF5A, 0xBED3, 0xCA6C, 0xDBE5, 0xE97E, 0xF8F7,
		0x1081, 0x0108, 0x3393, 0x221A, 0x56A5, 0x472C, 0x75B7, 0x643E,
		0x9CC9, 0x8D40, 0xBFDB, 0xAE52, 0xDAED, 0xCB64, 0xF9FF, 0xE876,
		0x2102, 0x308B, 0x0210, 0x1399, 0x6726, 0x76AF, 0x4434, 0x55BD,
		0xAD4A, 0xBCC3, 0x8E58, 0x9FD1, 0xEB6E, 0xFAE7, 0xC87C, 0xD9F5,
		0x3183, 0x200A, 0x1291, 0x0318, 0x77A7, 0x662E, 0x54B5, 0x453C,
		0xBDCB, 0xAC42, 0x9ED9, 0x8F50, 0xFBEF, 0xEA66, 0xD8FD, 0xC974,
		0x4204, 0x538D, 0x6116, 0x709F, 0x0420, 0x15A9, 0x2732, 0x36BB,
		0xCE4C, 0xDFC5, 0xED5E, 0xFCD7, 0x8868, 0x99E1, 0xAB7A, 0xBAF3,
		0x5285, 0x430C, 0x7197, 0x601E, 0x14A1, 0x0528, 0x37B3, 0x263A,
		0xDECD, 0xCF44, 0xFDDF, 0xEC56, 0x98E9, 0x8960, 0xBBFB, 0xAA72,
		0x6306, 0x728F, 0x4014, 0x519D, 0x2522, 0x34AB, 0x0630, 0x17B9,
		0xEF4E, 0xFEC7, 0xCC5C, 0xDDD5, 0xA96A, 0xB8E3, 0x8A78, 0x9BF1,
		0x7387, 0x620E, 0x5095, 0x411C, 0x35A3, 0x242A, 0x16B1, 0x0738,
		0xFFCF, 0xEE46, 0xDCDD, 0xCD54, 0xB9EB, 0xA862, 0x9AF9, 0x8B70,
		0x8408, 0x9581, 0xA71A, 0xB693, 0xC22C, 0xD3A5, 0xE13E, 0xF0B7,
		0x0840, 0x19C9, 0x2B52, 0x3ADB, 0x4E64, 0x5FED, 0x6D76, 0x7CFF,
		0x9489, 0x8500, 0xB79B, 0xA612, 0xD2AD, 0xC324, 0xF1BF, 0xE036,
		0x18C1, 0x0948, 0x3BD3, 0x2A5A, 0x5EE5, 0x4F6C, 0x7DF7, 0x6C7E,
		0xA50A, 0xB483, 0x8618, 0x9791, 0xE32E, 0xF2A7, 0xC03C, 0xD1B5,
		0x2942, 0x38CB, 0x0A50, 0x1BD9, 0x6F66, 0x7EEF, 0x4C74, 0x5DFD,
		0xB58B, 0xA402, 0x9699, 0x8710, 0xF3AF, 0xE226, 0xD0BD, 0xC134,
		0x39C3, 0x284A, 0x1AD1, 0x0B58, 0x7FE7, 0x6E6E, 0x5CF5, 0x4D7C,
		0xC60C, 0xD785, 0xE51E, 0xF497, 0x8028, 0x91A1, 0xA33A, 0xB2B3,
		0x4A44, 0x5BCD, 0x6956, 0x78DF, 0x0C60, 0x1DE9, 0x2F72, 0x3EFB,
		0xD68D, 0xC704, 0xF59F, 0xE416, 0x90A9, 0x8120, 0xB3BB, 0xA232,
		0x5AC5, 0x4B4C, 0x79D7, 0x685E, 0x1CE1, 0x0D68, 0x3FF3, 0x2E7A,
		0xE70E, 0xF687, 0xC41C, 0xD595, 0xA12A, 0xB0A3, 0x8238, 0x93B1,
		0x6B46, 0x7ACF, 0x4854, 0x59DD, 0x2D62, 0x3CEB, 0x0E70, 0x1FF9,
		0xF78F, 0xE606, 0xD49D, 0xC514, 0xB1AB, 0xA022, 0x92B9, 0x8330,
		0x7BC7, 0x6A4E, 0x58D5, 0x495C, 0x3DE3, 0x2C6A, 0x1EF1, 0x0F78
	};
	while(length--)
		r = (r >> 8) ^ CrctableCCITTRefl[(r ^ *src++) & 0xFF];
	return r;
}

void Communication::addCrc(QByteArray &qba)
{
	unsigned short crc=CRC16_CCITTCalc((unsigned char *)qba.data(),qba.size());
	qba.append((char *)&crc,sizeof(short));
}

//void Communication::createResendUnit(int fnc,QByteArray qba,bool retry)
//{
//    ResendUnit *ru=new ResendUnit;
//    ru->sendBuf=qba;
//    ru->fnc=fnc;
//    ru->retryTime=0;
//    pendingCmds.append(ru);
//    qsp.write(qba);
//    if(retry)
//    {
//        connect(&ru->qt,&QTimer::timeout,this,[=]{
//            if(ru->retryTime<RETRYTIME)
//            {
//                ru->retryTime++;
//                qsp.write(ru->sendBuf);
//                ru->qt.start(TIMEOUTTIME);
//            }
//            else
//            {
//                pendingCmds.removeOne(ru);
//                ru->deleteLater();
//            }
//        });
//        ru->qt.start(TIMEOUTTIME);
//    }
//}

//ResendUnit* Communication::findPending(int fnc)
//{
//    for(ResendUnit *ru:pendingCmds)
//        if(ru->fnc==fnc) return ru;
//    return nullptr;
//}

bool Communication::checkCrc(QByteArray &qba)
{
	char *data=qba.data();
	unsigned short crc=0;
	memcpy(&crc,data+qba.size()-3,sizeof(unsigned short));
	return crc==CRC16_CCITTCalc((unsigned char *)data,qba.size()-3);
}

//void Communication::getVersion()
//{
//	//不需重发
//	QByteArray qba;
//	qba.append(0x68);
//	qba.append(FNC_GET_SOFT_VER);
//	short len=0;
//	qba.append((char *)&len,sizeof(short));
//	addCrc(qba);
//	qba.append(0xd);
//	createResendUnit(FNC_GET_SOFT_VER,false);
//	qsp.write(qba);
//}

void Communication::getDebugInformation(MachineMode m)
{
	//不需重发
    debugInfoMode=m;
    QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_RD_DEBUG_INFO);
    short len=0;
    qba.append((char *)&len,sizeof(short));
    addCrc(qba);
    qba.append(0xd);
    qsp.write(qba);
}

void Communication::startSow()
{
	QByteArray qba;
	qba.append(0x68);
    qba.append(FNC_CMD_START_BZ);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_CMD_START_BZ,qba,true);
}

void Communication::stopSow()
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_CMD_STOP_BZ);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_CMD_STOP_BZ,qba,true);
}

void Communication::setSowParameters(BZCellParaType_st bzcpt)
{
    QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_SET_BZ_PARA);
    short len=sizeof(BZCellParaType_st);
    qba.append((char *)&len,sizeof(short));
    qba.append((char *)&bzcpt,len);
    addCrc(qba);
    qba.append(0xd);
    qsp.write(qba);
    //createResendUnit(FNC_SET_BZ_PARA,qba,true);
}

void Communication::getSowStatus()
{
	//不需重发
    QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_GET_BZ_STATUS);
    short len=0;
    qba.append((char *)&len,sizeof(short));
    addCrc(qba);
    qba.append(0xd);
    qsp.write(qba);
}

void Communication::getTestStatus()
{
	//不需重发
	QByteArray qba;
	qba.append(0x68);
    qba.append(FNC_GET_TEST_STATUS);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
}

void Communication::getABLine()
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_STORE_AB);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_STORE_AB,qba,true);
}

void Communication::setABLine(BDParaType bdpt)
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_SET_AB);
	short len=sizeof(BDParaType);
	qba.append((char *)&len,sizeof(short));
	qba.append((char *)&bdpt,len);
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_SET_AB,qba,true);
}

void Communication::setDotWhenClearSeed(bool b)
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_QZDD_ENABLE);
	short len=1;
	qba.append((char *)&len,sizeof(short));
	qba.append(b?1:0);
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_QZDD_ENABLE,qba,true);
}

void Communication::setManufacturerParameter(TerParaType tpt)
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_SET_TER_PARA);
	short len=sizeof(TerParaType);
	qba.append((char *)&len,sizeof(short));
	qba.append((char *)&tpt,len);
	addCrc(qba);
	qba.append(0xd);
	writeLog("下发厂家参数");
	qsp.write(qba);
    //createResendUnit(FNC_SET_TER_PARA,qba,true);
}

void Communication::setUserParameter(UserParaType upt,MachineMode m)
{
	preMode=m;
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_SET_USER_PARA);
	short len=sizeof(UserParaType);
	qba.append((char *)&len,sizeof(short));
	qba.append((char *)&upt,len);
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_SET_USER_PARA,qba,true);
}

void Communication::startContinuousSow(LXBZParaType lpt)
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_CMD_START_LXBZ);
	short len=sizeof(LXBZParaType);
	qba.append((char *)&len,sizeof(short));
	qba.append((char *)&lpt,len);
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_CMD_START_LXBZ,qba,true);
}

void Communication::stopContinuousSow()
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_CMD_STOP_LXBZ);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_CMD_STOP_LXBZ,qba,true);
}

void Communication::openPort()
{
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.setIniCodec(QTextCodec::codecForName("utf-8"));
	iniFile.beginGroup(APPLICATIONGROUP);
	qsp.setPortName(iniFile.value("SerialPort").toString());
	iniFile.endGroup();
    if(!qsp.isOpen())
        qsp.open(QIODevice::ReadWrite);
}

void Communication::closePort()
{
	qsp.close();
}

void Communication::getManufacturerParameter()
{
	QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_GET_TER_PARA);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_GET_TER_PARA,qba,true);
}

void Communication::getUserParameter()
{
	QByteArray qba;
	qba.append(0x68);
    qba.append(FNC_GET_USER_PARA);
	short len=0;
	qba.append((char *)&len,sizeof(short));
	addCrc(qba);
	qba.append(0xd);
	qsp.write(qba);
    //createResendUnit(FNC_GET_USER_PARA,qba,true);
}

bool Communication::getBdState() const
{
    return bdState;
}

MachineMode Communication::getPreMode()
{
	return preMode;
}

MachineMode Communication::getMode()
{
	return mode;
}

MachineMode Communication::getDebugInfoMode()
{
	return debugInfoMode;
}

void Communication::setEmptyABLine()
{
	BDParaType_st bdpt;
	bdpt.StartN=0;
	bdpt.StartE=0;
	bdpt.EndBN=0;
	bdpt.EndBE=0;
	bdpt.StartDir=0;
	bdpt.CalcDir=0;
	bdpt.StartState=0;
	bdpt.CalcDirFlag=0;
    bdpt.OffLen=0;
	bdpt.BDOffTime=0;
	bdpt.Resv=0;
	bdpt.CrcCheck=0;
    setABLine(bdpt);
}

bool Communication::getConnectionState()
{
    return state;
}

QString Communication::getVersion()
{
    return version;
}

void Communication::enableGapPoint(bool b)
{
    QByteArray qba;
    qba.append(0x68);
    qba.append(FNC_GDDD_ENABLE);
    short len=1;
    qba.append((char *)&len,sizeof(short));
    qba.append(b?1:0);
    addCrc(qba);
    qba.append(0xd);
    qsp.write(qba);
    //createResendUnit(FNC_GDDD_ENABLE,qba,true);
}

// template <typename... T>
// void Communication::sendCmd(int cmd,T... arg)
// {
//     QByteArray qba;
//     qba.append(0x68);
//     ReceiveUnit ru;
//     ru.cmd=cmd;
//     qba.append(ru.cmd);
//     receiveDeque.push_back(ru);
//     short len=sizeof(T);
//     qba.append((char *)&len,sizeof(short));
//     //qba.append((char *)&tpt,len);
//     addCrc(qba);
//     qba.append(0xd);
//     //createResendUnit(qba);
//     //writeLog("下发厂家参数");
//     qsp.write(qba);
// }
