#include "global.h"
#include <stdio.h>
#include <string.h>
#include <QScroller>
//#include "network/tcp.h"
//#include "network/threaddata.h"
#include "dataStructs/moisturecalibrationdata.h"
#include "dataStructs/masscalibrationdata.h"
#include <QDebug>
#include "uart/threaduart.h"
#include <QPainter>
#include <QSettings>
#include <cmath>
#include "../../common/database.h"
#include "tools/settingshandle.h"
#include <QFile>
#include <QDir>

const char *g_trigger_list[] = {"手动触发", "定时触发", "阈值触发", "TTL下降沿", "TTL上升沿", 0};
const char *g_threshold_list[] = {"无触发", "高于阈值", "低于阈值",  0};
const char *g_type_list[] = {"力", "力矩", 0};
const int   g_Hz_list[] = {10, 100, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, 1250000, 0};
const int   g_Vout_list[] = {5, 10, 0};
const char *units[][5]=
{
	{
		"N","kN",nullptr
	},
	{
		"Nm",nullptr
	}
};
QStringList channleList={
    "三通道","容重","1","2","3","4"
};
QStringList cropList={
	"玉米","小麦"
};
std::map<QString,QStringList> moistureSensorModeMap={
    {
        "旧",{
            "E","F","V"
        }
    },
    {
        "新",{
            "0","1","2","3","4"
        }
    }
};
GlobalData  G;

int Cache_load()
{
    FILE *fp = fopen("./global.tmp", "rb");
    if(fp && fread(&G.cache, sizeof(G.cache), 1, fp) == 1)
    {
        return 0;
    }
    memset(&G.cache, 0, sizeof(G.cache));
    return -1;
}

int Cache_save()
{
    FILE *fp = fopen("./global.tmp", "wb");
    if(fp && fwrite(&G.cache, sizeof(G.cache), 1, fp) == 1)
        return 0;
    return -1;
}

int  Calib_check_moisture(CalibData *calib)
{
    int i;
	double k;

    //正向值判断
    if(calib->val[0] < 0) return -1;
    if(calib->adc[0] < 0) return -1;
    for(i = 1; i < calib->n; i++)
    {
//        if(calib->val[i] - calib->val[i-1] < 0) break;
        if(calib->adc[i] - calib->adc[i-1] < 0) break;
    }
    if(i < calib->n) return -1;
    //反向值判断
    if(calib->flag & 0x01)
    {
        if(calib->val[MAXCALIBRATIONCOUNT] > 0) return -1;
        if(calib->adc[MAXCALIBRATIONCOUNT] > 0) return -1;
        for(i = 1; i < calib->n; i++)
        {
//            if(calib->val[i+9] - calib->val[i+10] < 0) break;
            if(calib->adc[i+MAXCALIBRATIONCOUNT-1] - calib->adc[i+MAXCALIBRATIONCOUNT] < 0) break;
        }
        if(i < calib->n) return -1;
    }

    return 0;
}

int  Calib_check(CalibData *calib)
{
	int i;
	double k;

	//正向值判断
	if(calib->val[0] < 0) return -1;
	if(calib->adc[0] < 0) return -1;
	for(i = 1; i < calib->n; i++)
	{
		if(calib->val[i] - calib->val[i-1] < 0) break;
		if(calib->adc[i] - calib->adc[i-1] < 0) break;
	}
	if(i < calib->n) return -1;
	//反向值判断
	if(calib->flag & 0x01)
	{
        if(calib->val[MAXCALIBRATIONCOUNT] > 0) return -1;
        if(calib->adc[MAXCALIBRATIONCOUNT] > 0) return -1;
		for(i = 1; i < calib->n; i++)
		{
            if(calib->val[i+MAXCALIBRATIONCOUNT-1] - calib->val[i+MAXCALIBRATIONCOUNT] < 0) break;
            if(calib->adc[i+MAXCALIBRATIONCOUNT-1] - calib->adc[i+MAXCALIBRATIONCOUNT] < 0) break;
		}
		if(i < calib->n) return -1;
	}

	return 0;
}

