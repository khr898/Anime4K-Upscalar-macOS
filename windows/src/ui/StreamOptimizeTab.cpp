#include "StreamOptimizeTab.h"
#include <QIcon>

StreamOptimizeTab::StreamOptimizeTab(StreamOptimizeViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_viewModel(viewModel)
{
    initUI();

    connect(m_viewModel, &StreamOptimizeViewModel::filesChanged, this, &StreamOptimizeTab::refreshLeftPanel);
    connect(m_viewModel, &StreamOptimizeViewModel::filesChanged, this, &StreamOptimizeTab::updateStartButton);
    connect(m_viewModel, &StreamOptimizeViewModel::directoriesChanged, this, &StreamOptimizeTab::updateFromViewModel);
    connect(m_viewModel, &StreamOptimizeViewModel::configurationChanged, this, &StreamOptimizeTab::updateFromViewModel);
    connect(m_viewModel, &StreamOptimizeViewModel::viewStateChanged, this, &StreamOptimizeTab::refreshRightPanel);

    refreshLeftPanel();
    refreshRightPanel();
    updateFromViewModel();
    updateStartButton();
}

void StreamOptimizeTab::initUI() {
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);

    m_splitter = new QSplitter(Qt::Horizontal, this);
    m_splitter->setChildrenCollapsible(false);

    // Left Panel: Directory configuration & scanned files
    m_leftPanel = new QWidget(this);
    auto* leftLayout = new QVBoxLayout(m_leftPanel);
    leftLayout->setContentsMargins(12, 12, 12, 12);
    leftLayout->setSpacing(10);

    auto* srcTitle = new QLabel("Source Directory", m_leftPanel);
    srcTitle->setStyleSheet("font-weight: bold; color: #515154;");
    leftLayout->addWidget(srcTitle);

    auto* srcHBox = new QHBoxLayout();
    m_sourceDirEdit = new QLineEdit(m_leftPanel);
    m_sourceDirEdit->setReadOnly(true);
    m_sourceDirBrowseBtn = new QPushButton("Browse...", m_leftPanel);
    srcHBox->addWidget(m_sourceDirEdit);
    srcHBox->addWidget(m_sourceDirBrowseBtn);
    leftLayout->addLayout(srcHBox);

    auto* destTitle = new QLabel("Destination Directory", m_leftPanel);
    destTitle->setStyleSheet("font-weight: bold; color: #515154;");
    leftLayout->addWidget(destTitle);

    auto* destHBox = new QHBoxLayout();
    m_destDirEdit = new QLineEdit(m_leftPanel);
    m_destDirEdit->setReadOnly(true);
    m_destDirBrowseBtn = new QPushButton("Browse...", m_leftPanel);
    destHBox->addWidget(m_destDirEdit);
    destHBox->addWidget(m_destDirBrowseBtn);
    leftLayout->addLayout(destHBox);

    m_detectedFilesLabel = new QLabel("Scanned Files (0)", m_leftPanel);
    m_detectedFilesLabel->setStyleSheet("font-weight: bold; font-size: 13px; color: #1d1d1f;");
    leftLayout->addWidget(m_detectedFilesLabel);

    m_filesListWidget = new QListWidget(m_leftPanel);
    leftLayout->addWidget(m_filesListWidget);

    m_splitter->addWidget(m_leftPanel);

    // Right Stack setup
    m_rightStack = new QStackedWidget(this);

    // Config Panel Setup
    m_configContainer = new QWidget(this);
    auto* configLayout = new QVBoxLayout(m_configContainer);
    configLayout->setContentsMargins(16, 16, 16, 16);
    configLayout->setSpacing(12);

    auto* titleLabel = new QLabel("Streaming Optimization", m_configContainer);
    titleLabel->setStyleSheet("font-weight: bold; font-size: 14px; color: #1d1d1f;");
    configLayout->addWidget(titleLabel);

    auto* card = new QGroupBox(m_configContainer);
    auto* cardLayout = new QVBoxLayout(card);
    cardLayout->setSpacing(10);

    auto* gridLayout = new QGridLayout();
    gridLayout->setHorizontalSpacing(10);
    gridLayout->setVerticalSpacing(8);

    // Encoder
    auto* encLabel = new QLabel("Video Encoder", card);
    encLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_encoderCombo = new QComboBox(card);
    m_encoderCombo->addItem(displayName(StreamEncoder::HEVC_NVENC), static_cast<int>(StreamEncoder::HEVC_NVENC));
    m_encoderCombo->addItem(displayName(StreamEncoder::H264_NVENC), static_cast<int>(StreamEncoder::H264_NVENC));
    m_encoderCombo->addItem(displayName(StreamEncoder::HEVC_AMF), static_cast<int>(StreamEncoder::HEVC_AMF));
    m_encoderCombo->addItem(displayName(StreamEncoder::H264_AMF), static_cast<int>(StreamEncoder::H264_AMF));
    m_encoderCombo->addItem(displayName(StreamEncoder::HEVC_QSV), static_cast<int>(StreamEncoder::HEVC_QSV));
    m_encoderCombo->addItem(displayName(StreamEncoder::H264_QSV), static_cast<int>(StreamEncoder::H264_QSV));
    m_encoderCombo->addItem(displayName(StreamEncoder::SVT_AV1), static_cast<int>(StreamEncoder::SVT_AV1));
    gridLayout->addWidget(encLabel, 0, 0);
    gridLayout->addWidget(m_encoderCombo, 0, 1);

    // Profile
    auto* profLabel = new QLabel("Stream Profile", card);
    profLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_profileCombo = new QComboBox(card);
    gridLayout->addWidget(profLabel, 1, 0);
    gridLayout->addWidget(m_profileCombo, 1, 1);

    // Pixel Format
    auto* pixLabel = new QLabel("Pixel Format", card);
    pixLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_pixelFormatCombo = new QComboBox(card);
    gridLayout->addWidget(pixLabel, 2, 0);
    gridLayout->addWidget(m_pixelFormatCombo, 2, 1);

    // Audio Mode
    auto* audioLabel = new QLabel("Audio Track", card);
    audioLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_audioCombo = new QComboBox(card);
    m_audioCombo->addItem(displayName(StreamAudioMode::Copy), static_cast<int>(StreamAudioMode::Copy));
    m_audioCombo->addItem(displayName(StreamAudioMode::AACTranscode), static_cast<int>(StreamAudioMode::AACTranscode));
    m_audioCombo->addItem(displayName(StreamAudioMode::AAC128), static_cast<int>(StreamAudioMode::AAC128));
    m_audioCombo->addItem(displayName(StreamAudioMode::AAC192), static_cast<int>(StreamAudioMode::AAC192));
    m_audioCombo->addItem(displayName(StreamAudioMode::AAC256), static_cast<int>(StreamAudioMode::AAC256));
    gridLayout->addWidget(audioLabel, 3, 0);
    gridLayout->addWidget(m_audioCombo, 3, 1);

    // Subtitle Mode
    auto* subLabel = new QLabel("Subtitles", card);
    subLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_subtitleCombo = new QComboBox(card);
    m_subtitleCombo->addItem(displayName(StreamSubtitleMode::MovText), static_cast<int>(StreamSubtitleMode::MovText));
    m_subtitleCombo->addItem(displayName(StreamSubtitleMode::Copy), static_cast<int>(StreamSubtitleMode::Copy));
    m_subtitleCombo->addItem(displayName(StreamSubtitleMode::Strip), static_cast<int>(StreamSubtitleMode::Strip));
    gridLayout->addWidget(subLabel, 4, 0);
    gridLayout->addWidget(m_subtitleCombo, 4, 1);

    // Keyframe Interval
    auto* keyLabel = new QLabel("Keyframe Interval", card);
    keyLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_keyframeCombo = new QComboBox(card);
    m_keyframeCombo->addItem(displayName(KeyframeInterval::OneSecond), static_cast<int>(KeyframeInterval::OneSecond));
    m_keyframeCombo->addItem(displayName(KeyframeInterval::TwoSeconds), static_cast<int>(KeyframeInterval::TwoSeconds));
    m_keyframeCombo->addItem(displayName(KeyframeInterval::ThreeSeconds), static_cast<int>(KeyframeInterval::ThreeSeconds));
    m_keyframeCombo->addItem(displayName(KeyframeInterval::FiveSeconds), static_cast<int>(KeyframeInterval::FiveSeconds));
    m_keyframeCombo->addItem(displayName(KeyframeInterval::TenSeconds), static_cast<int>(KeyframeInterval::TenSeconds));
    gridLayout->addWidget(keyLabel, 5, 0);
    gridLayout->addWidget(m_keyframeCombo, 5, 1);

    cardLayout->addLayout(gridLayout);

    // Quality Slider
    auto* qLabel = new QLabel("Encoder Quality (CRF/Q)", card);
    qLabel->setStyleSheet("font-weight: bold; color: #515154;");
    cardLayout->addWidget(qLabel);

    auto* qualLayout = new QHBoxLayout();
    m_qualitySlider = new QSlider(Qt::Horizontal, card);
    m_qualitySpin = new QSpinBox(card);
    m_qualitySpin->setFixedWidth(60);
    qualLayout->addWidget(m_qualitySlider);
    qualLayout->addWidget(m_qualitySpin);
    cardLayout->addLayout(qualLayout);

    // Checkboxes
    m_faststartCheck = new QCheckBox("Enable Faststart (optimize for web playback)", card);
    m_faststartCheck->setStyleSheet("color: #1d1d1f;");
    cardLayout->addWidget(m_faststartCheck);

    m_allowSWFallbackCheck = new QCheckBox("Allow Software fallback if GPU encoding fails", card);
    m_allowSWFallbackCheck->setStyleSheet("color: #1d1d1f;");
    cardLayout->addWidget(m_allowSWFallbackCheck);

    configLayout->addWidget(card);
    configLayout->addStretch();

    // Footer
    auto* footerLayout = new QHBoxLayout();
    m_summaryLabel = new QLabel(m_configContainer);
    m_summaryLabel->setStyleSheet("color: #86868b; font-size: 12px;");

    m_startBtn = new QPushButton("Start Optimization", m_configContainer);
    m_startBtn->setIcon(QIcon(":/icons/play.svg"));
    m_startBtn->setObjectName("primaryButton");
    m_startBtn->setStyleSheet(
        "QPushButton#primaryButton {"
        "  background-color: #007aff;"
        "  border: 1px solid #0071e3;"
        "  color: #ffffff;"
        "  font-weight: bold;"
        "  padding: 10px 20px;"
        "  border-radius: 6px;"
        "  font-size: 14px;"
        "}"
        "QPushButton#primaryButton:hover {"
        "  background-color: #0071e3;"
        "}"
    );

    footerLayout->addWidget(m_summaryLabel);
    footerLayout->addStretch();
    footerLayout->addWidget(m_startBtn);
    configLayout->addLayout(footerLayout);

    // Processing View
    m_processingPanel = new ProcessingPanel(m_viewModel, this);

    m_rightStack->addWidget(m_configContainer);
    m_rightStack->addWidget(m_processingPanel);

    m_splitter->addWidget(m_rightStack);

    // Set initial splitter stretch ratios (35% left, 65% right)
    m_splitter->setStretchFactor(0, 35);
    m_splitter->setStretchFactor(1, 65);

    mainLayout->addWidget(m_splitter);

    // Connections
    connect(m_sourceDirBrowseBtn, &QPushButton::clicked, m_viewModel, &StreamOptimizeViewModel::selectSourceDirectory);
    connect(m_destDirBrowseBtn, &QPushButton::clicked, m_viewModel, &StreamOptimizeViewModel::selectDestinationDirectory);
    connect(m_encoderCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &StreamOptimizeTab::onEncoderChanged);
    connect(m_qualitySlider, &QSlider::valueChanged, this, &StreamOptimizeTab::onQualitySliderChanged);
    connect(m_qualitySpin, QOverload<int>::of(&QSpinBox::valueChanged), this, &StreamOptimizeTab::onQualitySpinChanged);
    connect(m_profileCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &StreamOptimizeTab::onProfileChanged);
    connect(m_pixelFormatCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &StreamOptimizeTab::onPixelFormatChanged);
    connect(m_audioCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &StreamOptimizeTab::onAudioModeChanged);
    connect(m_subtitleCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &StreamOptimizeTab::onSubtitleModeChanged);
    connect(m_keyframeCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &StreamOptimizeTab::onKeyframeIntervalChanged);
    connect(m_faststartCheck, &QCheckBox::stateChanged, this, &StreamOptimizeTab::onFaststartChanged);
    connect(m_allowSWFallbackCheck, &QCheckBox::stateChanged, this, &StreamOptimizeTab::onAllowSWFallbackChanged);
    connect(m_startBtn, &QPushButton::clicked, m_viewModel, &StreamOptimizeViewModel::startProcessing);
}

