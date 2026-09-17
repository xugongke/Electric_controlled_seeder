#include "formmasscalibration.h"
#include "ui_formmasscalibration.h"
#include <QTimer>
#include <QMessageBox>
#include "dialogs/dialogcalibrationauthentication.h"
#include <QDebug>
#include <QListView>
#include <QLineSeries>
#include <QChart>
#include <QValueAxis>
#include <QScatterSeries>
#include <QSettings>

#define VALUECOLUMN 0
#define SENSITIVITYCOLUMN 1
#define UPDATEBUTTONCOLUMN 2

FormMassCalibration::FormMassCalibration(QWidget *parent) :
	QWidget(parent),
	ui(new Ui::FormMassCalibration)
{
	ui->setupUi(this);
	ui->tableWidget->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
//	for(int i=0;i<channleList.size();++i)
//		if(!MassCalibrationData::existData(channleList[i]))
//		{
//			MassCalibrationData cd;
//			cd.channle=channleList[i];
//			cd.range=0.1;
//			cd.n=ui->sbPoint->value();
//			cd.zero=0;
//			cd.flag=0;
//			cd.val[0]=1;
//			cd.adc[0]=1;
//			cd.add();
//		}
	connect(ui->comboBoxChannle,&QComboBox::currentTextChanged,this,[=](QString value){
		MassCalibrationData cd;
		cd.load(value);
		ui->checkInv->setCheckState((cd.flag&0b10)!=0?Qt::Checked:Qt::Unchecked);
		ui->sbRange->setValue(cd.range);
		ui->sbPoint->setValue(cd.n);
		bool reverse=(cd.flag&1)!=0;
		ui->checkNeg->setCheckState(reverse?Qt::Checked:Qt::Unchecked);
		ui->sbZero->setValue(cd.zero);
		ui->tableWidget->setRowCount(0);
        for(int i=0;i<cd.n;connectUpdatePointSlots(i++))
		{
			createCalibrationRow(i);
			setCailbrationPoint(i,cd.val[i],cd.adc[i]);
		}
		if(reverse)
            for(int i=0;i<cd.n;connectUpdatePointSlots(i++))
			{
				int t=i+10,r=i+cd.n;
				createCalibrationRow(r);
				setCailbrationPoint(r,cd.val[t],cd.adc[t]);
			}
		redrawChart();
		if(value=="三通道")
		{
			ui->labA->setText("实时质量：");
			ui->label_6->setText("kg");
            ui->checkInv->setVisible(true);
            ui->tableWidget->horizontalHeaderItem(SENSITIVITYCOLUMN)->setText("实时质量(kg)");
            ui->label->setVisible(true);
            ui->label->setText("1通道");
            ui->label_3->setVisible(true);
            ui->label_5->setVisible(true);
            ui->labelChannel1->setVisible(true);
            ui->labelChannel2->setVisible(true);
            ui->labelChannel3->setVisible(true);
		}
        else if(value=="容重")
        {
            ui->labA->setText("实时质量：");
            ui->label_6->setText("kg");
            ui->checkInv->setVisible(true);
            ui->tableWidget->horizontalHeaderItem(SENSITIVITYCOLUMN)->setText("实时质量(kg)");
            ui->label->setVisible(true);
            ui->label->setText("4通道");
            ui->label_3->setVisible(false);
            ui->label_5->setVisible(false);
            ui->labelChannel1->setVisible(true);
            ui->labelChannel2->setVisible(false);
            ui->labelChannel3->setVisible(false);
        }
        else
        {
            ui->labA->setText("实时灵敏度：");
            ui->label_6->setText("mV/V");
            ui->checkInv->setVisible(false);
            ui->tableWidget->horizontalHeaderItem(SENSITIVITYCOLUMN)->setText("灵敏度(mV/V)");
            ui->label->setVisible(false);
            ui->label_3->setVisible(false);
            ui->label_5->setVisible(false);
            ui->labelChannel1->setVisible(false);
            ui->labelChannel2->setVisible(false);
            ui->labelChannel3->setVisible(false);
        }
        return;
	});
    connect(ui->sbPoint,static_cast<void(QSpinBox:: *)(int)>(&QSpinBox::valueChanged),this,&FormMassCalibration::slotSbPointValueChanged);
    connect(ui->sbRange,static_cast<void(QDoubleSpinBox:: *)(double)>(&QDoubleSpinBox::valueChanged),this,[=](double value){
        QList<QtCharts::QAbstractAxis *> ql=ui->graphicsView->chart()->axes(Qt::Vertical);
        QtCharts::QValueAxis *yAxis=(QtCharts::QValueAxis *)ql[0];
        yAxis->setRange(-value,value);
        for(int i=0;i<ui->tableWidget->rowCount();((QDoubleSpinBox *)ui->tableWidget->cellWidget(i++,VALUECOLUMN))->setRange(-value,value));
    });
	connect(ui->checkNeg,&QCheckBox::stateChanged,this,[=](int state){
		int p=ui->sbPoint->value(),range=ui->sbRange->value();
		switch(state)
		{
		case Qt::Unchecked:
			for(;ui->tableWidget->rowCount()>p;ui->tableWidget->removeRow(p));
			break;
		case Qt::Checked:
			float valueAvg=range/p,sensitivityAvg=range/p;
            for(int i=p;i<p*2;connectUpdatePointSlots(i++))
			{
				createCalibrationRow(i);
				int j=i+1-p;
                setCailbrationPoint(i,-valueAvg*j,-sensitivityAvg*j);
			}
		}
        redrawChart();
	});
	connect(ui->btnReset,&QPushButton::clicked,this,[=]{
		int n= ui->sbPoint->value(),range=ui->sbRange->value();
		float valueAvg=range/ n,sensitivityAvg=range/ n;
		for(int i = 0; i < n; i++)
		{
			int j=i+1;
			float x=valueAvg*j,y=sensitivityAvg*j;
			setCailbrationPoint(i,x,y);
			if(ui->checkNeg->checkState()==Qt::Checked)
				setCailbrationPoint(i+n,-x,-y);
		}
	});
	connect(ui->btnZero,&QPushButton::clicked,this,[=]{
		ui->sbZero->setValue(ui->sbZero->value()+ui->labelRealtimeSensitivity->text().toFloat());
	});
	connect(ui->btnN,&QPushButton::clicked,this,[=]{
		deleteLater();
	});
	connect(ui->btnY,&QPushButton::clicked,this,[=]{
        QString channel=ui->comboBoxChannle->currentText();
        if(channel!="三通道"&&channel!="容重"&&DialogCalibrationAuthentication().exec()==QDialog::Rejected)
			return;
		MassCalibrationData cd=currentCalibrationData();
		if(Calib_check(&cd)==-1)
		{
			QMessageBox::information(this,"提示","校准点应按顺序排列");
			return;
		}
		cd.update();
		initMassCalibMap();
		QMessageBox::information(this,"提示","保存成功");
	});
	connect(&realtimeSensitivityTimer,&QTimer::timeout,this,[=]{
        QString channel=ui->comboBoxChannle->currentText();
        if(channel=="三通道")
        {
			switch(ui->checkInv->checkState())
			{
            case Qt::Unchecked:
				ui->labelRealtimeSensitivity->setText(QString::number(G.rd->uniteMass()-ui->sbZero->value(),'f',3));
				break;
            case Qt::Checked:
                ui->labelRealtimeSensitivity->setText(QString::number(ui->sbZero->value()-G.rd->uniteMass(),'f',3));
				break;
			default:;
			}
            ui->labelChannel1->setText(QString::number(G.rd->channelMass("1"),'f',3)+"kg");
            ui->labelChannel2->setText(QString::number(G.rd->channelMass("2"),'f',3)+"kg");
            ui->labelChannel3->setText(QString::number(G.rd->channelMass("3"),'f',3)+"kg");
        }
        else if(channel=="容重")
        {
            showRealtimeSensitivity(G.rd->unitWeightMass());
            ui->labelChannel1->setText(QString::number(G.rd->channelMass("4"),'f',3)+"kg");
        }
        else
            showRealtimeSensitivity(G.rd->singleMass(channel));
    });
    QtCharts::QChart *chart=new QtCharts::QChart;
    ui->graphicsView->setRenderHint(QPainter::Antialiasing);
    ui->graphicsView->setChart(chart);
    QtCharts::QValueAxis *xAxis=new QtCharts::QValueAxis,*yAxis=new QtCharts::QValueAxis;
    chart->addAxis(xAxis,Qt::AlignBottom);
    chart->addAxis(yAxis,Qt::AlignLeft);
    slotSbPointValueChanged(ui->sbPoint->value());
    ui->comboBoxChannle->setView(new QListView);
    ui->comboBoxChannle->addItems(channleList);
	realtimeSensitivityTimer.start(200);
}

