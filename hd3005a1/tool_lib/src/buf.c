/***************************************************************************************************
*                    (c) Copyright 1992-2017 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          buf.c
*\Description   
*\Note          
*\Log           2017.07.11    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "buf.h"

#define BUF_MUTEX_APPLY 
#define BUF_MUTEX_RELEASE 
/***************************************************************************************************
*\Function      BufFix
*\Description   数据修正
*\Parameter     buf
*\Return        bool
*\Note          1)读写指针异常检测
***************************************************************************************************/
static bool BufFix(BufType* buf);
/***************************************************************************************************
*\Function      GetDataLen
*\Description
*\Parameter     buf
*\Return        u32
*\Note
***************************************************************************************************/
static u32 GetDataLen(BufType* buf)
{
    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        return (buf->WPos + buf->Size - buf->RPos) % buf->Size;
        //break;

    case BUF_MODE_LINE:
        return buf->WPos;
        //break;

    default:
        break;
    }
    return 0x00;
}

static void* MemMove(void* dst, const void* src, u32 len)
{
    void* dstend = NULL;

    if (dst == src)
    {
        return dst;
    }
    else if ((dst < src) || ((u8*)dst >= (((u8*)src) + len)))
    {
        /*forward copy*/
        dstend = (u8*)dst + len;
        while (dst < dstend)
        {
            *(u8*)dst = *(u8*)src;
            *(u8*)src = 0x00;
            dst = (u8*)dst + 1;
            src = (u8*)src + 1;
        }
    }
    else
    {
        /*backward copy*/
        dstend  = dst;
        dst = (u8*)dst + len - 1;
        src = (u8*)src + len - 1;

        while (dst >= dstend)
        {
            *(u8*)dst = *(u8*)src;
            *(u8*)src = 0x00;
            dst = (u8*)dst - 1;
            src = (u8*)src - 1;
        }
    }

    return dst;
}
static u8* MemLineToCycle(u8* dst, const u32 dst_size, u32 start_offset, u8* src, u32 len)
{
    u32 copy_len = 0x00;

    if ((dst_size == 0x00) || (start_offset >= dst_size))
    {
        return dst;
    }

    copy_len = dst_size - start_offset;

    if (len > copy_len)
    {
        memcpy(dst + start_offset, src, dst_size - start_offset);
        src += copy_len;
        len -= copy_len;
        start_offset = 0x00;
        copy_len = dst_size;
    }
    while (len > copy_len)
    {
        memcpy(dst, src, dst_size);
        src += copy_len;
        len -= copy_len;
    }
    memcpy(dst + start_offset, src, len);

    return dst + (start_offset + len) % dst_size;
}
static u32 MemCycleSubToLine(u8* dst, const u8* src, const u32 start_pos, const u32 end_pos,
                      const u32 src_size, const u32 request_len)
{
    u32 head_len = 0x00;/*前段数据*/

    if (end_pos > start_pos)
    {
        head_len = end_pos - start_pos;
        if (head_len > request_len)
        {
            head_len = request_len;
        }
        memcpy(dst, src + start_pos, head_len);
        return head_len;
    }

    else if (end_pos < start_pos)
    {
        head_len = src_size - start_pos;
        if (head_len >= request_len)
        {
            /*若[前段长度][满足]则拷贝[请求长度]*/
            memcpy(dst, src + start_pos, request_len);
            return request_len;
        }
        else
        {
            /*若[前段长度][不满足]则[先]拷贝[前段长度]*/
            memcpy(dst, src + start_pos, head_len);

            if (end_pos >= (request_len - head_len))
            {
                /*若[后段长度][满足]则拷贝[请求长度]减[前段长度]*/
                memcpy(dst + head_len, src, request_len - head_len);
                return request_len;
            }
            else
            {
                /*若[后段长度][不满足]则拷贝[后段长度]*/
                memcpy(dst + head_len, src, end_pos);
                return head_len + end_pos;
            }
        }
    }

    return 0;
}
/***************************************************************************************************
*\Function      BufInit
*\Description   缓冲区初始化
*\Parameter     addr    缓冲区地址
*\Parameter     size    缓冲区大小
*\Parameter     mode    缓冲区存储模式 BUF_MODE_CYCLE or BUF_MODE_LINE
*\Return        BufType
***************************************************************************************************/
BufType BufInit(u8* addr, u32 size, BufModeType mode)
{
    BufType buf;
    buf.Addr = addr;
    buf.Size = size;
    buf.Mode = mode;
    buf.RPos = 0x00;
    buf.WPos = 0x00;

    BufFix(&buf);
    return buf;
}

