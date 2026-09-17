#include "formmap.h"
#include "ui_formmap.h"
#include "global.h"
#include <QDir>
#include "dataStructs/yieldmap.h"
#include <QMessageBox>
#include "dialogs/dialognewmap.h"
#include <QStandardItemModel>
#include "dialogs/dialogbatchmapblockinfo.h"
#include <QDebug>
#include "../../common/database.h"
#include <QDesktopWidget>
#include <QFileDialog>
#include <xlsxdocument.h>

FormMap::FormMap(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormMap)
{
	ui->setupUi(this);
    ui->textEditMapMark->setReadOnly(true);
    setTouchable(ui->listViewMap);
    setTouchable(ui->tableViewMap);
	ui->comboBoxView->addItems(YieldBlock::viewType);
    ui->pushButtonImportAttribute->setVisible(false);
    connect(ui->listViewMap,&QListView::clicked,this,[=](const QModelIndex &index){
        QString map=index.data().toString();
        if(currentMap.name!=map)
            loadCurrentMap(map);
    });
    connect(ui->pushButtonNewMap,&QPushButton::clicked,this,[=]{
        DialogNewMap dnm(this);
        if(dnm.exec()==QDialog::Rejected)
            return;
        QString newMap=dnm.newMapName();
        QStandardItem *qsi=new QStandardItem(newMap);
        qsi->setCheckable(true);
        ((QStandardItemModel *)ui->listViewMap->model())->appendRow(qsi);
        ui->listViewMap->setCurrentIndex(qsi->index());
        loadCurrentMap(qsi->text());
    });
    connect(ui->pushButtonSaveMap,&QPushButton::clicked,this,[=]{
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.prepare("SELECT Name FROM "+TASKTABLE+" WHERE MapName=?");
        qsq.addBindValue(currentMap.name);
        qsq.exec();
        if(qsq.next())
            QMessageBox::information(this,"提示","有任务使用了该地图，无法更新");
		else
		{
			currentMap.mark=ui->textEditMapMark->toPlainText();
			currentMap.save();
			QMessageBox::information(this,"提示","保存成功");
		}
        d.close();
    });
    connect(ui->tableViewMap,&QTableView::clicked,this,[=](const QModelIndex &index){
        int row=index.row(),column=index.column();
        if(row%2==0)
            return;
        int realRow=row/2;
        switch(ui->checkBoxMutipleCheckedMode->checkState())
        {
        case Qt::Checked:
            setBlockCheckedState(row,column,!checkedDv[realRow][column]);
            break;
        case Qt::Unchecked:
            ui->tableViewMap->setBlock(&(currentMap.blockVector)[realRow][column]);
            ui->tableViewMap->showBlockDialog(row,column);
            break;
        default:;
        }
    });
    connect(ui->tableViewMap,&MapTable::signalDataModified,this,[=](int row,int column){
        row=currentMap.blockVector.size()-row-1;
        currentMap.blockVector[row][column].updateFlag=true;
        QStandardItem *qsi=((QStandardItemModel *)ui->tableViewMap->model())->item(row*2+1,column);
        QString text=ui->comboBoxView->currentText();
        if(text==YieldBlock::viewType[1])
            qsi->setText(currentMap.blockVector[row][column].number);
        else if(text==YieldBlock::viewType[2])
            qsi->setText(currentMap.blockVector[row][column].crop);
    });
    connect(ui->checkBoxMutipleCheckedMode,&QCheckBox::stateChanged,this,[=](int state){
        QHeaderView *hqhv=ui->tableViewMap->horizontalHeader(),*vqhv=ui->tableViewMap->verticalHeader();
        switch(state)
        {
        case Qt::Checked:
            ui->pushButtonBatchSet->setEnabled(true);
            ui->checkBoxCheckAllBlock->setEnabled(true);
            connect(vqhv,&QHeaderView::sectionClicked,this,&FormMap::slotVerticalSectionClicked);
            connect(hqhv,&QHeaderView::sectionClicked,this,&FormMap::slotHorizontalSectionClicked);
            break;
        case Qt::Unchecked:
            ui->pushButtonBatchSet->setEnabled(false);
            ui->checkBoxCheckAllBlock->setEnabled(false);
            switch(ui->checkBoxCheckAllBlock->checkState())
            {
            case Qt::Unchecked:
                slotCheckBoxCheckAllBlockStateChanged(state);
                break;
            case Qt::Checked:
                ui->checkBoxCheckAllBlock->setCheckState(Qt::Unchecked);
                break;
            default:;
            }
            disconnect(vqhv,&QHeaderView::sectionClicked,this,&FormMap::slotVerticalSectionClicked);
            disconnect(hqhv,&QHeaderView::sectionClicked,this,&FormMap::slotHorizontalSectionClicked);
        }
    });
    connect(ui->pushButtonBatchSet,&QPushButton::clicked,this,[=]{
        size_t rowCount=currentMap.blockVector.size();
        for(size_t i=0;i<rowCount;++i)
            for(size_t j=0;j<currentMap.blockVector[i].size();++j)
                if(checkedDv[i][j])
                {
                    DialogBatchMapBlockInfo dbbi(this);
                    if(dbbi.exec()==QDialog::Accepted)
                    {
                        //若有区域被选中，从该格开始往后找
                        YieldBlock b=dbbi.value();
                        for(size_t t=i;i<rowCount;++i)
                        {
                            if(i>t)
                                j=0;
                            for(;j<currentMap.blockVector[i].size();++j)
                                if(checkedDv[i][j])
                                {
                                    currentMap.blockVector[i][j]=b;
                                    currentMap.blockVector[i][j].updateFlag=true;
                                    QStandardItem *qsi=((QStandardItemModel *)ui->tableViewMap->model())->item(i*2+1,j);
                                    QString text=ui->comboBoxView->currentText();
                                    if(text==YieldBlock::viewType[1])
                                        qsi->setText(currentMap.blockVector[i][j].number);
                                    else if(text==YieldBlock::viewType[2])
                                        qsi->setText(currentMap.blockVector[i][j].crop);
                                }
                        }
                    }
                    return;
                }
        QMessageBox::information(this,"提示","未选中区域");
    });
    connect(ui->checkBoxCheckAllBlock,&QCheckBox::stateChanged,this,&FormMap::slotCheckBoxCheckAllBlockStateChanged);
    QStandardItemModel *qsim=new QStandardItemModel;
    ui->listViewMap->setModel(qsim);
    connect(ui->pushButtonDeleteMap,&QPushButton::clicked,this,[=]{
        if(QMessageBox::question(this,"提示","删除地图会同时删除所有关联任务及其历史记录，确定吗？")==QMessageBox::No)
            return;
        QString sql="DELETE FROM "+MAPTABLE+" WHERE Name IN (";
        QStringList qsl;
        for(int i=0;i<qsim->rowCount();)
        {
            QStandardItem *qsi=qsim->item(i);
            if(qsi->checkState()!=Qt::Checked)
            {
                ++i;
                continue;
            }
            if(qsl.size()>0)
                sql+=',';
            sql+='?';
            qsl.append(qsi->text());
            ui->listViewMap->model()->removeRow(i);
        }
        sql+=')';
        Database d;
        d.open();
        QSqlQuery qsq(d.qsd);
        qsq.exec("PRAGMA foreign_keys=ON");
        qsq.prepare(sql);
        for(int i=0;i<qsl.size();qsq.addBindValue(qsl[i++]));
        qsq.exec();
        d.close();
        QMessageBox::information(this,"提示","删除成功");
        currentMap.name.clear();
        ui->labelCreateTime->clear();
        ui->labelModifyTime->clear();
        ui->textEditMapMark->clear();
        ui->textEditMapMark->setReadOnly(true);
        ui->checkBoxMutipleCheckedMode->setEnabled(false);
		ui->pushButtonImportAttribute->setEnabled(false);
        ui->checkBoxMutipleCheckedMode->setCheckState(Qt::Unchecked);
        ((QStandardItemModel *)ui->tableViewMap->model())->clear();
    });
	connect(ui->pushButtonImportAttribute,&QPushButton::clicked,this,[=]{
		QString text=ui->comboBoxView->currentText();
        QString file=QFileDialog::getOpenFileName(this,"选择"+text+"文件","","Excel 工作簿(*.xlsx)");
        if(file.isEmpty())
            return;
        QXlsx::Document d(file);
        if(text==Block::viewType[1])
        {
			for(size_t i=0;i<currentMap.blockVector.size();i++)
                for(size_t j=0;j<currentMap.blockVector[i].size();currentMap.blockVector[i][j++].updateFlag=true)
                    currentMap.blockVector[i][j].number=d.read(i+2,j+2).toString();
			currentMap.saveNumber();
		}
		else if(text==Block::viewType[2])
		{
			for(size_t i=0;i<currentMap.blockVector.size();i++)
                for(size_t j=0;j<currentMap.blockVector[i].size();currentMap.blockVector[i][j++].updateFlag=true)
                    currentMap.blockVector[i][j].crop=d.read(i+2,j+2).toInt();
			currentMap.saveCrop();
		}
        slotComboBoxViewCurrentTextChanged(text);
	});
    connect(ui->comboBoxView,&QComboBox::currentTextChanged,this,&FormMap::slotComboBoxViewCurrentTextChanged);
    connect(ui->pushButtonImport,&QPushButton::clicked,this,[=]{
		QStringList qsl=QFileDialog::getOpenFileNames(this,"选择文件","","Excel 工作簿(*.xlsx)"),existList;
		YieldMap m;
		QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewMap->model();
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		bool b=false;
		for(int i=0;i<qsl.size();i++)
		{
            QString mapName=QFileInfo(qsl[i]).fileName().section("任务",1,1).section(".",0,0);
			qsq.prepare("SELECT Name FROM "+MAPTABLE+" WHERE Name=?");
			qsq.addBindValue(mapName);
			qsq.exec();
			if(qsq.next())
				existList.append(mapName);
			else
			{
				QStandardItem *qsi=new QStandardItem(mapName);
				qsi->setCheckable(true);
				qsim->appendRow(qsi);
				m.importFromXlsx(qsl[i],mapName);
				b=true;
			}
		}
		d.close();
		if(existList.size()>0)
			QMessageBox::information(this,"提示","地图"+listString(existList)+"已存在");
		if(b)
			QMessageBox::information(this,"提示","导入成功");
//        QStringList qsl=QFileDialog::getOpenFileNames(this,"选择文件","","Excel 工作簿(*.xlsx)"),existList;
//        Map m;
//		QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewMap->model();
//		Database d;
//		d.open();
//		QSqlQuery qsq(d.qsd);
//		for(int i=0;i<qsl.size();i++)
//        {
//			QString mapName=QFileInfo(qsl[i]).fileName().section(" ",1,1).section(".",0,0);;
//            QStandardItem *qsi=new QStandardItem(mapName);
//            qsi->setCheckable(true);
//			qsim->appendRow(qsi);
//			qsq.prepare("SELECT Name FROM "+MAPTABLE+" WHERE Name=?");
//			qsq.addBindValue(mapName);
//			qsq.exec();
//			if(qsq.next())
//				existList.append(qsl[i]);
//			else
//				m.importFromXlsx(qsl[i],mapName);
//        }
//		d.close();
    });
    connect(ui->pushButtonExport,&QPushButton::clicked,this,[=]{
        QStringList qsl=checkedMapList();
        if(qsl.isEmpty())
        {
            QMessageBox::information(this,"提示","未选中地图");
            return;
        }
        QString dirPath=QFileDialog::getExistingDirectory(this,"请选择文件保存路径");
		if(dirPath.isEmpty())
			return;
		QStringList existMapList,failedList,successList;
        for(int i=0;i<qsl.size();)
            if(QFile::exists(dirPath+"/"+qsl[i]+".xlsx"))
            {
                existMapList.append(qsl[i]);
                qsl.removeOne(qsl[i]);
            }
            else
                i++;
        if(existMapList.size()>0)
            QMessageBox::information(this,"信息","无法导出"+listString(existMapList)+"，文件已存在");
        int qsls=qsl.size();
        for(int i=0;i<qsls;i++)
        {
			YieldMap m;
			m.load(qsl[i]);
			(m.exportToXlsx(dirPath)?successList:failedList).append(qsl[i++]);
        }
        if(failedList.size()>0)
            QMessageBox::information(this,"信息","地图"+listString(failedList)+"导出失败");
		if(successList.size()>0)
            QMessageBox::information(this,"信息","导出完成");
    });
    refreshList();
}

