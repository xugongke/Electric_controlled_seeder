#ifndef DATABASE_H
#define DATABASE_H
#define DATABASE "data.db"
#define DATABASECONNECTION "dbconnection"

#include <QSqlQuery>

class Database
{
	static int usedCount;
public:
	QSqlDatabase qsd;
	Database();
	void open();
	void close();
};

int count(QSqlQuery qsq);

#endif // DATABASE_H
