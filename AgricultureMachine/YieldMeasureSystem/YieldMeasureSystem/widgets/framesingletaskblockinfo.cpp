#include "framesingletaskblockinfo.h"
#include "ui_framesingletaskblockinfo.h"
#include <QPainter>
#include <QGraphicsDropShadowEffect>
#include <QDebug>
#include "global.h"
#include <QListView>
#include <QPainterPath>

#define TRIANGLE_WIDTH 0//小三角底长;
#define TRIANGLE_HEIGHT 0//小三角的高度;
#define BORDER_RADIUS 5//窗口边角的弧度;

FrameSingleTaskBlockInfo::FrameSingleTaskBlockInfo(QWidget *parent)
    : QFrame(parent)
    , ui(new Ui::FrameSingleTaskBlockInfo)
{
    ui->setupUi(this);
    QGraphicsDropShadowEffect shadowEffect;
    shadowEffect.setOffset(0,0);
    shadowEffect.setColor(Qt::gray);
    shadowEffect.setBlurRadius(SHADOW_WIDTH);
    setGraphicsEffect(&shadowEffect);
}

FrameSingleTaskBlockInfo::~FrameSingleTaskBlockInfo()
{
    delete ui;
}

void FrameSingleTaskBlockInfo::paintEvent(QPaintEvent *)
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

void FrameSingleTaskBlockInfo::setBlock(TaskBlock *b)
{
    //disconnect用于防止函数被调多次而出错
    disconnect(ui->checkBoxMeasure,&QCheckBox::stateChanged,this,&FrameSingleTaskBlockInfo::slotCheckBoxMeasureStateChanged);//disconnect防止这个函数被调多次
    ui->checkBoxMeasure->setCheckState(b->measure?Qt::Checked:Qt::Unchecked);
    connect(ui->checkBoxMeasure,&QCheckBox::stateChanged,this,&FrameSingleTaskBlockInfo::slotCheckBoxMeasureStateChanged);
    this->b=b;
}

void FrameSingleTaskBlockInfo::slotCheckBoxMeasureStateChanged(int state)
{
    b->measure=state==Qt::Checked;
    b->updateFlag=true;
    emit signalDataModified();
}

void FrameSingleTaskBlockInfo::setReadOnly(bool b)
{
    ui->checkBoxMeasure->setEnabled(!b);
}

bool FrameSingleTaskBlockInfo::measure()
{
    return b->measure;
}

void FrameSingleTaskBlockInfo::setCoordinate(int row,int column)
{
    ui->labelRow->setNum(row+1);
    ui->labelColumn->setNum(column+1);
}

int FrameSingleTaskBlockInfo::row()
{
    return ui->labelRow->text().toInt()-1;
}

int FrameSingleTaskBlockInfo::column()
{
    return ui->labelColumn->text().toInt()-1;
}
