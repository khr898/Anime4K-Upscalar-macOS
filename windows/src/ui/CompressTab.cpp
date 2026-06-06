#include "CompressTab.h"
#include <QIcon>

CompressTab::CompressTab(CompressViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_viewModel(viewModel)
{
    initUI();

    connect(m_viewModel, &CompressViewModel::filesChanged, this, &CompressTab::refreshLeftPanel);
    connect(m_viewModel, &CompressViewModel::filesChanged, this, &CompressTab::updateStartButton);
    connect(m_viewModel, &CompressViewModel::configurationChanged, this, &CompressTab::updateFromViewModel);
    connect(m_viewModel, &CompressViewModel::configurationChanged, this, &CompressTab::updateStartButton);
    connect(m_viewModel, &CompressViewModel::outputDirectoryChanged, this, &CompressTab::updateFromViewModel);
    connect(m_viewModel, &CompressViewModel::viewStateChanged, this, &CompressTab::refreshRightPanel);

    refreshLeftPanel();
    refreshRightPanel();
    updateFromViewModel();
    updateStartButton();
}

void CompressTab::initUI() {
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);

    m_splitter = new QSplitter(Qt::Horizontal, this);
    m_splitter->setChildrenCollapsible(false);

    // Left Stack setup
    m_leftStack = new QStackedWidget(this);
    m_emptyWidget = new EmptyStateWidget(
        "No Video Files Selected",
        "Drag & drop video files here, or click Add Files to start compression.",
        "Add Files...",
        this
    );
    m_fileListPanel = new FileListPanel(m_viewModel, this);

    m_leftStack->addWidget(m_emptyWidget);
    m_leftStack->addWidget(m_fileListPanel);

    connect(m_emptyWidget, &EmptyStateWidget::addFilesRequested, m_viewModel, &CompressViewModel::addFiles);
    connect(m_emptyWidget, &EmptyStateWidget::filesDropped, m_viewModel, &CompressViewModel::addFilesFromDrop);
    connect(m_fileListPanel, &FileListPanel::filesDropped, m_viewModel, &CompressViewModel::addFilesFromDrop);

    m_splitter->addWidget(m_leftStack);

    // Right Stack setup
    m_rightStack = new QStackedWidget(this);

    // Config Panel Setup
    m_configContainer = new QWidget(this);
    auto* configLayout = new QVBoxLayout(m_configContainer);
    configLayout->setContentsMargins(16, 16, 16, 16);
    configLayout->setSpacing(14);

    auto* titleLabel = new QLabel("Compression Settings", m_configContainer);
    titleLabel->setStyleSheet("font-weight: bold; font-size: 14px; color: #1d1d1f;");
    configLayout->addWidget(titleLabel);

    // Card Box
    auto* card = new QGroupBox(m_configContainer);
    auto* cardLayout = new QVBoxLayout(card);
    cardLayout->setSpacing(12);

    auto* gridLayout = new QGridLayout();
    gridLayout->setHorizontalSpacing(10);
    gridLayout->setVerticalSpacing(10);

    // Encoder
    auto* encLabel = new QLabel("Video Encoder", card);
    encLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_encoderCombo = new QComboBox(card);
    m_encoderCombo->addItem(displayName(CompressEncoder::HEVC_NVENC), static_cast<int>(CompressEncoder::HEVC_NVENC));
    m_encoderCombo->addItem(displayName(CompressEncoder::HEVC_AMF), static_cast<int>(CompressEncoder::HEVC_AMF));
    m_encoderCombo->addItem(displayName(CompressEncoder::HEVC_QSV), static_cast<int>(CompressEncoder::HEVC_QSV));
    m_encoderCombo->addItem(displayName(CompressEncoder::SVT_AV1), static_cast<int>(CompressEncoder::SVT_AV1));
    gridLayout->addWidget(encLabel, 0, 0);
    gridLayout->addWidget(m_encoderCombo, 0, 1);

    // Content Type
    auto* typeLabel = new QLabel("Content Type", card);
    typeLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_contentTypeCombo = new QComboBox(card);
    m_contentTypeCombo->addItem(displayName(ContentType::LiveAction), static_cast<int>(ContentType::LiveAction));
    m_contentTypeCombo->addItem(displayName(ContentType::Anime), static_cast<int>(ContentType::Anime));
    gridLayout->addWidget(typeLabel, 1, 0);
    gridLayout->addWidget(m_contentTypeCombo, 1, 1);

    // B-Frames
    auto* bLabel = new QLabel("B-Frames count", card);
    bLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_bFramesSpin = new QSpinBox(card);
    m_bFramesSpin->setRange(0, 16);
    gridLayout->addWidget(bLabel, 2, 0);
    gridLayout->addWidget(m_bFramesSpin, 2, 1);

    cardLayout->addLayout(gridLayout);

    // Quality Slider/SpinBox
    auto* qualLabel = new QLabel("Encoder Quality (CRF/Q)", card);
    qualLabel->setStyleSheet("font-weight: bold; color: #515154;");
    cardLayout->addWidget(qualLabel);

    auto* qualLayout = new QHBoxLayout();
    m_qualitySlider = new QSlider(Qt::Horizontal, card);
    m_qualitySpin = new QSpinBox(card);
    m_qualitySpin->setFixedWidth(60);

    qualLayout->addWidget(m_qualitySlider);
    qualLayout->addWidget(m_qualitySpin);
    cardLayout->addLayout(qualLayout);

    // Long GOP
    m_longGOPCheck = new QCheckBox("Optimize compression (Long GOP / Keyframe 10s)", card);
    m_longGOPCheck->setStyleSheet("color: #1d1d1f;");
    cardLayout->addWidget(m_longGOPCheck);

    // Output Directory
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

    configLayout->addWidget(card);
    configLayout->addStretch();

    // Footer
    auto* footerLayout = new QHBoxLayout();
    m_summaryLabel = new QLabel(m_configContainer);
    m_summaryLabel->setStyleSheet("color: #86868b; font-size: 12px;");

    m_startBtn = new QPushButton("Start Compression", m_configContainer);
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
    connect(m_encoderCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &CompressTab::onEncoderChanged);
    connect(m_contentTypeCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &CompressTab::onContentTypeChanged);
    connect(m_bFramesSpin, QOverload<int>::of(&QSpinBox::valueChanged), this, &CompressTab::onBFramesChanged);
    connect(m_qualitySlider, &QSlider::valueChanged, this, &CompressTab::onQualitySliderChanged);
    connect(m_qualitySpin, QOverload<int>::of(&QSpinBox::valueChanged), this, &CompressTab::onQualitySpinChanged);
    connect(m_longGOPCheck, &QCheckBox::stateChanged, this, &CompressTab::onLongGOPChanged);
    connect(m_outputDirBrowseBtn, &QPushButton::clicked, m_viewModel, &CompressViewModel::selectOutputDirectory);
    connect(m_startBtn, &QPushButton::clicked, m_viewModel, &CompressViewModel::startProcessing);
}

