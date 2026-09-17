#ifndef YIELDMAP_H
#define YIELDMAP_H
#define MAPDIRECTORY QString("maps")

#include "yieldblock.h"

class YieldMap:public Map
{
public:
    static bool isExist(QString name);

	YieldMap();
    void load(QString qs);
    void save();
    bool exportToXlsx(QString dir);
	void importFromXlsx(QString file,QString name);
	void saveNumber();
	void saveCrop();
    void initSheet(QXlsx::Document &d);

    std::vector<std::vector<YieldBlock>> blockVector;

//    bool operator==(const YieldMap &m)
//    {
//        size_t row=blockVector.size();
//        if(row!=m.blockVector.size())
//            return false;
//        if(row>0)
//            for(size_t i=0;i<row;++i)
//            {
//                size_t column=blockVector[i].size();
//                if(column!=m.blockVector[i].size())
//                    return false;
//                for(size_t j=0;j<column;++j)
//                    if(blockVector[i][j].crop!=m.blockVector[i][j].crop||blockVector[i][j].number!=m.blockVector[i][j].number)
//                        return false;
//            }
//        return createTime==m.createTime&&modifyTime==m.modifyTime&&mark==m.mark&&name==m.name;
//    }

//    bool operator!=(const YieldMap &m)
//    {
//        return !(*this==m);
//    }
};

#endif // YIELDMAP_H
