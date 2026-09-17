QT       += core gui sql xlsx axcontainer serialport

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

CONFIG += c++17# console

#MAINVERSION=1
#SUBVERSION=1
#UPDATEDATE=2023.2.6
#DEFINES += APP_VERSION=\\\"$$MAINVERSION\\.\\$$SUBVERSION($$UPDATEDATE)\\\"

#QMAKE_CXXFLAGS_RELEASE = $$QMAKE_CFLAGS_RELEASE_WITH_DEBUGINFO
#QMAKE_LFLAGS_RELEASE   = $$QMAKE_LFLAGS_RELEASE_WITH_DEBUGINFO

# You can make your code fail to compile if it uses deprecated APIs.
# In order to do so, uncomment the following line.
#DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0

SOURCES += \
    ../../common/database.cpp \
    ../../common/globalfilter.cpp \
    ../../common/map.cpp \
    dataStruct/blockresult.cpp \
    dataStruct/task.cpp \
	delegate/doublespinboxdelegate.cpp \
	delegate/pushbuttondelegate.cpp \
	delegate/spinboxdelegate.cpp \
	dialog/dialogabline.cpp \
	dialog/dialogaisle.cpp \
	dialog/dialogbatchblockinfo.cpp \
	dialog/dialogchooseabline.cpp \
	dialog/dialogconfigverification.cpp \
    dialog/dialogdevicestate.cpp \
	dialog/dialoginputablinename.cpp \
	dialog/dialognewmap.cpp \
	dialog/dialognewtask.cpp \
	dialog/dialogrealtimetask.cpp \
	dialog/dialogrowattribute.cpp \
	dialog/dialogsingleblockinfo.cpp \
	#dialog/dongle_dialog.cpp \
	dialog/dialogtaskresult.cpp \
	dialog/dongle_dialog.cpp \
	form/formconfig.cpp \
	form/formcontinuoussow.cpp \
	form/formhistory.cpp \
    form/formmap.cpp \
    form/formtask.cpp \
	form/formtest.cpp \
    global.cpp \
    main.cpp \
    mainwindow.cpp \
	model/currentblocktablemodel.cpp \
	model/lastblocktablemodel.cpp \
	model/resultmodel.cpp \
	model/taskresultmodel.cpp \
	tool/communication.cpp \
    widget/checkbox.cpp \
	widget/framesingleblockinfo.cpp \
	widget/widgetstatusbar.cpp

HEADERS += \
    ../../common/database.h \
    ../../common/globalfilter.h \
    ../../common/map.h \
    ../../common/protocol.h \
    dataStruct/blockresult.h \
    dataStruct/task.h \
	delegate/doublespinboxdelegate.h \
	delegate/pushbuttondelegate.h \
	delegate/spinboxdelegate.h \
	dialog/dialogabline.h \
	dialog/dialogaisle.h \
	dialog/dialogbatchblockinfo.h \
	dialog/dialogchooseabline.h \
	dialog/dialogconfigverification.h \
    dialog/dialogdevicestate.h \
	dialog/dialoginputablinename.h \
	dialog/dialognewmap.h \
	dialog/dialognewtask.h \
	dialog/dialogrealtimetask.h \
	dialog/dialogrowattribute.h \
	dialog/dialogsingleblockinfo.h \
	#dialog/dongle_dialog.h \
	dialog/dialogtaskresult.h \
	dialog/dongle_dialog.h \
	form/formconfig.h \
	form/formcontinuoussow.h \
	form/formhistory.h \
    form/formmap.h \
    form/formtask.h \
	form/formtest.h \
    global.h \
	lib/id2num.h \
    mainwindow.h \
	model/currentblocktablemodel.h \
	model/lastblocktablemodel.h \
	model/resultmodel.h \
	model/taskresultmodel.h \
	tool/communication.h \
    widget/checkbox.h \
	widget/framesingleblockinfo.h \
	widget/widgetstatusbar.h

FORMS += \
	dialog/dialogabline.ui \
    dialog/dialogaisle.ui \
    dialog/dialogbatchblockinfo.ui \
	dialog/dialogchooseabline.ui \
    dialog/dialogconfigverification.ui \
    dialog/dialogdevicestate.ui \
	dialog/dialoginputablinename.ui \
    dialog/dialognewmap.ui \
    dialog/dialognewtask.ui \
    dialog/dialogrealtimetask.ui \
    dialog/dialogrowattribute.ui \
    dialog/dialogsingleblockinfo.ui \
	#dialog/dongle_dialog.ui \
	dialog/dialogtaskresult.ui \
	dialog/dongle_dialog.ui \
    form/formconfig.ui \
	form/formcontinuoussow.ui \
    form/formhistory.ui \
    form/formmap.ui \
    form/formtask.ui \
    form/formtest.ui \
    mainwindow.ui \
    widget/framesingleblockinfo.ui \
	widget/widgetstatusbar.ui

# Default rules for deployment.
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target

RESOURCES += \
	resorce.qrc

LIBS += -ldwmapi

win32:CONFIG(release, debug|release): LIBS += -L$$PWD/lib/ -lid2num
else:win32:CONFIG(debug, debug|release): LIBS += -L$$PWD/lib/ -lid2num

INCLUDEPATH += $$PWD/.
DEPENDPATH += $$PWD/.

DISTFILES +=
