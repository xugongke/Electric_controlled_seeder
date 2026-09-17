#ifndef MASSCALIBRATIONDATA_H
#define MASSCALIBRATIONDATA_H

#include <QString>
#include <QSqlQuery>
#include "global.h"

class MassCalibrationData:public CalibData
{
public:
	MassCalibrationData();
	void load(QString channle);
	void update();

	static bool existData(QString channle);

	bool operator==(const MassCalibrationData &cd)
	{
		if(n!=cd.n||flag!=cd.flag)
			return false;
		bool unidirectional=(flag&1)==0;
		for(int i=0;i<n;++i)
		{
			if(val[i]!=cd.val[i]||adc[i]!=cd.adc[i])
				return false;
			if(unidirectional)
				continue;
			int t=i+10;
			if(val[t]!=cd.val[t]||adc[t]!=cd.adc[t])
				return false;
		}
		return channle==cd.channle&&range==cd.range&&zero==cd.zero;
	}

	bool operator!=(const MassCalibrationData &cd)
	{
		return !(*this==cd);
	}

	QString channle;
	float range;
};

#endif // MASSCALIBRATIONDATA_H
