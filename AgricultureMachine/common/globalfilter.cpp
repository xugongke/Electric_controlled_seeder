#include "globalfilter.h"
#include <QEvent>
#include <QLineEdit>
#include <QTextEdit>
#include <QAbstractSpinBox>
#include <QDebug>
#include <Initguid.h>
#include <dwmapi.h>

#define KEYBOARDWINDOW L"IPTip_Main_Window"

DEFINE_GUID(CLSID_UIHostNoLaunch, 0x4CE576FA, 0x83DC, 0x4f88, 0x95, 0x1C, 0x9D, 0x07, 0x82, 0xB4, 0xE3, 0x76);
DEFINE_GUID(IID_ITipInvocation, 0x37c994e7, 0x432b, 0x4834, 0xa2, 0xf7, 0xdc, 0xe1, 0xf1, 0x3b, 0x83, 0x4b);

struct ITipInvocation : IUnknown
{
	virtual HRESULT STDMETHODCALLTYPE Toggle(HWND wnd) = 0;
};

GlobalFilter::GlobalFilter(QObject *parent)
	: QObject{parent},lastWatchedObject(nullptr)
{

}

bool GlobalFilter::eventFilter(QObject *watched, QEvent *event)
{
	switch(event->type())
	{
	case QEvent::FocusIn:
		if(strcmp(watched->metaObject()->className(),"QWindowsVistaStyle")==0||strcmp(watched->metaObject()->className(),"QStyleSheetStyle")==0)
			break;
		if(watched->inherits("QLineEdit"))
		{
			QLineEdit *qle=(QLineEdit *)watched;
			if(qle->isEnabled()&&!qle->isReadOnly()&&!keyboardIsShow())
				toggleKeyboardShowState();
		}
		else if(watched->inherits("QTextEdit"))
		{
			QTextEdit *qte=(QTextEdit *)watched;
			if(qte->isEnabled()&&!qte->isReadOnly()&&!keyboardIsShow())
				toggleKeyboardShowState();
		}
		else if(watched->inherits("QAbstractSpinBox"))
		{
			QAbstractSpinBox *qasb=(QAbstractSpinBox *)watched;
			if(qasb->isEnabled()&&!qasb->isReadOnly()&&!keyboardIsShow())
				toggleKeyboardShowState();
		}
		else if(lastWatchedObject!=watched&&keyboardIsShow())
			toggleKeyboardShowState();
		lastWatchedObject=watched;
		break;
	default:;
	}
	return QObject::eventFilter(watched,event);
}

void GlobalFilter::toggleKeyboardShowState()
{
	if(FindWindowEx(nullptr,nullptr,KEYBOARDWINDOW,nullptr)!=nullptr)
	{
        ITipInvocation *tip_invocation_;
        CoCreateInstance(CLSID_UIHostNoLaunch,nullptr,CLSCTX_INPROC_HANDLER|CLSCTX_LOCAL_SERVER,IID_ITipInvocation,(void **)&tip_invocation_);
        if(CoCreateInstance(CLSID_UIHostNoLaunch,nullptr,CLSCTX_INPROC_HANDLER|CLSCTX_LOCAL_SERVER,IID_ITipInvocation,(void **)&tip_invocation_)==S_OK)
            tip_invocation_->Toggle(GetDesktopWindow());
		return;
	}
	PVOID OldValue=nullptr;
	BOOL bRet=Wow64DisableWow64FsRedirection(&OldValue);//用32位文件系统
	ShellExecute(nullptr,L"open",L"C:\\Program Files\\Common Files\\microsoft shared\\ink\\TabTip.exe",nullptr,nullptr,SW_SHOWNORMAL);
	if(bRet)
		Wow64RevertWow64FsRedirection(OldValue);//用回64位文件系统
}

bool GlobalFilter::keyboardIsShow()
{
	int cloaked=0;
	return DwmGetWindowAttribute(FindWindowExW(FindWindowExW(nullptr,nullptr,L"ApplicationFrameWindow",nullptr),nullptr,L"Windows.UI.Core.CoreWindow",L"Microsoft Text Input Application"),DWMWA_CLOAKED,&cloaked,DWM_CLOAKED_INHERITED)==S_OK?0==cloaked:false;
}
