#include "QualityTuneTab.h"
#include <QHeaderView>
#include <QIcon>

QualityTuneTab::QualityTuneTab(AppViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_viewModel(viewModel)
{
    initUI();

    connect(m_viewModel, &AppViewModel::qualityTuneStateChanged, this, &QualityTuneTab::updateState);
    connect(m_viewModel, &AppViewModel::qualityTuneCandidatesChanged, this, &QualityTuneTab::updateCandidates);

    // Initial sync
    updateState();
    updateCandidates();
}

void QualityTuneTab::initUI() {
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(16, 16, 16, 16);
    mainLayout->setSpacing(14);

    auto* titleLabel = new QLabel("Quality Tuning & Analysis", this);
    titleLabel->setStyleSheet("font-weight: bold; font-size: 14px; color: #1d1d1f;");
    mainLayout->addWidget(titleLabel);

    // 1. File Input Group
    auto* fileCard = new QGroupBox("Sample Video Selection", this);
    auto* fileLayout = new QHBoxLayout(fileCard);
    m_inputFileEdit = new QLineEdit(fileCard);
    m_inputFileEdit->setReadOnly(true);
    m_inputFileBrowseBtn = new QPushButton("Browse Sample...", fileCard);
    fileLayout->addWidget(m_inputFileEdit);
    fileLayout->addWidget(m_inputFileBrowseBtn);
    mainLayout->addWidget(fileCard);

    // 2. Parameters Group
    auto* paramCard = new QGroupBox("Tuning Parameters", this);
    auto* gridLayout = new QGridLayout(paramCard);
    gridLayout->setHorizontalSpacing(12);
    gridLayout->setVerticalSpacing(10);

    // Codec
    auto* codecLabel = new QLabel("Target Codec", paramCard);
    codecLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_codecCombo = new QComboBox(paramCard);
    m_codecCombo->addItem(displayName(VideoCodec::HEVC_NVENC), static_cast<int>(VideoCodec::HEVC_NVENC));
    m_codecCombo->addItem(displayName(VideoCodec::HEVC_AMF), static_cast<int>(VideoCodec::HEVC_AMF));
    m_codecCombo->addItem(displayName(VideoCodec::HEVC_QSV), static_cast<int>(VideoCodec::HEVC_QSV));
    m_codecCombo->addItem(displayName(VideoCodec::H264_NVENC), static_cast<int>(VideoCodec::H264_NVENC));
    m_codecCombo->addItem(displayName(VideoCodec::H264_AMF), static_cast<int>(VideoCodec::H264_AMF));
    m_codecCombo->addItem(displayName(VideoCodec::H264_QSV), static_cast<int>(VideoCodec::H264_QSV));
    m_codecCombo->addItem(displayName(VideoCodec::SVT_AV1), static_cast<int>(VideoCodec::SVT_AV1));
    gridLayout->addWidget(codecLabel, 0, 0);
    gridLayout->addWidget(m_codecCombo, 0, 1);

    // Range Start
    auto* startLabel = new QLabel("Quality Range Start", paramCard);
    startLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_rangeStartSpin = new QSpinBox(paramCard);
    m_rangeStartSpin->setRange(0, 100);
    gridLayout->addWidget(startLabel, 0, 2);
    gridLayout->addWidget(m_rangeStartSpin, 0, 3);

    // Range End
    auto* endLabel = new QLabel("Quality Range End", paramCard);
    endLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_rangeEndSpin = new QSpinBox(paramCard);
    m_rangeEndSpin->setRange(0, 100);
    gridLayout->addWidget(endLabel, 1, 0);
    gridLayout->addWidget(m_rangeEndSpin, 1, 1);

    // Step
    auto* stepLabel = new QLabel("Scan Step Size", paramCard);
    stepLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_stepSpin = new QSpinBox(paramCard);
    m_stepSpin->setRange(1, 20);
    gridLayout->addWidget(stepLabel, 1, 2);
    gridLayout->addWidget(m_stepSpin, 1, 3);

    // Duration
    auto* durLabel = new QLabel("Sample Duration (s)", paramCard);
    durLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_sampleSecsSpin = new QSpinBox(paramCard);
    m_sampleSecsSpin->setRange(5, 120);
    gridLayout->addWidget(durLabel, 2, 0);
    gridLayout->addWidget(m_sampleSecsSpin, 2, 1);

    // Target SSIM
    auto* ssimLabel = new QLabel("Target SSIM threshold", paramCard);
    ssimLabel->setStyleSheet("font-weight: bold; color: #515154;");
    m_targetSSIMSpin = new QDoubleSpinBox(paramCard);
    m_targetSSIMSpin->setRange(0.800, 0.999);
    m_targetSSIMSpin->setDecimals(4);
    m_targetSSIMSpin->setSingleStep(0.001);
    gridLayout->addWidget(ssimLabel, 2, 2);
    gridLayout->addWidget(m_targetSSIMSpin, 2, 3);

    mainLayout->addWidget(paramCard);

    // 3. Scan & Status Footer
    auto* scanLayout = new QHBoxLayout();
    m_statusLabel = new QLabel("Ready to analyze.", this);
    m_statusLabel->setStyleSheet("font-weight: bold; color: #86868b;");
    m_startScanBtn = new QPushButton("Start Quality Analysis", this);
    m_startScanBtn->setIcon(QIcon(":/icons/play.svg"));
    m_startScanBtn->setObjectName("primaryButton");
    m_startScanBtn->setStyleSheet(
        "QPushButton#primaryButton {"
        "  background-color: #007aff;"
        "  border: 1px solid #0071e3;"
        "  color: #ffffff;"
        "  font-weight: bold;"
        "  padding: 8px 16px;"
        "  border-radius: 6px;"
        "}"
        "QPushButton#primaryButton:hover {"
        "  background-color: #0071e3;"
        "}"
    );

    scanLayout->addWidget(m_statusLabel);
    scanLayout->addStretch();
    scanLayout->addWidget(m_startScanBtn);
    mainLayout->addLayout(scanLayout);

    // 4. Candidates Table
    m_candidatesTable = new QTableWidget(this);
    m_candidatesTable->setColumnCount(4);
    m_candidatesTable->setHorizontalHeaderLabels({"Quality Value", "SSIM", "PSNR", "Output Size"});
    m_candidatesTable->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    m_candidatesTable->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_candidatesTable->setSelectionMode(QAbstractItemView::NoSelection);
    m_candidatesTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    mainLayout->addWidget(m_candidatesTable);

    // Connections to sync config back
    connect(m_inputFileBrowseBtn, &QPushButton::clicked, m_viewModel, &AppViewModel::selectQualityTuneInputFile);
    connect(m_codecCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, [this](int idx){
        if (idx >= 0) {
            auto codec = static_cast<VideoCodec>(m_codecCombo->itemData(idx).toInt());
            m_viewModel->setQualityTuneCodec(codec);
            m_viewModel->onQualityTuneCodecChanged();
            updateState();
        }
    });
    connect(m_rangeStartSpin, QOverload<int>::of(&QSpinBox::valueChanged), m_viewModel, &AppViewModel::setQualityTuneRangeStart);
    connect(m_rangeEndSpin, QOverload<int>::of(&QSpinBox::valueChanged), m_viewModel, &AppViewModel::setQualityTuneRangeEnd);
    connect(m_stepSpin, QOverload<int>::of(&QSpinBox::valueChanged), m_viewModel, &AppViewModel::setQualityTuneStep);
    connect(m_sampleSecsSpin, QOverload<int>::of(&QSpinBox::valueChanged), m_viewModel, &AppViewModel::setQualityTuneSampleSeconds);
    connect(m_targetSSIMSpin, QOverload<double>::of(&QDoubleSpinBox::valueChanged), m_viewModel, &AppViewModel::setQualityTuneTargetSSIM);
    connect(m_startScanBtn, &QPushButton::clicked, this, &QualityTuneTab::onStartScanClicked);
}

void QualityTuneTab::updateState() {
    blockSignals(true);

    m_inputFileEdit->setText(m_viewModel->qualityTuneInputPath());

    int cIdx = m_codecCombo->findData(static_cast<int>(m_viewModel->qualityTuneCodec()));
    if (cIdx >= 0) m_codecCombo->setCurrentIndex(cIdx);

    m_rangeStartSpin->setValue(m_viewModel->qualityTuneRangeStart());
    m_rangeEndSpin->setValue(m_viewModel->qualityTuneRangeEnd());
    m_stepSpin->setValue(m_viewModel->qualityTuneStep());
    m_sampleSecsSpin->setValue(m_viewModel->qualityTuneSampleSeconds());
    m_targetSSIMSpin->setValue(m_viewModel->qualityTuneTargetSSIM());

    bool isRunning = m_viewModel->qualityTuneIsRunning();
    bool hasInput = !m_viewModel->qualityTuneInputPath().isEmpty();

    m_startScanBtn->setEnabled(hasInput && !isRunning);
    m_codecCombo->setEnabled(!isRunning);
    m_rangeStartSpin->setEnabled(!isRunning);
    m_rangeEndSpin->setEnabled(!isRunning);
    m_stepSpin->setEnabled(!isRunning);
    m_sampleSecsSpin->setEnabled(!isRunning);
    m_targetSSIMSpin->setEnabled(!isRunning);

    if (isRunning) {
        m_statusLabel->setText(m_viewModel->qualityTuneStatusText());
    } else if (!m_viewModel->qualityTuneErrorText().isEmpty()) {
        m_statusLabel->setText(QString("Error: %1").arg(m_viewModel->qualityTuneErrorText()));
    } else {
        m_statusLabel->setText("Ready to analyze.");
    }

    blockSignals(false);
}

void QualityTuneTab::updateCandidates() {
    m_candidatesTable->setRowCount(0);

    const auto& candidates = m_viewModel->qualityTuneCandidates();
    auto bestOpt = m_viewModel->qualityTuneBestCandidate();

    for (int i = 0; i < candidates.size(); ++i) {
        const auto& cand = candidates[i];
        m_candidatesTable->insertRow(i);

        bool isBest = bestOpt.has_value() && cand.id == bestOpt->id;

        QString valStr = cand.valueLabel();
        if (isBest) {
            valStr = valStr + " (Best Choice)";
        }

        auto* itemVal = new QTableWidgetItem(valStr);
        auto* itemSSIM = new QTableWidgetItem(QString::number(cand.ssim, 'f', 4));
        auto* itemPSNR = new QTableWidgetItem(QString::number(cand.psnr, 'f', 2) + " dB");
        auto* itemSize = new QTableWidgetItem(cand.sizeLabel());

        if (isBest) {
            QFont f = itemVal->font();
            f.setBold(true);
            itemVal->setFont(f);
            itemSSIM->setFont(f);
            itemPSNR->setFont(f);
            itemSize->setFont(f);

            QBrush bestBrush(QColor("#007aff"));
            itemVal->setForeground(bestBrush);
            itemSSIM->setForeground(bestBrush);
            itemPSNR->setForeground(bestBrush);
            itemSize->setForeground(bestBrush);
        }

        m_candidatesTable->setItem(i, 0, itemVal);
        m_candidatesTable->setItem(i, 1, itemSSIM);
        m_candidatesTable->setItem(i, 2, itemPSNR);
        m_candidatesTable->setItem(i, 3, itemSize);
    }
}

void QualityTuneTab::onStartScanClicked() {
    m_viewModel->runQualityTuneScan();
    updateState();
}
