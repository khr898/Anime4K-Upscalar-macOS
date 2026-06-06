#pragma once

#include <QWidget>
#include <QStackedWidget>
#include <QSplitter>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QPushButton>
#include <QLabel>
#include "../viewmodels/AppViewModel.h"
#include "EmptyStateWidget.h"
#include "FileListPanel.h"
#include "ModePickerWidget.h"
#include "ConfigurationPanel.h"
#include "ProcessingPanel.h"

class UpscaleTab : public QWidget {
    Q_OBJECT
public:
    explicit UpscaleTab(AppViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void refreshLeftPanel();
    void refreshRightPanel();
    void updateStartButton();

private:
    void initUI();

    AppViewModel* m_viewModel;

    QSplitter* m_splitter;
    
    // Left Stack
    QStackedWidget* m_leftStack;
    EmptyStateWidget* m_emptyWidget;
    FileListPanel* m_fileListPanel;

    // Right Stack
    QStackedWidget* m_rightStack;
    
    // Config Mode Views
    QWidget* m_configContainer;
    ModePickerWidget* m_modePicker;
    ConfigurationPanel* m_configPanel;
    QLabel* m_summaryLabel;
    QPushButton* m_startBtn;

    // Processing View
    ProcessingPanel* m_processingPanel;
};
