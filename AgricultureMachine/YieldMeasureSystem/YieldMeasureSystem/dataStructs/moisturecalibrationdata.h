#ifndef MOISTURECALIBRATIONDATA_H
#define MOISTURECALIBRATIONDATA_H

#include <QSqlQuery>
#include "global.h"

class MoistureCalibrationData:public CalibData
{
    //没有(0,0)，至少标定2点
public:
	MoistureCalibrationData();
	void load(QString crop);
	void update();
	bool isValid(float f);//传感器读数是否在标定范围内，只有k为-时才用

	static bool existData(QString crop);

	bool operator==(const MoistureCalibrationData &mcd)
	{
		if(n!=mcd.n)
			return false;
		for(int i=0;i<n;++i)
			if(val[i]!=mcd.val[i]||adc[i]!=mcd.adc[i])
				return false;
		return crop==mcd.crop;
	}

	bool operator!=(const MoistureCalibrationData &mcd)
	{
		return !(*this==mcd);
	}

	QString crop;
};

#endif // MOISTURECALIBRATIONDATA_H