void Calib_init(CalibMap *map)
{
    int i, n;

    //正向
    n = map->d.n;
    if(n <= 0 || n >2*MAXCALIBRATIONCOUNT)
    {
        map->d.n = 1;
        map->k[0] = map->k[MAXCALIBRATIONCOUNT] = 1;
        map->b[0] = map->b[MAXCALIBRATIONCOUNT] = 0;
        return;
    }

    map->k[0] = map->d.val[0] / map->d.adc[0];
    map->b[0] = 0;
    for(i = 1; i < n; i++)
    {
        map->k[i] = (map->d.val[i] - map->d.val[i-1]) / (map->d.adc[i] - map->d.adc[i-1]);
        map->b[i] = map->d.val[i] - map->k[i] * map->d.adc[i];
    }

    //反向
    if(map->d.flag & 0x01)
    {
        n = map->d.n +MAXCALIBRATIONCOUNT;
        map->k[MAXCALIBRATIONCOUNT] = map->d.val[MAXCALIBRATIONCOUNT] / map->d.adc[MAXCALIBRATIONCOUNT];
        map->b[MAXCALIBRATIONCOUNT] = 0;
        for(i =MAXCALIBRATIONCOUNT+1; i < n; i++)
        {
            map->k[i] = (map->d.val[i] - map->d.val[i-1]) / (map->d.adc[i] - map->d.adc[i-1]);
            map->b[i] = map->d.val[i] - map->k[i] * map->d.adc[i];
        }
    }
    else
    {
        for(i = 0; i < n; i++)
        {
            map->k[i+MAXCALIBRATIONCOUNT] =  map->k[i];
            map->b[i+MAXCALIBRATIONCOUNT] = -map->b[i];
            map->d.adc[i+MAXCALIBRATIONCOUNT] = -map->d.adc[i];
        }
    }

}

double Calib_trans(const CalibMap *map, float adc)
{
    int i, n;
	if(map->d.flag & 0x02)
        adc = map->d.zero - adc;
    else
        adc = adc - map->d.zero;

    if(adc > 0)
    {
        n = map->d.n - 1;
        for(i = 0; i < n; i++)
        {
            if(adc < map->d.adc[i]) break;
        }
    }
    else
    {
        n = map->d.n +MAXCALIBRATIONCOUNT- 1;
        for(i =MAXCALIBRATIONCOUNT; i < n; i++)
        {
            if(adc > map->d.adc[i]) break;
        }
    }

    return adc * map->k[i] + map->b[i];
}

double Calib_inv(const CalibMap *map, double val)
{
    int i, n;

    if(val > 0)
    {
        n = map->d.n - 1;
        for(i = 0; i < n; i++)
        {
            if(val < map->d.val[i]) break;
        }
    }
    else
    {
        n = map->d.n +MAXCALIBRATIONCOUNT- 1;
        for(i =MAXCALIBRATIONCOUNT; i < n; i++)
        {
            if(val > map->d.val[i]) break;
        }
    }

    return (val - map->b[i]) / map->k[i] + map->d.zero;
}

double *Decoupling_3f(double *out, const double *in, const double *matrix)
{
    out[0] =in[0]*matrix[0] + in[0]*in[0]*matrix[9] +
            in[1]*matrix[3] + in[1]*in[1]*matrix[12] +
            in[2]*matrix[6] + in[2]*in[2]*matrix[15];

    out[1] =in[0]*matrix[1] + in[0]*in[0]*matrix[10] +
            in[1]*matrix[4] + in[1]*in[1]*matrix[13] +
            in[2]*matrix[7] + in[2]*in[2]*matrix[16];

    out[2] =in[0]*matrix[2] + in[0]*in[0]*matrix[11] +
            in[1]*matrix[5] + in[1]*in[1]*matrix[14] +
            in[2]*matrix[8] + in[2]*in[2]*matrix[17];

    return out;
}

static int s_clear_dir(char *path)
{
#ifdef WIN32
	return 0;
#elif linux
    DIR             *dp;
    unsigned int    *pi;
    char            *ptr;
    struct dirent   *info;
    int             e = 0;
	dp = opendir(path);
	if(dp == NULL) return -1;

	ptr = path + strlen(path);
	while((info = readdir(dp)))
	{
		pi = (unsigned int*)info->d_name;
		if((*pi & 0x0000ffff) == 0x2e)  continue;   //"."
		if((*pi & 0x00ffffff) == 0x2e2e)continue;   //".."

		strcpy(ptr, info->d_name);
		if(info->d_type == DT_DIR)
		{
			e |= s_clear_dir(path);
			e |= rmdir(path);
		}
		else
		{
			e |= remove(path);
		}
	}
	closedir(dp);
	*ptr = 0;
    return e;
#endif
}

int c_clear_dir(const char *path)
{
    char buf[1024];
	return s_clear_dir(strcpy(buf, path));
}

