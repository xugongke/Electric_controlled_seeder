/***************************************************************************************************
*                    (c) Copyright 1992-2017 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          tlib_crc.h
*\Description   
*\Note          
*\Log           2017.09.23    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#ifndef _TLIB_CRC_H
#define _TLIB_CRC_H
#include "type.h"

/***************************************************************************************************
*\Function      CRC32Calc
*\Description   对src所指向的长度为length的缓冲区计算CRC32校验值。基础CRC32校验方式。
*\Parameter     seed    种子值
*\Parameter     src     数据缓冲区指针
*\Parameter     lenth   数据长度
*\Return        u32
***************************************************************************************************/
u32 CRC32Calc(u32 seed, u8* src, u32 length);

unsigned short CRC16_CCITTCalc(unsigned char* src, unsigned int length);
unsigned short CRC16_IBMCalc(unsigned char* src, unsigned int length);
unsigned int hash_CRC32_png(u32 seed, unsigned char *data, unsigned int length);

/***************************************************************************************************
*\Function      CRC16_ANSICalc
*\Description   ANSI  CRC-16（X16+X15+X2+1）格式
*\Parameter     src
*\Parameter     length
*\Return        unsigned short
*\Note          
***************************************************************************************************/
u16 CRC16_ANSICalc(unsigned char* src, unsigned int length);
#endif /*_TLIB_CRC_H*/
