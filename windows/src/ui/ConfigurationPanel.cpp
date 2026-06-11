#include "ConfigurationPanel.h"
#include <QFileDialog>

ConfigurationPanel::ConfigurationPanel(AppViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_viewModel(viewModel)
{
    initUI();
    connect(m_viewModel, &AppViewModel::configurationChanged, this, &ConfigurationPanel::updateFromViewModel);
    connect(m_viewModel, &AppViewModel::outputDirectoryChanged, this, &ConfigurationPanel::updateFromViewModel);
    updateFromViewModel();
}

void ConfigurationPanel::initUI() {
    auto* layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(14);

    m_sectionTitle = new QLabel("Upscale Configuration", this);
    m_sectionTitle->setStyleSheet("font-weight: bold; font-size: 14px; color: #1d1d1f;");
    layout->addWidget(m_sectionTitle);

    // GroupBox Card
    auto* card = new QGroupBox(this);
    auto* cardLayout = new QVBoxLayout(card);
    cardLayout->setSpacing(12);

    // 1. Target Resolution Section
    auto* resLabel = new QLabel("Target Resolution", card);
    resLabel->setStyleSheet("font-weight: bold; color: #515154;");
    cardLayout->addWidget(resLabel);

    auto* resButtonsWidget = new QWidget(card);
    resButtonsWidget->setStyleSheet("background-color: #e8e8ed; border-radius: 6px; padding: 2px;");
    auto* resButtonsLayout = new QHBoxLayout(resButtonsWidget);
    resButtonsLayout->setContentsMargins(0, 0, 0, 0);
    resButtonsLayout->setSpacing(2);

    m_resOriginalBtn = new QPushButton("Original Size", card);
    m_resDoubleBtn = new QPushButton("2x Scale", card);
    m_resQuadrupleBtn = new QPushButton("4x Scale", card);

    QString segmentStyle = 
        "QPushButton {"
        "  background-color: transparent;"
        "  border: none;"
        "  border-radius: 4px;"
        "  padding: 6px 12px;"
        "  color: #515154;"
        "  font-weight: 500;"
        "}"
        "QPushButton:checked {"
        "  background-color: #ffffff;"
        "  color: #1d1d1f;"
        "  font-weight: bold;"
        "}"
        "QPushButton:hover:!checked {"
        "  background-color: #f0f0f5;"
        "}";

    m_resOriginalBtn->setStyleSheet(segmentStyle);
    m_resDoubleBtn->setStyleSheet(segmentStyle);
    m_resQuadrupleBtn->setStyleSheet(segmentStyle);

    m_resOriginalBtn->setCheckable(true);
    m_resDoubleBtn->setCheckable(true);
    m_resQuadrupleBtn->setCheckable(true);

    m_resolutionGroup = new QButtonGroup(card);
    m_resolutionGroup->addButton(m_resOriginalBtn, static_cast<int>(TargetResolution::KeepOriginal));
    m_resolutionGroup->addButton(m_resDoubleBtn, static_cast<int>(TargetResolution::Double));
    m_resolutionGroup->addButton(m_resQuadrupleBtn, static_cast<int>(TargetResolution::Quadruple));
    m_resolutionGroup->setExclusive(true);

    resButtonsLayout->addWidget(m_resOriginalBtn);
    resButtonsLayout->addWidget(m_resDoubleBtn);
    resButtonsLayout->addWidget(m_resQuadrupleBtn);
    cardLayout->addWidget(resButtonsWidget);

    // Grid Layout for Codec, Preset
    auto* gridLayout = new QGridLayout();
    gridLayout->setHorizontalSpacing(10);
    gridLayout->setVerticalSpacing(10);

    // 2. Video Codec
    auto* codecLabel = new QLabel("Video Codec", card);
    codecLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_codecCombo = new QComboBox(card);
    m_codecCombo->addItem(displayName(VideoCodec::HEVC_NVENC), static_cast<int>(VideoCodec::HEVC_NVENC));
    m_codecCombo->addItem(displayName(VideoCodec::HEVC_AMF), static_cast<int>(VideoCodec::HEVC_AMF));
    m_codecCombo->addItem(displayName(VideoCodec::HEVC_QSV), static_cast<int>(VideoCodec::HEVC_QSV));
    m_codecCombo->addItem(displayName(VideoCodec::H264_NVENC), static_cast<int>(VideoCodec::H264_NVENC));
    m_codecCombo->addItem(displayName(VideoCodec::H264_AMF), static_cast<int>(VideoCodec::H264_AMF));
    m_codecCombo->addItem(displayName(VideoCodec::H264_QSV), static_cast<int>(VideoCodec::H264_QSV));
    m_codecCombo->addItem(displayName(VideoCodec::SVT_AV1), static_cast<int>(VideoCodec::SVT_AV1));

    gridLayout->addWidget(codecLabel, 0, 0);
    gridLayout->addWidget(m_codecCombo, 0, 1);

    // 3. Compression Preset
    auto* presetLabel = new QLabel("Compression Preset", card);
    presetLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_presetCombo = new QComboBox(card);
    m_presetCombo->addItem(displayName(CompressionPreset::VisuallyLossless), static_cast<int>(CompressionPreset::VisuallyLossless));
    m_presetCombo->addItem(displayName(CompressionPreset::Balanced), static_cast<int>(CompressionPreset::Balanced));
    m_presetCombo->addItem(displayName(CompressionPreset::CustomQuality), static_cast<int>(CompressionPreset::CustomQuality));
    m_presetCombo->addItem(displayName(CompressionPreset::FixedBitrate), static_cast<int>(CompressionPreset::FixedBitrate));

    gridLayout->addWidget(presetLabel, 1, 0);
    gridLayout->addWidget(m_presetCombo, 1, 1);

    cardLayout->addLayout(gridLayout);

    // 4. Custom Quality Slider
    m_qualityContainer = new QWidget(card);
    auto* qualLayout = new QHBoxLayout(m_qualityContainer);
    qualLayout->setContentsMargins(0, 0, 0, 0);
    auto* qualLabel = new QLabel("Quality (CRF/Q):", m_qualityContainer);
    qualLabel->setStyleSheet("font-weight: bold; color: #515154;");
    qualLabel->setMinimumWidth(100);
    m_qualitySlider = new QSlider(Qt::Horizontal, m_qualityContainer);
    m_qualitySlider->setRange(0, 100);
    m_qualitySpin = new QSpinBox(m_qualityContainer);
    m_qualitySpin->setRange(0, 100);
    m_qualitySpin->setFixedWidth(60);

    qualLayout->addWidget(qualLabel);
    qualLayout->addWidget(m_qualitySlider);
    qualLayout->addWidget(m_qualitySpin);
    cardLayout->addWidget(m_qualityContainer);

    // 5. Custom Bitrate Slider
    m_bitrateContainer = new QWidget(card);
    auto* bitLayout = new QHBoxLayout(m_bitrateContainer);
    bitLayout->setContentsMargins(0, 0, 0, 0);
    auto* bitLabel = new QLabel("Bitrate (Mbps):", m_bitrateContainer);
    bitLabel->setStyleSheet("font-weight: bold; color: #515154;");
    bitLabel->setMinimumWidth(100);
    m_bitrateSlider = new QSlider(Qt::Horizontal, m_bitrateContainer);
    m_bitrateSlider->setRange(1, 150);
    m_bitrateSpin = new QSpinBox(m_bitrateContainer);
    m_bitrateSpin->setRange(1, 150);
    m_bitrateSpin->setFixedWidth(60);

    bitLayout->addWidget(bitLabel);
    bitLayout->addWidget(m_bitrateSlider);
    bitLayout->addWidget(m_bitrateSpin);
    cardLayout->addWidget(m_bitrateContainer);

    // 5b. SVT-AV1 Speed Preset Slider
    m_svtPresetContainer = new QWidget(card);
    auto* svtVLayout = new QVBoxLayout(m_svtPresetContainer);
    svtVLayout->setContentsMargins(0, 0, 0, 0);
    svtVLayout->setSpacing(4);

    auto* svtHLayout = new QHBoxLayout();
    svtHLayout->setContentsMargins(0, 0, 0, 0);
    auto* svtLabel = new QLabel("AV1 Speed Preset:", m_svtPresetContainer);
    svtLabel->setStyleSheet("font-weight: bold; color: #515154;");
    svtLabel->setMinimumWidth(100);
    m_svtPresetSlider = new QSlider(Qt::Horizontal, m_svtPresetContainer);
    m_svtPresetSlider->setRange(0, 13);
    m_svtPresetSpin = new QSpinBox(m_svtPresetContainer);
    m_svtPresetSpin->setRange(0, 13);
    m_svtPresetSpin->setFixedWidth(60);

    svtHLayout->addWidget(svtLabel);
    svtHLayout->addWidget(m_svtPresetSlider);
    svtHLayout->addWidget(m_svtPresetSpin);
    svtVLayout->addLayout(svtHLayout);

    m_svtPresetDescLabel = new QLabel(m_svtPresetContainer);
    m_svtPresetDescLabel->setStyleSheet("color: #8e8e93; font-size: 11px;");
    svtVLayout->addWidget(m_svtPresetDescLabel);

    cardLayout->addWidget(m_svtPresetContainer);

    // 6. Long GOP Checkbox
    m_longGOPCheck = new QCheckBox("Optimize compression (Long GOP / Keyframe 10s)", card);
    m_longGOPCheck->setStyleSheet("color: #1d1d1f;");
    cardLayout->addWidget(m_longGOPCheck);

    // 7. Output Directory
    auto* outLabel = new QLabel("Output Directory", card);
    outLabel->setStyleSheet("font-weight: bold; color: #515154;");
    cardLayout->addWidget(outLabel);

    auto* outDirLayout = new QHBoxLayout();
    m_outputDirEdit = new QLineEdit(card);
    m_outputDirEdit->setReadOnly(true);
    m_outputDirBrowseBtn = new QPushButton("Browse...", card);

    outDirLayout->addWidget(m_outputDirEdit);
    outDirLayout->addWidget(m_outputDirBrowseBtn);
    cardLayout->addLayout(outDirLayout);

    layout->addWidget(card);

    // Connections
    connect(m_resolutionGroup, &QButtonGroup::idClicked, this, &ConfigurationPanel::onResolutionSelected);
    connect(m_codecCombo, &QComboBox::currentIndexChanged, this, &ConfigurationPanel::onCodecChanged);
    connect(m_presetCombo, &QComboBox::currentIndexChanged, this, &ConfigurationPanel::onPresetChanged);
    connect(m_qualitySlider, &QSlider::valueChanged, this, &ConfigurationPanel::onQualitySliderChanged);
    connect(m_qualitySpin, &QSpinBox::valueChanged, this, &ConfigurationPanel::onQualitySpinChanged);
    connect(m_bitrateSlider, &QSlider::valueChanged, this, &ConfigurationPanel::onBitrateSliderChanged);
    connect(m_bitrateSpin, &QSpinBox::valueChanged, this, &ConfigurationPanel::onBitrateSpinChanged);
    connect(m_longGOPCheck, &QCheckBox::stateChanged, this, &ConfigurationPanel::onLongGOPChanged);
    connect(m_svtPresetSlider, &QSlider::valueChanged, this, &ConfigurationPanel::onSvtPresetSliderChanged);
    connect(m_svtPresetSpin, &QSpinBox::valueChanged, this, &ConfigurationPanel::onSvtPresetSpinChanged);
    connect(m_outputDirBrowseBtn, &QPushButton::clicked, m_viewModel, &AppViewModel::selectOutputDirectory);
}

void ConfigurationPanel::updateFromViewModel() {
    const auto& config = m_viewModel->configuration();
    
    // Block signals to avoid feedback loop
    blockSignals(true);

    // Resolution
    QPushButton* btn = qobject_cast<QPushButton*>(m_resolutionGroup->button(static_cast<int>(config.resolution)));
    if (btn) btn->setChecked(true);

    // Codec
    int codecIdx = m_codecCombo->findData(static_cast<int>(config.codec));
    if (codecIdx >= 0) m_codecCombo->setCurrentIndex(codecIdx);

    // Preset
    int presetIdx = m_presetCombo->findData(static_cast<int>(m_viewModel->compressionPreset()));
    if (presetIdx >= 0) m_presetCombo->setCurrentIndex(presetIdx);

    // Custom UI visibility & sliders
    CompressionPreset preset = m_viewModel->compressionPreset();
    m_qualityContainer->setVisible(preset == CompressionPreset::CustomQuality);
    m_bitrateContainer->setVisible(preset == CompressionPreset::FixedBitrate);

    int qualMax = maxQuality(config.codec);
    m_qualitySlider->setMaximum(qualMax);
    m_qualitySpin->setMaximum(qualMax);

    m_qualitySlider->setValue(m_viewModel->customQualityValue());
    m_qualitySpin->setValue(m_viewModel->customQualityValue());

    m_bitrateSlider->setValue(m_viewModel->customBitrateValue());
    m_bitrateSpin->setValue(m_viewModel->customBitrateValue());

    // Update SVT-AV1 preset UI
    bool isAV1 = (config.codec == VideoCodec::SVT_AV1);
    m_svtPresetContainer->setVisible(isAV1);
    m_svtPresetSlider->setValue(config.svtAV1Preset);
    m_svtPresetSpin->setValue(config.svtAV1Preset);
    
    // Update SVT-AV1 preset description text
    QString desc;
    int p = config.svtAV1Preset;
    if (p >= 0 && p <= 3) desc = "Archival (Slowest, Maximum Compression)";
    else if (p >= 4 && p <= 6) desc = "Standard (Balanced Speed & Quality - Recommended)";
    else if (p >= 7 && p <= 10) desc = "Fast (High Speed, Moderate Compression)";
    else if (p >= 11 && p <= 13) desc = "Real-time (Ultra Fast, Lower Compression)";
    m_svtPresetDescLabel->setText(desc);

    m_longGOPCheck->setChecked(config.longGOPEnabled);
    m_outputDirEdit->setText(m_viewModel->outputDirectoryDisplayName());

    blockSignals(false);
}

void ConfigurationPanel::onResolutionSelected(int id) {
    m_viewModel->configurationRef().resolution = static_cast<TargetResolution>(id);
    emit m_viewModel->configurationChanged();
}

void ConfigurationPanel::onCodecChanged(int index) {
    if (index >= 0) {
        VideoCodec codec = static_cast<VideoCodec>(m_codecCombo->itemData(index).toInt());
        m_viewModel->configurationRef().codec = codec;
        m_viewModel->onCodecChanged();
        emit m_viewModel->configurationChanged();
    }
}

void ConfigurationPanel::onPresetChanged(int index) {
    if (index >= 0) {
        CompressionPreset preset = static_cast<CompressionPreset>(m_presetCombo->itemData(index).toInt());
        m_viewModel->setCompressionPreset(preset);
    }
}

void ConfigurationPanel::onQualitySliderChanged(int value) {
    m_viewModel->updateCustomQuality(value);
}

void ConfigurationPanel::onQualitySpinChanged(int value) {
    m_viewModel->updateCustomQuality(value);
}

void ConfigurationPanel::onBitrateSliderChanged(int value) {
    m_viewModel->updateCustomBitrate(value);
}

void ConfigurationPanel::onBitrateSpinChanged(int value) {
    m_viewModel->updateCustomBitrate(value);
}

void ConfigurationPanel::onLongGOPChanged(int state) {
    m_viewModel->configurationRef().longGOPEnabled = (state == Qt::Checked);
    emit m_viewModel->configurationChanged();
}

void ConfigurationPanel::onSvtPresetSliderChanged(int value) {
    m_viewModel->configurationRef().svtAV1Preset = value;
    m_svtPresetSpin->blockSignals(true);
    m_svtPresetSpin->setValue(value);
    m_svtPresetSpin->blockSignals(false);
    
    QString desc;
    if (value >= 0 && value <= 3) desc = "Archival (Slowest, Maximum Compression)";
    else if (value >= 4 && value <= 6) desc = "Standard (Balanced Speed & Quality - Recommended)";
    else if (value >= 7 && value <= 10) desc = "Fast (High Speed, Moderate Compression)";
    else if (value >= 11 && value <= 13) desc = "Real-time (Ultra Fast, Lower Compression)";
    m_svtPresetDescLabel->setText(desc);

    emit m_viewModel->configurationChanged();
}

void ConfigurationPanel::onSvtPresetSpinChanged(int value) {
    m_viewModel->configurationRef().svtAV1Preset = value;
    m_svtPresetSlider->blockSignals(true);
    m_svtPresetSlider->setValue(value);
    m_svtPresetSlider->blockSignals(false);

    QString desc;
    if (value >= 0 && value <= 3) desc = "Archival (Slowest, Maximum Compression)";
    else if (value >= 4 && value <= 6) desc = "Standard (Balanced Speed & Quality - Recommended)";
    else if (value >= 7 && value <= 10) desc = "Fast (High Speed, Moderate Compression)";
    else if (value >= 11 && value <= 13) desc = "Real-time (Ultra Fast, Lower Compression)";
    m_svtPresetDescLabel->setText(desc);

    emit m_viewModel->configurationChanged();
}
