#include "threaddata.h"
#include "tcp.h"
#include "global.h"
#include <sys/stat.h>
#ifdef WIN32
#include <winsock2.h>
#elif linux
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#endif
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <QTimerEvent>

#include <QDebug>



struct DataSocketMap
{
    unsigned    fd;         //套接字
    int         offset;     //接收指针偏移
    int         bufSize;    //缓冲区长度
    int         pageSize;   //单个数据包大小
    char       *buffer;     //接收缓冲区

    int        *winAdc;     //实时ADC滑动窗口缓存
    float      *winVal;     //实时值滑动窗口缓存
    float      *temp;       //显示数据缓存
    int         winWidth;   //滑动窗口大小
    int         winIndex;   //滑动窗口大小
    int         winLen;     //滑动窗口
    int         tempSize;   //显示缓冲区长度
    int         tempLen;    //显示数据长度
    int         tempPre;    //触发前数据 -1表示没触发

    uint16_t    idFlag;     //0:没有传感器, 1:手动id, 2:电压表, 3:芯片id
    uint16_t    saveFlag;   //0-未触发 1-已触发 2-缓存空
    int         queueSize;  //原始数据队列容量
    int         queueLen;   //原始数据队列有效数据长度
    int         queueOffset;//原始数据写指针索引
    float      *queue;      //原始数据队列
    FILE       *fp;         //原始数据文件流
    FileHead    fileHead;   //原始文件头
};
struct DataCardMap
{
    int         fd;
    uint32_t    ip;
    CmdInfo     info;
};

static sockaddr pipeaddr;

ThreadData::ThreadData(QObject *p)
	: QThread(p),disconnectedFlag(0)
{
    m       = 0;
    n       = 0;
    flag    = false;
    map     = NULL;
    cmd     = NULL;
    state   = 0;
    timerId = -1;
    pipefd[0] = pipefd[1] = 0;
    connect(this, &ThreadData::tsig_sensor, this, &ThreadData::tslot_sensor, Qt::QueuedConnection);


    sockaddr_in *paddr = (sockaddr_in*)&pipeaddr;
    paddr->sin_family = AF_INET;
	paddr->sin_addr.s_addr = inet_addr("127.0.0.1");
	paddr->sin_port = htons(9600);
}
ThreadData::~ThreadData()
{
    closeServer();
}

