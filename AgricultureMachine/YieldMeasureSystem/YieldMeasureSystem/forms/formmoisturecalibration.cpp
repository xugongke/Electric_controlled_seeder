#include "formmoisturecalibration.h"
#include "ui_formmoisturecalibration.h"
#include <QMessageBox>
#include <QTimer>
#include "global.h"
#include <QDebug>
#include <QListView>
#include <QLineSeries>
#include <QChart>
#include <QAbstractSeries>
#include <QValueAxis>
#include <QScatterSeries>

#define MOISTURECOLUMN 0
#define NONCALIBRATIONVALUECOLUMN 1
#define UPDATEBUTTONCOLUMN 2
#define MAXMOISTURE 100
#define MAXNONCALIBRATIONVALUE 1000

FormMoistureCalibration::FormMoistureCalibration(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormMoistureCalibration)
{
	ui->setupUi(this);
	ui->tableWidget->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
//	for(int i=0;i<cropList.size();++i)
//		if(!MoistureCalibrationData::existData(cropList[i]))
//		{
//			MoistureCalibrationData mcd;
//			mcd.crop=cropList[i];
//			mcd.n=1;
//			mcd.val[0]=10;
//			mcd.adc[0]=20;
//			mcd.add();
//		}
	connect(ui->comboBoxCrop,&QComboBox::currentTextChanged,this,[=](QString value){
		MoistureCalibrationData mcd;
		mcd.load(value);
		ui->sbPoint->setValue(mcd.n);
		ui->tableWidget->setRowCount(0);
        for(int i=0;i<mcd.n;connectUpdatePointSlots(i++))
		{
			createCalibrationRow(i);
			setCailbrationPoint(i,mcd.val[i],mcd.adc[i]);
        }
        redrawChart();
    });
    connect(ui->sbPoint,static_cast<void(QSpinBox:: *)(int)>(&QSpinBox::valueChanged),this,&FormMoistureCalibration::slotSbPointValueChanged);
	connect(ui->btnReset,&QPushButton::clicked,this,[=]{
        int n=ui->sbPoint->value();
        float moistureAve=MAXMOISTURE/n,nonCalibrationValueAve=MAXNONCALIBRATIONVALUE/n;
		for(int i = 0; i < n; i++)
		{
			int j=i+1;
			float x=moistureAve*j,y=nonCalibrationValueAve*j;
			setCailbrationPoint(i,x,y);
		}
	});
	connect(ui->btnN,&QPushButton::clicked,this,[=]{
		deleteLater();
	});
	connect(ui->btnY,&QPushButton::clicked,this,[=]{
		MoistureCalibrationData mcd=currentCalibrationData();
		if(Calib_check_moisture(&mcd)==-1)
		{
			QMessageBox::information(this,"提示","非标定值应递增");
			return;
		}
		MoistureCalibrationData mcd2;
		mcd2.load(ui->comboBoxCrop->currentText());
		if(mcd==mcd2)
            return;
		mcd.update();
		initMoistureCalibMap();
		QMessageBox::information(this,"提示","保存成功");
	});
	connect(&qt,&QTimer::timeout,this,[=]{
		ui->labelRealtimeNonCalibrationValue->setText(QString::number(G.rd->newestMoisture(),'f',2));
    });
    QtCharts::QChart *chart=new QtCharts::QChart;
    ui->graphicsView->setRenderHint(QPainter::Antialiasing);
    ui->graphicsView->setChart(chart);
    QtCharts::QValueAxis *xAxis=new QtCharts::QValueAxis,*yAxis=new QtCharts::QValueAxis;
    chart->addAxis(xAxis,Qt::AlignBottom);
    chart->addAxis(yAxis,Qt::AlignLeft);
    slotSbPointValueChanged(ui->sbPoint->value());
    ui->comboBoxCrop->setView(new QListView);
    ui->comboBoxCrop->addItems(cropList);
	qt.start(200);
}

FormMoistureCalibration::~FormMoistureCalibration()
{
	delete ui;
}

void FormMoistureCalibration::createCalibrationRow(int row)
{
	QDoubleSpinBox *qdsb1=new QDoubleSpinBox,*qdsb2=new QDoubleSpinBox;
	qdsb1->setMaximum(MAXMOISTURE);
	qdsb1->setMinimum(0);
	qdsb2->setMaximum(MAXNONCALIBRATIONVALUE);
	qdsb2->setMinimum(0);
	qdsb1->setButtonSymbols(QAbstractSpinBox::NoButtons);
	qdsb2->setButtonSymbols(QAbstractSpinBox::NoButtons);
	ui->tableWidget->insertRow(row);
	ui->tableWidget->setCellWidget(row,MOISTURECOLUMN,qdsb1);
	ui->tableWidget->setCellWidget(row,NONCALIBRATIONVALUECOLUMN,qdsb2);
	QPushButton *qpb=new QPushButton("更新");
	connect(qpb,&QPushButton::clicked,this,[=]{
		qdsb2->setValue(ui->labelRealtimeNonCalibrationValue->text().toFloat());
	});
	ui->tableWidget->setCellWidget(row,UPDATEBUTTONCOLUMN,qpb);
}

