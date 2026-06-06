#pragma once

#include <QWidget>
#include <QStackedWidget>
#include <QSplitter>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QPushButton>
#include <QLabel>
#include <QComboBox>
#include <QSlider>
#include <QSpinBox>
#include <QCheckBox>
#include <QLineEdit>
#include <QGroupBox>
#include "../viewmodels/CompressViewModel.h"
#include "EmptyStateWidget.h"
#include "FileListPanel.h"
#include "ProcessingPanel.h"

class CompressTab : public QWidget {
    Q_OBJECT
public:
    explicit CompressTab(CompressViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void refreshLeftPanel();
    void refreshRightPanel();
    void updateStartButton();
    void updateFromViewModel();
    void onEncoderChanged(int index);
    void onQualitySliderChanged(int value);
    void onQualitySpinChanged(int value);
    void onContentTypeChanged(int index);
    void onBFramesChanged(int value);
    void onLongGOPChanged(int state);

private:
    void initUI();

    CompressViewModel* m_viewModel;

    QSplitter* m_splitter;

    // Left Stack
    QStackedWidget* m_leftStack;
    EmptyStateWidget* m_emptyWidget;
    FileListPanel* m_fileListPanel;

    // Right Stack
    QStackedWidget* m_rightStack;

    // Config Mode Views
    QWidget* m_configContainer;
    QComboBox* m_encoderCombo;
    QSlider* m_qualitySlider;
    QSpinBox* m_qualitySpin;
    QComboBox* m_contentTypeCombo;
    QSpinBox* m_bFramesSpin;
    QCheckBox* m_longGOPCheck;
    QLineEdit* m_outputDirEdit;
    QPushButton* m_outputDirBrowseBtn;

    QLabel* m_summaryLabel;
    QPushButton* m_startBtn;

    // Processing View
    ProcessingPanel* m_processingPanel;
};
