#include "database.h"

int Database::usedCount=0;

Database::Database()
{
	qsd=QSqlDatabase::contains(DATABASECONNECTION)?QSqlDatabase::database(DATABASECONNECTION):QSqlDatabase::addDatabase("QSQLITE",DATABASECONNECTION);
	qsd.setDatabaseName(DATABASE);
}

void Database::open()
{
	if(usedCount++==0)
		qsd.open();
}

void Database::close()
{
	if(--usedCount==0)
		qsd.close();
}

int count(QSqlQuery qsq)
{
	qsq.last();
	int c=qsq.at()+1;
	qsq.first();
	qsq.previous();
	return c;
}
