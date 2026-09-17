#ifndef THREADDATA_H
#define THREADDATA_H

#include <QThread>
#include <QMutex>
#ifdef WIN32
#include <windef.h>
#endif

struct TcpFormat;
struct DataCardMap;
struct DataSocketMap;
struct ProjectHead;
struct ProjectSave;
struct FileHead;
struct CmdInfo;

struct TapN
{
    int i;  //索引
    int n;  //长度
};

class ThreadData : public QThread
{
    Q_OBJECT
public:
    ThreadData(QObject *p);
    ~ThreadData();

    int startServer(int m, int n);
    int closeServer();

    /*命令端口操作接口*/
    int sendCmd(int i, TcpFormat *fmt); //发送命令
    int sockState(int timeout);         //判断命令端口连接
    int getCardInfo(CmdInfo *info, int index);
    unsigned int cardIp(char *ipaddr, int index);
	QString cardIp(int index);

    //开始记录数据
    int detStart();
    //停止记录数据
    int detEnd();
    int detEnd(ProjectHead *h, ProjectSave *s);

    //获得实时值
    int currentAdc(int index);
    float currentVal(int index);
    int getcurrtenData(int *pAdc, float *pVal, const TapN *in, int num);
    int getAnalyseData(float *res, int dataLen);
    /** *读取显示数据
     * buffer   单个通道的缓冲区
     * maxLen   要读取的最大长度
     * index    通道索引
     * return   成功:实际拷贝的数据长度 失败:-1
     *
     * pBuffers 所有通道的缓冲区指针数组
     * out      i 触发点索引 -1表示未触发, n 数据长度
     * in       i 缓冲区通道索引, n 缓冲区最大长度
     * num      缓冲区个数
     * return   成功:0 失败:-1
     * */
    TapN getShowData(float *buffer, int maxLen, int index);
    int getShowData(float **pBuffers, TapN *out, const TapN *in, int num);

    /** *读取传感器id
     * idList 用于接收id 0表示传感器未连接
     * flag 0-返回所有传感器 1-只返回使能的传感器
//     * stateArray   bit[0] 是否使能, bit[1] id是否可编辑 bit[7] 是否有传感器
     * stateArray  bit[0:3] 0:没有传感器, 1:手动id, 2:电压表, 3:芯片id;
     * bit[7] 是否使能; bit[6] 是否已经配置标定信息
     * return 感器通道总数量
     * */
    int getSensorId(uint64_t *idArray, uint8_t *stateArray);

	//获取/设置文件头
	int clearFileHead(int flag);
	int getFileHead(FileHead *head, int index);
	int setFileHead(FileHead *head, int index);
	int setFileZero(double zero, int index);

	//设置包大小
	int setAveWindow(int size);
	int setPageSize(int pageLen);

signals:
	void sig_sensor_change();
	void tsig_sensor();
	void tsig_full();
	void signalConnected();
	void signalDisconnected();
	void signalValveChanged();
public slots:
	void addSensor(int fd, int i, int j);
	void addCard(int fd, int i, unsigned int ip);
	int  removeCard(int i);

private slots:
    void tslot_sensor();

protected:
    void run();
    int  analyse(float *res, int len);
    int  trytoWrite(DataSocketMap *p, float *d, int len, int trigger);
    int  fileflush(DataSocketMap *p);

    void timerEvent(QTimerEvent *e);

private:
    QMutex          lock;
	QMutex          lock_ex;
    int             state;      //0-空闲 1-接收数据
    int             epfd;       //epoll句柄
    unsigned        pipefd[2];  //管道
    DataSocketMap  *map;        //套接字-画布对应关系    
    DataCardMap    *cmd;        //命令端口
    int             m;          //采集板个数
    int             n;          //每个采集板的通道数
    bool            flag;       //线程标志
    bool            isTrigger;  //触发标志
    int             timerId;
    int64_t         startUTF;   //开始检测时间
	int disconnectedFlag;
};

#endif // THREADDATA_H