int ThreadData::startServer(int m, int n)
{
    int i;
    int len;

    if(flag) return -1;

    this->m = m;
    this->n = n;

    /* TODO 创建通信*/
	pipefd[0] = socket(AF_INET, SOCK_DGRAM, 0);
    if(pipefd[0] <= 0 ) return -1;
	pipefd[1] = socket(AF_INET, SOCK_DGRAM, 0);
    if(pipefd[1] <= 0) { closesocket(pipefd[0]); pipefd[0] = 0; return -1; }
	i = bind(pipefd[0], &pipeaddr, sizeof(pipeaddr));
    if(i == -1)
    {
        return -2;
    }

    len     = m*n;
    map     = (DataSocketMap*)malloc(len * sizeof(DataSocketMap));
    cmd     = (DataCardMap*)malloc(m * sizeof(DataCardMap));
    memset(cmd, 0, m * sizeof(DataCardMap));
    memset(map, 0, len * sizeof(DataSocketMap));

    for(i = 0; i < len; i++)
    {
        map[i].fd       = -1;
        map[i].bufSize  = 65536*8;
        map[i].buffer   = (char*)malloc(65536*8);
        map[i].tempSize = 256;
        map[i].temp     = (float*)malloc(256*4);
        map[i].winVal   = (float*)malloc(10*4);
        map[i].winAdc   = (int*)malloc(10*4);
        map[i].winWidth = 10;

        map[i].queueSize    = 2048*1000;
        map[i].queueLen     = 0;
        map[i].queueOffset  = 0;
        map[i].queue        = (float*)malloc(2048*1000*4);

        map[i].pageSize = 16 + 200*4;
        map[i].tempPre  = -1;

        map[i].fileHead.body.type   = -1;
        map[i].fileHead.param.id    = 0;
    }

    start();
    return 0;
}
int ThreadData::closeServer()
{
    int i, len;
    PipeCmd pc;

    flag = false;
	if(pipefd[0] <= 0) return -1;
    if(pipefd[1] <= 0) return -1;
    pc.fd       = -1;
    pc.index    = -1;
#ifdef WIN32
    sendto(pipefd[1], (char*)&pc, sizeof(pc), 0, &pipeaddr, sizeof(pipeaddr));
#elif linux
    i = write(pipefd[1], &pc, sizeof(pc));
#endif
    wait(1000);
#ifdef WIN32
    closesocket(pipefd[0]);
    closesocket(pipefd[1]);
#elif linux
    close(epfd);
    close(pipefd[0]);
    close(pipefd[1]);
#endif
    len = m*n;
    if(map)
    {
        for(i = 0; i < len; i++)
        {
            free(map[i].buffer);
            free(map[i].temp);
			if(map[i].fd > 0)
#ifdef WIN32
				closesocket(map[i].fd);
#elif linux
				close(map[i].fd);
#endif
        }
        free(map);
        map = NULL;
    }
    if(cmd)
    {
        for(i = 0; i < m; i++)
        {
			if(cmd[i].fd > 0)
#ifdef WIN32
				closesocket(cmd[i].fd);
#elif linux
				close(cmd[i].fd);
#endif
        }
        free(cmd);
        cmd = NULL;
    }

    m = 0;
    n = 0;

    return 0;
}
#include <QDateTime>
int ThreadData::sendCmd(int i, TcpFormat *fmt)
{
	//qDebug("sendCmd:%d,%d,%d",i,fmt->h.len, fmt->h.cmd);
	int n, len;
	int F = fmt->h.cmd;
	if(cmd[i].fd <= 0)
	{
		++disconnectedFlag;
		return -1;
	}
    len = fmt->h.len;
	lock_ex.lock();
#ifdef WIN32
	n = send(cmd[i].fd,(char *)fmt, len, 0);
	Sleep(2);
#elif linux
	n = send(cmd[i].fd, fmt, len, 0);
#endif
    if(n <= 0) goto errs;
    fmt->h.len = 0;
#ifdef WIN32
	n = recv(cmd[i].fd,(char *)fmt,4096, 0);
	Sleep(2);
#elif linux
    n = recv(cmd[i].fd, fmt, 4096, 0);
#endif
	if(fmt->h.cmd==CMD_EX_W_REG)
		emit signalValveChanged();
    if(n <= 0) goto errs;

	if(fmt->h.cmd != F)
	{
		n = recv(cmd[i].fd, (char *)fmt, 4096, 0);
		if(n <= 0) goto errs;
	}
	lock_ex.unlock();
	disconnectedFlag=0;
    return n;

errs:
#ifdef WIN32
	//closesocket(cmd[i].fd);
#elif linux
	close(cmd[i].fd);
#endif
	//cmd[i].fd = 0;
	qDebug("%x:%d-%d",fmt->h.cmd, n, fmt->h.len);
	lock_ex.unlock();
	if(++disconnectedFlag==5)
		emit signalDisconnected();
    return -1;
}
int ThreadData::sockState(int timeout)
{
#ifdef WIN32
	int i, n;
	SOCKET maxfd;
#elif linux
    int i, n, maxfd;
#endif
    int flag, res;
    fd_set rdfs, temp;
    timeval tv;
    TcpFormat fmt;

    fmt.h.h = 0;
    fmt.h.cmd = CMD_ALIVE;
    fmt.h.len = sizeof(fmt.h);
    FD_ZERO(&temp);
    flag = 0;
    maxfd = 0;
    for(i = 0; i < G.m; i++)
    {
        if(cmd[i].fd <= 0) continue;

        if(timeout > 0)
        {
#ifdef WIN32
			n = send(cmd[i].fd,(char *)&fmt,fmt.h.len, 0);
#elif linux
            n = send(cmd[i].fd, &fmt, fmt.h.len, 0);
#endif
            if(n <= 0)
            {
#ifdef WIN32
				closesocket(cmd[i].fd);
#elif linux
				close(cmd[i].fd);
#endif
                cmd[i].fd = 0;
                continue;
            }
        }

        FD_SET(cmd[i].fd, &temp);

        flag |= 0x01 << i;
        if(cmd[i].fd > maxfd) maxfd = cmd[i].fd;

    }

    if(timeout <= 0) return flag;
    if(flag == 0) return 0;

    tv.tv_sec  = timeout / 1000;
    tv.tv_usec =(timeout % 1000) * 1000;
    res = 0;
    do
    {
        rdfs = temp;
        n = select(maxfd + 1, &rdfs, NULL, NULL, &tv);

        if(n <= 0)
        {
            for(i = 0; i < G.m; i++)
            {
                if(((0x01 << i) & res) == 0 && cmd[i].fd > 0)
                {
                    removeCard(i);
                    flag &= ~(0x01 << i);
                }
            }
        }


        for(i = 0; i < G.m; i++)
        {
            if(cmd[i].fd > 0 && FD_ISSET(cmd[i].fd, &rdfs))
            {
                FD_CLR(cmd[i].fd, &temp);
#ifdef WIN32
				n =recv(cmd[i].fd,(char *)&fmt,sizeof(fmt), 0);
#elif linux
                n = recv(cmd[i].fd, &fmt, sizeof(fmt), 0);
#endif
                if(n <= 0)
                {
                    removeCard(i);
                    flag &= ~(0x01 << i);
                }
                else
                {
                    res |= 0x01 << i;
                }
            }
        }

    } while(res != flag);

    return res;
}