void StreamOptimizeTab::refreshLeftPanel() {
    m_filesListWidget->clear();
    const auto& files = m_viewModel->files();
    m_detectedFilesLabel->setText(QString("Detected Files (%1)").arg(files.size()));

    for (const auto& file : files) {
        QString duration = file.durationSeconds.has_value() ? file.formattedDuration() : "00:00:00";
        QString label = QString("%1 (%2 • %3)")
            .arg(file.fileName)
            .arg(file.formattedFileSize())
            .arg(duration);
        new QListWidgetItem(QIcon(":/icons/video.svg"), label, m_filesListWidget);
    }
}

void StreamOptimizeTab::refreshRightPanel() {
    if (m_viewModel->viewState() == StreamOptimizeViewModel::ViewState::Configuration) {
        m_rightStack->setCurrentWidget(m_configContainer);
    } else {
        m_rightStack->setCurrentWidget(m_processingPanel);
    }
}

void StreamOptimizeTab::updateStartButton() {
    m_startBtn->setEnabled(m_viewModel->canStartProcessing());
    if (!m_viewModel->files().isEmpty()) {
        m_summaryLabel->setText(QString("Batch: %1 (%2)")
            .arg(m_viewModel->totalFileSize())
            .arg(m_viewModel->totalDuration()));
    } else {
        m_summaryLabel->setText("");
    }
}