/***************************************************************************************************
*\Function      BufAddData
*\Description   向缓冲区中增加数据
*\Parameter     buf
*\Parameter     src
*\Parameter     len
*\Return        u32
***************************************************************************************************/
u32 BufAddData(BufType* buf, u8* src, u32 len)
{
    u32 left_len = 0x00;
    BufFix(buf);
    BUF_MUTEX_APPLY;
    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        left_len = buf->Size - ((buf->WPos + buf->Size - buf->RPos) % buf->Size);
        buf->WPos = MemLineToCycle(buf->Addr, buf->Size, buf->WPos, src, len) - buf->Addr;
        if (len >= left_len)
        {
            buf->RPos = (buf->WPos + 1) % buf->Size;
        }

        BUF_MUTEX_RELEASE;
        return len;
        //break;

    case BUF_MODE_LINE:
        /*比较剩余长度*/
        left_len = buf->Size - buf->WPos;
        if (len > left_len )
        {
            len = left_len;
        }
        memcpy(buf->Addr + buf->WPos, src, len);
        buf->WPos = buf->WPos + len;

        BUF_MUTEX_RELEASE;
        return len;
        //break;

    default:
        break;
    }
    BUF_MUTEX_RELEASE;
    return 0x00;
}

/***************************************************************************************************
*\Function      BufGetData
*\Description   
*\Parameter     buf
*\Parameter     dst
*\Parameter     start
*\Parameter     len
*\Return        u32  实际获取到的数据长度
*\Note          
***************************************************************************************************/
u32 BufGetData(BufType* buf, u8* dst, u32 start, u32 len)
{
    u32 data_len = 0x00;
    u32 result = 0x00;
    BufFix(buf);
    BUF_MUTEX_APPLY;
    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        if (start >= BufGetDataLen(buf))
        {
            BUF_MUTEX_RELEASE;
            return 0x00;
        }
        result = MemCycleSubToLine(dst, buf->Addr,
            (buf->RPos + start) % buf->Size, buf->WPos, buf->Size, len);

        BUF_MUTEX_RELEASE;
        return result;
        //break;

    case BUF_MODE_LINE:
        if (start >= buf->WPos)
        {
            BUF_MUTEX_RELEASE;
            return 0x00;
        }

        /*比较数据长度*/
        data_len = buf->WPos - start;
        if (len > data_len)
        {
            len = data_len;
        }
        memcpy(dst, buf->Addr + start, len);

        BUF_MUTEX_RELEASE;
        return len;
        //break;

    default:
        break;
    }
    BUF_MUTEX_RELEASE;
    return 0x00;
}

/***************************************************************************************************
*\Function      BufDelHeadData
*\Description   删除缓冲区中数据，从头部开始
*\Parameter     buf
*\Parameter     len
*\Return        u32 实际删除数据长度
*\Note          
***************************************************************************************************/
u32 BufDelHeadData(BufType* buf, u32 len)
{
    u32 data_len = 0x00;
    BUF_MUTEX_APPLY;
    BufFix(buf);
    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        data_len = GetDataLen(buf);
        if (len > data_len)
        {
            len = data_len;
        }

        buf->RPos = (buf->RPos + len) % buf->Size;

        BUF_MUTEX_RELEASE;
        return len;
        //break;

    case BUF_MODE_LINE:
        /*比较数据长度*/
        data_len = buf->WPos;
        if (len > data_len)
        {
            len = data_len;
        }
        MemMove(buf->Addr, buf->Addr + len, data_len - len);
        buf->WPos = buf->WPos - len;

        BUF_MUTEX_RELEASE;
        return len;
        //break;

    default:
        break;
    }

    BUF_MUTEX_RELEASE;
    return 0x00;
}

