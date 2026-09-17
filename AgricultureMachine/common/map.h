#ifndef MAP_H
#define MAP_H
#define MAPTABLECELLHEIGHT 80
#define MAPTABLECELLWIDTH 80
#define MAPTABLEAISLEHEIGHT MAPTABLECELLHEIGHT/2
#define MAPTABLEAISLEWIDTH MAPTABLECELLWIDTH/2

#include <vector>
#include <QString>
#include "protocol.h"
#include <xlsxdocument.h>

struct Block
{
	QString number;
	int density;
	bool sowSeed;
    bool updateFlag;
	static QStringList viewType;
};

struct RowAttributes
{
	int length;//排长 cm
};

struct Aisle
{
	int length;//过道长 cm
};

class Map
{
public:
    static bool isExist(QString name);


	Map();
	void load(QString qs);
	void save();
	bool exportToXlsx(QString dir);
	void importFromXlsx(QString file,QString name);
	int blockEachTrip();//每趟几个小区
	std::vector<int> getColumnNode(int column);
    u32 GetZhuShu(u32 density, u32 cell_len, u16 hju);//密度 行长 行间距
    u32 GetZhuShu(int row,int column);
	float seedGap(int row,int column);//株距
	void loadABLine();
	void saveABLine(QString ablName="");
	void clearABLine();
	int columnWidth();
	int columnOffset(int column,bool);//true列左边线，false右边线
	int rowToOffset(int row);
    int offsetToRow(int offset);//-999999：过道，-1：0过道前，rowCount：最后一个过道后
	UserParaType getUserParameter();
	int forwardSowStartPosition(int row);//排上沿到0排上沿的距离
	int backwardSowStartPosition(int row);//排下沿到0排上沿的距离
	int startPosition(int row,bool tractorDirection);
	int centralOffset(int column);//该列对应组的中点距离AB线的偏移，column为该组第一列
	void saveNumber();
	void saveDensity();
    void initSheet(QXlsx::Document &d);

	BDParaType_st abLine;
	QString createTime,modifyTime,mark,name;
	std::vector<std::vector<Block>> blockVector;
	std::vector<RowAttributes> rowAttributesVector;
	std::vector<Aisle> aisleVector;
	int blockColumn;//小区行数，每小区一趟几列种子
	int machineColumn;//机器行数，一趟播几列种子
	int seedColumnGap;//种子行间距
	bool abLineDirection;
	int aRow;//a点所在排，实际位置根据AB线方向决定，+：排上沿，-：排下沿（均不包含过道）
	int aColumn;//a点所在区域首列，非AB线实际所在列（实际在区域列方向的中心，即(区域首列+区域末列)/2的位置）
    QString abLineName;
};

#endif // MAP_H
