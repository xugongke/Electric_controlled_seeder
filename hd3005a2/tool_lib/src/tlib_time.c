/***************************************************************************************************
*                    (c) Copyright 1992-2017 Embedded Products Research Center
*                                       All Rights Reserved
*
*\File          tlib_time.c
*\Description   时间操作模块，提供丰富的时间计算函数。
*\Note          1)时间数据类型目前仅定义DEC、BCD两种。
*\Note          2)时间数据含义目前仅定义时间、时间量两种。
*\Log           2017.09.15    Ver 1.0    骆兆松
*               创建文件。
***************************************************************************************************/
#include "tlib_time.h"

/***************************************************************************************************
*\Ver           InitTime
*\Description   默认基准时间（00年1月1日0点0分0秒）。
***************************************************************************************************/
const TIME InitTime = INIT_TIME;

/***************************************************************************************************
*\Ver           InvalidTime
*\Description   非法时间（00年1月1日0点0分0秒）。
*               创建函数。
***************************************************************************************************/
const TIME InvalidTime = INVALID_TIME;

/***************************************************************************************************
*\Ver           ChineseWeekName
*\Description   中文星期表。
***************************************************************************************************/
const u8* ChineseWeekName[] = {
    "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日", "时间错误"
};

/***************************************************************************************************
*\Ver           EnglishWeekName
*\Description   英文星期表。
***************************************************************************************************/
const u8* EnglishWeekName[] = {
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "时间错误"
};

/***************************************************************************************************
*\Ver           EnWeekName
*\Description   英文简写星期表。
***************************************************************************************************/
const u8* EnWeekName[] = {
    "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN", "ERR"
};

/***************************************************************************************************
*\Ver           ChineseMonthName
*\Description   中文月分表
***************************************************************************************************/
const u8* ChineseMonthName[] = {
    "一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月",
    "时间错误"
};

/***************************************************************************************************
*\Ver           EnglishMonthName
*\Description   英文简写月分表。
***************************************************************************************************/
const u8* EnglishMonthName[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", "Err"
};

const u8 CenturyYearTable[] = {
    1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
    1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
    1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
    1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
    1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0
};