int ThreadData::getCardInfo(CmdInfo *info, int index)
{
    if(cmd[index].fd <= 0) return -1;
    *info = cmd[index].info;
    return 0;
}

unsigned int ThreadData::cardIp(char *ipaddr, int index)
{
    if(ipaddr)
    {
        unsigned char *p = (unsigned char *)&cmd[index].ip;
        sprintf(ipaddr, "%u.%u.%u.%u", p[0], p[1], p[2], p[3]);
    }
    return cmd[index].ip;
}

QString ThreadData::cardIp(int index)
{
	unsigned char *p = (unsigned char *)&cmd[index].ip;
	return QString::asprintf("%u.%u.%u.%u", p[0], p[1], p[2], p[3]);
}

int ThreadData::detStart()
{
    int i, len;
    char path[260];

    if(state != 0) return -1;

    len = m*n;
    for(i = 0; i < len; i++)
    {
        //清空显示缓冲区
        map[i].tempLen = 0;
        map[i].winLen = 0;
        map[i].winIndex = 0;
        //清空文件缓冲区
        map[i].queueLen = 0;
        map[i].queueOffset = 0;
        map[i].saveFlag = 0;
    }

//    time(&startUTF);
//    sprintf(path, HISTORY_PATH"%lx/", startUTF);
//    mkdir(path, 0777);

    //开启接收模式
    state = 1;
    return 0;
}

