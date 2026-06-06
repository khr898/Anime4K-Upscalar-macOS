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
#include <QListWidget>
#include <QGroupBox>
#include "../viewmodels/StreamOptimizeViewModel.h"
#include "ProcessingPanel.h"

class StreamOptimizeTab : public QWidget {
    Q_OBJECT
public:
    explicit StreamOptimizeTab(StreamOptimizeViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void refreshLeftPanel();
    void refreshRightPanel();
    void updateStartButton();
    void updateFromViewModel();
    void onEncoderChanged(int index);
    void onQualitySliderChanged(int value);
    void onQualitySpinChanged(int value);
    void onProfileChanged(int index);
    void onPixelFormatChanged(int index);
    void onAudioModeChanged(int index);
    void onSubtitleModeChanged(int index);
    void onKeyframeIntervalChanged(int index);
    void onFaststartChanged(int state);
    void onAllowSWFallbackChanged(int state);

private:
    void initUI();

    StreamOptimizeViewModel* m_viewModel;

    QSplitter* m_splitter;

    // Left Panel (Paths & Files)
    QWidget* m_leftPanel;
    QLineEdit* m_sourceDirEdit;
    QPushButton* m_sourceDirBrowseBtn;
    QLineEdit* m_destDirEdit;
    QPushButton* m_destDirBrowseBtn;
    QLabel* m_detectedFilesLabel;
    QListWidget* m_filesListWidget;

    // Right Stack
    QStackedWidget* m_rightStack;

    // Configuration View
    QWidget* m_configContainer;
    QComboBox* m_encoderCombo;
    QSlider* m_qualitySlider;
    QSpinBox* m_qualitySpin;
    QComboBox* m_profileCombo;
    QComboBox* m_pixelFormatCombo;
    QComboBox* m_audioCombo;
    QComboBox* m_subtitleCombo;
    QComboBox* m_keyframeCombo;
    QCheckBox* m_faststartCheck;
    QCheckBox* m_allowSWFallbackCheck;

    QLabel* m_summaryLabel;
    QPushButton* m_startBtn;

    // Processing View
    ProcessingPanel* m_processingPanel;
};
