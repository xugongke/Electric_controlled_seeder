#include "threaduart.h"
#include "common_port.h"
#include "global.h"
#include "tools/settingshandle.h"
#include <QDebug>

ThreadUart::ThreadUart(QObject *parent)
{
    hUart = -1;
    hPipe[0] = -1;
    hPipe[1] = -1;
}

ThreadUart::~ThreadUart()
{

}

int ThreadUart::threadCreate()
{
//    hUart = port_open(iniFile.value("Port").toString().toStdString().c_str(), "9600-8-N-1");
    //hUart = port_open(getPort().toStdString().c_str(), "9600-8-N-1");
    strcpy(portName, getPort().toLatin1().data());

    port_pipe(hPipe);
    ThreadFlag = 1;
    hUart = -1;
    start();
    return 0;


    if(hUart < 0) return -1;

    int n;
    CmdHead head;


    head.h = CMD_HEAD;
    head.len = sizeof(head);
    head.cmd = CMD_CECHAN;
    head.res = 0;
    port_send(hUart, (char*)&head, sizeof(head), 1);
    n = port_read(hUart, (char*)&head, sizeof(CmdHead), 1);
    if(n <= 0)
    {
        port_close(hUart);
        hUart = -1;
        return -1;
    }

    port_pipe(hPipe);

    ThreadFlag = 1;
    start();
    return 0;
}

int ThreadUart::threadStop()
{
    CmdHead head;
    head.h = HEAD_EXIT;
    head.len = sizeof(head);
    head.cmd = 0;
    head.res = 0;
    ThreadFlag = 0;
    port_send(hPipe[1], (char*)&head, sizeof(head), 1);
    sem.release();

    wait(500);

    if(hUart > 0)
    {
        head.h = CMD_HEAD;
        head.len = sizeof(head);
        head.cmd = CMD_STOP;
        head.res = 0;
        port_send(hUart, (char*)&head, sizeof(head), 1);
        port_close(hUart);
    }
    if(hPipe[0] > 0)port_close(hPipe[0]);
    if(hPipe[1] > 0)port_close(hPipe[1]);
    hUart = -1;
    hPipe[0] = -1;
    hPipe[1] = -1;
    return 0;
}

int ThreadUart::sendCmd(int cmd, int argLen, void *args)
{
    char buf[4096];
    CmdHead *ptHead = (CmdHead*)buf;
	CmdBody *ptBody = (CmdBody*)(ptHead+1);

    if(!isRunning()) return -1;

    ptHead->h   = CMD_HEAD;
    ptHead->cmd = cmd;
    ptHead->len = sizeof(CmdHead) + argLen;
    ptHead->res = 0;

    if(argLen > 0) memcpy(ptBody, args, argLen);
    port_send(hPipe[1], buf, ptHead->len, 1);
    sem.release();
    return 0;
}

#include<Windows.h>
void ThreadUart::run()
{
    int n, len;
    unsigned int ms;
    char buf[4096];
    CmdHead *ptHead = (CmdHead*)buf;
    CmdBody *ptBody = (CmdBody*)(ptHead+1);
    ms = 100;
    while(1)
    {
        //读取主线程命令
        if(sem.tryAcquire(1, ms))
        {
            n = port_read(hPipe[0], buf, sizeof(CmdHead), 1);
            if(n <= 0) continue;
            len = ptHead->len - sizeof(CmdHead);
            if(len > 0) port_read(hPipe[0], buf + sizeof(CmdHead), len, 1);

            switch(ptHead->h)
            {
            case CMD_HEAD: //发送命令
                if(hUart < 0) break;
                n = port_send(hUart, buf, ptHead->len, 1);
                if(n <= 0) {emit sig_errs(1); port_close(hUart); hUart = -1; continue;}
                n = port_read(hUart, buf, sizeof(CmdHead), 1);
                if(n <= 0) {emit sig_errs(0); continue;}
                len = ptHead->len - sizeof(CmdHead);
                if(len > 0) port_read(hUart, buf + sizeof(CmdHead), len, 1);
                if(ThreadFlag) emit sig_uart(ptHead->cmd, len, ptBody);
                break;
            case HEAD_EXIT: //退出线程
                return;
            }
        }

        //重连
        if(hUart < 0)
        {
            hUart = port_open(portName, "9600-8-N-1");
            if(hUart < 0) {emit sig_errs(2); hUart = -1; continue;}

            ptHead->h = CMD_HEAD;
            ptHead->len = sizeof(CmdHead);
            ptHead->cmd = CMD_CECHAN;
            ptHead->res = 0;
            port_send(hUart, buf, sizeof(CmdHead), 1);
            n = port_read(hUart, buf, sizeof(CmdHead), 1);
            if(n <= 0) {emit sig_errs(2); port_close(hUart); hUart = -1; continue;}
            sendCmd(CMD_G_INFO,0,new CmdBody);
            continue;
        }

        //读取水分
        ptHead->h   = CMD_HEAD;
        ptHead->cmd = CMD_EX_R_RH;
        ptHead->len = sizeof(CmdHead) + sizeof(int);
        ptHead->res = 0;
        ptBody->ia[0]=getMoistureValueMode();

		n = port_send(hUart, buf, ptHead->len, 1);
        if(n <= 0) {emit sig_errs(3); port_close(hUart); hUart = -1; continue;}
        n = port_read(hUart, buf, sizeof(CmdHead), 1);
        if(n <= 0) {emit sig_errs(4); continue;}
        len = ptHead->len - sizeof(CmdHead);
        if(len > 0) port_read(hUart, buf + sizeof(CmdHead), len, 1);
        if(ThreadFlag) emit sig_uart(ptHead->cmd, len, ptBody);

        //读取实时值
        ptHead->h   = CMD_HEAD;
        ptHead->cmd = CMD_EX_VAL;
        ptHead->len = sizeof(CmdHead) + sizeof(int);
        ptHead->res = 0;
        ptBody->ia[0] = 4000;

        n = port_send(hUart, buf, ptHead->len, 1);
        if(n <= 0) {emit sig_errs(5); port_close(hUart); hUart = -1; continue;}
        n = port_read(hUart, buf, sizeof(CmdHead), 1);
        if(n <= 0) {emit sig_errs(6); continue;}
        len = ptHead->len - sizeof(CmdHead);
        if(len > 0) port_read(hUart, buf + sizeof(CmdHead), len, 1);
        if(ThreadFlag) emit sig_uart(ptHead->cmd, len, ptBody);

        //读取按键状态
        ptHead->h   = CMD_HEAD;
        ptHead->cmd = CMD_EX_R_REG;
        ptHead->len = sizeof(CmdHead);
        ptHead->res = 0;

        n = port_send(hUart, buf, ptHead->len, 1);
        if(n <= 0) {emit sig_errs(7); port_close(hUart); hUart = -1; continue;}
        n = port_read(hUart, buf, sizeof(CmdHead), 1);
        if(n <= 0) {emit sig_errs(8); continue;}
        len = ptHead->len - sizeof(CmdHead);
        if(len > 0) port_read(hUart, buf + sizeof(CmdHead), len, 1);
        if(ThreadFlag) emit sig_uart(ptHead->cmd, len, ptBody);

    }


}
