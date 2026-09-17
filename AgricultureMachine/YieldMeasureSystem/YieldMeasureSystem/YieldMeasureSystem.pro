QT       += core gui sql xlsx axcontainer serialport charts

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

CONFIG += c++17# console

# You can make your code fail to compile if it uses deprecated APIs.
# In order to do so, uncomment the following line.
#DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000    # disables all the APIs deprecated before Qt 6.0.0

SOURCES += \
    ../../common/database.cpp \
    ../../common/globalfilter.cpp \
    ../../common/map.cpp \
    dataStructs/blockresult.cpp \
    dataStructs/masscalibrationdata.cpp \
    dataStructs/moisturecalibrationdata.cpp \
    dataStructs/task.cpp \
    dataStructs/taskblock.cpp \
    dataStructs/yieldblock.cpp \
    dataStructs/yieldmap.cpp \
    delegate/pushbuttondelegate.cpp \
    dialogs/dialogbatchmapblockinfo.cpp \
    dialogs/dialogbatchtaskblockinfo.cpp \
    dialogs/dialogcalibrationauthentication.cpp \
    dialogs/dialognewmap.cpp \
    dialogs/dialognewtask.cpp \
    dialogs/dialogrealtimetask.cpp \
    dialogs/dialogresult.cpp \
    dialogs/dialogsinglemapblockinfo.cpp \
    dialogs/dialogsingletaskblockinfo.cpp \
    forms/formcalibration.cpp \
    forms/formhistory.cpp \
    forms/formmap.cpp \
    forms/formmasscalibration.cpp \
    forms/formmoisturecalibration.cpp \
    forms/formsetting.cpp \
    forms/formtask.cpp \
    global.cpp \
    main.cpp \
    mainwindow.cpp \
    models/recordmodel.cpp \
    models/taskresultmodel.cpp \
    network/threadaccept.cpp \
    network/threaddata.cpp \
    threads/yieldmeasurementthread.cpp \
    tools/realtimedata.cpp \
    tools/settingshandle.cpp \
    uart/common_port.c \
    uart/threaduart.cpp \
    widgets/framesinglemapblockinfo.cpp \
    widgets/framesingletaskblockinfo.cpp \
    widgets/maptable.cpp \
    widgets/verticalbartabwidget.cpp \
    widgets/verticaltabbar.cpp \
    widgets/widgetmapinfo.cpp \
    widgets/widgetstatusbar.cpp

HEADERS += \
    ../../common/database.h \
    ../../common/globalfilter.h \
    ../../common/map.h \
    ../../common/protocol.h \
    dataStructs/blockresult.h \
    dataStructs/masscalibrationdata.h \
    dataStructs/moisturecalibrationdata.h \
    dataStructs/task.h \
    dataStructs/taskblock.h \
    dataStructs/yieldblock.h \
    dataStructs/yieldmap.h \
    delegate/pushbuttondelegate.h \
    dialogs/dialogbatchmapblockinfo.h \
    dialogs/dialogbatchtaskblockinfo.h \
    dialogs/dialogcalibrationauthentication.h \
    dialogs/dialognewmap.h \
    dialogs/dialognewtask.h \
    dialogs/dialogrealtimetask.h \
    dialogs/dialogresult.h \
    dialogs/dialogsinglemapblockinfo.h \
    dialogs/dialogsingletaskblockinfo.h \
    forms/formcalibration.h \
    forms/formhistory.h \
    forms/formmap.h \
    forms/formmasscalibration.h \
    forms/formmoisturecalibration.h \
    forms/formsetting.h \
    forms/formtask.h \
    global.h \
    mainwindow.h \
    models/recordmodel.h \
    models/taskresultmodel.h \
    network/tcp.h \
    network/threadaccept.h \
    network/threaddata.h \
    threads/yieldmeasurementthread.h \
    tools/realtimedata.h \
    tools/settingshandle.h \
    uart/common_port.h \
    uart/threaduart.h \
    widgets/framesinglemapblockinfo.h \
    widgets/framesingletaskblockinfo.h \
    widgets/maptable.h \
    widgets/verticalbartabwidget.h \
    widgets/verticaltabbar.h \
    widgets/widgetmapinfo.h \
    widgets/widgetstatusbar.h

FORMS += \
    dialogs/dialogbatchmapblockinfo.ui \
    dialogs/dialogbatchtaskblockinfo.ui \
    dialogs/dialogcalibrationauthentication.ui \
    dialogs/dialognewmap.ui \
    dialogs/dialognewtask.ui \
    dialogs/dialogrealtimetask.ui \
    dialogs/dialogresult.ui \
    dialogs/dialogsinglemapblockinfo.ui \
    dialogs/dialogsingletaskblockinfo.ui \
    forms/formcalibration.ui \
    forms/formhistory.ui \
    forms/formmap.ui \
    forms/formmasscalibration.ui \
    forms/formmoisturecalibration.ui \
    forms/formsetting.ui \
    forms/formtask.ui \
    mainwindow.ui \
    widgets/framesinglemapblockinfo.ui \
    widgets/framesingletaskblockinfo.ui \
    widgets/widgetmapinfo.ui \
    widgets/widgetstatusbar.ui

# Default rules for deployment.
qnx: target.path = /tmp/$${TARGET}/bin
else: unix:!android: target.path = /opt/$${TARGET}/bin
!isEmpty(target.path): INSTALLS += target

RESOURCES += \
	resources.qrc

DISTFILES +=

LIBS += -ldwmapi -lWs2_32
