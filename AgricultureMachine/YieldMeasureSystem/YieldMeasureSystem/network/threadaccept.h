#ifndef THREADACCEPT_H
#define THREADACCEPT_H

#include <QThread>
#ifdef WIN32
#include <winsock2.h>
#endif

class ThreadAccept : public QThread
{
    Q_OBJECT
public:
    ThreadAccept(QObject *p);
    ~ThreadAccept();

    void startServer(int m, int n);
    void closeServer();

signals:
    void sig_cmd_link(int fd, int i, unsigned int ip);
    void sig_data_link(int fd, int i, int j);

protected:
    void run();

private:
#ifdef WIN32
	SOCKET cmdfd,datafd;
#elif linux
	int cmdfd;
	int datafd;
#endif
    bool flag;

    unsigned int m;
    unsigned int n;
};

#endif // THREADACCEPT_H
