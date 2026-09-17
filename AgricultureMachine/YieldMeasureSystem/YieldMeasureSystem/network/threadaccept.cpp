#include "threadaccept.h"
#include "tcp.h"
#ifdef WIN32
#include <ws2tcpip.h>
#elif
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdio.h>
#endif
#include <QDebug>

#define CMD_PORT    9601
#define DATA_PORT   9602
//#define SERVER_IP   "192.168.1.176"
#define  SERVER_IP  "169.254.1.2"

ThreadAccept::ThreadAccept(QObject *p)
    : QThread(p)
{
    datafd = -1;
    cmdfd  = -1;

    flag = false;
}
ThreadAccept::~ThreadAccept()
{
    closeServer();
}

void ThreadAccept::startServer(int m, int n)
{
    if(isRunning()) return;
#ifdef WIN32
	WSADATA ws;
	WSAStartup(MAKEWORD(2,2),&ws);
#endif
    this->m = m;
    this->n = n;
#ifdef WIN32
	char value = 1;
	cmdfd   = socket(AF_INET, SOCK_STREAM,0);
	datafd  = socket(AF_INET, SOCK_STREAM,0);
	setsockopt(cmdfd, SOL_SOCKET,SO_REUSEADDR,&value,sizeof(value));
	setsockopt(datafd,SOL_SOCKET,SO_REUSEADDR,&value,sizeof(value));
#elif linux
	unsigned int value = 1;
	cmdfd   = socket(AF_INET, SOCK_STREAM, 0);
	datafd  = socket(AF_INET, SOCK_STREAM, 0);
	setsockopt(cmdfd, SOL_SOCKET,SO_REUSEADDR,(void *)&value,sizeof(value));
	setsockopt(datafd,SOL_SOCKET,SO_REUSEADDR,(void *)&value,sizeof(value));
#endif

    flag = true;
    start();
}
void ThreadAccept::closeServer()
{
#ifdef linux
	shutdown(cmdfd, SHUT_RD);
	shutdown(datafd,SHUT_RD);
#endif
	flag = false;
	wait();
#ifdef WIN32
	closesocket(cmdfd);
	closesocket(datafd);
	WSACleanup();
#elif linux
	close(cmdfd);
	close(datafd);
#endif
    cmdfd = -1;
    datafd= -1;

}

void ThreadAccept::run()
{
    int n;
    int fd;
    int maxfd;
    socklen_t len;
	timeval tv;
    fd_set  rdfs;
    char buf[260];
    DataInfo *p;
    struct sockaddr_in addr;


    tv.tv_sec  = 0;
    tv.tv_usec = 200000; //200ms
    p = (DataInfo *)buf;
#ifdef WIN32
	ZeroMemory(&addr, sizeof(addr));
#elif linux
	bzero(&addr, sizeof(addr));
#endif
    addr.sin_family     = AF_INET;
    addr.sin_addr.s_addr= inet_addr(SERVER_IP);

    while(flag)
    {
        addr.sin_port       = htons(CMD_PORT);
        n = bind(cmdfd, (struct sockaddr*)&addr, sizeof(addr));
//        qDebug("bind CMD_PORT :%d", n);
        if(n == 0)
        {
            listen(cmdfd, 8);
            break;
        }
        sleep(1);
    }
    while(flag)
    {
        addr.sin_port       = htons(DATA_PORT);
        n = bind(datafd, (struct sockaddr*)&addr, sizeof(addr));
//        qDebug("bind DATA_PORT :%d", n);
        if(n == 0)
        {
            listen(datafd, 12);
            break;
        }
        sleep(1);
    }

    maxfd = (cmdfd > datafd) ? cmdfd : datafd;
    maxfd += 1;

    while(flag)
    {
#ifdef WIN32
		ZeroMemory(&rdfs, sizeof(rdfs));
#elif linux
		bzero(&rdfs, sizeof(rdfs));
#endif
        FD_SET(cmdfd, &rdfs);
        FD_SET(datafd, &rdfs);
		tv.tv_sec=0;
		tv.tv_usec=0;
		n = select(maxfd, &rdfs, NULL, NULL,&tv);

        if(n < 0) break;

        if(FD_ISSET(cmdfd, &rdfs))
        {
            len = sizeof(addr);
            fd = accept(cmdfd, (sockaddr*)&addr, &len);
            qDebug()<<fd<<"cmdfd";
            if(fd < 0) break;

            //设置超时时间
            tv.tv_sec = 0;
            tv.tv_usec = 20000;
#ifdef WIN32
			long tt = 2000;
			setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, (char*)&tt, sizeof(tt));
#elif linux
			setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif
            //接收身份信息
			n = recv(fd, buf, sizeof(DataInfo), 0);
            //判断身份信息
            if(n < (int)sizeof(DataInfo) || p->m >= this->m || p->n != 0xff)
            {
#ifdef WIN32
				closesocket(fd);
#elif linux
				close(fd);
#endif
            }
            else
            {
                tv.tv_sec = 2;
                tv.tv_usec = 0;
#ifdef WIN32
				tt = 2000;
				setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, (char*)&tt, sizeof(tt));
#elif linux
				setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif
				qDebug()<<fd<<"fd";
                emit sig_cmd_link(fd, p->m, addr.sin_addr.s_addr);
            }
        }

        if(FD_ISSET(datafd, &rdfs))
        {
            fd = accept(datafd, NULL, NULL);
            qDebug()<<fd<<"datafd";
            if(fd < 0) break;

            //设置超时时间
            tv.tv_sec = 0;
            tv.tv_usec = 20000;
#ifdef WIN32
			long tt=20;
			setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, (char*)&tt, sizeof(tt));
#elif linux
			setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif
            //接收身份信息
            n = recv(fd, buf, sizeof(DataInfo), 0);
            //判断身份信息
            if(n < (int)sizeof(DataInfo) || p->m >= this->m || p->n >= this->n)
            {
                qDebug()<<p->m<<p->n;
#ifdef WIN32
				closesocket(fd);
#elif linux
				close(fd);
#endif
            }
            else
            {
                emit sig_data_link(fd, p->m, p->n);
            }
        }
    }

    qDebug()<<"ThreadAccept exit";
}