void FormMoistureCalibration::setCailbrationPoint(int row,float moisture,float nonCalibrationValue)
{
	((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,MOISTURECOLUMN))->setValue(moisture);
	((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,NONCALIBRATIONVALUECOLUMN))->setValue(nonCalibrationValue);
}

MoistureCalibrationData FormMoistureCalibration::currentCalibrationData()
{
	MoistureCalibrationData mcd;
	mcd.crop=ui->comboBoxCrop->currentText();
    mcd.n=ui->sbPoint->value();
	for(int i=0;i<mcd.n;++i)
	{
		mcd.val[i]=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,MOISTURECOLUMN))->value();
		mcd.adc[i]=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,NONCALIBRATIONVALUECOLUMN))->value();
	}
	return mcd;
}

void FormMoistureCalibration::redrawChart()
{
    QtCharts::QChart *qc=ui->graphicsView->chart();
	QtCharts::QLineSeries *qs=new QtCharts::QLineSeries;
	QtCharts::QScatterSeries *qcqss=new QtCharts::QScatterSeries;
	int pointCount=ui->tableWidget->rowCount();
	for(int i=0;i<pointCount;++i)
    {
		double y=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,MOISTURECOLUMN))->value(),x=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,NONCALIBRATIONVALUECOLUMN))->value();
		qs->append(x,y);
		qcqss->append(x,y);
    }
    qc->removeAllSeries();
	qc->addSeries(qs);
	qc->addSeries(qcqss);
    QList<QtCharts::QAbstractAxis *> ql=qc->axes(Qt::Horizontal),ql2=qc->axes(Qt::Vertical);
    QtCharts::QValueAxis *xAxis=(QtCharts::QValueAxis *)ql[0],*yAxis=(QtCharts::QValueAxis *)ql2[0];
	xAxis->setTitleText("水分非标定值");
	xAxis->setMin(qs->at(0).x());
	xAxis->setMax(qs->at(pointCount-1).x());
    yAxis->setTitleText("湿度(%)");
	float minY=qs->at(0).y(),maxY=minY;
	for(int i=0;i<pointCount;)
	{
		float y=qs->at(i++).y();
		if(y<minY)
			minY=y;
		else if(maxY<y)
			maxY=y;
	}
	yAxis->setMin(minY);
	yAxis->setMax(maxY);
	qs->attachAxis(xAxis);
	qs->attachAxis(yAxis);
	qcqss->attachAxis(xAxis);
	qcqss->attachAxis(yAxis);
}

void FormMoistureCalibration::updatePoint(int index,double x,double y)
{
	QList<QtCharts::QAbstractSeries *> ql=ui->graphicsView->chart()->series();
	if(((QtCharts::QLineSeries *)ql[0])->count()==index)
	{
		((QtCharts::QXYSeries *)ql[0])->append(x,y);
		((QtCharts::QXYSeries *)ql[1])->append(x,y);
	}
	else
	{
		((QtCharts::QXYSeries *)ql[0])->replace(index,x,y);
		((QtCharts::QXYSeries *)ql[1])->replace(index,x,y);
	}
}

void FormMoistureCalibration::slotSbPointValueChanged(int value)
{
    ui->tableWidget->setRowCount(0);
    float moistureAve=MAXMOISTURE/value,nonCalibrationValueAve=MAXNONCALIBRATIONVALUE/value;
    for(int i=0;i<value;connectUpdatePointSlots(i++))
    {
        createCalibrationRow(i);
        int j=i+1;
        setCailbrationPoint(i,moistureAve*j,nonCalibrationValueAve*j);
    }
    redrawChart();
}

void FormMoistureCalibration::connectUpdatePointSlots(int row)
{
    connect((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,MOISTURECOLUMN),(void(QDoubleSpinBox:: *)(double))(&QDoubleSpinBox::valueChanged),this,[=](double value){
		updatePoint(row,((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,NONCALIBRATIONVALUECOLUMN))->value(),value);
    });
    connect((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,NONCALIBRATIONVALUECOLUMN),(void(QDoubleSpinBox:: *)(double))(&QDoubleSpinBox::valueChanged),this,[=](double value){
		updatePoint(row,value,((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,MOISTURECOLUMN))->value());
    });
}