FormMassCalibration::~FormMassCalibration()
{
	delete ui;
}

void FormMassCalibration::createCalibrationRow(int row)
{
	QDoubleSpinBox *qdsb1=new QDoubleSpinBox,*qdsb2=new QDoubleSpinBox;
    double range=ui->sbRange->value();
    qdsb1->setMaximum(range);
    qdsb1->setMinimum(-range);
	qdsb2->setMaximum(range);
	qdsb2->setMinimum(-range);
	qdsb1->setDecimals(6);
	qdsb2->setDecimals(6);
	qdsb1->setButtonSymbols(QAbstractSpinBox::NoButtons);
	qdsb2->setButtonSymbols(QAbstractSpinBox::NoButtons);
	ui->tableWidget->insertRow(row);
	ui->tableWidget->setCellWidget(row,VALUECOLUMN,qdsb1);
	ui->tableWidget->setCellWidget(row,SENSITIVITYCOLUMN,qdsb2);
	QPushButton *qpb=new QPushButton("更新");
	connect(qpb,&QPushButton::clicked,this,[=]{
		qdsb2->setValue(ui->labelRealtimeSensitivity->text().toDouble());
	});
	ui->tableWidget->setCellWidget(row,UPDATEBUTTONCOLUMN,qpb);
}

void FormMassCalibration::setCailbrationPoint(int row,float value,float sensitivity)
{
	((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,VALUECOLUMN))->setValue(value);
	((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,SENSITIVITYCOLUMN))->setValue(sensitivity);
}