int ThreadData::detEnd()
{
    char path[260];
    state = 0;
    msleep(500);

//    sprintf(path, HISTORY_PATH"%lx/", startUTF);
//    rmdir(path);

    return 0;
}
int ThreadData::detEnd(ProjectHead *h, ProjectSave *s)
{
    int i, j, len;
    FILE *fp;
    char path[260];

    if(startUTF == 0) return -1;

    //等待线程状态切换
    state = 0;
    msleep(500);

    //刷新原始数据缓冲区,关闭原始数据文件
    len = m*n;
    for(i = 0, j = 0; i < len; i++)
    {
        if(map[i].fp == NULL) continue;
        fileflush(map + i);
        fclose(map[i].fp);
        map[i].fp = NULL;
        j++;
    }

    //如果文件夹为空,认为没有产生历史数据,删除文件夹
    sprintf(path, HISTORY_PATH"%lx/", startUTF);
    rmdir(path);

    //生成目录文件
    sprintf(path, HISTORY_PATH"%lx/info", startUTF);
    fp = fopen(path, "wb");
    if(fp == NULL) return -1;
    fwrite(h, sizeof(ProjectHead), 1, fp);
    fwrite(s, sizeof(ProjectSave), 1, fp);
    fclose(fp);

    startUTF = 0;
    return j;
}

//获得实时值
int ThreadData::currentAdc(int index)
{
    int i, n;
    int64_t sum;

    lock.lock();
    n = map[index].winLen;
    sum = map[index].winAdc[0];
    for(i = 1; i < n; i++)
    {
        sum += map[index].winAdc[i];
    }
    lock.unlock();

    return n > 0 ? (int)(sum / n) : 0;
}
float ThreadData::currentVal(int index)
{
    int i, n;
    double sum;

    lock.lock();
	n = map[index].winLen;
    sum = map[index].winVal[0];
    for(i = 1; i < n; i++)
	{
        sum += map[index].winVal[i];
    }
    lock.unlock();

    return n > 0 ? (float)(sum / n) : 0;
}
int ThreadData::getcurrtenData(int *pAdc, float *pVal, const TapN *in, int num)
{
    int i, j, n, index;
    int64_t ld;
    double  lf;

    lock.lock();

    for(i = 0; i < num; i++)
    {
        index = in[i].i;
        n =  map[index].winLen;
        ld = map[index].winAdc[0];
        lf = map[index].winVal[0];
        for(j = 1; j < n; j++)
        {
            ld += map[index].winAdc[j];
            lf += map[index].winVal[j];
        }
        pAdc[i] = (int)(ld / n);
        pVal[i] = (float)(lf / n);
    }

    lock.unlock();
    return 0;
}

int ThreadData::getAnalyseData(float *res, int dataLen)
{
    int e;
    lock.lock();
    e = analyse(res, dataLen);
    lock.unlock();
    return e;
}

TapN ThreadData::getShowData(float *buffer, int maxLen, int index)
{
    int e, u;
    if(index >= m*n || index < 0 || maxLen <= 0) return {-1, -1};

    lock.lock();

    if(map[index].tempLen > maxLen)
    {
        e = maxLen;
        u = map[index].tempPre;
        map[index].tempLen -= maxLen;
        memcpy(buffer, map[index].temp, e*sizeof(int));
        memmove(map[index].temp, map[index].temp + maxLen, map[index].tempLen*sizeof(int));
        if(u < maxLen)
        {
            map[index].tempPre = -1;
        }
        else
        {
            map[index].tempPre = u - maxLen;
            u = -1;
        }
    }
    else if(map[index].tempLen == 0)
    {
        e = 0;
        u = -1;
//        qDebug() << "000000";
    }
    else
    {
        e = map[index].tempLen;
        u = map[index].tempPre;
        memcpy(buffer, map[index].temp, e*sizeof(int));
        map[index].tempLen = 0;
        map[index].tempPre = -1;
    }

    lock.unlock();

    return {u, e};
}
int ThreadData::getShowData(float **pBuffers, TapN *out, const TapN *in, int num)
{
    int i, e, u;
    int index, maxLen;
    int len = m*n;

    lock.lock();

    for(i = 0; i < num; i++)
    {
        index = in[i].i;
        maxLen = in[i].n;
        if(index >= len || index < 0 || maxLen <= 0)
        {
            continue;
        }

        if(map[index].tempLen > maxLen)
        {
            e = maxLen;
            u = map[index].tempPre;
            map[index].tempLen -= maxLen;
            memcpy(pBuffers[index], map[index].temp, e*sizeof(int));
            memmove(map[index].temp, map[index].temp + maxLen, map[index].tempLen*sizeof(int));
            if(u < maxLen)
            {
                map[index].tempPre = -1;
            }
            else
            {
                map[index].tempPre = u - maxLen;
                u = -1;
            }
        }
        else if(map[index].tempLen == 0)
        {
            e = 0;
            u = -1;
        }
        else
        {
            e = map[index].tempLen;
            u = map[index].tempPre;
            memcpy(pBuffers[index], map[index].temp, e*sizeof(int));
            map[index].tempLen = 0;
            map[index].tempPre = -1;
        }
        out[i].n = e;
        out[i].i = u;
    }

    lock.unlock();

    return 0;
}

