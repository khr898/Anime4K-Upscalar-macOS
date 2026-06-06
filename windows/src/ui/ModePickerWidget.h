#pragma once

#include <QWidget>
#include <QButtonGroup>
#include <QPushButton>
#include <QListWidget>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include "../models/Models.h"
#include "../viewmodels/AppViewModel.h"

class ModePickerWidget : public QWidget {
    Q_OBJECT
public:
    explicit ModePickerWidget(AppViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void refreshCategoryModes();
    void selectMode(int index);
    void updateFromViewModel();

private:
    void initUI();

    AppViewModel* m_viewModel;
    QButtonGroup* m_categoryButtonGroup;
    QPushButton* m_hqButton;
    QPushButton* m_fastButton;
    QPushButton* m_noUpButton;
    QPushButton* m_neuralButton;
    QPushButton* m_specialButton;
    QListWidget* m_modeListWidget;

    ModeCategory m_currentCategory = ModeCategory::HQ;
    QVector<Anime4KMode> m_displayedModes;
};