MassCalibrationData FormMassCalibration::currentCalibrationData()
{
	MassCalibrationData cd;
	cd.n=ui->sbPoint->value();
	cd.channle=ui->comboBoxChannle->currentText();
	cd.range=ui->sbRange->value();
	cd.zero=ui->sbZero->value();
	switch(ui->checkInv->checkState())
	{
	case Qt::Unchecked:
		cd.flag=0;
		break;
	case Qt::Checked:
        cd.flag=2;
		break;
	default:;
	}
	bool b=ui->checkNeg->checkState()==Qt::Checked;
	if(b)
		cd.flag&=1;
	for(int i=0;i<cd.n;i++)
	{
		cd.val[i]=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,VALUECOLUMN))->value();
		cd.adc[i]=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,SENSITIVITYCOLUMN))->value();
		if(!b)
			continue;
		int t=i+10,r=i+cd.n;
		cd.val[t]=((QDoubleSpinBox *)ui->tableWidget->cellWidget(r,VALUECOLUMN))->value();
		cd.adc[t]=((QDoubleSpinBox *)ui->tableWidget->cellWidget(r,SENSITIVITYCOLUMN))->value();
	}
	return cd;
}

void FormMassCalibration::showRealtimeSensitivity(float f)
{
	switch(ui->checkInv->checkState())
	{
	case Qt::Unchecked:
		ui->labelRealtimeSensitivity->setText(QString::number(f-ui->sbZero->value(),'f',3));
		break;
	case Qt::Checked:
		ui->labelRealtimeSensitivity->setText(QString::number(ui->sbZero->value()-f,'f',3));
		break;
	default:;
	}
}

