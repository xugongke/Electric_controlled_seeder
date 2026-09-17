#include "formcalibration.h"
#include "ui_formcalibration.h"
#include "forms/formmasscalibration.h"
#include "forms/formmoisturecalibration.h"

FormCalibration::FormCalibration(QWidget *parent) :
	QStackedWidget(parent),
	ui(new Ui::FormCalibration)
{
	ui->setupUi(this);
    connect(ui->pushButtonCalibrateMoistore,&QPushButton::clicked,this,[=]{
        addWidget(new FormMoistureCalibration(this));
        setCurrentIndex(1);
    });
    connect(ui->pushButtonCalibrateMass,&QPushButton::clicked,this,[=]{
        addWidget(new FormMassCalibration(this));
        setCurrentIndex(1);
    });
}

FormCalibration::~FormCalibration()
{
	delete ui;
}
