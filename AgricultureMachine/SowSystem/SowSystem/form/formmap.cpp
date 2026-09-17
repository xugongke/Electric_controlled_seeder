#include "formmap.h"
#include "ui_formmap.h"
#include "global.h"
#include "dialog/dialognewmap.h"
#include <QStandardItemModel>
#include "../../common/database.h"
#include <QMessageBox>
#include <QDebug>
#include "dialog/dialogrowattribute.h"
#include "dialog/dialogaisle.h"
#include "dialog/dialogbatchblockinfo.h"
#include <xlsxdocument.h>
#include <QFileDialog>
#include <QFileInfo>
#include "dialog/dialogchooseabline.h"
#include "dialog/dialogabline.h"
#include <QScreen>

FormMap::FormMap(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormMap)
{
	ui->setupUi(this);
	setFocus();
	ui->textEditMapMark->setReadOnly(true);
	setTouchable(ui->listViewMap);
	setTouchable(ui->tableViewMap);
	ui->tableViewMap->setModel(new QStandardItemModel);
	ui->listViewMap->setModel(new QStandardItemModel);
	ui->comboBoxView->addItems(Block::viewType);
    ui->pushButtonImportAttribute->setVisible(false);
    dsbi=new DialogSingleBlockInfo(this);
	connect(ui->listViewMap,&QListView::clicked,this,[=](const QModelIndex &index){
		QString map=index.data().toString();
		if(currentMap.name!=map)
			loadCurrentMap(map);
	});
	connect(ui->comboBoxView,&QComboBox::currentTextChanged,this,&FormMap::slotComboBoxViewCurrentTextChanged);
	connect(ui->pushButtonNewMap,&QPushButton::clicked,this,[=]{
		DialogNewMap dnm(this);
		if(dnm.exec()==QDialog::Rejected)
			return;
		QString newMap=dnm.newMapName();
		QStandardItem *qsi=new QStandardItem(newMap);
		qsi->setCheckable(true);
		((QStandardItemModel *)ui->listViewMap->model())->appendRow(qsi);
		ui->listViewMap->setCurrentIndex(qsi->index());
		loadCurrentMap(newMap);
	});
	connect(ui->pushButtonClearABLine,&QPushButton::clicked,this,[=](bool b){
		if(!currentMap.abLineName.isEmpty()&&QMessageBox::question(this,"提示","确定要删除AB线吗？")==QMessageBox::Yes)
		{
			currentMap.clearABLine();
			ui->pushButtonABLine->setText("无");
		}
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
		int row=index.row();
		if(row%2==0)
			return;
		QPoint qp(ui->tableViewMap->mapToGlobal(QPoint(0,0)));//转换为相对于屏幕左上角坐标
        int realRow=row/2,column=index.column(),margin,x,y,screenWidth=QGuiApplication::primaryScreen()->geometry().width(),dialogWidth;
		switch(ui->checkBoxMutipleCheckedMode->checkState())
		{
		case Qt::Checked:
			setBlockCheckedState(realRow,column,!checkedDv[realRow][column]);
			break;
		case Qt::Unchecked:
            dsbi->show();
            margin=dsbi->margin();
            dialogWidth=dsbi->width();
            x=qp.x()+ui->tableViewMap->columnViewportPosition(column)+ui->tableViewMap->verticalHeader()->width()-(dialogWidth-MAPTABLECELLWIDTH)/2;
            y=qp.y()+ui->tableViewMap->rowViewportPosition(row)+ui->tableViewMap->horizontalHeader()->height()+margin-dsbi->height();
            dsbi->setCoordinate(currentMap.blockVector.size()-realRow-1,column);
            dsbi->setBlock(&(currentMap.blockVector[realRow][column]));
			if(x<0)
				x=-margin;
			else if(x-margin+dialogWidth>screenWidth)
				x=screenWidth-dialogWidth+margin;
			if(y<0)
				y=-margin;
            dsbi->move(x,y);
			break;
		default:;
		}
	});
    connect(dsbi,&DialogSingleBlockInfo::signalSowSeedModified,this,[=](int row,int column){
        row=currentMap.blockVector.size()-row-1;
		currentMap.blockVector[row][column].sowSeed?((QStandardItemModel *)ui->tableViewMap->model())->item(row*2+1,column)->setBackground(Qt::NoBrush):((QStandardItemModel *)ui->tableViewMap->model())->item(row*2+1,column)->setBackground(Qt::gray);
        currentMap.blockVector[row][column].updateFlag=true;
	});
    connect(dsbi,&DialogSingleBlockInfo::signalDataModified,this,[=](int row,int column){
        row=currentMap.blockVector.size()-row-1;
        std::vector<int> v=currentMap.getColumnNode(column);
        for(size_t i=0;i<v.size();i++)
        {
            currentMap.blockVector[row][v[i]].density=currentMap.blockVector[row][v[i]].density;
            currentMap.blockVector[row][column].updateFlag=true;
            QString text=ui->comboBoxView->currentText();
            if(text==Block::viewType[1])
                ((QStandardItemModel *)ui->tableViewMap->model())->item(row*2+1,column)->setText(currentMap.blockVector[row][column].number);
            else if(text==Block::viewType[2])
                ((QStandardItemModel *)ui->tableViewMap->model())->item(row*2+1,column)->setText(QString::number(currentMap.blockVector[row][column].density));
        }
	});
	connect(ui->pushButtonRowAttribute,&QPushButton::clicked,this,[=]{
		DialogRowAttribute dra(currentMap.rowAttributesVector,this);
		if(dra.exec()==QDialog::Accepted)
			currentMap.rowAttributesVector=dra.value();
	});
	connect(ui->pushButtonAisle,&QPushButton::clicked,this,[=]{
		DialogAisle da(currentMap.aisleVector,this);
		if(da.exec()==QDialog::Accepted)
			currentMap.aisleVector=da.value();
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
	connect(ui->checkBoxCheckAllBlock,&QCheckBox::stateChanged,this,&FormMap::slotCheckBoxCheckAllBlockStateChanged);
	connect(ui->pushButtonBatchSet,&QPushButton::clicked,this,[=]{
		size_t rowCount=currentMap.blockVector.size();
		for(size_t i=0;i<rowCount;++i)
			for(size_t j=0;j<currentMap.blockVector[i].size();++j)
				if(checkedDv[i][j])
				{
					DialogBatchBlockInfo dbbi(this);
					if(dbbi.exec()==QDialog::Accepted)
					{
						//若有区域被选中，从该格开始往后找
						Block b=dbbi.value();
						for(size_t t=i;i<rowCount;++i)
						{
							if(i>t)
								j=0;
							for(;j<currentMap.blockVector[i].size();++j)
								if(checkedDv[i][j])
								{
                                    currentMap.blockVector[i][j].updateFlag=true;
									currentMap.blockVector[i][j].density=b.density;
									currentMap.blockVector[i][j].sowSeed=b.sowSeed;
                                    QStandardItem *item=((QStandardItemModel *)ui->tableViewMap->model())->item(2*i+1,j);
                                    currentMap.blockVector[i][j].sowSeed?item->setBackground(Qt::NoBrush):item->setBackground(Qt::gray);
                                    QString text=ui->comboBoxView->currentText();
                                    if(text==Block::viewType[1])
                                        item->setText(currentMap.blockVector[i][j].number);
                                    else if(text==Block::viewType[2])
                                        item->setText(QString::number(currentMap.blockVector[i][j].density));
								}
						}
					}
					return;
				}
		QMessageBox::information(this,"提示","未选中区域");
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
                    currentMap.blockVector[i][j].density=d.read(i+2,j+2).toInt();
            currentMap.saveDensity();
		}
        slotComboBoxViewCurrentTextChanged(text);
	});
	connect(ui->pushButtonDeleteMap,&QPushButton::clicked,this,[=]{
		QString sql="DELETE FROM "+MAPTABLE+" WHERE Name IN (";
		QStringList qsl,taskMapList;
		QStandardItemModel *model=(QStandardItemModel *)ui->listViewMap->model();
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		for(int i=0;i<model->rowCount();i++)
		{
			QStandardItem *qsi=model->item(i);
			if(qsi->checkState()!=Qt::Checked)
				continue;
			if(qsl.size()>0)
				sql+=',';
			sql+='?';
			qsq.prepare("SELECT Name FROM "+TASKTABLE+" WHERE MapName=?");
			QString mapName=qsi->text();
			qsq.addBindValue(mapName);
			qsq.exec();
			(qsq.next()?taskMapList:qsl).append(mapName);
		}
		if(qsl.isEmpty()&&taskMapList.isEmpty())
		{
			QMessageBox::information(this,"提示","未选中地图");
			return;
		}
		if(taskMapList.size()>0)
			QMessageBox::information(this,"信息","地图"+listString(taskMapList)+"有相关联的任务，不能删除");
		for(int i=0;i<model->rowCount();)
		{
			QStandardItem *qsi=model->item(i);
			if(qsi->checkState()!=Qt::Unchecked&&qsl.contains(qsi->text()))
				model->removeRow(i);
			else
				i++;
		}
		sql+=')';
		qsq.exec("PRAGMA foreign_keys=ON");
		qsq.prepare(sql);
		int s=qsl.size();
		for(int i=0;i<s;qsq.addBindValue(qsl[i++]));
		qsq.exec();
		d.close();
		if(s>0)
			QMessageBox::information(this,"提示","删除成功");
		currentMap.name.clear();
		ui->labelCreateTime->clear();
		ui->labelModifyTime->clear();
		ui->textEditMapMark->clear();
		ui->textEditMapMark->setReadOnly(true);
		ui->checkBoxMutipleCheckedMode->setEnabled(false);
		ui->checkBoxMutipleCheckedMode->setCheckState(Qt::Unchecked);
		ui->pushButtonRowAttribute->setEnabled(false);
		ui->pushButtonAisle->setEnabled(false);
		ui->pushButtonImportAttribute->setEnabled(false);
        ui->pushButtonABLine->setText("");
        ui->pushButtonABLine->setEnabled(false);
		ui->pushButtonClearABLine->setEnabled(false);
		((QStandardItemModel *)ui->tableViewMap->model())->clear();
		ui->pushButtonSaveMap->setEnabled(false);
        ui->pushButtonImportABLine->setEnabled(false);
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
		for(int i=0;i<qsl.size();)
		{
			Map m;
			m.load(qsl[i]);
			m.loadABLine();
			(m.exportToXlsx(dirPath)?successList:failedList).append(qsl[i++]);
		}
		if(failedList.size()>0)
			QMessageBox::information(this,"信息","地图"+listString(failedList)+"导出失败");
		if(successList.size()>0)
			QMessageBox::information(this,"信息","导出完成");
	});
	connect(ui->pushButtonImport,&QPushButton::clicked,this,[=]{
		QStringList qsl=QFileDialog::getOpenFileNames(this,"选择文件","","Excel 工作簿(*.xlsx)"),existList;
		Map m;
		QStandardItemModel *qsim=(QStandardItemModel *)ui->listViewMap->model();
		Database d;
		d.open();
		QSqlQuery qsq(d.qsd);
		bool b=false;
		for(int i=0;i<qsl.size();i++)
		{
            QString mapName=QFileInfo(qsl[i]).fileName().section("地图",1,1).section(".",0,0);
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
	});
    connect(ui->pushButtonImportABLine,&QPushButton::clicked,this,[=]{
        DialogChooseABLine dca(currentMap.name,this);
        if(dca.exec()==QDialog::Accepted)
        {
            Database d;
            d.open();
            QSqlQuery qsq(d.qsd);
			qsq.prepare("UPDATE "+MAPTABLE+" SET ARow=?,AColumn=?,ABLineDirection=?,ABLineName=? WHERE Name=?");
			bool b=dca.getDirection();
            int aRow=b?0:currentMap.blockVector.size()-1,aColumn=dca.getColumn();
            qsq.addBindValue(aRow);
            qsq.addBindValue(aColumn);
            qsq.addBindValue(b);
            QString abLineName=dca.getABLineName();
            qsq.addBindValue(abLineName);
            qsq.addBindValue(currentMap.name);
            if(qsq.exec())
            {
                currentMap.abLineName=abLineName;
                currentMap.aRow=aRow;
                currentMap.aColumn=aColumn;
                ui->pushButtonABLine->setText(abLineName);
            }
			d.close();
			currentMap.loadABLine();
        }
    });
    connect(ui->pushButtonABLine,&QPushButton::clicked,this,[=]{
        if(currentMap.abLineName.isEmpty())
            return;
        DialogABLine da(currentMap.abLineName,this);
        da.setPosition(currentMap.aRow,currentMap.aColumn,currentMap.abLineDirection);
		da.setGroupBox2Visible(true);
        da.exec();
    });
	refreshList();
}

FormMap::~FormMap()
{
	delete ui;
}

void FormMap::loadCurrentMap(QString map)
{
	currentMap.load(map);
    currentMap.loadABLine();
	ui->labelCreateTime->setText(currentMap.createTime);
	ui->labelModifyTime->setText(currentMap.modifyTime);
	ui->labelBlockColumnCount->setNum(currentMap.blockColumn);
	ui->labelMachineColumnCount->setNum(currentMap.machineColumn);
	ui->labelBlockEachTime->setNum(currentMap.machineColumn/currentMap.blockColumn);
	ui->labelSeedColumnGap->setText(QString::number(currentMap.seedColumnGap/100.0)+"m");
    size_t columnCount=currentMap.blockVector[0].size();
    ui->labelSize->setText(QString::number(currentMap.blockVector.size())+"排×"+QString::number(columnCount)+"列");
	ui->labelColumnWidth->setText(QString::number(currentMap.columnWidth()/100.0,'f',2)+"m");
    ui->pushButtonABLine->setEnabled(true);
    ui->pushButtonABLine->setText(currentMap.abLineName.isEmpty()?"无":currentMap.abLineName);
	ui->textEditMapMark->setText(currentMap.mark);
	ui->textEditMapMark->setReadOnly(false);
	ui->checkBoxMutipleCheckedMode->setEnabled(true);
	ui->pushButtonSaveMap->setEnabled(true);
	ui->pushButtonRowAttribute->setEnabled(true);
	ui->pushButtonAisle->setEnabled(true);
	ui->pushButtonClearABLine->setEnabled(true);
	ui->pushButtonImportAttribute->setEnabled(true);
    ui->pushButtonImportABLine->setEnabled(true);
	QStandardItemModel *model=(QStandardItemModel *)ui->tableViewMap->model();
	model->clear();
	std::vector<std::deque<bool>>().swap(checkedDv);
    int rowCount=currentMap.blockVector.size();
    for(int i=0;i<rowCount;ui->tableViewMap->setRowHeight(i++,MAPTABLECELLHEIGHT))
	{
		std::deque<bool> bd;
		for(size_t j=0;j<columnCount;bd.push_back(false))
		{
			QStandardItem *qsi=new QStandardItem;
            qsi->setTextAlignment(Qt::AlignCenter);
			model->setItem(i,j,qsi);
			currentMap.blockVector[i][j++].sowSeed?qsi->setBackground(Qt::NoBrush):qsi->setBackground(Qt::gray);
		}
        model->setVerticalHeaderItem(i,new QStandardItem("排"+QString::number(rowCount-i)));
		checkedDv.push_back(bd);
	}
    for(size_t i=0;i<columnCount;i++)
        model->setHorizontalHeaderItem(i,new QStandardItem("列"+QString::number(i+1)));
	for(size_t i=0;i<currentMap.aisleVector.size();)
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
    for(int i=0;i<model->columnCount();ui->tableViewMap->setColumnWidth(i++,MAPTABLECELLWIDTH));
	slotComboBoxViewCurrentTextChanged(ui->comboBoxView->currentText());
}

void FormMap::setBlockCheckedState(int row,int column,bool b)
{//row为小区实际排号，不包括地图中过道行
	int tableRow=2*row+1;
	checkedDv[row][column]=b;
	b?((QStandardItemModel *)ui->tableViewMap->model())->item(tableRow,column)->setBackground(QPixmap(":/resource/image/block-checked.png").scaled(ui->tableViewMap->columnWidth(column),ui->tableViewMap->rowHeight(tableRow))):currentMap.blockVector[row][column].sowSeed?((QStandardItemModel *)ui->tableViewMap->model())->item(tableRow,column)->setBackground(Qt::NoBrush):((QStandardItemModel *)ui->tableViewMap->model())->item(tableRow,column)->setBackground(Qt::gray);
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
		QString mapName=qsq.value("Name").toString();
		QStandardItem *qsi=new QStandardItem(mapName);
		qsi->setCheckable(true);
		qsim->appendRow(qsi);
	}
	d.close();
}

void FormMap::slotVerticalSectionClicked(int logicalIndex)
{
	if(logicalIndex%2==0)
		return;
	bool f=false;
	int realRow=logicalIndex/2,columnCount=ui->tableViewMap->model()->columnCount();
	for(int i=1;i<columnCount;++i)
		if(checkedDv[realRow][i]!=checkedDv[realRow][i-1])
		{
			f=true;
			break;
		}
	for(int i=0;i<columnCount;++i)
		setBlockCheckedState(realRow,i,f?true:!checkedDv[realRow][i]);
}

void FormMap::slotHorizontalSectionClicked(int logicalIndex)
{
	bool f=false;
	size_t rowCount=checkedDv.size();
	for(size_t i=1;i<rowCount;++i)
		if(checkedDv[i][logicalIndex]!=checkedDv[i-1][logicalIndex])
		{
			f=true;
			break;
		}
	for(size_t i=0;i<rowCount;++i)
		setBlockCheckedState(i,logicalIndex,f?f:!checkedDv[i][logicalIndex]);
}

void FormMap::slotCheckBoxCheckAllBlockStateChanged(int state)
{
	for(size_t i=0;i<currentMap.blockVector.size();++i)
		for(size_t j=0;j<currentMap.blockVector[i].size();++j)
			switch(state)
			{
			case Qt::Checked:
				if(!checkedDv[i][j])
					setBlockCheckedState(i,j,true);
				break;
			case Qt::Unchecked:
				if(checkedDv[i][j])
					setBlockCheckedState(i,j,false);
				break;
			default:;
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

void FormMap::slotABLineStateUpdated(QString mapName)
{
	if(currentMap.name!=mapName)
		return;
	currentMap.loadABLine();
    ui->pushButtonABLine->setText(currentMap.abLineName.isEmpty()?"无":currentMap.abLineName);
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
            if(qsi==nullptr)
                continue;
            if(text==Block::viewType[0])
            {
                qsi->setText(QString::number(rowCount-i)+','+QString::number(j+1));
                ui->pushButtonImportAttribute->setVisible(false);
            }
            else
            {
                ui->pushButtonImportAttribute->setVisible(true);
                if(text==Block::viewType[1])
                    qsi->setText(currentMap.blockVector[i][j].number);
                else if(text==Block::viewType[2])
                    qsi->setText(QString::number(currentMap.blockVector[i][j].density));
            }
        }
}