int ThreadData::getSensorId(uint64_t *idArray, uint8_t *stateArray)
{
    uint8_t flag;
    int i, len;
    len = m*n;

    for(i = 0; i < len; i++)
    {
        if(map[i].fd <= 0)
        {
            map[i].fileHead.sensorId = 0;
            map[i].idFlag = 0;
        }
        flag  = ((map[i].fileHead.body.type >= 0) << 7);
        flag |= ((map[i].fileHead.param.id == map[i].fileHead.sensorId) << 6);

        if(idArray)    idArray[i]   = map[i].fileHead.sensorId;
        if(stateArray) stateArray[i]= map[i].idFlag | flag;
    }

    return len;
}

int ThreadData::clearFileHead(int flag)
{
    int i, len;
    len = m*n;

    for(i = 0; i < len; i++)
    {
        if(flag & 0x01) map[i].fileHead.body.type   = -1;
        if(flag & 0x02) map[i].fileHead.param.id    = 0;
        if(map[i].fp != NULL)
        {
            fclose(map[i].fp);
            map[i].fp = NULL;
        }
    }

    return len;
}
int ThreadData::getFileHead(FileHead *head, int index)
{
    if(map[index].fd <= 0)
        return -1;

    memcpy(head, &map[index].fileHead, sizeof(FileHead));
    return 0;
}
int ThreadData::setFileHead(FileHead *head, int index)
{
    if(map[index].fd <= 0) return -1;

    map[index].fileHead.Hz      = head->Hz;
    map[index].fileHead.preLen  = head->preLen;
    map[index].fileHead.body    = head->body;
    map[index].fileHead.param   = head->param;
    map[index].fileHead.calib   = head->calib;
    map[index].fileHead.zero    = head->zero;

    memcpy(head, &map[index].fileHead, sizeof(FileHead));
    return 0;
}
int ThreadData::setFileZero(double zero, int index)
{
    if(map[index].fd <= 0) return -1;
    map[index].fileHead.zero   = zero;
    return 0;
}

int ThreadData::setAveWindow(int size)
{
    int i, len;

    len = m*n;

    if(size < 10) size = 10;

    for(i = 0; i < len; i++)
    {
        if(map[i].winAdc) free(map[i].winAdc);
        map[i].winAdc = (int *)malloc(size * 4);
        if(map[i].winVal) free(map[i].winVal);
        map[i].winVal = (float*)malloc(size * 4);
        map[i].winWidth = size;
        map[i].winIndex = 0;
        map[i].winLen = 0;
    }

    return size;
}

int ThreadData::setPageSize(int pageLen)
{
    int i, len;

    len = m*n;
    pageLen = pageLen * sizeof(float) + sizeof(DataHead);

    for(i = 0; i < len; i++)
    {
        map[i].pageSize = pageLen;
    }

    return 0;
}

