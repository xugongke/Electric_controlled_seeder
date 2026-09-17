#ifndef THREADUART_H
#define THREADUART_H

#include <QThread>
#include <QSemaphore>

class ThreadUart : public QThread
{
    Q_OBJECT
public:
    ThreadUart(QObject *parent);
    ~ThreadUart();

    int threadCreate();
    int threadStop();

    int sendCmd(int cmd, int argLen, void *args);

signals:
    int sig_uart(int cmd, int argLen, void *args);
    int sig_errs(int e); //0-接收失败 1-发送失败 2-重连失败

protected:
    void run();

private:
    QSemaphore      sem;
    long hUart;
    long hPipe[2];
    int ThreadFlag;
    char portName[260];
};




#define CMD_HEAD    0xA8
#define HEAD_EXIT   0xFF

#define CMD_G_INFO      0x01    //  ----        char[24]    获得板卡参数
#define CMD_STOP        0x80    //  ----        ----        结束
#define CMD_CECHAN      0x85    //  ----        ----        测产模式
#define CMD_EX_R_REG    0xA0    //  ----        int         读寄存器
#define CMD_EX_W_REG    0xA1    //  int         int         写寄存器
#define CMD_EX_R_RH     0xA2    //  int         float       读取水分 模式 - 值
#define CMD_EX_VAL      0xA3    //  ----        float[4]    读取实时值
#define CMD_EX_ANA      0xA4    //  int         float[4]    读取分析值  要分析的采样点数量 - 结果
#define CMD_ERROR       0xff    //  ----        int         错误

struct CmdHead
{
    uint8_t     h;      //消息头
    uint8_t     cmd;    //命令数
    uint16_t    len;    //数据长度 包括数据头
    uint32_t    res;
};
union  CmdBody
{
    char  buf[256];
    float fa[64];
    int   ia[64];
};

#endif //THREADUART_H
