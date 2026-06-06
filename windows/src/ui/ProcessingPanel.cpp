#include "ProcessingPanel.h"
#include <QIcon>

ProcessingPanel::ProcessingPanel(AppViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_appViewModel(viewModel)
{
    initUI();
    // Connect to viewmodel state triggers to update the summary/buttons
    connect(m_appViewModel, &AppViewModel::viewStateChanged, this, &ProcessingPanel::updateUI);
    // Since jobs can change internally, we listen to view model configuration/files or connect to job changes
    updateUI();
}

ProcessingPanel::ProcessingPanel(CompressViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_compressViewModel(viewModel)
{
    initUI();
    connect(m_compressViewModel, &CompressViewModel::viewStateChanged, this, &ProcessingPanel::updateUI);
    connect(m_compressViewModel, &CompressViewModel::jobProgressUpdated, this, &ProcessingPanel::updateUI);
    updateUI();
}

ProcessingPanel::ProcessingPanel(StreamOptimizeViewModel* viewModel, QWidget* parent)
    : QWidget(parent)
    , m_streamOptimizeViewModel(viewModel)
{
    initUI();
    connect(m_streamOptimizeViewModel, &StreamOptimizeViewModel::viewStateChanged, this, &ProcessingPanel::updateUI);
    connect(m_streamOptimizeViewModel, &StreamOptimizeViewModel::jobProgressUpdated, this, &ProcessingPanel::updateUI);
    updateUI();
}

void ProcessingPanel::initUI() {
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(16, 16, 16, 16);
    mainLayout->setSpacing(12);

    // Summary Card / Banner
    auto* bannerWidget = new QWidget(this);
    bannerWidget->setStyleSheet("background-color: #ffffff; border: 1px solid #e2e2e7; border-radius: 8px;");
    auto* bannerLayout = new QVBoxLayout(bannerWidget);
    bannerLayout->setContentsMargins(16, 16, 16, 16);
    bannerLayout->setSpacing(8);

    m_summaryLabel = new QLabel("Processing Video Files...", this);
    m_summaryLabel->setStyleSheet("font-weight: bold; font-size: 16px; color: #1d1d1f;");

    m_statsLabel = new QLabel("", this);
    m_statsLabel->setStyleSheet("font-size: 12px; color: #86868b;");

    m_overallProgressBar = new QProgressBar(this);
    m_overallProgressBar->setRange(0, 100);

    bannerLayout->addWidget(m_summaryLabel);
    bannerLayout->addWidget(m_statsLabel);
    bannerLayout->addWidget(m_overallProgressBar);

    mainLayout->addWidget(bannerWidget);

    // Scroll Area for individual jobs
    m_scrollArea = new QScrollArea(this);
    m_scrollArea->setWidgetResizable(true);
    m_scrollArea->setFrameShape(QFrame::NoFrame);
    m_scrollArea->setStyleSheet("background: transparent;");

    m_scrollContent = new QWidget(m_scrollArea);
    m_scrollContent->setStyleSheet("background: transparent;");
    m_scrollLayout = new QVBoxLayout(m_scrollContent);
    m_scrollLayout->setContentsMargins(0, 0, 0, 0);
    m_scrollLayout->setSpacing(8);
    m_scrollLayout->addStretch();

    m_scrollArea->setWidget(m_scrollContent);
    mainLayout->addWidget(m_scrollArea);

    // Action buttons footer
    auto* footerLayout = new QHBoxLayout();
    m_cancelButton = new QPushButton("Cancel Processing", this);
    m_cancelButton->setIcon(QIcon(":/icons/stop.svg"));
    m_cancelButton->setObjectName("dangerButton");
    m_cancelButton->setStyleSheet(
        "QPushButton#dangerButton {"
        "  background-color: #ff3b30;"
        "  border: 1px solid #e02d24;"
        "  color: #ffffff;"
        "  font-weight: bold;"
        "  padding: 8px 16px;"
        "  border-radius: 6px;"
        "}"
        "QPushButton#dangerButton:hover {"
        "  background-color: #e02d24;"
        "}"
    );

    m_returnButton = new QPushButton("Return to Configuration", this);
    m_returnButton->setIcon(QIcon(":/icons/arrow_left.svg"));
    m_returnButton->setObjectName("primaryButton");
    m_returnButton->setStyleSheet(
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

    footerLayout->addStretch();
    footerLayout->addWidget(m_cancelButton);
    footerLayout->addWidget(m_returnButton);

    mainLayout->addLayout(footerLayout);

    connect(m_cancelButton, &QPushButton::clicked, this, &ProcessingPanel::onCancelClicked);
    connect(m_returnButton, &QPushButton::clicked, this, &ProcessingPanel::onReturnClicked);
}

void ProcessingPanel::populateJobs() {
    // Clear old widgets
    QLayoutItem* item;
    while ((item = m_scrollLayout->takeAt(0)) != nullptr) {
        if (item->widget()) {
            delete item->widget();
        }
        delete item;
    }

    if (m_appViewModel) {
        for (auto* job : m_appViewModel->jobs()) {
            auto* row = new ProgressRowWidget(job, m_scrollContent);
            m_scrollLayout->addWidget(row);
            connect(job, &ProcessingJob::progressChanged, this, &ProcessingPanel::updateUI);
            connect(job, &ProcessingJob::stateChanged, this, &ProcessingPanel::updateUI);
        }
    } else if (m_compressViewModel) {
        for (auto* job : m_compressViewModel->jobs()) {
            auto* row = new ProgressRowWidget(job, m_scrollContent);
            m_scrollLayout->addWidget(row);
        }
    } else if (m_streamOptimizeViewModel) {
        for (auto* job : m_streamOptimizeViewModel->jobs()) {
            auto* row = new ProgressRowWidget(job, m_scrollContent);
            m_scrollLayout->addWidget(row);
        }
    }

    m_scrollLayout->addStretch();
    m_populated = true;
}

void ProcessingPanel::updateUI() {
    if (!m_populated) {
        populateJobs();
    }

    double overallProgress = 0.0;
    bool finished = false;
    int completed = 0;
    int failed = 0;
    int total = 0;
    QString summaryText;

    if (m_appViewModel) {
        total = m_appViewModel->jobs().size();
        completed = m_appViewModel->completedJobCount();
        failed = m_appViewModel->failedJobCount();
        finished = m_appViewModel->allJobsFinished();
        summaryText = m_appViewModel->batchSummary();

        // Calculate custom overall progress
        if (total > 0) {
            double sum = 0.0;
            for (auto* job : m_appViewModel->jobs()) {
                sum += job->progress;
            }
            overallProgress = sum / total;
        }
    } else if (m_compressViewModel) {
        total = m_compressViewModel->jobs().size();
        completed = m_compressViewModel->completedJobCount();
        failed = m_compressViewModel->failedJobCount();
        finished = m_compressViewModel->allJobsFinished();
        summaryText = m_compressViewModel->batchSummary();
        overallProgress = m_compressViewModel->overallProgress();
    } else if (m_streamOptimizeViewModel) {
        total = m_streamOptimizeViewModel->jobs().size();
        completed = m_streamOptimizeViewModel->completedJobCount();
        failed = m_streamOptimizeViewModel->failedJobCount();
        finished = m_streamOptimizeViewModel->allJobsFinished();
        overallProgress = m_streamOptimizeViewModel->overallProgress();
        summaryText = QString("Processing %1 of %2 files").arg(m_streamOptimizeViewModel->currentJobIndex() + 1).arg(total);
    }

    m_overallProgressBar->setValue(static_cast<int>(overallProgress * 100));
    m_summaryLabel->setText(summaryText);

    QString stats = QString("Completed: %1 • Failed: %2 • Total: %3").arg(completed).arg(failed).arg(total);
    m_statsLabel->setText(stats);

    // Toggle button visibility based on finish state
    m_cancelButton->setVisible(!finished);
    m_returnButton->setVisible(finished);
}

void ProcessingPanel::onCancelClicked() {
    if (m_appViewModel) {
        m_appViewModel->cancelProcessing();
    } else if (m_compressViewModel) {
        m_compressViewModel->cancelProcessing();
    } else if (m_streamOptimizeViewModel) {
        m_streamOptimizeViewModel->cancelProcessing();
    }
}

void ProcessingPanel::onReturnClicked() {
    // Reset populated flag so next run rebuilds list
    m_populated = false;

    if (m_appViewModel) {
        m_appViewModel->returnToConfiguration();
    } else if (m_compressViewModel) {
        m_compressViewModel->returnToConfiguration();
    } else if (m_streamOptimizeViewModel) {
        m_streamOptimizeViewModel->returnToConfiguration();
    }
}
