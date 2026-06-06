#pragma once

#include <QWidget>
#include <QLabel>
#include <QComboBox>
#include <QSlider>
#include <QSpinBox>
#include <QCheckBox>
#include <QLineEdit>
#include <QPushButton>
#include <QGroupBox>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QButtonGroup>
#include "../models/Models.h"
#include "../viewmodels/AppViewModel.h"

class ConfigurationPanel : public QWidget {
    Q_OBJECT
public:
    explicit ConfigurationPanel(AppViewModel* viewModel, QWidget* parent = nullptr);

private slots:
    void updateFromViewModel();
    void onResolutionSelected(int id);
    void onCodecChanged(int index);
    void onPresetChanged(int index);
    void onQualitySliderChanged(int value);
    void onQualitySpinChanged(int value);
    void onBitrateSliderChanged(int value);
    void onBitrateSpinChanged(int value);
    void onLongGOPChanged(int state);

private:
    void initUI();

    AppViewModel* m_viewModel;

    // UI elements
    QLabel* m_sectionTitle;
    
    // Resolution Segment buttons
    QButtonGroup* m_resolutionGroup;
    QPushButton* m_resOriginalBtn;
    QPushButton* m_resDoubleBtn;
    QPushButton* m_resQuadrupleBtn;

    QComboBox* m_codecCombo;
    QComboBox* m_presetCombo;

    // Quality slider/spinbox
    QWidget* m_qualityContainer;
    QSlider* m_qualitySlider;
    QSpinBox* m_qualitySpin;

    // Bitrate slider/spinbox
    QWidget* m_bitrateContainer;
    QSlider* m_bitrateSlider;
    QSpinBox* m_bitrateSpin;

    QCheckBox* m_longGOPCheck;

    // Output directory
    QLineEdit* m_outputDirEdit;
    QPushButton* m_outputDirBrowseBtn;
};
