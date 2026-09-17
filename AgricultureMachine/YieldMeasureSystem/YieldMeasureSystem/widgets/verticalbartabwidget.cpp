#include "verticalbartabwidget.h"
#include "verticaltabbar.h"

QStringList VerticalBarTabWidget::tabText{
	"任务","地图","历史记录","标定","新建"
};

VerticalBarTabWidget::VerticalBarTabWidget(QWidget *parent):QTabWidget(parent)
{
//	VerticalTabBar *vtb=new VerticalTabBar;
//	setTabBar(vtb);
//	for(int i=0;i<tabText.size();++i)
//		vtb->setTabText(i,tabText[i]);
}
