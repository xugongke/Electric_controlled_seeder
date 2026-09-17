TEMPLATE = subdirs

SUBDIRS += \
	SowSystem/SowSystem \
	YieldMeasureSystem/YieldMeasureSystem

SOURCES += \
    common/database.cpp \
	common/globalfilter.cpp \
	common/map.cpp

HEADERS += \
    common/database.h \
	common/globalfilter.h \
	common/map.h \
	common/protocol.h
