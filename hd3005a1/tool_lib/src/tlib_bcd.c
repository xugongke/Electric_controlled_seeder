/***************************************************************************************************
*                    (c) Copyright 1992-2017 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          tlib_bcd.c
*\Description   
*\Note          
*\Log           2017.09.16    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "tlib_bcd.h"
#include "tlib_data.h"
#include "string.h"
/***************************************************************************************************
*\Function      GetBCDToDECU8
*\Description   BCDu8转为DEC
*\Parameter     bcd BCD值
*\Return        u8  DEC值
***************************************************************************************************/
u8 GetBCDToDECU8(const u8 bcd)
{
    u8 dec = 0x00;

    dec = ((bcd >> 4) & 0x0F) * 10 + (bcd & 0x0F);

    return dec;
}

/***************************************************************************************************
*\Function      GetDECToBCDU8
*\Description   DECu8转为BCD
*\Parameter     dec DEC值
*\Return        u8  BCD值
***************************************************************************************************/
u8 GetDECToBCDU8(const u8 dec)
{
    DECToBCD((void*)&dec, sizeof(dec), dec);
    return dec;
}

/***************************************************************************************************
*\Function      DECToBCDU8
*\Description   DEC转为BCD
*\Parameter     dec DEC值（指针）
*\Return        void
***************************************************************************************************/
void DECToBCDU8(u8* dec)
{
    u8 quotient = 0x00;

    quotient = ((*dec)/10);
    quotient %= 10;
    *dec = (quotient<<4)  + (*dec) - 10 * quotient;
}

/***************************************************************************************************
*\Function      CheckDECToBCD
*\Description   检查用来转为BCD码的DEC码是否正确
*\Parameter     dec     DEC值
*\Return        bool    检查结果
*\Note          判断dec是否小于99
***************************************************************************************************/
bool CheckDECToBCD(u8 dec)
{
    return (bool)(dec <= 99);
}

/***************************************************************************************************
*\Function      BCDToDECU8
*\Description   U8BCD转为DEC
*\Parameter     bcd BCD值（指针）
*\Return        void

***************************************************************************************************/
void BCDToDECU8(u8* bcd)
{
    *bcd = (((*bcd) >> 4) & 0x0F) * 10 + ((*bcd)&0x0F);
}

/***************************************************************************************************
*\Function      DECToBCD
*\Description   DEC转为BCD
*\Parameter     dst BCD值存储空间
*\Parameter     len 空间长度
*\Parameter     dec DEC值
*\Return        u8* dst + 实际存储长度
***************************************************************************************************/
u8* DECToBCD(void* dst, u8 len, u64 dec)
{
    u8 index = 0x00;
    u8 h = 0x00;
    u8 l = 0x00;

    memset((u8*)dst, 0x00, len);

    while (dec > 0x00)
    {
        l = dec % 10;
        dec /= 10;
        h = dec % 10;
        dec /= 10;
        ((u8*)dst)[index] = (h<<4)|l;
        index++;

        if (index >= len)
        {
            return (u8*)dst + len;
        }
    }

    return (u8*)dst + index;
}

/***************************************************************************************************
*\Function      GetDECToBCDU64
*\Description   DECu64转为BCD
*\Parameter     dec DEC值
*\Return        u64 BCD值
***************************************************************************************************/
u64 GetDECToBCDU64(const u64 dec)
{
    DECToBCD((void*)&dec, sizeof(dec), dec);
    return dec;
}

/***************************************************************************************************
*\Function      BCDToDECU64
*\Description   U64BCD转为DEC
*\Parameter     bcd BCD值（指针）
*\Return        void
***************************************************************************************************/
void BCDToDECU64(u64* bcd)
{
    *bcd =
        (((*bcd) >> 60) & 0x0F) * 1000000000000000 +
        (((*bcd) >> 56) & 0x0F) * 100000000000000 +
        (((*bcd) >> 52) & 0x0F) * 10000000000000 +
        (((*bcd) >> 48) & 0x0F) * 1000000000000 +
        (((*bcd) >> 44) & 0x0F) * 100000000000 +
        (((*bcd) >> 40) & 0x0F) * 10000000000 +
        (((*bcd) >> 36) & 0x0F) * 1000000000 +
        (((*bcd) >> 32) & 0x0F) * 100000000 +
        (((*bcd) >> 28) & 0x0F) * 10000000 +
        (((*bcd) >> 24) & 0x0F) * 1000000 +
        (((*bcd) >> 20) & 0x0F) * 100000 +
        (((*bcd) >> 16) & 0x0F) * 10000 +
        (((*bcd) >> 12) & 0x0F) * 1000 +
        (((*bcd) >> 8)  & 0x0F) * 100 +
        (((*bcd) >> 4)  & 0x0F) * 10 +
        (((*bcd) >> 0)  & 0x0F) * 1;
}

