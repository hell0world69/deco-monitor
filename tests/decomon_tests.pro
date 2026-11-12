QT += core gui quick quickcontrols2 testlib network
CONFIG += c++17 testcase
TARGET = decomon_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += ../src/backend.h ../src/theme.h ../src/translator.h
SOURCES += decomon_tests.cpp ../src/backend.cpp ../src/theme.cpp ../src/translator.cpp
