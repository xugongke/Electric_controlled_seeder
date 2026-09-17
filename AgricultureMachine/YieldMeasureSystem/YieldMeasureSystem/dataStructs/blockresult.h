#ifndef BLOCKRESULT_H
#define BLOCKRESULT_H

#include <QString>
#include <vector>

class BlockResult
{
public:
    static std::vector<BlockResult> loadAll();
    static std::vector<BlockResult> loadAll(QString task);
    BlockResult();
    void save();
    void load();

    QString taskName;
    int row;
    int column;
    QString startTime;
    QString endTime;
    QString mark;
    float moisture;
    float mass;
    float unitWeight;
    QString crop;
    int state;
};

#endif // BLOCKRESULT_H