/***************************************************************************************************
*\Function      CheckBCD
*\Description   检查BCD码是否正确
*\Parameter     bcd     要检查的BCD码
*\Return        bool    检查结果
***************************************************************************************************/
bool CheckBCD(u8 bcd)
{
    if (((((bcd >> 4) & 0x0F)) < 10) && ((bcd & 0x0F) < 10))
    {
        return TRUE;
    }

    return FALSE;
}

/***************************************************************************************************
*\Function      MemBCDCheck
*\Description   检查内存区域src中len个字节是否均为BCD码。
*\Parameter     src
*\Parameter     len
*\Return        bool
***************************************************************************************************/
bool MemBCDCheck(const u8* src, const u32 len)
{
    u16 i = 0x00;
    for (i = 0x00; i < len; i++)
    {
        if (CheckBCD(src[i]) == FALSE)
        {
            return FALSE;
        }
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      BCDAdd
*\Description   BCD加运算
*\Parameter     bcd     BCD
*\Parameter     value   加数DEC
*\Return        u64     结果BCD
*\Note          1)若BCD错误则停止计算并返回参数bcd。
***************************************************************************************************/
u64 BCDAdd(u64 bcd, u64 value)
{
    if (CheckBCD((u8)bcd) == FALSE)
    {
        return bcd;
    }

    BCDToDECU64(&bcd);

    bcd += value;

    return GetDECToBCDU64(bcd);
}

/***************************************************************************************************
*\Function      BCDSub
*\Description   BCD减运算
*\Parameter     bcd     BCD
*\Parameter     value   加数DEC
*\Return        u64     结果BCD
*\Note          1)若BCD错误则停止计算并返回参数bcd。
***************************************************************************************************/
u64 BCDSub(u64 bcd, u64 value)
{
    if (CheckBCD((u8)bcd) == FALSE)
    {
        return bcd;
    }

    BCDToDECU64(&bcd);

    bcd -= value;

    return GetDECToBCDU64(bcd);
}

/***************************************************************************************************
*\Function      BCDFix
*\Description   BCD修正
*\Parameter     bcd     数据指针
*\Return        bool    是否被修正
*\Note          1)修正方法：大于0x99修正为0x00；高位合法、低位大于0x09修正为高位进1，低位为0。
***************************************************************************************************/
bool BCDFix(u8* bcd)
{
    if (CheckBCD(*bcd) == TRUE)
    {
        return FALSE;
    }
    else
    {
        if (*bcd > 0x99)
        {
            *bcd = 0x00;
        }
        else if (GetU8LowU4(*bcd) > 0x09)
        {
            /*高位进位*/
            *bcd = SetU8LowU4(*bcd, 0x00);
            *bcd = SetU8HighU4(*bcd, GetU8HighU4(*bcd) + 1);
        }
        else
        {
            return FALSE;
        }

        return TRUE;
    }
}

/***************************************************************************************************
*\Function      BCDArrayFix
*\Description   BCD数组修正
*\Parameter     bcd     BCD数组指针
*\Return        bool    是否被修正
*\Note          1)修正方法：大于0x99修正为0x00；高位合法、低位大于0x09修正为高位进1，低位为0。
***************************************************************************************************/
bool BCDArrayFix(void* bcd_array, u32 len)
{
    bool fix_flag = FALSE;
    while(len--)
    {
        fix_flag |= BCDFix((u8*)bcd_array + len);
    }

    return fix_flag;
}

/***************************************************************************************************
*\Function      BCDLeftMov
*\Description   BCD数值左移。
*\Parameter     bcd_array   BCD字节数组
*\Parameter     len         BCD字节数组长度
*\Parameter     mov_num     左移数值个数
*\Return        void
*\Note          1)len为字节长度，包含数值个数为len * 2。
*\Note          2)本函数不检查BCD正确性。
***************************************************************************************************/
void BCDLeftMov(void* bcd_array, u32 len, u32 mov_num)
{
    u8* data = bcd_array;
    u32 mov_bytes = 0x00; /*移动字节数，最大偶数数位*/
    u32 valid_data_len = 0x00;
    u32 i = 0x00;

    mov_bytes = mov_num / 2;

    if ((mov_num == 0x00) || (bcd_array == NULL))
    {
        return;
    }

    if ((mov_bytes >= len))
    {
        memset(data, 0x00, len);
        return;
    }

    valid_data_len = len - mov_bytes;

    if (mov_bytes > 0x00)
    {
        memcpy(data, data + mov_bytes, valid_data_len);
        memset(data + mov_bytes, 0x00, valid_data_len);
    }

    /*奇数判断，1个数位*/
    if ((mov_num & 1) == 1)
    {
        /*上面判断保证valid_data_len大于0*/
        valid_data_len--;
        for (i = 0x00; i < valid_data_len; i++)
        {
            data[i] = (data[i]<<4) | (data[i + 1]>>4);
        }
        data[valid_data_len] = (data[valid_data_len] << 4) | 0x00;
    }
}

/***************************************************************************************************
*\Function      BCDRightMov
*\Description   BCD数值右移。
*\Parameter     bcd_array   BCD字节数组
*\Parameter     len         BCD字节数组长度
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)len为字节长度，包含数值个数为len * 2。
*\Note          2)本函数不检查BCD正确性。
***************************************************************************************************/
void BCDRightMov(void* bcd_array, u32 len, u32 mov_num)
{
    u8* data = bcd_array;
    u32 mov_bytes = 0x00; /*移动字节数，最大偶数数位*/
    u32 valid_data_len = 0x00;
    u32 i = 0x00;

    mov_bytes = mov_num / 2;

    if ((mov_num == 0x00) || (bcd_array == NULL))
    {
        return;
    }

    if ((mov_bytes >= len))
    {
        memset(data, 0x00, len);
        return;
    }

    valid_data_len = len - mov_bytes;

    if (mov_bytes > 0x00)
    {
        memcpy(data + mov_bytes, data, valid_data_len);
        memset(data, 0x00, mov_bytes);
    }

    /*奇数判断，1个数位*/
    if ((mov_num & 1) == 1)
    {
        /*上面判断保证valid_data_len，len大于0*/
        for (i = 0x01; i < valid_data_len; i++)
        {
            data[len - i] = (data[len - i] >> 4) | (data[len - i - 1] << 4);
        }
        data[len - valid_data_len] = (data[len - valid_data_len] >> 4) | 0x00;
    }
}

/***************************************************************************************************
*\Function      BCDLeftMovU8
*\Description   BCD数值左移。
*\Parameter     bcd         用来存放BCD码的u8整数，里边包含2个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u8 BCDLeftMovU8(u8 bcd, u32 mov_num)
{
    return bcd << (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDLeftMovU16
*\Description   BCD数值左移。
*\Parameter     bcd         用来存放BCD码的u16整数，里边包含4个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u16 BCDLeftMovU16(u16 bcd, u32 mov_num)
{
    return bcd << (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDLeftMovU32
*\Description   BCD数值左移。
*\Parameter     bcd         用来存放BCD码的u32整数，里边包含8个BCD码
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u32 BCDLeftMovU32(u32 bcd, u32 mov_num)
{
    return bcd << (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDLeftMovU64
*\Description   BCD数值左移。
*\Parameter     bcd         用来存放BCD码的u64整数，里边包含16个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u64 BCDLeftMovU64(u64 bcd, u32 mov_num)
{
    return bcd << (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDRightMovU8
*\Description   BCD数值右移。
*\Parameter     bcd         用来存放BCD码的u8整数，里边包含2个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u8 BCDRightMovU8(u8 bcd, u32 mov_num)
{
    return bcd >> (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDRightMovU16
*\Description   BCD数值右移。
*\Parameter     bcd         用来存放BCD码的u16整数，里边包含4个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u16 BCDRightMovU16(u16 bcd, u32 mov_num)
{
    return bcd >> (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDRightMovU32
*\Description   BCD数值右移。
*\Parameter     bcd         用来存放BCD码的u32整数，里边包含8个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u32 BCDRightMovU32(u32 bcd, u32 mov_num)
{
    return bcd >> (mov_num * 4);
}

/***************************************************************************************************
*\Function      BCDRightMovU64
*\Description   BCD数值右移。
*\Parameter     bcd         用来存放BCD码的u68整数，里边包含16个BCD码
*\Parameter     mov_num     右移数值个数
*\Return        void
*\Note          1)本函数不检查BCD正确性。
***************************************************************************************************/
u64 BCDRightMovU64(u64 bcd, u32 mov_num)
{
    return bcd >> (mov_num * 4);
}
