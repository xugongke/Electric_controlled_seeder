/***************************************************************************************************
*                    (c) Copyright 1992-2020 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          update.c
*\Description   程序升级源文件
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "update.h"
#include "tlib_crc.h"
#include "string.h"


osSemaphoreId         UpdateDevLock;    /*设备互斥信号量*/
UpDataFileStartHeader UpStartHead;      /*启动传输升级文件信息*/
UpDataFileEndHeader   UpEndHead;        //升级结束标志 UpDataFileEndHeader
UpDataFileHeader      UpdateFlag;       //升级标志
bool Updateing = FALSE;                 //是否正在升级过程中
u32 GetSectroNum(u32 addr)
{
    u32 off_addr = addr-STM32_FLASH_START_ADDR;
    if ((off_addr) < (64*1024)){
        return FLASH_SECTOR_0+off_addr/(16*1024);
    }
    else if (off_addr < (128*1024)){
        return FLASH_SECTOR_4;
    }
    else {
        return FLASH_SECTOR_4 + ((off_addr)/(128*1024));;
    }
}

/**
  * @brief  Wait for a FLASH operation to complete.
  * @param  Timeout maximum flash operationtimeout
  * @retval HAL Status
  */
HAL_StatusTypeDef FLASH_WaitForLastOperation1(uint32_t Timeout)
{ 
  uint32_t tickstart = 0U;
  
  /* Clear Error Code */
  //pFlash.ErrorCode = HAL_FLASH_ERROR_NONE;
  
  /* Wait for the FLASH operation to complete by polling on BUSY flag to be reset.
     Even if the FLASH operation fails, the BUSY flag will be reset and an error
     flag will be set */
  /* Get tick */
  tickstart = osTimeGet();

  while(__HAL_FLASH_GET_FLAG(FLASH_FLAG_BSY) != RESET) 
  {
    if((osTimeGet() - tickstart) > Timeout){
        return HAL_TIMEOUT;
    }
    osThreadYield();
  }

  /* Check FLASH End of Operation flag  */
  if (__HAL_FLASH_GET_FLAG(FLASH_FLAG_EOP) != RESET)
  {
    /* Clear FLASH End of Operation pending bit */
    __HAL_FLASH_CLEAR_FLAG(FLASH_FLAG_EOP);
  }
#if defined(FLASH_SR_RDERR)  
  if(__HAL_FLASH_GET_FLAG((FLASH_FLAG_OPERR | FLASH_FLAG_WRPERR | FLASH_FLAG_PGAERR | \
                           FLASH_FLAG_PGPERR | FLASH_FLAG_PGSERR | FLASH_FLAG_RDERR)) != RESET)
#else
  if(__HAL_FLASH_GET_FLAG((FLASH_FLAG_OPERR | FLASH_FLAG_WRPERR | FLASH_FLAG_PGAERR | \
                           FLASH_FLAG_PGPERR | FLASH_FLAG_PGSERR)) != RESET)
#endif /* FLASH_SR_RDERR */
  {
    /*Save the error code*/
   // FLASH_SetErrorCode();
    return HAL_ERROR;
  }

  /* If there is no error flag set */
  return HAL_OK;
  
}
/***************************************************************************************************
*\Function      UpdateFlagCheck
*\Description   检查升级标记
*\Parameter     
*\Return        void
*\Note          
***************************************************************************************************/
void UpdateFlagCheck(void)
{
    u32 crc_ch;
    u32 sector = 0;
    u8* tmp_ptr;
    HAL_StatusTypeDef st;
    u32 i;

    memcpy(&UpdateFlag, (void*)UP_FLAG_START_ADDR, sizeof(UpdateFlag));

    crc_ch = hash_CRC32_png(UP_CRC32_SEED, (u8*)&UpdateFlag.UpdateFlag, sizeof(UpDataFileHeader) - 4);
    if((crc_ch == UpdateFlag.FileHeaderChk) &&
        (UpdateFlag.UpdateFlag == UPDATE_SUCESS)
        )
    {
        //更新升级成功标志为不需要升级
        UpdateFlag.UpdateFlag = NO_NEED_UPDATE;
        UpdateFlag.FileHeaderChk = hash_CRC32_png(UP_CRC32_SEED, (u8*)&UpdateFlag.UpdateFlag, sizeof(UpDataFileHeader) - 4);
//         StorageErase(Stm32Flash, UP_FLAG_START_ADDR - STM32_FLASH_START_ADDR, sizeof(UpdateFlag));
//         StorageWrite(Stm32Flash, UP_FLAG_START_ADDR - STM32_FLASH_START_ADDR,(u8*) &UpdateFlag, sizeof(UpdateFlag));
        HAL_FLASH_Unlock(); //解锁Flash
        sector = GetSectroNum(UP_FLAG_START_ADDR);
        FLASH_Erase_Sector(sector, FLASH_VOLTAGE_RANGE_3);
        st = FLASH_WaitForLastOperation1(5000);
        if (st == HAL_OK){
            tmp_ptr = (u8*)&UpdateFlag;
            for (i = 0; i < sizeof(UpdateFlag); i++){
                st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_BYTE, UP_FLAG_START_ADDR+i, tmp_ptr[i]);
                if (st != HAL_OK){
                    break;
                }
            }
        }
        HAL_FLASH_Lock(); //锁住Flash
    } 
}

