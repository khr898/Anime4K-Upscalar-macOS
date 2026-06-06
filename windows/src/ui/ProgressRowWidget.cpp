#include "ProgressRowWidget.h"
#include <QIcon>

ProgressRowWidget::ProgressRowWidget(ProcessingJob* job, QWidget* parent)
    : QWidget(parent)
    , m_processingJob(job)
{
    initUI(job->file.fileName, job->state, job->progress, "");
    connect(job, &ProcessingJob::stateChanged, this, &ProgressRowWidget::updateUI);
    connect(job, &ProcessingJob::progressChanged, this, &ProgressRowWidget::updateUI);
    updateUI();
}

ProgressRowWidget::ProgressRowWidget(CompressJob* job, QWidget* parent)
    : QWidget(parent)
    , m_compressJob(job)
{
    initUI(job->file.fileName, job->state, job->progress, "");
    connect(job, &CompressJob::stateChanged, this, &ProgressRowWidget::updateUI);
    connect(job, &CompressJob::progressChanged, this, &ProgressRowWidget::updateUI);
    updateUI();
}

ProgressRowWidget::ProgressRowWidget(StreamOptimizeJob* job, QWidget* parent)
    : QWidget(parent)
    , m_streamOptimizeJob(job)
{
    initUI(job->file.fileName, job->state, job->progress, "");
    connect(job, &StreamOptimizeJob::stateChanged, this, &ProgressRowWidget::updateUI);
    connect(job, &StreamOptimizeJob::progressChanged, this, &ProgressRowWidget::updateUI);
    updateUI();
}

void ProgressRowWidget::initUI(const QString& fileName, JobState state, double progress, const QString& detailText) {
    Q_UNUSED(state);
    auto* mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(12, 12, 12, 12);
    mainLayout->setSpacing(6);

    // Card background
    setStyleSheet(
        "ProgressRowWidget {"
        "  background-color: #ffffff;"
        "  border: 1px solid #e2e2e7;"
        "  border-radius: 8px;"
        "}"
    );

    auto* topLayout = new QHBoxLayout();
    topLayout->setSpacing(8);

    auto* iconLabel = new QLabel(this);
    iconLabel->setPixmap(QIcon(":/icons/video.svg").pixmap(16, 16));

    m_fileNameLabel = new QLabel(fileName, this);
    m_fileNameLabel->setStyleSheet("font-weight: bold; color: #1d1d1f; font-size: 13px;");
    
    topLayout->addWidget(iconLabel);
    
    m_statusBadge = new QLabel(this);
    m_statusBadge->setAlignment(Qt::AlignCenter);

    topLayout->addWidget(m_fileNameLabel);
    topLayout->addStretch();
    topLayout->addWidget(m_statusBadge);

    m_progressBar = new QProgressBar(this);
    m_progressBar->setRange(0, 100);
    m_progressBar->setValue(static_cast<int>(progress * 100));

    m_detailsLabel = new QLabel(detailText, this);
    m_detailsLabel->setStyleSheet("color: #86868b; font-size: 11px;");

    mainLayout->addLayout(topLayout);
    mainLayout->addWidget(m_progressBar);
    mainLayout->addWidget(m_detailsLabel);
}

void ProgressRowWidget::updateUI() {
    JobState state = JobState::Idle;
    double progress = 0.0;
    QString details;
    QString durationStr = "--:--:--";
    QString currentTime = "00:00:00.00";
    QString fps = "0";
    QString speed = "0.0x";
    QString elapsedStr = "00:00:00";

    if (m_processingJob) {
        state = m_processingJob->state;
        progress = m_processingJob->progress;
        if (m_processingJob->file.durationSeconds.has_value()) {
            durationStr = m_processingJob->file.formattedDuration();
        }
        currentTime = m_processingJob->currentTime;
        fps = m_processingJob->fps;
        speed = m_processingJob->speed;
        elapsedStr = m_processingJob->formattedElapsedTime();
    } else if (m_compressJob) {
        state = m_compressJob->state;
        progress = m_compressJob->progress;
        if (m_compressJob->file.durationSeconds.has_value()) {
            durationStr = m_compressJob->file.formattedDuration();
        }
        currentTime = m_compressJob->currentTime;
        fps = m_compressJob->fps;
        speed = m_compressJob->speed;
        elapsedStr = m_compressJob->formattedElapsedTime();
    } else if (m_streamOptimizeJob) {
        state = m_streamOptimizeJob->state;
        progress = m_streamOptimizeJob->progress;
        if (m_streamOptimizeJob->file.durationSeconds.has_value()) {
            durationStr = m_streamOptimizeJob->file.formattedDuration();
        }
        currentTime = m_streamOptimizeJob->currentTime;
        fps = m_streamOptimizeJob->fps;
        speed = m_streamOptimizeJob->speed;
        elapsedStr = m_streamOptimizeJob->formattedElapsedTime();
    }

    m_progressBar->setValue(static_cast<int>(progress * 100));

    // Badge configuration
    QString stateName = displayName(state);
    QColor color = tintColor(state);
    m_statusBadge->setText(stateName.toUpper());
    m_statusBadge->setStyleSheet(QString(
        "background-color: %1; color: #ffffff; border-radius: 4px; padding: 2px 6px; font-weight: bold; font-size: 10px;"
    ).arg(color.name()));

    // Construct details text
    if (state == JobState::Running) {
        details = QString("%1% • %2 fps • %3 • %4 / %5 • Elapsed: %6")
                      .arg(QString::number(progress * 100, 'f', 1))
                      .arg(fps)
                      .arg(speed)
                      .arg(currentTime)
                      .arg(durationStr)
                      .arg(elapsedStr);
    } else if (state == JobState::Completed) {
        details = QString("Completed • Elapsed: %1").arg(elapsedStr);
    } else if (state == JobState::Failed) {
        QString err = "Unknown error";
        if (m_processingJob && !m_processingJob->errorMessage.isEmpty()) err = m_processingJob->errorMessage;
        else if (m_compressJob && !m_compressJob->errorMessage.isEmpty()) err = m_compressJob->errorMessage;
        else if (m_streamOptimizeJob && !m_streamOptimizeJob->errorMessage.isEmpty()) err = m_streamOptimizeJob->errorMessage;
        details = QString("Failed: %1 • Elapsed: %2").arg(err).arg(elapsedStr);
    } else if (state == JobState::Queued) {
        details = "Queued for processing...";
    } else if (state == JobState::Cancelled) {
        details = "Cancelled by user.";
    } else {
        details = "Idle";
    }

    m_detailsLabel->setText(details);
}