void StreamOptimizeTab::updateFromViewModel() {
    blockSignals(true);

    m_sourceDirEdit->setText(m_viewModel->sourceDisplayName());
    m_destDirEdit->setText(m_viewModel->destinationDisplayName());

    // Encoder
    int encIdx = m_encoderCombo->findData(static_cast<int>(m_viewModel->encoder()));
    if (encIdx >= 0) m_encoderCombo->setCurrentIndex(encIdx);

    // Populate dependent Profiles & Pixel formats
    m_profileCombo->clear();
    for (auto prof : availableProfiles(m_viewModel->encoder())) {
        m_profileCombo->addItem(displayName(prof), static_cast<int>(prof));
    }
    int profIdx = m_profileCombo->findData(static_cast<int>(m_viewModel->profile()));
    if (profIdx >= 0) m_profileCombo->setCurrentIndex(profIdx);

    m_pixelFormatCombo->clear();
    for (auto pix : availablePixelFormats(m_viewModel->encoder())) {
        m_pixelFormatCombo->addItem(displayName(pix), static_cast<int>(pix));
    }
    int pixIdx = m_pixelFormatCombo->findData(static_cast<int>(m_viewModel->pixelFormat()));
    if (pixIdx >= 0) m_pixelFormatCombo->setCurrentIndex(pixIdx);

    // Quality limits
    int maxQ = maxQuality(m_viewModel->encoder());
    m_qualitySlider->setMaximum(maxQ);
    m_qualitySpin->setMaximum(maxQ);
    m_qualitySlider->setValue(m_viewModel->quality());
    m_qualitySpin->setValue(m_viewModel->quality());

    // Other Combos
    int audIdx = m_audioCombo->findData(static_cast<int>(m_viewModel->audioMode()));
    if (audIdx >= 0) m_audioCombo->setCurrentIndex(audIdx);

    int subIdx = m_subtitleCombo->findData(static_cast<int>(m_viewModel->subtitleMode()));
    if (subIdx >= 0) m_subtitleCombo->setCurrentIndex(subIdx);

    int keyIdx = m_keyframeCombo->findData(static_cast<int>(m_viewModel->keyframeInterval()));
    if (keyIdx >= 0) m_keyframeCombo->setCurrentIndex(keyIdx);

    m_faststartCheck->setChecked(m_viewModel->faststart());
    m_allowSWFallbackCheck->setChecked(m_viewModel->allowSWFallback());

    blockSignals(false);
}