int c_check_dir()
{
#ifdef linux
	int n;
	char buf[260] = "";
	char *p;

	//更改系统路径
	n = readlink("/proc/self/exe", buf, 260);
	if(n <= 0) return -1;
	p = strrchr(buf, '/');
	if(p == NULL) return -1;
	*p = 0;
	n = chdir(buf);
	if(n != 0) return -1;

	mkdir(PROJECT_PATH, 0775);
	mkdir(HISTORY_PATH, 0775);
	mkdir(TEMP_PATH, 0755);
	c_clear_dir(TEMP_PATH);
#endif
	return 0;
}

void setTouchable(QAbstractItemView *qaiv)
{
    QScroller::grabGesture(qaiv,QScroller::LeftMouseButtonGesture);
    qaiv->setHorizontalScrollMode(QAbstractItemView::ScrollPerPixel);
    qaiv->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    qaiv->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    qaiv->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
}

void setValve(int valveFlag)
{
//	TcpFormat tf;
//	tf.h.h=CMD_HEAD;
//	tf.h.cmd=CMD_EX_W_REG;
//	tf.h.len=sizeof(CmdHead)+sizeof(int);
//    tf.b.i=valveFlag;
//    G.tData->sendCmd(0,&tf);
	CmdBody cb;
	cb.ia[0]=valveFlag;
    G.tUart->sendCmd(CMD_EX_W_REG,sizeof(int),&cb);
}

void initMassCalibMap()
{
	G.massCmMap.clear();
	for(int i=0;i<channleList.size();)
	{
		CalibMap cm;
		MassCalibrationData cd;
		cd.load(channleList[i]);
		cm.d=cd;
		Calib_init(&cm);
		G.massCmMap[channleList[i++]]=cm;
	}
}

void initMoistureCalibMap()
{
	G.moistureCmMap.clear();
	for(int i=0;i<cropList.size();++i)
	{
		CalibMap cm;
		MoistureCalibrationData mcd;
		mcd.load(cropList[i]);
		cm.d=mcd;
		Calib_init(&cm);
		G.moistureCmMap[cropList[i]]=cm;
	}
}

QString listString(QStringList qsl)
{
    int s=qsl.size();
    QString qs;
    for(int i=0;i<s;)
    {
        qs+=qsl[i++];
        if(i<s)
            qs+="、";
    }
    return qs;
}

QPixmap getTransparentPixmap(QString path)
{
	QPixmap temp(path),qp(temp.size());
	qp.fill(Qt::transparent);
	QPainter p1(&qp);
	p1.setCompositionMode(QPainter::CompositionMode_Source);
	p1.drawPixmap(0,0,temp);
	p1.setCompositionMode(QPainter::CompositionMode_DestinationIn);
	QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
	iniFile.beginGroup(APPLICATIONGROUP);
	p1.fillRect(qp.rect(),QColor(0,0,0,iniFile.value("Alpha",128).toInt()));
	iniFile.endGroup();
	p1.end();
	return qp;
}

float setPrecision(float f,int precision)
{
    long long e=pow(10,precision);
    return round(f*e)/1.0/e;
}

void updateResultFailureState()
{
    Database d;
    d.open();
    QSqlQuery qsq(d.qsd);
    qsq.exec("UPDATE "+RESULTTABLE+" SET State=3 WHERE State=1");
    d.close();
}

std::vector<int> getColumnNode(int column)
{
    int b=getMeasureColumnCount();
    column=column/b*b;//获取该列所在组的第一列，每b列为一组
    std::vector<int> columnNodeVector;
    for(int i=0;i<b;columnNodeVector.push_back(column+i++));
    return columnNodeVector;
}

void writeLog(QString log)
{
    QFile qf(QDir::currentPath()+'/'+QDate::currentDate().toString()+"_DebugInfo.log");
    qf.open(QIODevice::Append|QIODevice::Text);
    QTextStream qts(&qf);
    qts<<log<<" "<<QTime::currentTime().toString("hh:mm:ss.zzz")+'\n';
    qf.close();
}

QString transMoisture(const CalibMap *map,float adc,int precision)
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.beginGroup(APPLICATIONGROUP);
    float maxMoisture=iniFile.value("MaxMoisture").toFloat();
    iniFile.endGroup();
    float f=Calib_trans(map,adc);
    return f>maxMoisture?"nan":QString::number(f,'f',precision);
}

QString transMoisture(float value,int precision)
{
    QSettings iniFile(CONFIGFILE,QSettings::IniFormat);
    iniFile.beginGroup(APPLICATIONGROUP);
    float maxMoisture=iniFile.value("MaxMoisture").toFloat();
    iniFile.endGroup();
    return value>maxMoisture?"nan":QString::number(value,'f',precision)+"%";
}