void ThreadData::addSensor(int fd, int i, int j)
{
    int index;
    PipeCmd pc;

    //采集时不接收新连接
//    if(state == 1)
//    {
//        close(fd);
//        return;
//    }

    index = i * n + j;

    memset(&map[index].fileHead, 0, sizeof(FileHead));
    map[index].fileHead.i        = i;
    map[index].fileHead.j        = j;
    map[index].fileHead.sensorId = 0;
    map[index].idFlag            = 0;
    map[index].fileHead.h        = FILE_HEAD;

    pc.fd       = fd;
    pc.index    = index;
#ifdef WIN32
    sendto(pipefd[1], (char*)&pc, sizeof(pc), 0, &pipeaddr, sizeof(pipeaddr));
#elif linux
    index = write(pipefd[1], &pc, sizeof(pc));
#endif
}
void ThreadData::addCard(int fd, int i, unsigned int ip)
{
    TcpFormat fmt;
	if(cmd[i].fd > 0)
#ifdef WIN32
		closesocket(cmd[i].fd);
#elif linux
		close(cmd[i].fd);
#endif
    cmd[i].fd = fd;

    //获取
    fmt.h.h   = 0;
    fmt.h.cmd = CMD_G_INFO;
    fmt.h.len = sizeof(fmt.h);
    if(sendCmd(i, &fmt) < 0) return;

    cmd[i].info = fmt.b.info;
    cmd[i].ip   = ip;

    tslot_sensor();
	fmt.h.h=CMD_HEAD;
	fmt.h.cmd=CMD_START;
	fmt.h.len=sizeof(CmdHead);
	sendCmd(0,&fmt);
	setAveWindow(10);
    detStart();
    G.rd->start();
	emit signalConnected();
    disconnectedFlag=0;
    G.rd->setDialogFlag(true);
	emit signalValveChanged();
}

int ThreadData::removeCard(int i)
{
    int j;
    int index;
    PipeCmd pc;

    if(cmd[i].fd > 0)
    {
#ifdef WIN32
		closesocket(cmd[i].fd);
#elif linux
        close(cmd[i].fd);
#endif
        cmd[i].fd = 0;

        for(j = 0; j < G.n; j++)
        {
            index = i * n + j;
            pc.fd       = -1;
            pc.index    = index;
#ifdef WIN32
            sendto(pipefd[1], (char*)&pc, sizeof(pc), 0, &pipeaddr, sizeof(pipeaddr));
#elif linux
            index = write(pipefd[1], &pc, sizeof(pc));
#endif
        }
    }
    return 0;
}

void ThreadData::tslot_sensor()
{
    if(timerId == -1)
    {
        timerId = startTimer(200);
    }
}

