#pragma once

#include <QWidget>
#include <QLabel>
#include <QProgressBar>
#include <QScrollArea>
#include <QPushButton>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include "../viewmodels/AppViewModel.h"
#include "../viewmodels/CompressViewModel.h"
#include "../viewmodels/StreamOptimizeViewModel.h"
#include "ProgressRowWidget.h"

class ProcessingPanel : public QWidget {
    Q_OBJECT
public:
    explicit ProcessingPanel(AppViewModel* viewModel, QWidget* parent = nullptr);
    explicit ProcessingPanel(CompressViewModel* viewModel, QWidget* parent = nullptr);
    explicit ProcessingPanel(StreamOptimizeViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void updateUI();
    void onCancelClicked();
    void onReturnClicked();

private:
    void initUI();
    void populateJobs();

    AppViewModel* m_appViewModel = nullptr;
    CompressViewModel* m_compressViewModel = nullptr;
    StreamOptimizeViewModel* m_streamOptimizeViewModel = nullptr;

    QLabel* m_summaryLabel;
    QLabel* m_statsLabel;
    QProgressBar* m_overallProgressBar;
    QScrollArea* m_scrollArea;
    QWidget* m_scrollContent;
    QVBoxLayout* m_scrollLayout;
    
    QPushButton* m_cancelButton;
    QPushButton* m_returnButton;

    bool m_populated = false;
};