/***************************************************************************************************
*DEC时间修改函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeDECAddYears
*\Description   DEC时间加年。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeDECAddYears(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    time->TUn.TSt.Year = (value + time->TUn.TSt.Year) % 100;

    if (time->TUn.TSt.Day > 28)
    {
        TimeDECFix(time);
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAddMonths
*\Description   DEC时间加月。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeDECAddMonths(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if ((value + time->TUn.TSt.Month) > 12)
    {
        value += time->TUn.TSt.Month;
        time->TUn.TSt.Month = value % 12;

        if (time->TUn.TSt.Month == 0x00)
        {
            time->TUn.TSt.Month = 12;
            if (TimeDECAddYears(time, (value / 12) - 1) == FALSE)
            {
                return FALSE;
            }
        }
        else
        {
            if (TimeDECAddYears(time, value / 12) == FALSE)
            {
                return FALSE;
            }
        }

    }
    else
    {
        time->TUn.TSt.Month += (u8)value;
    }

    if (time->TUn.TSt.Day > 28)
    {
        TimeDECFix(time);
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAddDays
*\Description   DEC时间加日。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeDECAddDays(TIME* time, u32 value)
{
    u8 days_in_month = 0x00;

    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    value += time->TUn.TSt.Day;
    time->TUn.TSt.Day = 1;
    days_in_month = TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month);

    while (value > days_in_month)
    {
        value -= days_in_month;
        if (TimeDECAddMonths(time, 1) == FALSE)
        {
            return FALSE;
        }
        days_in_month = TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month);
    }
    time->TUn.TSt.Day = (u8)value;

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAddHours
*\Description   DEC时间加小时。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeDECAddHours(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if ((value + time->TUn.TSt.Hour) >= 24)
    {
        value += time->TUn.TSt.Hour;
        if (TimeDECAddDays(time, value / 24) == FALSE)
        {
            return FALSE;
        }
        time->TUn.TSt.Hour = value % 24;
    }
    else
    {
        time->TUn.TSt.Hour += (u8)value;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAddMinutes
*\Description   DEC时间加分钟
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeDECAddMinutes(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if ((value + time->TUn.TSt.Minute) >= 60)
    {
        value += time->TUn.TSt.Minute;
        if (TimeDECAddHours(time, value / 60) == FALSE)
        {
            return FALSE;
        }
        time->TUn.TSt.Minute = value % 60;
    }
    else
    {
        time->TUn.TSt.Minute += (u8)value;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAddSeconds
*\Description   DEC时间加秒。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          调整时间范围大约为139年。
***************************************************************************************************/
bool TimeDECAddSeconds(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if ((value + time->TUn.TSt.Second) >= 60)
    {
        value += time->TUn.TSt.Second;
        if (TimeDECAddMinutes(time, value / 60) == FALSE)
        {
            return FALSE;
        }

        time->TUn.TSt.Second = value % 60;
    }
    else
    {
        time->TUn.TSt.Second += (u8)value;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECSubYears
*\Description   DEC时间减年。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeDECSubYears(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if (time->TUn.TSt.Year >= (value % 100))
    {
        time->TUn.TSt.Year -= (value % 100);
    }
    else
    {
        time->TUn.TSt.Year += 100;
        time->TUn.TSt.Year -= (value % 100);
    }

    if (time->TUn.TSt.Day > 28)
    {
        TimeDECFix(time);
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECSubMonths
*\Description   DEC时间减月。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeDECSubMonths(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if (value >= time->TUn.TSt.Month)
    {
        value -= time->TUn.TSt.Month;
        if (TimeDECSubYears(time, 1 + value / 12) == FALSE)
        {
            return FALSE;
        }
        time->TUn.TSt.Month = 12 - (value % 12);
    }
    else
    {
        time->TUn.TSt.Month -= (u8)value;
    }

    if (time->TUn.TSt.Day > 28)
    {
        TimeDECFix(time);
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECSubDays
*\Description   DEC时间减天。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeDECSubDays(TIME* time, u32 value)
{
    u8 day = 0x00;

    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    day = time->TUn.TSt.Day;
    time->TUn.TSt.Day = 0x01;

    if (value >= day)
    {
        value -= day;
        if (TimeDECSubMonths(time, 1) == FALSE)
        {
            return FALSE;
        }
        day = TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month);
    }

    while (value >= day)
    {
        value -= day;
        if (TimeDECSubMonths(time, 1) == FALSE)
        {
            return FALSE;
        }
        day = TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month);
    }

    time->TUn.TSt.Day = day - (u8)value;

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECSubHours
*\Description   DEC时间减小时。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeDECSubHours(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if (value > time->TUn.TSt.Hour)
    {
        value -= time->TUn.TSt.Hour;
        time->TUn.TSt.Hour = value % 24;/*临时存放value*/
        if (TimeDECSubDays(time, (time->TUn.TSt.Hour != 0) + value / 24) == FALSE)
        {
            return FALSE;
        }
        if (time->TUn.TSt.Hour != 0)
        {
            time->TUn.TSt.Hour = 24 - (value % 24);
        }
    }
    else
    {
        time->TUn.TSt.Hour -= (u8)value;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECSubMinutes
*\Description   DEC时间减分钟。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeDECSubMinutes(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if (value > time->TUn.TSt.Minute)
    {
        value -= time->TUn.TSt.Minute;
        time->TUn.TSt.Minute = value % 60;/*临时存放value*/
        if (TimeDECSubHours(time, (time->TUn.TSt.Minute != 0) + value / 60) == FALSE)
        {
            return FALSE;
        }
        if (time->TUn.TSt.Minute != 0)
        {
            time->TUn.TSt.Minute = 60 - (value % 60);
        }
    }
    else
    {
        time->TUn.TSt.Minute -= (u8)value;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECSubSeconds
*\Description   DEC时间减秒。
*\Parameter     time    时间指针DEC
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          调整时间范围大约为139年。
***************************************************************************************************/
bool TimeDECSubSeconds(TIME* time, u32 value)
{
    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    if (value > time->TUn.TSt.Second)
    {
        value -= time->TUn.TSt.Second;
        time->TUn.TSt.Second = value % 60;/*临时存放value*/
        if (TimeDECSubMinutes(time, (time->TUn.TSt.Second != 0) + value / 60) == FALSE)
        {
            return FALSE;
        }
        if (time->TUn.TSt.Second != 0)
        {
            time->TUn.TSt.Second = 60 - (value % 60);
        }
    }
    else
    {
        time->TUn.TSt.Second -= (u8)value;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAdjustYears
*\Description   调整时间的年数。
*\Parameter     time
*\Parameter     years
*\Return        bool
***************************************************************************************************/
bool TimeDECAdjustYears(TIME* time, s32 years)
{
    bool negative = FALSE;
    u32 u_num = 0;

    if (years < 0)
    {
        years = -years;
        negative = TRUE;
    }
    u_num = (u32)years;
    if (negative)
    {
        TimeDECSubYears(time, u_num);
    }
    else
    {
        TimeDECAddYears(time, u_num);
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAdjustMonths
*\Description   调整时间的月数。
*\Parameter     time
*\Parameter     months
*\Return        bool
***************************************************************************************************/
bool TimeDECAdjustMonths(TIME* time, s32 months)
{
    bool negative = FALSE;
    u32 u_num = 0;

    if (months < 0)
    {
        months = -months;
        negative = TRUE;
    }

    u_num = (u32)months;

    if (negative)
    {
        TimeDECSubMonths(time, u_num);
    }
    else
    {
        TimeDECAddMonths(time, u_num);
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAdjustDays
*\Description   调整时间的天数。
*\Parameter     time
*\Parameter     days
*\Return        bool
***************************************************************************************************/
bool TimeDECAdjustDays(TIME* time, s32 days)
{
    bool negative = FALSE;
    u32 u_num = 0;

    if (days < 0)
    {
        days = -days;
        negative = TRUE;
    }

    u_num = (u32)days;
    if (negative)
    {
        TimeDECSubDays(time, u_num);
    }
    else
    {
        TimeDECAddDays(time, u_num);
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAdjustHours
*\Description   调整时间的小时数。
*\Parameter     time
*\Parameter     hours
*\Return        bool
***************************************************************************************************/
bool TimeDECAdjustHours(TIME* time, s32 hours)
{
    bool negative = FALSE;
    u32 u_num = 0;

    if (hours < 0)
    {
        hours = -hours;
        negative = TRUE;
    }

    u_num = (u32)hours;

    if (negative)
    {
        TimeDECSubHours(time, u_num);
    }
    else
    {
        TimeDECAddHours(time, u_num);
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAdjustMinutes
*\Description   调整时间的分钟数。
*\Parameter     time
*\Parameter     minutes
*\Return        bool
***************************************************************************************************/
bool TimeDECAdjustMinutes(TIME* time, s32 minutes)
{
    bool negative = FALSE;
    u32 u_num = 0;

    if (minutes < 0)
    {
        minutes = -minutes;
        negative = TRUE;
    }
    u_num = (u32)minutes;

    if (negative)
    {
        TimeDECSubMinutes(time, u_num);
    }
    else
    {
        TimeDECAddMinutes(time, u_num);
    }
    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECAdjustSeconds
*\Description   调整时间的秒数。
*\Parameter     time
*\Parameter     seconds
*\Return        bool
*\Note          调整时间范围大约为139年。
***************************************************************************************************/
bool TimeDECAdjustSeconds(TIME* time, s64 seconds)
{
    bool negative = FALSE;
    u32 u_num = 0;
    bool ret = FALSE;

    if (seconds < 0)
    {
        seconds = -seconds;
        negative = TRUE;
    }
    if (seconds > U32_MAX)
    {
        u_num = U32_MAX;
    }
    else
    {
        u_num = (u32)seconds;
    }
    if (negative)
    {
        ret = TimeDECSubSeconds(time, u_num);
    }
    else
    {
        ret = TimeDECAddSeconds(time, u_num);
    }
    return ret;
}

/***************************************************************************************************
*BCD时间修改函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeDECAddYears
*\Description   BCD时间加年。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeBCDAddYears(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECAddYears(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDAddMonths
*\Description   BCD时间加月。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeBCDAddMonths(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECAddMonths(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDAddDays
*\Description   BCD时间加日。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDAddDays(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECAddDays(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDAddHours
*\Description   BCD时间加小时。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDAddHours(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECAddHours(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDAddMinutes
*\Description   BCD时间加分钟。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDAddMinutes(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECAddMinutes(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDAddSeconds
*\Description   BCD时间加秒。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDAddSeconds(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECAddSeconds(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDSubYears
*\Description   BCD时间减年。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeBCDSubYears(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECSubYears(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDSubMonths
*\Description   BCD时间减月。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
*\Note          1)若计算后日超出上限则取日上限。
***************************************************************************************************/
bool TimeBCDSubMonths(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECSubMonths(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDSubDays
*\Description   BCD时间减日。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换。
***************************************************************************************************/
bool TimeBCDSubDays(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECSubDays(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDSubHours
*\Description   BCD时间减小时。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDSubHours(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECSubHours(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDSubMinutes
*\Description   BCD时间减分钟。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDSubMinutes(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECSubMinutes(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeBCDSubSeconds
*\Description   BCD时间减秒。
*\Parameter     time    时间指针BCD
*\Parameter     value   数值
*\Return        bool    是否成功转换
***************************************************************************************************/
bool TimeBCDSubSeconds(TIME* time, u32 value)
{
    if (TimeBCDToDEC(time) == FALSE)
    {
        return FALSE;
    }
    if (TimeDECSubSeconds(time, value) == FALSE)
    {
        return FALSE;
    }
    return TimeDECToBCD(time);
}

/***************************************************************************************************
*\Function      TimeSwap
*\Description   时间交换函数。
*\Parameter     time1   时间指针DEC/BCD
*\Parameter     time2   时间指针DEC/BCD
*\Return        void
*\Note          1)该函数不检查时间参数正确性。
***************************************************************************************************/
void TimeSwap(TIME* time1, TIME* time2)
{
    Swap(time1->TUn.TSt.Year,   time2->TUn.TSt.Year);
    Swap(time1->TUn.TSt.Month,  time2->TUn.TSt.Month);
    Swap(time1->TUn.TSt.Day,    time2->TUn.TSt.Day);
    Swap(time1->TUn.TSt.Hour,   time2->TUn.TSt.Hour);
    Swap(time1->TUn.TSt.Minute, time2->TUn.TSt.Minute);
    Swap(time1->TUn.TSt.Second, time2->TUn.TSt.Second);
}

/***************************************************************************************************
*时间计算函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeSubTimeDEC
*\Description   计算两时间秒差。
*\Parameter     time1   时间结构DEC
*\Parameter     time2   时间结构DEC
*\Return        u32     秒差
*\Note          1)计算结果为绝对值。
*\Note          2)若时间数据错误则返回0，注意：时间相等也返回0。
***************************************************************************************************/
u32 TimeDECSubTime(TIME time1, TIME time2)
{
    u32 sum = 0;

    if ((TimeDECCheck(&time1) == FALSE) || (TimeDECCheck(&time2) == FALSE))
    {
        return 0;
    }

    /*交换*/
    if (TimeComp(&time1, &time2, TIME_LATE))
    {
        TimeSwap(&time1, &time2);
    }

    while (!((time1.TUn.TSt.Year == time2.TUn.TSt.Year) && (time1.TUn.TSt.Month == time2.TUn.TSt.Month)))
    {
        sum += (TimeMonthDays(time1.TUn.TSt.Year, time1.TUn.TSt.Month) * ONE_DAY);

        if (time1.TUn.TSt.Month == 12)
        {
            time1.TUn.TSt.Year++;
            time1.TUn.TSt.Month = 0;
        }

        time1.TUn.TSt.Month++;
    }
    sum = (u32)(
        (s64)sum +
        ((s8)time2.TUn.TSt.Day - (s8)time1.TUn.TSt.Day) * ONE_DAY +
        ((s8)time2.TUn.TSt.Hour - (s8)time1.TUn.TSt.Hour) * ONE_HOUR +
        ((s8)time2.TUn.TSt.Minute - (s8)time1.TUn.TSt.Minute) * ONE_MINUTE +
        ((s8)time2.TUn.TSt.Second - (s8)time1.TUn.TSt.Second)
        );

    return sum;
}

/***************************************************************************************************
*\Function      TimeBCDSubTime
*\Description   计算两时间秒差。
*\Parameter     time1   时间结构BCD
*\Parameter     time2   时间结构BCD
*\Return        u32     秒差
*\Note          1)计算结果为绝对值。
*\Note          2)若时间数据错误则返回0，注意：时间相等也返回0。
***************************************************************************************************/
u32 TimeBCDSubTime(TIME time1, TIME time2)
{
    if ((TimeBCDToDEC(&time1) == FALSE) || (TimeBCDToDEC(&time2) == FALSE))
    {
        return 0;
    }

    return TimeDECSubTime(time1, time2);
}

/***************************************************************************************************
*时间类型转换函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeBCDToDEC
*\Description   将BCD时间转为DEC时间。
*\Parameter     time    时间指针BCD
*\Return        bool    是否成功转换
*\Note          1)time为引用，原值会改变。
*\Note          2)若时间数据非法则不转换并返回FALSE。
*\Note          3)本函数已检查时间正确性，无需再次检查。
***************************************************************************************************/
bool TimeBCDToDEC(TIME* time)
{
    u8 i = 0x00;

    if (MemBCDCheck((u8*)time, 6) == FALSE)
    {
        return FALSE;
    }

    for (i = 0; i < 6; i++)
    {
        BCDToDECU8((u8*)time + i);
    }

    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECToBCD
*\Description   将DEC时间转为BCD时间。
*\Parameter     time    时间指针DEC
*\Return        bool    是否成功转换
*\Note          1)time为引用，原值会改变。
*\Note          2)若时间数据非法则不转换并返回FALSE。
*\Note          3)本函数已检查时间正确性，无需再次检查。
***************************************************************************************************/
bool TimeDECToBCD(TIME* time)
{
    u8 i = 0x00;

    if (TimeDECCheck(time) == FALSE)
    {
        return FALSE;
    }

    for (i = 0; i <= 5; i++)
    {
        if (CheckDECToBCD(*((u8*)time + i)) == FALSE)
        {
            return FALSE;
        }
    }

    for (i = 0; i < 6; i++)
    {
        DECToBCDU8((u8*)time + i);
    }
    return TRUE;
}

/***************************************************************************************************
*时间比较函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeComp
*\Description   时间比较
*\Parameter     time1       时间指针DEC/BCD，必须是合法的时间。
*\Parameter     time2       时间指针DEC/BCD，必须是合法的时间。
*\Parameter     time_flags  时间比较标志。可以是TIME_EARLY, TIME_EQUAL, TIME_LATE及其相位与的组合。
*\Return        bool        若比较的时间结果符合time_flags标志,则返回TRUE，否则返回FALSE。
*\Note          1)该函数不检查时间参数正确性。
*\Note          2)time为引用，但原值不会改变。
***************************************************************************************************/
bool TimeComp(TIME* time1, TIME* time2, u32 time_flags)
{
    u8 i = 0;
    u32 result = TIME_EQUAL;

    for (i = 0; i < sizeof(TIME); i++)
    {
        if (time1->TUn.Array[i] < time2->TUn.Array[i])
        {
            result = TIME_EARLY;
            break;
        }
        else if (time1->TUn.Array[i] > time2->TUn.Array[i])
        {
            result = TIME_LATE;
            break;
        }
    }
    if (time_flags & result)
    {
        return TRUE;
    }

    return FALSE;
}

/***************************************************************************************************
*时间查询函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeMonthDays
*\Description   获取某月天数。
*\Parameter     year    年DEC
*\Parameter     month   月DEC
*\Return        u8      本月天数DEC
*\Note          1)若月份错误则默认返回30天。
*\Note          2)默认为21世纪年份。
***************************************************************************************************/
u8 TimeMonthDays(u8 year, u8 month)
{
    switch(month)
    {
    case 1:case 3:case 5:case 7:case 8:case 10:case 12:
        return 31;
    case 2:
        return 28 + CenturyYearTable[year];
    case 4:case 6:case 9:case 11:
        return 30;
    default:
        return 0;
    }
}


/***************************************************************************************************
*\Function      TimeDECMonthDays
*\Description   获取某月天数。
*\Parameter     time    时间结构DEC
*\Return        u8      本月天数DEC
*\Note          1)默认为21世纪年份。
*\Note          2)若时间数据非法则返回0。
***************************************************************************************************/
u8 TimeDECMonthDays(TIME time)
{
    if (TimeDECCheck(&time) == FALSE)
    {
        return 0;
    }
    return TimeMonthDays(time.TUn.TSt.Year, time.TUn.TSt.Month);
}

/***************************************************************************************************
*\Function      TimeBCDMonthDays
*\Description   获取某月天数。
*\Parameter     time    时间结构BCD
*\Return        u8      本月天数DEC
*\Note          1)默认为21世纪年份。
*\Note          2)若时间数据非法则返回0。
***************************************************************************************************/
u8 TimeBCDMonthDays(TIME time)
{
    if (TimeBCDToDEC(&time) == FALSE)
    {
        return 0;
    }

    return TimeMonthDays(time.TUn.TSt.Year, time.TUn.TSt.Month);
}

/***************************************************************************************************
*\Function      TimeDECWeekDay
*\Description   获取DEC时间为星期几。
*\Parameter     time    时间结构DEC
*\Return        u8      取值范围：0~7。 0：周一， 6：周日；7代表时间错误。
*\Note          1)若时间数据非法则不查询并返回7。
*\Note          2)使用Zeller公式。
***************************************************************************************************/
u8 TimeDECWeekDay(TIME time)
{
    u16 year = 0x00;

    if (TimeDECCheck(&time) == FALSE)
    {
        return 0x07;
    }

    year = 2000 + time.TUn.TSt.Year;

    if ((time.TUn.TSt.Month == 1) || (time.TUn.TSt.Month == 2))
    {
        time.TUn.TSt.Month += 12;
        year--;
    }

    return (time.TUn.TSt.Day + 2*time.TUn.TSt.Month + 3*(time.TUn.TSt.Month+1)/5 + year + year/4 - year/100 + year/400) % 7;
}

/***************************************************************************************************
*\Function      TimeBCDWeekDay
*\Description   获取BCD时间为星期几。
*\Parameter     time    时间结构BCD
*\Return        u8      取值范围：0~7。 0：周一， 6：周日；7代表时间错误。
*\Note          1)若时间数据非法则不查询并返回7。
*\Note          2)使用Zeller公式。
***************************************************************************************************/
u8 TimeBCDWeekDay(TIME time)
{
    if (TimeBCDToDEC(&time) == FALSE)
    {
        return 0x07;
    }
    return TimeDECWeekDay(time);
}

/***************************************************************************************************
*时间检查函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeDECCheck
*\Description   检查DEC时间是否正确。
*\Parameter     time    时间指针DEC
*\Return        bool    检查结果
***************************************************************************************************/
bool TimeDECCheck(TIME* time)
{
    if (
        (time->TUn.TSt.Year <= 99) &&
        (1 <= time->TUn.TSt.Month) &&
        (time->TUn.TSt.Month <= 12) &&
        (1 <= time->TUn.TSt.Day) &&
        (time->TUn.TSt.Day <= TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month)) && //绝对不可使用TimeDECMonthDays函数，递归。
        (time->TUn.TSt.Hour < 24) &&
        (time->TUn.TSt.Minute < 60) &&
        (time->TUn.TSt.Second < 60)
        )
    {
        return TRUE;
    }
    else
    {
        return FALSE;
    }
}

/***************************************************************************************************
*\Function      TimeBCDCheck
*\Description   检查BCD时间是否正确。
*\Parameter     time    时间指针BCD
*\Return        bool    检查结果
***************************************************************************************************/
bool TimeBCDCheck(TIME* time)
{
    TIME time1 = *time;
    /*TimeBCDToDEC中调用TimeDECCheck所以无需再次调用。*/
    return TimeBCDToDEC(&time1);
}

/***************************************************************************************************
*\Function      TimeZeroCheck
*\Description   检查时间是否为0。
*\Parameter     time    时间指针DEC/BCD
*\Return        bool    检查结果
*\Note          1)该函数不检查时间参数正确性。
*\Note          2)用于时间量检查。
***************************************************************************************************/
bool TimeZeroCheck(TIME* time)
{
    if ((time->TUn.TSt.Year == 0) && (time->TUn.TSt.Month == 0)  && (time->TUn.TSt.Day == 0)
        &&(time->TUn.TSt.Hour == 0) && (time->TUn.TSt.Minute == 0) && (time->TUn.TSt.Second == 0))
    {
        return TRUE;
    }

    return FALSE;
}

/***************************************************************************************************
*时间初始化函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeInit
*\Description   初始化时间
*\Parameter     time    时间指针
*\Return        void
*\Note          1)也可以直接将InitTime赋给时间结构代替本函数。
***************************************************************************************************/
void TimeInit(TIME* time)
{
    *time = InitTime;
}


/***************************************************************************************************
*时间修正函数
***************************************************************************************************/
void BitPointSet(void* src, u8 pos, u8 width)
{
    switch (width)
    {
    case sizeof(u8):
        (*(u8*)src) |= (1UL<<(pos));
        break;

    case sizeof(u16):
        (*(u16*)src) |= (1UL<<(pos));
        break;

    case sizeof(u32):
        (*(u32*)src) |= (1ULL<<(pos));
        break;

    case sizeof(u64):
        (*(u64*)src) |= (1ULL<<(pos));
        break;

    default:

        break;
    }
}
/***************************************************************************************************
*\Def           BitSet
*\Description   将src的第pos位置置位
*\Parameter     src 数据地址
*\Parameter     pos 位，从0开始计
*\Return        u8
*\Note          src和pos均为变量，不可填写指针、函数或表达式。

***************************************************************************************************/
#define BitSet(src, pos)  { BitPointSet(&(src), (pos), sizeof(src)); }

/***************************************************************************************************
*\Function      TimeDECFix
*\Description   DEC时间修正
*\Parameter     time    时间指针DEC
*\Return        u8      修正位集合
*\Note          1)将错误的时间按其含义取近似值。
*\Note          2)修正规则：大于上限：取上限。小于下限：取下限。
*\Note          3)该函数不检查时间参数正确性。
***************************************************************************************************/
u8 TimeDECFix(TIME* time)
{
    u8 flag = 0x00;

    while (1)
    {
        /*年修正*/
        if (time->TUn.TSt.Year > 99)
        {
            time->TUn.TSt.Year = 99;
            BitSet(flag, 5);
        }

        /*月修正*/
        else if (time->TUn.TSt.Month == 0x00)
        {
            time->TUn.TSt.Month = 0x01;
            BitSet(flag, 4);
        }
        else if (time->TUn.TSt.Month > 12)
        {
            time->TUn.TSt.Month = 12;
            BitSet(flag, 4);
        }

        /*日修正*/
        else if (time->TUn.TSt.Day == 0x00)
        {
            time->TUn.TSt.Day = 0x01;
            BitSet(flag, 3);
        }
        /*此时年月数据已经被修正*/
        else if (time->TUn.TSt.Day > TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month))
        {
            time->TUn.TSt.Day = TimeMonthDays(time->TUn.TSt.Year, time->TUn.TSt.Month);
            BitSet(flag, 3);
        }

        /*时修正*/
        else if (time->TUn.TSt.Hour >= 24)
        {
            time->TUn.TSt.Hour = 23;
            BitSet(flag, 2);
        }

        /*分修正*/
        else if (time->TUn.TSt.Minute >= 60)
        {
            time->TUn.TSt.Minute = 59;
            BitSet(flag, 1);
        }

        /*秒修正*/
        else if (time->TUn.TSt.Second >= 60)
        {
            time->TUn.TSt.Second = 59;
            BitSet(flag, 0);
        }
        else
        {
            break;
        }
    }

    return flag;
}

/***************************************************************************************************
*\Function      TimeBCDFix
*\Description   BCD时间修正
*\Parameter     time    时间指针BCD
*\Return        u8      修正位集合
*\Note          1)将错误的时间按其含义取近似值。
*\Note          2)修正规则：大于上限：取上限。小于下限：取下限。
*\Note            BCD数值非法且小于上限：取下一个正确BCD值，如：0x1F -> 0x20。
*\Note          3)该函数不检查时间参数正确性。
*               创建函数。
***************************************************************************************************/
u8 TimeBCDFix(TIME* time)
{
    u8 flag = 0x00;

    while (1)
    {
        /*年修正*/
        if (time->TUn.TSt.Year > 0x99)
        {
            time->TUn.TSt.Year = 0x99;
            BitSet(flag, 5);
        }
        else if (BCDFix((u8*)&time->TUn.TSt.Year) == TRUE)
        {
            BitSet(flag, 5);
            continue;
        }

        /*月修正*/
        else if (time->TUn.TSt.Month == 0x00)
        {
            time->TUn.TSt.Month = 0x01;
            BitSet(flag, 4);
        }
        else if (time->TUn.TSt.Month > 0x12)
        {
            time->TUn.TSt.Month = 0x12;
            BitSet(flag, 4);
        }
        else if (BCDFix((u8*)&time->TUn.TSt.Month) == TRUE)
        {
            BitSet(flag, 4);
            continue;
        }

        /*日修正*/
        else if (time->TUn.TSt.Day == 0x00)
        {
            time->TUn.TSt.Day = 0x01;
            BitSet(flag, 3);
        }
        /*此时年月数据已经被修正*/
        else if (GetBCDToDECU8(time->TUn.TSt.Day) > TimeMonthDays(GetBCDToDECU8(time->TUn.TSt.Year), GetBCDToDECU8(time->TUn.TSt.Month)))
        {
            time->TUn.TSt.Day = GetDECToBCDU8(TimeMonthDays(GetBCDToDECU8(time->TUn.TSt.Year), GetBCDToDECU8(time->TUn.TSt.Month)));
            BitSet(flag, 3);
        }
        else if (BCDFix((u8*)&time->TUn.TSt.Day) == TRUE)
        {
            BitSet(flag, 3);
            continue;
        }

        /*时修正*/
        else if (time->TUn.TSt.Hour >= 0x24)
        {
            time->TUn.TSt.Hour = 0x23;
            BitSet(flag, 2);
        }
        else if (BCDFix((u8*)&time->TUn.TSt.Hour) == TRUE)
        {
            BitSet(flag, 2);
            continue;
        }

        /*分修正*/
        else if (time->TUn.TSt.Minute >= 0x60)
        {
            time->TUn.TSt.Minute = 0x59;
            BitSet(flag, 1);
        }
        else if (BCDFix((u8*)&time->TUn.TSt.Minute) == TRUE)
        {
            BitSet(flag, 1);
            continue;
        }

        /*秒修正*/
        else if (time->TUn.TSt.Second >= 0x60)
        {
            time->TUn.TSt.Second = 0x59;
            BitSet(flag, 0);
        }
        else if (BCDFix((u8*)&time->TUn.TSt.Second) == TRUE)
        {
            BitSet(flag, 0);
            continue;
        }

        /*正确*/
        else
        {
            break;
        }
    }

    return flag;
}


/***************************************************************************************************
*时间转换函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeDECToStamp
*\Description   将DEC时间转为时间戳。
*\Parameter     time    时间结构DEC
*\Return        u32     时间戳
*\Note          1)时间戳为相对基本时间InitTime的秒差+1。
*\Note          2)若时间数据非法则不计算并返回0（ERROR_STAMP）。
***************************************************************************************************/
u32 TimeDECToStamp(TIME time)
{
    if (TimeDECCheck(&time) == FALSE)
    {
        return ERROR_STAMP;
    }

    return TimeDECSubTime(time, InitTime) + 1;
}

/***************************************************************************************************
*\Function      TimeBCDToStamp
*\Description   将BCD时间转为时间戳。
*\Parameter     time    时间结构BCD
*\Return        u32     时间戳
*\Note          1)时间戳为相对基本时间InitTime的秒差+1。
*\Note          2)若时间数据非法则不计算并返回0（ERROR_STAMP）。
*               创建函数。
***************************************************************************************************/
u32 TimeBCDToStamp(TIME time)
{
    if (TimeBCDCheck(&time) == FALSE)
    {
        return ERROR_STAMP;
    }

    return TimeBCDSubTime(time, InitTime) + 1;
}

/***************************************************************************************************
*\Function      TimeDECStampToTime
*\Description   将时间戳转为DEC时间。
*\Parameter     stamp   时间戳
*\Return        TIME    时间结构
*\Note          1)时间戳为相对基本时间InitTime的秒差+1。
*\Note          2)若参数stamp（时间戳）为0或1均返回基本时间InitTime。
*               创建函数。
***************************************************************************************************/
TIME TimeDECStampToTime(u32 stamp)
{
    TIME time = INIT_TIME;

    if (stamp != ERROR_STAMP)
    {
        TimeDECAddSeconds(&time, stamp - 1);
    }

    return time;
}

/***************************************************************************************************
*\Function      TimeBCDStampToTime
*\Description   将时间戳转为BCD时间。
*\Parameter     stamp   时间戳
*\Return        TIME    时间结构
*\Note          1)时间戳为相对基本时间InitTime的秒差+1。
*\Note          2)若参数stamp（时间戳）为0或1均返回基本时间InitTime。
*               创建函数。
***************************************************************************************************/
TIME TimeBCDStampToTime(u32 stamp)
{
    TIME time = INIT_TIME;

    if (stamp != ERROR_STAMP)
    {
        TimeBCDAddSeconds(&time, stamp - 1);
    }

    return time;
}


/***************************************************************************************************
*时间量函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeValueToSecond
*\Description   将时间量转换为秒。
*\Parameter     time            时间结构DEC
*\Parameter     year_seconds    年时长
*\Parameter     month_seconds   月时长
*\Return        u32             秒
*\Note          1)该函数不检查时间参数正确性。
*\Note          2)年时长和秒时长建议使用时间宏。
*               创建函数。
***************************************************************************************************/
u32 TimeValueToSecond(TIME time, u32 year_seconds, u32 month_seconds)
{
    return time.TUn.TSt.Year * year_seconds +
        time.TUn.TSt.Month * month_seconds +
        time.TUn.TSt.Day * ONE_DAY +
        time.TUn.TSt.Hour * ONE_HOUR +
        time.TUn.TSt.Minute * ONE_MINUTE +
        time.TUn.TSt.Second;
}


/***************************************************************************************************
*时间单元函数
***************************************************************************************************/

/***************************************************************************************************
*\Function      TimeDECToUnit
*\Description   将DEC时间转为单元数值。
*\Parameter     unit_num        单元数值指针
*\Parameter     target_time     目标时间
*\Parameter     base_time       单元基准时间
*\Parameter     unit_second     单元时长
*\Parameter     fill            填补剩余时间为1个单元
*\Return        s32             单元数值（可能为负）
*\Note          1)函数作用：计算距target_time最近的1个单元点。
*\Note          2)target_time与单元点重合时结果为0。
*\Note          3)unit_second为1个单元的时间长度，unit_second = 0时所有单元都落在base_time一点上。
*\Note          4)target_time落在两个单元点之间时，target_time比上个单元点多出的时间称为剩余时间。
*\Note          5)fill = TRUE 且剩余时间大于0时，结果为最近的下1个单元点数值。
*\Note          6)fill = FALSE且剩余时间大于0时，结果为最近的上1个单元点数值。
*\Note          7)本函数进行时间正确性检查，非法时间返回FALSE。
*               创建函数。
***************************************************************************************************/
bool TimeDECToUnit(s32* unit_num, TIME target_time, TIME base_time, u32 unit_second, bool fill)
{
    s32 diff                = 0x00; /*时间差*/
    s32 remainder           = 0x00; /*多余秒数*/
    s32 units_second_diff   = 0x00; /*小于diff的整单位秒时间*/

    if ((TimeDECCheck(&target_time) == FALSE) || (TimeDECCheck(&base_time) == FALSE))
    {
        return FALSE;
    }

    if (unit_second == 0x00)
    {
        *unit_num = 0;
        return TRUE;
    }

    diff = TimeDECSubTime(target_time, base_time);

    if (TimeComp(&target_time, &base_time, TIME_EARLY) == TRUE)
    {
        diff = -diff;
    }

    *unit_num = diff / unit_second;
    units_second_diff = *unit_num * unit_second;
    remainder = diff - units_second_diff;

    /*目标时间与单元点重合*/
    if (remainder == 0x00)
    {
        return TRUE;
    }
    /*填补剩余进入下一单元*/
    if (fill == TRUE)
    {
        /*将剩余填充*/
        *unit_num += 1;
    }

    return TRUE;
}

/***************************************************************************************************
*\Function      TimeDECUnitToTime
*\Description   将时间单元值转为DEC时间。
*\Parameter     target_time     目标时间指针
*\Parameter     base_time       单元基准时间
*\Parameter     unit_second     单元时长
*\Return        bool            转换结果
*\Note
***************************************************************************************************/
bool TimeDECUnitToTime(TIME* target_time, u32 unit_num, TIME base_time, u32 unit_second)
{
    if (TimeDECCheck(&base_time) == FALSE)
    {
        return FALSE;
    }

    *target_time = base_time;
    return TimeDECAddSeconds(target_time, unit_second * unit_num);
}

/***************************************************************************************************
*\Function      TimeDECToUnitTime
*\Description   将DEC时间转为单元时间。
*\Parameter     target_time     目标时间指针
*\Parameter     base_time       单元基准时间
*\Parameter     unit_second     单元时长
*\Parameter     fill            填补剩余时间为1个单元
*\Return        bool            转换结果
*\Note          1)函数作用：将target_time改为距target_time最近的1个单元点的时间。
*\Note          2)target_time与单元点重合时不做修改。
*\Note          3)unit_second为1个单元的时间长度，unit_second = 0时所有单元都落在base_time一点上。
*\Note          4)target_time落在2个单元点之间时，target_time比上个单元点多出的时间称为剩余时间。
*\Note          5)fill = TRUE 且剩余时间大于0时，target_time将被改为最近的下1个单元点时间。
*\Note          6)fill = FALSE且剩余时间大于0时，target_time将被改为最近的上1个单元点时间。
*\Note          7)本函数进行时间正确性检查，非法时间返回FALSE。
***************************************************************************************************/
bool TimeDECToUnitTime(TIME* target_time, TIME base_time, u32 unit_second, bool fill)
{
    u32 diff                = 0x00; /*时间差*/
    u32 remainder           = 0x00; /*多余秒数*/

    if ((TimeDECCheck(target_time) == FALSE) || (TimeDECCheck(&base_time) == FALSE))
    {
        return FALSE;
    }

    if (unit_second == 0x00)
    {
        *target_time = base_time;
        return TRUE;
    }

    diff = TimeDECSubTime(*target_time, base_time);
    remainder = diff % unit_second;

    /*目标时间与单元点重合*/
    if (remainder == 0x00)
    {
        return TRUE;
    }
    /*填补剩余进入下一单元*/
    if (fill == TRUE)
    {
        return TimeDECAddSeconds(target_time, unit_second - remainder);
    }
    /*舍弃剩余*/
    return TimeDECSubSeconds(target_time, remainder);
}

/***************************************************************************************************
*\Function      TimeSameMinute
*\Description   判断两时间是否处于相同的分钟。
*\Parameter     t1_dec  第一个时间，格式为DEC。
*\Parameter     t2_dec  第二个时间，格式为DEC。
*\Return        bool
***************************************************************************************************/
bool TimeSameMinute(TIME* t1_dec, TIME* t2_dec)
{
    if ((TimeDECCheck(t1_dec) == FALSE) || (TimeDECCheck(t2_dec) == FALSE))
    {
        return FALSE;
    }
    if ((t1_dec->TUn.TSt.Year == t2_dec->TUn.TSt.Year) &&
        (t1_dec->TUn.TSt.Month == t2_dec->TUn.TSt.Month) &&
        (t1_dec->TUn.TSt.Day == t2_dec->TUn.TSt.Day) &&
        (t1_dec->TUn.TSt.Hour == t2_dec->TUn.TSt.Hour) &&
        (t1_dec->TUn.TSt.Minute == t2_dec->TUn.TSt.Minute))
    {
        return TRUE;
    }
    return FALSE;
}

/***************************************************************************************************
*\Function      TimeSameHour
*\Description   判断两时间是否处于相同的小时。
*\Parameter     t1_dec  第一个时间，格式为DEC。
*\Parameter     t2_dec  第二个时间，格式为DEC。
*\Return        bool
*               创建函数。
***************************************************************************************************/
bool TimeSameHour(TIME* t1_dec, TIME* t2_dec)
{
    if ((TimeDECCheck(t1_dec) == FALSE) || (TimeDECCheck(t2_dec) == FALSE))
    {
        return FALSE;
    }
    if ((t1_dec->TUn.TSt.Year == t2_dec->TUn.TSt.Year) &&
        (t1_dec->TUn.TSt.Month == t2_dec->TUn.TSt.Month) &&
        (t1_dec->TUn.TSt.Day == t2_dec->TUn.TSt.Day) &&
        (t1_dec->TUn.TSt.Hour == t2_dec->TUn.TSt.Hour))
    {
        return TRUE;
    }
    return FALSE;
}

/***************************************************************************************************
*\Function      TimeSameDay
*\Description   判断两时间是否处于相同的日。
*\Parameter     t1_dec  第一个时间，格式为DEC。
*\Parameter     t2_dec  第二个时间，格式为DEC。
*\Return        bool
*               创建函数。
***************************************************************************************************/
bool TimeSameDay(TIME* t1_dec, TIME* t2_dec)
{
    if ((TimeDECCheck(t1_dec) == FALSE) || (TimeDECCheck(t2_dec) == FALSE))
    {
        return FALSE;
    }
    if ((t1_dec->TUn.TSt.Year == t2_dec->TUn.TSt.Year) &&
        (t1_dec->TUn.TSt.Month == t2_dec->TUn.TSt.Month) &&
        (t1_dec->TUn.TSt.Day == t2_dec->TUn.TSt.Day))
    {
        return TRUE;
    }
    return FALSE;
}

/***************************************************************************************************
*\Function      TimeSameDay
*\Description   判断两时间是否处于相同的月。
*\Parameter     t1_dec  第一个时间，格式为DEC。
*\Parameter     t2_dec  第二个时间，格式为DEC。
*\Return        bool
*               创建函数。
***************************************************************************************************/
bool TimeSameMonth(TIME* t1_dec, TIME* t2_dec)
{
    if ((TimeDECCheck(t1_dec) == FALSE) || (TimeDECCheck(t2_dec) == FALSE))
    {
        return FALSE;
    }
    if ((t1_dec->TUn.TSt.Year == t2_dec->TUn.TSt.Year) &&
        (t1_dec->TUn.TSt.Month == t2_dec->TUn.TSt.Month))
    {
        return TRUE;
    }
    return FALSE;
}
#if 0
static u32 gsize = 0;
static u8* pt = NULL;

static int _add(u8* str)
{
    for (;; ++pt, --gsize) {
        if (!gsize)
            return(0);
        if (!(*pt = *str++))
            return(1);
    }
}

static int _conv(s32 n, s32 digits, u8 pad)
{
    u8 buf[10] = {0};
    u8* p;

    for (p = buf + sizeof(buf) - 2; (n > 0) && (p > buf); n /= 10, --digits)
    {
        *p-- = n % 10 + '0';
    }
    while (p > buf && digits-- > 0)
        *p-- = pad;
    return(_add(++p));
}

static u32 _fmt(const u8* format, TIME* t)
{
    u8 tmp = 0;

    for (; *format; ++format) {
        if (*format == '%')
            switch(*++format) {
            case '\0':
                --format;
                break;
            case 'A':
                tmp = TimeDECWeekDay(*t);
                if (tmp > 6)
                {
                    return 0;
                }

                if (!_add((u8*)EnglishWeekName[tmp]))
                    return(0);
                continue;
            case 'a':
                tmp = TimeDECWeekDay(*t);
                if (tmp > 6)
                {
                    return 0;
                }
                if (!_add((u8*)EnWeekName[tmp]))
                    return 0;
                continue;
            case 'B':
                if (t->TUn.TSt.Month < 1 || t->TUn.TSt.Month > 12)
                    return 0;
                if (!_add((u8*)EnglishMonthName[t->TUn.TSt.Month - 1]))
                    return 0;
                continue;
            case 'b':
            case 'h':
                if (t->TUn.TSt.Month < 1 || t->TUn.TSt.Month > 12)
                    return 0;
                if (!_add((u8*)EnglishMonthName[t->TUn.TSt.Month - 1]))
                    return 0;
                continue;
            case 'C':
                if (!_fmt("%a %b %e %H:%M:%S %Y", t))
                    return 0;
                continue;
            case 'c':
                if (!_fmt("%y-%m-%d %H:%M:%S", t))
                    return 0;
                continue;
            case 'D':
                if (!_fmt("%y-%m-%d/", t))
                    return 0;
                continue;
            case 'd':
                if (!_conv(t->TUn.TSt.Day, 2, '0'))
                    return 0;
                continue;
            case 'e':
                if (!_conv(t->TUn.TSt.Day, 2, ' '))
                    return 0;
                continue;
            case 'H':
                if (!_conv(t->TUn.TSt.Hour, 2, '0'))
                    return 0;
                continue;
            case 'I':
                if (!_conv(t->TUn.TSt.Hour % 12 ? t->TUn.TSt.Hour % 12 : 12, 2, '0'))
                    return 0;
                continue;
            case 'j':
                if (!_conv(t->TUn.TSt.Day + 1, 3, '0'))
                    return 0;
                continue;
            case 'k':
                if (!_conv(t->TUn.TSt.Hour, 2, ' '))
                    return 0;
                continue;
            case 'l':
                if (!_conv(t->TUn.TSt.Hour % 12 ? t->TUn.TSt.Hour % 12 : 12, 2, ' '))
                    return 0;
                continue;
            case 'M':
                if (!_conv(t->TUn.TSt.Minute, 2, '0'))
                    return 0;
                continue;
            case 'm':
                if (!_conv(t->TUn.TSt.Month, 2, '0'))
                    return 0;
                continue;
            case 'n':
                if (!_add("\n"))
                    return 0;
                continue;
            case 'p':
                if (!_add(t->TUn.TSt.Hour >= 12 ? (u8*)"PM" : (u8*)"AM"))
                    return 0;
                continue;
            case 'R':
                if (!_fmt("%H:%M", t))
                    return 0;
                continue;
            case 'r':
                if (!_fmt("%I:%M:%S %p", t))
                    return 0;
                continue;
            case 'S':
                if (!_conv(t->TUn.TSt.Second, 2, '0'))
                    return 0;
                continue;
//             case 's':
//                 if (!_secs(t))
//                     return(0);
//                 continue;
            case 'T':
            case 'X':
                if (!_fmt("%H:%M:%S", t))
                    return 0;
                continue;
            case 't':
                if (!_add("\t"))
                    return 0;
                continue;
//             case 'U':
//                 if (!_conv((t->tm_yday + 7 - t->tm_wday) / 7,
//                     2, '0'))
//                     return(0);
//                 continue;
//             case 'W':
//                 if (!_conv((t->tm_yday + 7 -
//                     (t->tm_wday ? (t->tm_wday - 1) : 6))
//                     / 7, 2, '0'))
//                     return(0);
//                 continue;
            case 'w':
                if (!_conv(t->TUn.TSt.Day, 1, '0'))
                    return 0;
                continue;
            case 'x':
                if (!_fmt("%m-%d-%y", t))
                    return 0;
                continue;
            case 'y':
                if (!_conv((t->TUn.TSt.Year + 2000)
                    % 100, 2, '0'))
                    return 0;
                continue;
            case 'Y':
                if (!_conv(t->TUn.TSt.Year + 2000, 4, '0'))
                    return 0;
                continue;
//             case 'Z':
//                 if (!t->tm_zone || !_add(t->tm_zone))
//                     return 0;
//                 continue;
            case '%':
            /*
             * X311J/88-090 (4.12.3.5): if conversion char is
             * undefined, behavior is undefined.  Print out the
             * character itself as printf(3) does.
             */
            default:
                break;
        }
        if (!gsize--)
            return(0);
        *pt++ = *format;
    }
    return gsize;
}

/***************************************************************************************************
*\Function      StrFTime
*\Description   根据format对格式为TIME的t进行格式化，并存入长度为max_len的buf缓冲区中。
*\Parameter     s
*\Parameter     maxsize
*\Parameter     format
*\Parameter     t
*\Return        u32
*\Note          format的格式定义请参见C标准库strftime的说明。
*\Note          s,U,W,Z格式未实现。
*\Note          c和D中的日期格式为年-月-日。
*               创建函数。
***************************************************************************************************/
u32 StrFTime(u8* buf, u32 max_len, const u8* format, TIME* t)
{

    pt = buf;
    if ((gsize = max_len) < 1)
        return(0);
    if (_fmt(format, t)) {
        *pt = '\0';
        return(max_len - gsize);
    }
    return(0);
}

static u8 StrTimeTempBuf[18] = {0};

/***************************************************************************************************
*\Function      StrTime
*\Description   将TIME类型的t以“年-月-日 时:分:秒”格式进行格式化为字符串并返回。
*\Parameter     t
*\Return        u8*
*\Note          返回的字符串存储在局部静态缓冲区，请不要对其进行写操作。
*               创建函数。
***************************************************************************************************/
u8* StrTime(TIME* t)
{
    StrFTime(StrTimeTempBuf, sizeof(StrTimeTempBuf), "%c", t);
    return StrTimeTempBuf;
}

#endif