void CompressTab::refreshLeftPanel() {
    if (m_viewModel->files().isEmpty()) {
        m_leftStack->setCurrentWidget(m_emptyWidget);
    } else {
        m_leftStack->setCurrentWidget(m_fileListPanel);
    }
}

void CompressTab::refreshRightPanel() {
    if (m_viewModel->viewState() == CompressViewModel::ViewState::Configuration) {
        m_rightStack->setCurrentWidget(m_configContainer);
    } else {
        m_rightStack->setCurrentWidget(m_processingPanel);
    }
}

void CompressTab::updateStartButton() {
    m_startBtn->setEnabled(m_viewModel->canStartProcessing());
    if (!m_viewModel->files().isEmpty()) {
        m_summaryLabel->setText(QString("Batch: %1 (%2)")
            .arg(m_viewModel->totalFileSize())
            .arg(m_viewModel->totalDuration()));
    } else {
        m_summaryLabel->setText("");
    }
}

void CompressTab::updateFromViewModel() {
    blockSignals(true);

    int encIdx = m_encoderCombo->findData(static_cast<int>(m_viewModel->encoder()));
    if (encIdx >= 0) m_encoderCombo->setCurrentIndex(encIdx);

    int typeIdx = m_contentTypeCombo->findData(static_cast<int>(m_viewModel->contentType()));
    if (typeIdx >= 0) m_contentTypeCombo->setCurrentIndex(typeIdx);

    m_bFramesSpin->setValue(m_viewModel->bFrames());
    m_longGOPCheck->setChecked(m_viewModel->longGOPEnabled());

    int maxQual = maxQuality(m_viewModel->encoder());
    m_qualitySlider->setMaximum(maxQual);
    m_qualitySpin->setMaximum(maxQual);
    m_qualitySlider->setValue(m_viewModel->quality());
    m_qualitySpin->setValue(m_viewModel->quality());

    m_outputDirEdit->setText(m_viewModel->outputDirectoryDisplayName());

    blockSignals(false);
}

void CompressTab::onEncoderChanged(int index) {
    if (index >= 0) {
        auto enc = static_cast<CompressEncoder>(m_encoderCombo->itemData(index).toInt());
        m_viewModel->setEncoder(enc);
        m_viewModel->onEncoderChanged();
        updateFromViewModel();
    }
}

void CompressTab::onQualitySliderChanged(int value) {
    m_viewModel->updateQuality(value);
    blockSignals(true);
    m_qualitySpin->setValue(value);
    blockSignals(false);
}

void CompressTab::onQualitySpinChanged(int value) {
    m_viewModel->updateQuality(value);
    blockSignals(true);
    m_qualitySlider->setValue(value);
    blockSignals(false);
}

void CompressTab::onContentTypeChanged(int index) {
    if (index >= 0) {
        auto type = static_cast<ContentType>(m_contentTypeCombo->itemData(index).toInt());
        m_viewModel->setContentType(type);
    }
}

void CompressTab::onBFramesChanged(int value) {
    m_viewModel->setBFrames(value);
}

void CompressTab::onLongGOPChanged(int state) {
    m_viewModel->setLongGOPEnabled(state == Qt::Checked);
}