void StreamOptimizeTab::onEncoderChanged(int index) {
    if (index >= 0) {
        auto enc = static_cast<StreamEncoder>(m_encoderCombo->itemData(index).toInt());
        m_viewModel->setEncoder(enc);
        m_viewModel->onEncoderChanged();
        updateFromViewModel();
    }
}

void StreamOptimizeTab::onQualitySliderChanged(int value) {
    m_viewModel->setQuality(value);
    blockSignals(true);
    m_qualitySpin->setValue(value);
    blockSignals(false);
}

void StreamOptimizeTab::onQualitySpinChanged(int value) {
    m_viewModel->setQuality(value);
    blockSignals(true);
    m_qualitySlider->setValue(value);
    blockSignals(false);
}

void StreamOptimizeTab::onProfileChanged(int index) {
    if (index >= 0) {
        auto prof = static_cast<StreamProfile>(m_profileCombo->itemData(index).toInt());
        m_viewModel->setProfile(prof);
    }
}

void StreamOptimizeTab::onPixelFormatChanged(int index) {
    if (index >= 0) {
        auto pix = static_cast<StreamPixelFormat>(m_pixelFormatCombo->itemData(index).toInt());
        m_viewModel->setPixelFormat(pix);
    }
}

void StreamOptimizeTab::onAudioModeChanged(int index) {
    if (index >= 0) {
        auto mode = static_cast<StreamAudioMode>(m_audioCombo->itemData(index).toInt());
        m_viewModel->setAudioMode(mode);
    }
}

void StreamOptimizeTab::onSubtitleModeChanged(int index) {
    if (index >= 0) {
        auto mode = static_cast<StreamSubtitleMode>(m_subtitleCombo->itemData(index).toInt());
        m_viewModel->setSubtitleMode(mode);
    }
}

void StreamOptimizeTab::onKeyframeIntervalChanged(int index) {
    if (index >= 0) {
        auto val = static_cast<KeyframeInterval>(m_keyframeCombo->itemData(index).toInt());
        m_viewModel->setKeyframeInterval(val);
    }
}

void StreamOptimizeTab::onFaststartChanged(int state) {
    m_viewModel->setFaststart(state == Qt::Checked);
}

void StreamOptimizeTab::onAllowSWFallbackChanged(int state) {
    m_viewModel->setAllowSWFallback(state == Qt::Checked);
}
