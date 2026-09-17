#include "framesinglemapblockinfo.h"
#include "ui_framesinglemapblockinfo.h"
#include <QPainter>
#include <QGraphicsDropShadowEffect>
#include <QDebug>
#include "global.h"
#include <QListView>
#include <QPainterPath>

#define TRIANGLE_WIDTH 0//小三角底长;
#define TRIANGLE_HEIGHT 0//小三角的高度;
#define BORDER_RADIUS 5//窗口边角的弧度;

FrameSingleMapBlockInfo::FrameSingleMapBlockInfo(QWidget *parent) :
	QFrame(parent),
    ui(new Ui::FrameSingleMapBlockInfo)
{
	ui->setupUi(this);
    QGraphicsDropShadowEffect shadowEffect;
    shadowEffect.setOffset(0,0);
    shadowEffect.setColor(Qt::gray);
    shadowEffect.setBlurRadius(SHADOW_WIDTH);
    setGraphicsEffect(&shadowEffect);
	ui->comboBoxCrop->setView(new QListView);
	ui->comboBoxCrop->addItem("无");
	ui->comboBoxCrop->addItems(cropList);
}

FrameSingleMapBlockInfo::~FrameSingleMapBlockInfo()
{
	delete ui;
}

void FrameSingleMapBlockInfo::paintEvent(QPaintEvent *)
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

void FrameSingleMapBlockInfo::setBlock(YieldBlock *b)
{
	//disconnect用于防止函数被调多次而出错
    disconnect(ui->comboBoxCrop,&QComboBox::currentTextChanged,this,&FrameSingleMapBlockInfo::slotComboBoxCropCurrentTextChanged);//disconnect防止这个函数被调多次
	ui->comboBoxCrop->setCurrentText(b->crop);
    connect(ui->comboBoxCrop,&QComboBox::currentTextChanged,this,&FrameSingleMapBlockInfo::slotComboBoxCropCurrentTextChanged);
    disconnect(ui->lineEditNumber,&QLineEdit::textChanged,this,&FrameSingleMapBlockInfo::slotLineEditNumberTextChanged);
	ui->lineEditNumber->setText(b->number);
    connect(ui->lineEditNumber,&QLineEdit::textChanged,this,&FrameSingleMapBlockInfo::slotLineEditNumberTextChanged);
	this->b=b;
}

void FrameSingleMapBlockInfo::slotComboBoxCropCurrentTextChanged(const QString &text)
{
    if(text=="无")
        b->crop.clear();
    else
        b->crop=text;
    emit signalDataModified();
}

void FrameSingleMapBlockInfo::slotLineEditNumberTextChanged(const QString &text)
{
	b->number=text;
	emit signalDataModified();
}

void FrameSingleMapBlockInfo::setReadOnly(bool b)
{
	ui->comboBoxCrop->setEnabled(!b);
	ui->lineEditNumber->setReadOnly(b);
}

QString FrameSingleMapBlockInfo::crop()
{
	return b->crop;
}

void FrameSingleMapBlockInfo::setCoordinate(int row,int column)
{
	ui->labelRow->setNum(row+1);
	ui->labelColumn->setNum(column+1);
}

int FrameSingleMapBlockInfo::row()
{
	return ui->labelRow->text().toInt()-1;
}

int FrameSingleMapBlockInfo::column()
{
	return ui->labelColumn->text().toInt()-1;
}