FormMap::~FormMap()
{
	delete ui;
}

void FormMap::refreshList()
{
	QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewMap->model();
	qsim->clear();
	Database d;
	d.open();
	QSqlQuery qsq(d.qsd);
	for(qsq.exec("SELECT Name FROM "+MAPTABLE);qsq.next();)
	{
        QStandardItem *qsi=new QStandardItem(qsq.value("Name").toString());
		qsi->setCheckable(true);
		qsim->appendRow(qsi);
	}
	d.close();
}

void FormMap::loadCurrentMap(QString map)
{
	currentMap.load(map);
	ui->labelCreateTime->setText(currentMap.createTime);
	ui->labelModifyTime->setText(currentMap.modifyTime);
	ui->textEditMapMark->setText(currentMap.mark);
	ui->textEditMapMark->setReadOnly(false);
	ui->checkBoxMutipleCheckedMode->setEnabled(true);
    ui->pushButtonSaveMap->setEnabled(true);
	ui->pushButtonImportAttribute->setEnabled(true);
    QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
    model->clear();
	std::vector<std::deque<bool>>().swap(checkedDv);
    size_t rowCount=currentMap.blockVector.size(),columnCount=currentMap.blockVector[0].size();
    for(size_t i=0;i<rowCount;ui->tableViewMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
    {
        std::deque<bool> bd;
        for(size_t j=0;j<columnCount;j++)
        {
            QStandardItem *qsi=new QStandardItem;
            model->setItem(i,j,qsi);
            qsi->setTextAlignment(Qt::AlignCenter);
            ui->tableViewMap->setItemCrop(i,j,currentMap.blockVector[i][j].crop);
            bd.push_back(false);
        }
        model->setVerticalHeaderItem(i,new QStandardItem("排"+QString::number(rowCount-i)));
        checkedDv.push_back(bd);
    }
    for(size_t i=0;i<rowCount+1;)
    {
        int r=2*i++;
        model->insertRow(r);
        for(size_t j=0;j<columnCount;)
        {
            QStandardItem *item=new QStandardItem;
            item->setBackground(Qt::gray);
            model->setItem(r,j++,item);
        }
        model->setVerticalHeaderItem(r,new QStandardItem);
        ui->tableViewMap->setRowHeight(r,MAPTABLEAISLEHEIGHT);
    }
    for(size_t i=0;i<columnCount;ui->tableViewMap->setColumnWidth(i++,MAPTABLECELLWIDTH))
        model->setHorizontalHeaderItem(i,new QStandardItem("列"+QString::number(i+1)));
    slotComboBoxViewCurrentTextChanged(ui->comboBoxView->currentText());
}

void FormMap::slotVerticalSectionClicked(int logicalIndex)
{
	bool f=false;
	int columnCount=currentMap.blockVector[0].size(),row=(logicalIndex-1)/2;
	for(int i=0;i<columnCount;)
		if(!checkedDv[row][i++])
		{
			f=true;
			break;
		}
	for(int i=0;i<columnCount;++i)
		setBlockCheckedState(logicalIndex,i,f);
}

void FormMap::slotHorizontalSectionClicked(int logicalIndex)
{
	bool f=false;
	int rowCount=currentMap.blockVector.size();
	for(int i=0;i<rowCount;)
		if(!checkedDv[i++][logicalIndex])
		{
			f=true;
			break;
		}
	for(int i=0;i<rowCount;++i)
		setBlockCheckedState(2*i+1,logicalIndex,f);
}

void FormMap::setBlockCheckedState(int row,int column,bool b)
{
    checkedDv[row/2][column]=b;
    if(b)
        ((QStandardItemModel *)ui->tableViewMap->model())->item(row,column)->setBackground(QPixmap(":/resources/images/block-checked.png").scaled(ui->tableViewMap->columnWidth(column),ui->tableViewMap->rowHeight(row)));
    else
        ui->tableViewMap->setItemCrop(row,column,currentMap.blockVector[row/2][column].crop);
}

void FormMap::slotCheckBoxCheckAllBlockStateChanged(int state)
{
	for(size_t i=0;i<currentMap.blockVector.size();++i)
		for(size_t j=0;j<currentMap.blockVector[i].size();++j)
			switch(state)
			{
			case Qt::Checked:
				if(!checkedDv[i][j])
                    setBlockCheckedState(i*2+1,j,true);
				break;
			case Qt::Unchecked:
				if(checkedDv[i][j])
                    setBlockCheckedState(i*2+1,j,false);
                break;
            default:;
			}
}

void FormMap::slotComboBoxViewCurrentTextChanged(const QString &text)
{
    if(currentMap.name.isEmpty())
        return;
    int rowCount=currentMap.blockVector.size();
    for(int i=0;i<rowCount;i++)
        for(size_t j=0;j<currentMap.blockVector[i].size();j++)
        {
            QStandardItem *qsi=((QStandardItemModel *)ui->tableViewMap->model())->item(2*i+1,j);
            if(text==YieldBlock::viewType[0])
            {
                qsi->setText(QString::number(rowCount-i)+','+QString::number(j+1));
                ui->pushButtonImportAttribute->setVisible(false);
            }
            else
            {
                ui->pushButtonImportAttribute->setVisible(true);
                if(text==YieldBlock::viewType[1])
                    qsi->setText(currentMap.blockVector[i][j].number);
                else if(text==YieldBlock::viewType[2])
                    qsi->setText(currentMap.blockVector[i][j].crop);
            }
        }
}

QStringList FormMap::checkedMapList()
{
    QStringList qsl;
    QStandardItemModel *model=(QStandardItemModel *)ui->listViewMap->model();
    for(int i=0;i<model->rowCount();)
    {
        QStandardItem *qsi=model->item(i++);
        if(qsi->checkState()==Qt::Checked)
            qsl.append(qsi->text());
    }
    return qsl;
}
