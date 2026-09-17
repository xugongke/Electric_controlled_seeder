#ifndef SETTINGSHANDLE_H
#define SETTINGSHANDLE_H
#define DEFAULTMEASURECOLUMNCOUNT "1"

#include <QString>

void setMeasureColumnCount(int measureColumnCount);
int getMeasureColumnCount();
void setMoistureValueMode(char mode);
char getMoistureValueMode();
void setPort(QString port);
QString getPort();

#endif // SETTINGSHANDLE_H
