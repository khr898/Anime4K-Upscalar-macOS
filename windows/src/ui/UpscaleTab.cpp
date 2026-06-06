#include "UpscaleTab.h"
#include <QIcon>

UpscaleTab::UpscaleTab(AppViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_viewModel(viewModel)
{
    initUI();

    connect(m_viewModel, &AppViewModel::filesChanged, this, &UpscaleTab::refreshLeftPanel);
    connect(m_viewModel, &AppViewModel::filesChanged, this, &UpscaleTab::updateStartButton);
    connect(m_viewModel, &AppViewModel::configurationChanged, this, &UpscaleTab::updateStartButton);
    connect(m_viewModel, &AppViewModel::viewStateChanged, this, &UpscaleTab::refreshRightPanel);

    refreshLeftPanel();
    refreshRightPanel();
}

void UpscaleTab::initUI() {
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);

    m_splitter = new QSplitter(Qt::Horizontal, this);
    m_splitter->setChildrenCollapsible(false);

    // Left Stack setup
    m_leftStack = new QStackedWidget(this);
    m_emptyWidget = new EmptyStateWidget(
        "No Video Files Selected",
        "Drag & drop video files here, or click Add Files to start upscaling.",
        "Add Files...",
        this
    );
    m_fileListPanel = new FileListPanel(m_viewModel, this);

    m_leftStack->addWidget(m_emptyWidget);
    m_leftStack->addWidget(m_fileListPanel);

    // Connect EmptyState add/drop signals to viewmodel
    connect(m_emptyWidget, &EmptyStateWidget::addFilesRequested, m_viewModel, &AppViewModel::addFiles);
    connect(m_emptyWidget, &EmptyStateWidget::filesDropped, m_viewModel, &AppViewModel::addFilesFromDrop);
    connect(m_fileListPanel, &FileListPanel::filesDropped, m_viewModel, &AppViewModel::addFilesFromDrop);

    m_splitter->addWidget(m_leftStack);

    // Right Stack setup
    m_rightStack = new QStackedWidget(this);

    // Config Container setup
    m_configContainer = new QWidget(this);
    auto* configLayout = new QVBoxLayout(m_configContainer);
    configLayout->setContentsMargins(16, 16, 16, 16);
    configLayout->setSpacing(16);

    m_modePicker = new ModePickerWidget(m_viewModel, m_configContainer);
    m_configPanel = new ConfigurationPanel(m_viewModel, m_configContainer);

    configLayout->addWidget(m_modePicker);
    configLayout->addWidget(m_configPanel);

    // Footer at the bottom of config panel
    auto* footerLayout = new QHBoxLayout();
    m_summaryLabel = new QLabel(m_configContainer);
    m_summaryLabel->setStyleSheet("color: #86868b; font-size: 12px;");

    m_startBtn = new QPushButton("Start Upscaling", m_configContainer);
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
        "QPushButton#primaryButton:disabled {"
        "  background-color: #aeaeb2;"
        "  border-color: #aeaeb2;"
        "}"
    );

    footerLayout->addWidget(m_summaryLabel);
    footerLayout->addStretch();
    footerLayout->addWidget(m_startBtn);
    configLayout->addLayout(footerLayout);

    connect(m_startBtn, &QPushButton::clicked, m_viewModel, &AppViewModel::startProcessing);

    // Processing Panel setup
    m_processingPanel = new ProcessingPanel(m_viewModel, this);

    m_rightStack->addWidget(m_configContainer);
    m_rightStack->addWidget(m_processingPanel);

    m_splitter->addWidget(m_rightStack);

    // Set initial splitter stretch ratios (35% left, 65% right)
    m_splitter->setStretchFactor(0, 35);
    m_splitter->setStretchFactor(1, 65);

    mainLayout->addWidget(m_splitter);
}

void UpscaleTab::refreshLeftPanel() {
    if (m_viewModel->files().isEmpty()) {
        m_leftStack->setCurrentWidget(m_emptyWidget);
    } else {
        m_leftStack->setCurrentWidget(m_fileListPanel);
    }
}

void UpscaleTab::refreshRightPanel() {
    if (m_viewModel->viewState() == AppViewModel::ViewState::Configuration) {
        m_rightStack->setCurrentWidget(m_configContainer);
    } else {
        m_rightStack->setCurrentWidget(m_processingPanel);
    }
}

void UpscaleTab::updateStartButton() {
    m_startBtn->setEnabled(m_viewModel->canStartProcessing());
    
    // Update summary text
    if (!m_viewModel->files().isEmpty()) {
        m_summaryLabel->setText(QString("Batch: %1 (%2)")
            .arg(m_viewModel->totalFileSize())
            .arg(m_viewModel->totalDuration()));
    } else {
        m_summaryLabel->setText("");
    }
}