void ThreadData::run()
{
    int i, j;
    int len;
    DataSocketMap *p;
    DataHead      *fmt;
    PipeCmd     pipecmd;

    fd_set rdfs, temp;

    FD_ZERO(&rdfs);
    FD_SET(pipefd[0], &rdfs);
    flag = true;
    while(flag)
    {
        /*select*/
        temp = rdfs;
        if(select(0, &temp, NULL, NULL, NULL) < 0) goto errs;

        for(i = 0; (unsigned)i < temp.fd_count; i++)
        {
            //控制命令
            if(temp.fd_array[i] == pipefd[0])
            {
                len = recvfrom(pipefd[0], (char*)&pipecmd, sizeof(PipeCmd), 0, NULL, NULL);

                if(pipecmd.index >= 0)    //传感器变化
                {
                    if(map[pipecmd.index].fd > 0)   //删除原有传感器连接
                    {
                        FD_CLR(map[pipecmd.index].fd, &rdfs);
                        close(map[pipecmd.index].fd);
                        map[pipecmd.index].fd   = -1;
                    }

                    if(pipecmd.fd > 0)              //增加新传感器连接
                    {
                        map[pipecmd.index].fd       = pipecmd.fd;
                        map[pipecmd.index].offset   = 0;
                        FD_SET(pipecmd.fd, &rdfs);
                    }

					emit tsig_sensor();
                    continue;
                }
                if(pipecmd.index == -1)     //退出线程
                {
                    return;
                }
            }

            //寻找数据
            for(j = 0; j < n; j++)
            {
                if(map[j].fd == temp.fd_array[i]) break;
            }
            if(j == n)
            {
                //TODO 检查
                continue;
            }
            p   = &map[j];
            len = recv(p->fd, p->buffer + p->offset, p->bufSize - p->offset, 0);
			//qDebug()<<len<<j<<"ttttttttttttttttttttttttttt";

            if(len <= 0) goto loop;

            p->offset += len;
            if(p->offset < (int)sizeof(DataHead)) continue;

			lock.lock();
			j = 0;
			while(1)
			{
				fmt = (DataHead*)(p->buffer + j);
				//计算数据长度
				if((j += sizeof(DataHead)) > p->offset) break;
				len = fmt->len;
				if(len > 0 && (j += len * sizeof(float)) > p->offset) break;

				//认为数据错位,关掉连接,等待重置
				if(/*len > p->pageSize ||*/ len < -2)
					goto loop;

				//存文件
				if(len > 0 && state == 1)
				{
					trytoWrite(p, (float*)(fmt+1), len, fmt->trigger);
				}
			}

			//加锁操作
			j   = 0;
			while(1)
			{
				fmt = (DataHead*)(p->buffer + j);
				//计算数据长度
				if(j + (int)sizeof(DataHead) > p->offset) break;
				if((len = fmt->len) > 0)
					len = sizeof(DataHead) + len * sizeof(float);
				else
					len = sizeof(DataHead);
				if((j + len) > p->offset) break;

				j += len;
				if(fmt->len == 0)   //接收id
				{
					p->idFlag = fmt->adc & 0x0f;
					p->fileHead.sensorId = fmt->sensorId;
					p->fileHead.cardId   = fmt->cardId;
					emit tsig_sensor();
				}
				else if(state == 1) //数据
				{
					*(p->temp + p->tempLen)     = fmt->max;
					*(p->temp + p->tempLen + 1) = fmt->min;
					*(p->winAdc + p->winIndex)  = fmt->adc;
					*(p->winVal + p->winIndex)  = fmt->ave;
					if(fmt->trigger >= 0 && p->tempPre < 0)
					{
						p->tempPre = p->tempLen;
					}
					p->tempLen = (p->tempLen + 2) % p->tempSize;
					p->winIndex= (p->winIndex+ 1) % p->winWidth;
					if(++p->winLen > p->winWidth) p->winLen = p->winWidth;
				}
			}
			lock.unlock();

            if(p->tempLen >= p->tempSize/2) emit tsig_full();

            //清理缓冲区
            p->offset -= j;
            if(j > 0 && p->offset > 0)
            {
                memmove(p->buffer, p->buffer + j, p->offset);
            }
            continue;

loop:
            qDebug("error:%d, %d line:%d, func:%s", len, p->fd, __LINE__, __FUNCTION__);
//            epoll_ctl(epfd, EPOLL_CTL_DEL, p->fd, &events[i]);
            FD_CLR(p->fd, &rdfs);
            close(p->fd);
            p->fd = -1;
			emit tsig_sensor();

        }

    }


errs:
    /*释放资源*/
    qDebug("ThreadData quit!!!!!!!!!!");
    return;
}

int ThreadData::analyse(float *res, int len)
{
    int i, j;
    int tmp;
    int offset, size;

    float max, min, ave;


    size = map->queueSize;
    if(map->queueLen == size && map->queueOffset < len)
        tmp = map->queueOffset + size;
    else
        tmp = map->queueOffset;
    offset = tmp;
    for(i = 1; i < 3; i++)
    {
        if(map[i].queueLen == size && map[i].queueOffset < len)
            tmp = map[i].queueOffset + size;
        else
            tmp = map[i].queueOffset;

        if(tmp < offset) offset = tmp;
    }

    if(offset < len) return -1;

    //简单取平均
    for(i = 0; i < 3; i++)
    {
        ave = 0;
		for(j = offset - len; j < offset; j++)
        {
            ave += map[i].queue[j % size];
        }
        res[i] = ave /= len;
    }

    return 3;
}