/***************************************************************************************************
*\Function      UpdateInit
*\Description   初始化程序升级相关变量
*\Parameter     
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateInit(void)
{
    UpdateFlagCheck();
    return TRUE;
}
u32 SectorErr;

/***************************************************************************************************
*\Function      UpdateStartFunc
*\Description   启动升级过程
*\Parameter     data 升级数据帧数据域内容
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateStartFunc(DataNode* data)
{
    u32 sector = 0;
    HAL_StatusTypeDef st;
    if (Updateing == TRUE){
        return FALSE;
    }
    if (data->Len != sizeof(UpDataFileStartHeader)){
        return FALSE;
    }
    memcpy(&UpStartHead, data->Data, data->Len);
    if (UpStartHead.Len > UPDATA_TOTAL_SIZE){
        return FALSE;
    }
    /*擦除 存放升级程序的FLASH*/
    HAL_FLASH_Unlock(); //解锁Flash
    sector = GetSectroNum(UP_APP_START_ADDR);
    FLASH_Erase_Sector(sector, FLASH_VOLTAGE_RANGE_3);
    st = FLASH_WaitForLastOperation1(5000);
    HAL_FLASH_Lock(); //锁住Flash
  
    if (st == HAL_OK){
        return TRUE;
    }

    return FALSE;
}

