#include "checkbox.h"

CheckBox::CheckBox(QWidget *parent):QCheckBox(parent) {}

bool CheckBox::hitButton(const QPoint &pos) const
{
    return true;
}