int ThreadData::trytoWrite(DataSocketMap *p, float *d, int len, int trigger)
{
    int     index;
    int     n;
    char    path[260];
    //直接往文件里写
#if 0
    if(p->saveFlag == 2)
    {
        fwrite(d, sizeof(float), len, p->fp);
        return 0;
    }
#endif
    //添加数据到缓冲区
    n = p->queueSize - p->queueOffset;

    if(n < len)
    {
        memcpy(p->queue + p->queueOffset, d, sizeof(float) * n);
        p->queueOffset = len - n;
        memcpy(p->queue, d, sizeof(float) * p->queueOffset);
    }
    else
    {
        memcpy(p->queue + p->queueOffset, d, sizeof(float) * len);
        p->queueOffset = (p->queueOffset + len) % p->queueSize;
    }
    p->queueLen += len;
    if(p->queueLen > p->queueSize) p->queueLen = p->queueSize;
#if 0
    //判断触发
    if(p->saveFlag == 0 && trigger >= 0)
    {
        n = p->fileHead.preLen + len - trigger;
        if(p->queueLen > n) p->queueLen = n;
        p->fileHead.index = p->queueLen - len + trigger;

        sprintf(path, HISTORY_PATH"%lx/%d-%d.his", startUTF, p->fileHead.i+1, p->fileHead.j+1);
        if(p->fp) fclose(p->fp);
        p->fp = fopen(path, "wb+");
        if(p->fp == NULL) return -1;

        fseek(p->fp, sizeof(FileHead), SEEK_SET);
        p->saveFlag = 1;
    }

    //存文件
    if(p->saveFlag == 1)
    {
        len = len + len/5;
        if(len < 10) len = 10;

        if(len >= p->queueLen)
        {
            len = p->queueLen;
            p->saveFlag = 2;
        }

        index = (p->queueOffset + p->queueSize - p->queueLen) % p->queueSize;
        n = p->queueSize - index;
        if(n < len)
        {
            fwrite(p->queue + index, sizeof(int), n, p->fp);
            fwrite(p->queue , sizeof(int), len - n, p->fp);
        }
        else
        {
            fwrite(p->queue + index, sizeof(int), len, p->fp);
        }
        p->queueLen -= len;
    }
#endif
    return 0;
}

int ThreadData::fileflush(DataSocketMap *p)
{
    int index;
    int n;

    if(p->fp == NULL) return -1;

    //保存剩余数据
    if(p->queueLen > 0)
    {
        index = (p->queueOffset + p->queueSize - p->queueLen) % p->queueSize;
        n = p->queueSize - index;
        if(n < p->queueLen)
        {
            fwrite(p->queue + index, sizeof(int), n, p->fp);
            fwrite(p->queue , sizeof(int), p->queueLen - n, p->fp);
        }
        else
        {
            fwrite(p->queue + index, sizeof(int), p->queueLen, p->fp);
        }
    }

    //保存文件头
    p->fileHead.lenth = (ftell(p->fp) - sizeof(FileHead)) / 4;
    fflush(p->fp);
    fseek(p->fp, 0, SEEK_SET);
    fwrite(&p->fileHead, sizeof(FileHead), 1, p->fp);

    return 0;
}

void ThreadData::timerEvent(QTimerEvent *e)
{
    if(e->timerId() != timerId)
    {
        killTimer(e->timerId());
        return;
    }
    killTimer(timerId);
    timerId = -1;

    emit sig_sensor_change();
}