/***************************************************************************************************
*\Function      UpdateBinFunc
*\Description   更新升级程序文件
*\Parameter     data 升级数据帧数据域内容
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateBinFunc(DataNode* data)
{
    u8* tmp_ptr;
    u32 off;
    u32 i;
    u32 cur_len;
    HAL_StatusTypeDef st = HAL_OK;
    if (Updateing == TRUE){
        return FALSE;
    }
    tmp_ptr = (u8*)data->Data;
    if (data->Len < 8){
        return FALSE;
    }
    memcpy(&off, tmp_ptr, 4);
    memcpy(&cur_len, tmp_ptr+4, 4);
    if (data->Len != (cur_len+8)){
        return FALSE;
    }
    if ((off > UPDATA_TOTAL_SIZE) || (cur_len > 1400) || (((off+cur_len) > UPDATA_TOTAL_SIZE))){
        return FALSE;
    }
    tmp_ptr = tmp_ptr+8;
    HAL_FLASH_Unlock(); //解锁Flash
    for (i = 0; i < cur_len; i++){
        st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_BYTE, UP_APP_START_ADDR+off+i, tmp_ptr[i]);
        if (st != HAL_OK){
            break;
        }
        if ((i % 100) == 0){
            osThreadYield();
        }
    }
    HAL_FLASH_Lock(); //锁住Flash
    if (st != HAL_OK){
        return FALSE;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      UpdateEndFunc
*\Description   升级过程结束，进行最终合法性检查
*\Parameter     data 升级数据帧数据域内容
*\Return        bool
*\Note          
*\Log           2020.08.07    Ver 1.0    骆兆松
*               创建函数。
***************************************************************************************************/
bool UpdateEndFunc(DataNode* data)
{
    u32 ch_num;
    u32 sector = 0;
    u8* tmp_ptr;
    HAL_StatusTypeDef st;
    u32 i;
    if (Updateing == TRUE){
        return FALSE;
    }
    if (data->Len != sizeof(UpDataFileEndHeader)){
        return FALSE;
    }
    memcpy(&UpEndHead, data->Data, data->Len);
    if ((UpEndHead.Len > UPDATA_TOTAL_SIZE) || (UpEndHead.Len < UPDATA_MIN_SIZE)){
        return FALSE;
    }
    /*CRC合法性检查*/
    ch_num = hash_CRC32_png(UP_CRC32_SEED, (u8*)UP_APP_START_ADDR, UpEndHead.Len);
    if (ch_num != UpEndHead.CrcNum){
        return FALSE;
    }
    //启动升级过程,标记需要升级
    UpdateFlag.FileAttr     = 0;
    UpdateFlag.FileLen      = UpEndHead.Len;
    UpdateFlag.FileChk      = UpEndHead.CrcNum;
    UpdateFlag.UpdateFlag = NEED_UPDATE;
    UpdateFlag.FileHeaderChk = hash_CRC32_png(UP_CRC32_SEED, (u8*)&UpdateFlag.UpdateFlag, sizeof(UpDataFileHeader) - 4);
  
    /*擦除 存放升级标志的FLASH*/
    HAL_FLASH_Unlock(); //解锁Flash
    sector = GetSectroNum(UP_FLAG_START_ADDR);
    FLASH_Erase_Sector(sector, FLASH_VOLTAGE_RANGE_3);
    st = FLASH_WaitForLastOperation1(5000);
    if (st == HAL_OK){
        tmp_ptr = (u8*)&UpdateFlag;
        for (i = 0; i < sizeof(UpdateFlag); i++){
            st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_BYTE, UP_FLAG_START_ADDR+i, tmp_ptr[i]);
            if (st != HAL_OK){
                break;
            }
        }
    }
    HAL_FLASH_Lock(); //锁住Flash

    if (st != HAL_OK){
        return FALSE;
    }
    Updateing = TRUE;
    return TRUE;
}
static u8 ParaWrBuf[MAX_PARA_LEN];
bool WriteFlashPara(u32 addr, u8* buf, u32 len)
{
    u8* tmp_ptr;
    u32 sector;
    u32 i;
    HAL_StatusTypeDef st;
    if( (addr >= MAX_PARA_LEN) ||
        (len >= MAX_PARA_LEN) ||
        (addr+len) > MAX_PARA_LEN){
            return FALSE;
    }

    /*备份所有参数*/
    memcpy(ParaWrBuf, (void*)PARA_START_ADDR, MAX_PARA_LEN);
    /*拷贝用户数据*/
    memcpy(ParaWrBuf+addr, buf, len);

    /*擦除 存放升级标志的FLASH*/
    HAL_FLASH_Unlock(); //解锁Flash
    sector = GetSectroNum(PARA_START_ADDR);
    FLASH_Erase_Sector(sector, FLASH_VOLTAGE_RANGE_3);
    st = FLASH_WaitForLastOperation1(5000);
    if (st == HAL_OK){
        tmp_ptr = ParaWrBuf;
        for (i = 0; i < MAX_PARA_LEN; i++){
            st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_BYTE, PARA_START_ADDR+i, tmp_ptr[i]);
            if (st != HAL_OK){
                break;
            }
        }
    }
    HAL_FLASH_Lock(); //锁住Flash

    if (st != HAL_OK){
        return FALSE;
    }
    return TRUE;
}

u32 ReadFlashPara(u32 addr, u8* buf, u32 len)
{
    if( (addr >= MAX_PARA_LEN) ||
        (len >= MAX_PARA_LEN) ||
        (addr+len) > MAX_PARA_LEN){
            return FALSE;
    }
    /*备份所有参数*/
    memcpy(ParaWrBuf, (void*)PARA_START_ADDR, MAX_PARA_LEN);
    /*拷贝用户数据*/
    memcpy(buf, ParaWrBuf+addr, len);

    return len;
}