/***************************************************************************************************
*\Function      BufClearData
*\Description   清空数据
*\Parameter     buf
*\Return        u32 实际清空数据长度
*\Note          
***************************************************************************************************/
u32 BufClearData(BufType* buf)
{
    u32 data_len = 0x00;
    BufFix(buf);
    BUF_MUTEX_APPLY;
    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        data_len = (buf->WPos + buf->Size - buf->RPos) % buf->Size;
        buf->RPos = buf->WPos;

        BUF_MUTEX_RELEASE;
        return data_len;
        //break;

    case BUF_MODE_LINE:
        /*比较数据长度*/
        data_len = buf->WPos;
        buf->WPos = 0;

        BUF_MUTEX_RELEASE;
        return data_len;
        //break;

    default:
        break;
    }

    BUF_MUTEX_RELEASE;
    return 0x00;
}

/***************************************************************************************************
*\Function      BufGetDataLen
*\Description   获取数据长度
*\Parameter     buf
*\Return        u32
*\Note
***************************************************************************************************/
u32 BufGetDataLen(BufType* buf)
{
    u32 result = 0x00;
    BUF_MUTEX_APPLY;
    BufFix(buf);
    result = GetDataLen(buf);
    BUF_MUTEX_RELEASE;
    return result;
}

/***************************************************************************************************
*\Function      BufGetLeftLen
*\Description   获取剩余空间长度
*\Parameter     buf
*\Return        u32
*\Note
*               创建函数。
***************************************************************************************************/
u32 BufGetLeftLen(BufType* buf)
{
    u32 result = 0x00;
    BUF_MUTEX_APPLY;
    BufFix(buf);
    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        result = buf->Size - ((buf->WPos + buf->Size - buf->RPos) % buf->Size);

        BUF_MUTEX_RELEASE;
        return result;
        //break;

    case BUF_MODE_LINE:
        result = buf->Size - buf->WPos;
        BUF_MUTEX_RELEASE;
        return result;
        //break;

    default:
        break;
    }

    BUF_MUTEX_RELEASE;
    return 0x00;
}

/***************************************************************************************************
*\Function      BufFix
*\Description   数据修正
*\Parameter     buf
*\Return        bool
*\Note          1)读写指针异常检测
***************************************************************************************************/
static bool BufFix(BufType* buf)
{
    static u8 err_buf[2] = {0x00};
    BUF_MUTEX_APPLY;

    if ((buf->Addr == NULL) || (buf->Size == 0x00))
    {
        *buf = BufInit(err_buf, 1, BUF_MODE_NONE);
    }

    switch (buf->Mode)
    {
    case BUF_MODE_CYCLE:
        if ((buf->RPos >= buf->Size) && (buf->WPos >= buf->Size))
        {
            buf->RPos = 0x00;
            buf->WPos = 0x00;

            BUF_MUTEX_RELEASE;
            return TRUE;
        }
        else if (buf->RPos >= buf->Size)
        {
            buf->RPos = buf->WPos;

            BUF_MUTEX_RELEASE;
            return TRUE;
        }
        else if (buf->WPos >= buf->Size)
        {
            buf->WPos = buf->RPos;

            BUF_MUTEX_RELEASE;
            return TRUE;
        }
        break;

    case BUF_MODE_LINE:
        buf->RPos = 0x00;
        if (buf->WPos >= buf->Size)
        {
            buf->WPos = buf->Size - 1;

            BUF_MUTEX_RELEASE;
            return TRUE;
        }
        break;

    default:
        break;
    }

    BUF_MUTEX_RELEASE;
    return FALSE;
}