void FormMassCalibration::redrawChart()
{
    QtCharts::QChart *qc=ui->graphicsView->chart();
    QtCharts::QLineSeries *qs=new QtCharts::QLineSeries;
    QtCharts::QScatterSeries *qcqss=new QtCharts::QScatterSeries;
    int point=ui->sbPoint->value();
    if(ui->checkNeg->checkState()==Qt::Checked)
        for(int i=ui->tableWidget->rowCount()-1;i>=point;i--)
        {
            double y=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,VALUECOLUMN))->value(),x=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,SENSITIVITYCOLUMN))->value();
            qs->append(x,y);
            qcqss->append(x,y);
        }
    qs->append(0,0);
    qcqss->append(0,0);
    for(int i=0;i<point&&i<ui->tableWidget->rowCount();i++)
    {
        double y=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,VALUECOLUMN))->value(),x=((QDoubleSpinBox *)ui->tableWidget->cellWidget(i,SENSITIVITYCOLUMN))->value();
        qs->append(x,y);
        qcqss->append(x,y);
    }
    qc->removeAllSeries();
    qc->addSeries(qs);
    qc->addSeries(qcqss);
    QList<QtCharts::QAbstractAxis *> ql=qc->axes(Qt::Horizontal),ql2=qc->axes(Qt::Vertical);
    QtCharts::QValueAxis *xAxis=(QtCharts::QValueAxis *)ql[0],*yAxis=(QtCharts::QValueAxis *)ql2[0];
    xAxis->setTitleText(ui->comboBoxChannle->currentText()==channleList[0]?"实时质量(kg)":"灵敏度(mV/V)");
    yAxis->setTitleText("质量(kg)");
    double range=ui->sbRange->value();
    xAxis->setRange(-10,10);
    yAxis->setRange(-range,range);
    qs->attachAxis(xAxis);
    qs->attachAxis(yAxis);
    qcqss->attachAxis(xAxis);
	qcqss->attachAxis(yAxis);
}

void FormMassCalibration::updatePoint(int index,double x,double y)
{
    QList<QtCharts::QAbstractSeries *> ql=ui->graphicsView->chart()->series();
    ((QtCharts::QXYSeries *)ql[0])->replace(index,x,y);
    ((QtCharts::QXYSeries *)ql[1])->replace(index,x,y);
}

void FormMassCalibration::slotSbPointValueChanged(int value)
{
    ui->tableWidget->setRowCount(0);
	int rowCount=value,range=ui->sbRange->value();
	if(ui->checkNeg->checkState()==Qt::Checked)
		rowCount*=2;
	float valueAve=range/value,sensitivityAve=range/value;
    for(int i=0;i<value;connectUpdatePointSlots(i++))
    {
        createCalibrationRow(i);
        int j=i+1;
        setCailbrationPoint(i,valueAve*j,sensitivityAve*j);
    }
    for(int i=value;i<rowCount;connectUpdatePointSlots(i++))
    {
        createCalibrationRow(i);
        int j=i-value+1;
        setCailbrationPoint(i,-valueAve*j,-sensitivityAve*j);
    }
    redrawChart();
}

void FormMassCalibration::connectUpdatePointSlots(int row)
{
    connect((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,VALUECOLUMN),(void(QDoubleSpinBox:: *)(double))(&QDoubleSpinBox::valueChanged),this,[=](double value){
        int point=ui->sbPoint->value(),index=row;
        switch(ui->checkNeg->checkState())
        {
        case Qt::Unchecked:
            index++;
            break;
        case Qt::Checked:
            if(index<point)
                index+=point+1;
            else
                index=2*point-index-1;
            break;
        default:;
        }
        updatePoint(index,((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,SENSITIVITYCOLUMN))->value(),value);
    });
    connect((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,SENSITIVITYCOLUMN),(void(QDoubleSpinBox:: *)(double))(&QDoubleSpinBox::valueChanged),this,[=](double value){
        int point=ui->sbPoint->value(),index=row;
        switch(ui->checkNeg->checkState())
        {
        case Qt::Unchecked:
            index++;
            break;
		case Qt::Checked:
			index=index<point?index+point+1:2*point-index-1;
            break;
        default:;
        }
        updatePoint(index,value,((QDoubleSpinBox *)ui->tableWidget->cellWidget(row,VALUECOLUMN))->value());
    });
}
