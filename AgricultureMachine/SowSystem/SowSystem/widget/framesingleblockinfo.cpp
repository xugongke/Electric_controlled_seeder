#include "framesingleblockinfo.h"
#include "ui_framesingleblockinfo.h"
#include <QPainter>
#include <QGraphicsDropShadowEffect>
#include <QDebug>
#include <QListView>
#include <QPainterPath>

#define TRIANGLE_WIDTH 0 //小三角底长;
#define TRIANGLE_HEIGHT 0 //小三角的高度;
#define BORDER_RADIUS 5 //窗口边角的弧度;

FrameSingleBlockInfo::FrameSingleBlockInfo(QWidget *parent) :
	QFrame(parent),
	ui(new Ui::FrameSingleBlockInfo)
{
	ui->setupUi(this);
	QGraphicsDropShadowEffect shadowEffect;
	shadowEffect.setOffset(0,0);
	shadowEffect.setColor(Qt::gray);
	shadowEffect.setBlurRadius(SHADOW_WIDTH);
	setGraphicsEffect(&shadowEffect);
}

FrameSingleBlockInfo::~FrameSingleBlockInfo()
{
	delete ui;
}

void FrameSingleBlockInfo::paintEvent(QPaintEvent *)
{
	//矩形
	QPainterPath drawPath;
	drawPath.addRoundedRect(QRect(SHADOW_WIDTH,TRIANGLE_HEIGHT+SHADOW_WIDTH,width()-SHADOW_WIDTH*2,height()-SHADOW_WIDTH*2-TRIANGLE_HEIGHT),BORDER_RADIUS,BORDER_RADIUS);
	//三角
	QPolygon trianglePolygon;
	int startX=(width()-SHADOW_WIDTH-TRIANGLE_WIDTH)/2,startY=TRIANGLE_HEIGHT+SHADOW_WIDTH;
	trianglePolygon<<QPoint(startX,startY)<<QPoint(startX+TRIANGLE_WIDTH/2,SHADOW_WIDTH)<<QPoint(startX+TRIANGLE_WIDTH,startY);
	drawPath.addPolygon(trianglePolygon);
	QPainter painter(this);
	//抗锯齿
	painter.setRenderHint(QPainter::Antialiasing);
	painter.setBrush(Qt::lightGray);
	painter.setPen(Qt::NoPen);
	painter.drawPath(drawPath);
}

void FrameSingleBlockInfo::setBlock(Block *b)
{
	//disconnect用于防止函数被调多次而出错
	disconnect(ui->checkBoxSowSeed,&QCheckBox::stateChanged,this,&FrameSingleBlockInfo::slotCheckBoxSowSeedStateChanged);
	ui->checkBoxSowSeed->setCheckState(b->sowSeed?Qt::Checked:Qt::Unchecked);
	connect(ui->checkBoxSowSeed,&QCheckBox::stateChanged,this,&FrameSingleBlockInfo::slotCheckBoxSowSeedStateChanged);
	disconnect(ui->lineEditNumber,&QLineEdit::textChanged,this,&FrameSingleBlockInfo::slotLineEditNumberTextChanged);
	ui->lineEditNumber->setText(b->number);
	connect(ui->lineEditNumber,&QLineEdit::textChanged,this,&FrameSingleBlockInfo::slotLineEditNumberTextChanged);
	disconnect(ui->spinBoxDensity,static_cast<void(QSpinBox:: *)(int)>(&QSpinBox::valueChanged),this,&FrameSingleBlockInfo::slotSpinBoxDensityValueChanged);
	ui->spinBoxDensity->setValue(b->density);
	connect(ui->spinBoxDensity,static_cast<void(QSpinBox:: *)(int)>(&QSpinBox::valueChanged),this,&FrameSingleBlockInfo::slotSpinBoxDensityValueChanged);
	this->b=b;
}

void FrameSingleBlockInfo::slotCheckBoxSowSeedStateChanged(int state)
{
	switch(state)
	{
	case Qt::Checked:
		b->sowSeed=true;
		break;
	case Qt::Unchecked:
		b->sowSeed=false;
		break;
	default:;
	}
	emit signalSowSeedModified();
}

void FrameSingleBlockInfo::slotLineEditNumberTextChanged(const QString &text)
{
	b->number=text;
	emit signalDataModified();
}

void FrameSingleBlockInfo::setReadOnly(bool b)
{
	ui->lineEditNumber->setReadOnly(b);
}

void FrameSingleBlockInfo::setCoordinate(int row,int column)
{
	ui->labelRow->setNum(row+1);
	ui->labelColumn->setNum(column+1);
}

int FrameSingleBlockInfo::row()
{
	return ui->labelRow->text().toInt()-1;
}

int FrameSingleBlockInfo::column()
{
	return ui->labelColumn->text().toInt()-1;
}

void FrameSingleBlockInfo::slotSpinBoxDensityValueChanged(int value)
{
	b->density=value;
	emit signalDataModified();
}
