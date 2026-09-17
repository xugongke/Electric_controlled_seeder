#include "common_port.h"
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <memory.h>

long port_open(const char *portName, const char *fmt)
{
    HANDLE hCom;
    char name[64]       = "\\\\.\\";
    DCB dcb;
    COMMTIMEOUTS TimeOuts;

    strcat(name, portName);
    //打开串口
    hCom = CreateFileA(name, GENERIC_READ | GENERIC_WRITE,
                       0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if(hCom == (HANDLE)-1)
    {
        return -1;
    }

    /*初始化串口*/
    GetCommState(hCom,&dcb);
    dcb.BaudRate    = 115200;     //波特率
    dcb.ByteSize    = 8;     //数据位
    dcb.Parity      = 0;       //校验位
    dcb.StopBits    = 0;     //停止位
    if(fmt && sscanf(fmt, "%ld-%c-%c", &dcb.BaudRate, &dcb.ByteSize, &dcb.Parity) == 3)
    {
        dcb.ByteSize -= 48;
        switch(dcb.Parity)
        {
        case 'N': dcb.Parity = 0; break;
        case 'O': dcb.Parity = 1; break;
        case 'E': dcb.Parity = 2; break;
        case 'M': dcb.Parity = 3; break;
        case 'S': dcb.Parity = 4; break;
        default: dcb.Parity = 0;
        }
    }
    SetCommState(hCom,&dcb);

    SetupComm(hCom,4096,4096); //输入缓冲区和输出缓冲区的大小都是4096
    GetCommTimeouts(hCom, &TimeOuts);
    //设定读超时
    TimeOuts.ReadIntervalTimeout = 10;
    TimeOuts.ReadTotalTimeoutMultiplier = 2;
    TimeOuts.ReadTotalTimeoutConstant = 300;
    //设定写超时
    TimeOuts.WriteTotalTimeoutMultiplier = 5;
    TimeOuts.WriteTotalTimeoutConstant = 20;
    SetCommTimeouts(hCom, &TimeOuts);

//    SetCommMask(hCom, EV_RXCHAR);
    PurgeComm(hCom,PURGE_TXCLEAR|PURGE_RXCLEAR);//清缓冲区

    return (long)hCom;
}
void port_close(long handle)
{
    CloseHandle((HANDLE)handle);
}

int port_send(long handle, char *buf, int len, int flag)
{
    DWORD b = 0;
	if(flag)PurgeComm((HANDLE)handle, PURGE_TXCLEAR|PURGE_RXCLEAR);//清缓冲区
	WriteFile((HANDLE)handle, buf, len, &b, NULL);
    return b;
}
int port_read(long handle, char *buf, int len, int flag)
{
    DWORD n = 0;
    DWORD b = 0;
    if(flag == 0)
    {
        ReadFile((HANDLE)handle, buf, 4096, &n, NULL);
    }
    else
    {
        do {
            if(!ReadFile((HANDLE)handle, buf+n, len, &b, NULL) || b == 0)
                break;
            len -= b;
            n += b;
        } while(len > 0);
    }
    return n;
}


int port_pipe(long pipefd[2])
{
    return CreatePipe((PHANDLE)pipefd, (PHANDLE)(pipefd+1), NULL, 4096);
}



int port_get_list(char ***pazResult)
{
    HKEY hKey;
    LPCSTR lpSubKey = "HARDWARE\\DEVICEMAP\\SERIALCOMM\\";

    if(RegOpenKeyExA(HKEY_LOCAL_MACHINE, lpSubKey, 0, KEY_READ, &hKey)!= ERROR_SUCCESS)
    {
        return 0;
    }

    unsigned   size;
    unsigned   offset;
    unsigned   count;
    char *pBuffer;
    char *bp;
    char**lpOffset;

    char  szValueName[100];
    BYTE *lpPortName;
    LONG  status;
    DWORD dwIndex;
    DWORD dwSizeValueName;
    DWORD dwSizeofPortName;
    DWORD Type;

    //读串口信息
    dwIndex = 0;
    offset = 0;
    count = 0;
    size = 128;
    pBuffer  = (char*)malloc(size);
    lpOffset = (char**)(pBuffer + size);
    do
    {
        dwSizeValueName = 100;
        dwSizeofPortName = 100;
        lpPortName = (BYTE*)(pBuffer + offset);
        status = RegEnumValueA(hKey, dwIndex++, szValueName, &dwSizeValueName, NULL, &Type,
                              lpPortName, &dwSizeofPortName);
        if(status != ERROR_SUCCESS)continue;

        *(--lpOffset) = (char*)offset;
        offset += dwSizeofPortName;
        count += 1;

        if(offset + 100 + (count+1)*sizeof(void*) >= size)
        {
            size *= 2;
            bp = (char*)malloc(size);
            *pazResult = (char**)(bp + size);
            *pazResult-= count;
            memcpy(bp, pBuffer, offset);
            memcpy(*pazResult, lpOffset, count*sizeof(void*));
            free(pBuffer);
            pBuffer  = bp;
            lpOffset = *pazResult;
        }
    } while((status!= ERROR_NO_MORE_ITEMS));
    RegCloseKey(hKey);
    *((int*)lpOffset - 1) = (int)((char*)lpOffset - pBuffer);

    //封装返回值
    dwSizeValueName = count/2;
    size = count-1;
    for(offset = 0; offset < dwSizeValueName; offset++)
    {
        Type = (DWORD)lpOffset[size];
        lpOffset[size--] = lpOffset[offset];
        lpOffset[offset] = pBuffer + Type;
    }
    for(; offset < count; offset++)
    {
        lpOffset[offset] = pBuffer + (DWORD)lpOffset[offset];
    }

    *pazResult = lpOffset;
    return count;
}

void port_free_list(char **result)
{
    char *p = (char*)result;
    p -= *(int*)(p-sizeof(int));
    free(p);
}
