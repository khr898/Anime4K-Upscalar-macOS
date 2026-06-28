#include "CompressViewModel.h"
#include "../utils/FFmpegLocator.h"
#include "../utils/DurationProbe.h"
#include "../utils/SleepPreventer.h"

#include <QFileInfo>
#include <QDir>
#include <QLocale>

CompressViewModel::CompressViewModel(QObject* parent) : QObject(parent) {
    m_throttleTimer = new QTimer(this);
    connect(m_throttleTimer, &QTimer::timeout, this, &CompressViewModel::handleThrottledUpdates);
}

CompressViewModel::~CompressViewModel() {
    cancelProcessing();
    qDeleteAll(m_jobs);
}

void CompressViewModel::setPickerService(IPickerService* picker) {
    m_picker = picker;
}

const QVector<VideoFile>& CompressViewModel::files() const {
    return m_files;
}

QUuid CompressViewModel::selectedFileID() const {
    return m_selectedFileID;
}

void CompressViewModel::setSelectedFileID(const QUuid& id) {
    if (m_selectedFileID != id) {
        m_selectedFileID = id;
        emit selectedFileChanged();
    }
}

VideoFile* CompressViewModel::selectedFile() {
    for (auto& f : m_files) {
        if (f.id == m_selectedFileID) return &f;
    }
    return nullptr;
}

void CompressViewModel::addFiles() {
    if (!m_picker) return;
    m_picker->pickFiles(
        "Select Video Files",
        "Video Files (*.mp4 *.mkv *.mov *.avi *.webm *.flv *.ts)",
        [this](QStringList paths) {
            if (!paths.isEmpty())
                addFilesFromDrop(paths);
        });
}

void CompressViewModel::addFilesFromDrop(const QStringList& paths) {
    for (const QString& path : paths) {
        QString clean = QDir::cleanPath(path);
        QFileInfo fi(clean);
        QString ext = fi.suffix().toLower();
        if (!supportedVideoExtensions().contains(ext)) continue;

        bool duplicate = false;
        for (const VideoFile& f : m_files) {
            if (f.filePath == clean) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;

        m_files.append(VideoFile::fromPath(clean));
    }

    probeNewFiles();
    if (m_selectedFileID.isNull() && !m_files.isEmpty()) {
        m_selectedFileID = m_files.first().id;
        emit selectedFileChanged();
    }
    emit filesChanged();
}

void CompressViewModel::removeFile(const QUuid& id) {
    for (int i = 0; i < m_files.size(); ++i) {
        if (m_files[i].id == id) {
            m_files.removeAt(i);
            break;
        }
    }
    if (m_selectedFileID == id) {
        m_selectedFileID = m_files.isEmpty() ? QUuid() : m_files.first().id;
        emit selectedFileChanged();
    }
    emit filesChanged();
}

void CompressViewModel::removeAllFiles() {
    m_files.clear();
    m_selectedFileID = QUuid();
    emit selectedFileChanged();
    emit filesChanged();
}

void CompressViewModel::probeNewFiles() {
    QStringList unprobed;
    for (const auto& file : m_files) {
        if (!file.durationSeconds.has_value()) {
            unprobed.append(file.filePath);
        }
    }
    if (unprobed.isEmpty()) return;

    DurationProbe::batchProbe(unprobed, [this](QMap<QString, std::optional<ProbeResult>> results) {
        for (auto it = results.begin(); it != results.end(); ++it) {
            QString path = it.key();
            auto res = it.value();
            if (res.has_value()) {
                for (auto& file : m_files) {
                    if (file.filePath == path) {
                        file.durationSeconds = res->durationSeconds;
                        file.width = res->width;
                        file.height = res->height;
                    }
                }
            }
        }
        emit filesChanged();
        emit selectedFileChanged();
    });
}

CompressEncoder CompressViewModel::encoder() const {
    return m_encoder;
}

void CompressViewModel::setEncoder(CompressEncoder enc) {
    if (m_encoder != enc) {
        m_encoder = enc;
        onEncoderChanged();
        emit configurationChanged();
    }
}

int CompressViewModel::quality() const {
    return m_quality;
}

void CompressViewModel::setQuality(int val) {
    if (m_quality != val) {
        m_quality = val;
        emit configurationChanged();
    }
}

ContentType CompressViewModel::contentType() const {
    return m_contentType;
}

void CompressViewModel::setContentType(ContentType type) {
    if (m_contentType != type) {
        m_contentType = type;
        emit configurationChanged();
    }
}

int CompressViewModel::bFrames() const {
    return m_bFrames;
}

void CompressViewModel::setBFrames(int val) {
    if (m_bFrames != val) {
        m_bFrames = val;
        emit configurationChanged();
    }
}

bool CompressViewModel::longGOPEnabled() const {
    return m_longGOPEnabled;
}

void CompressViewModel::setLongGOPEnabled(bool val) {
    if (m_longGOPEnabled != val) {
        m_longGOPEnabled = val;
        emit configurationChanged();
    }
}

void CompressViewModel::onEncoderChanged() {
    m_quality = defaultQuality(m_encoder);
}

void CompressViewModel::updateQuality(int value) {
    m_quality = qBound(0, value, maxQuality(m_encoder));
    emit configurationChanged();
}

QString CompressViewModel::outputDirectory() const {
    return m_outputDirectory;
}

void CompressViewModel::setOutputDirectory(const QString& path) {
    if (m_outputDirectory != path) {
        m_outputDirectory = QDir::cleanPath(path);
        emit outputDirectoryChanged();
    }
}

QString CompressViewModel::outputDirectoryDisplayName() const {
    if (m_outputDirectory.isEmpty()) return "Not selected";
    return QFileInfo(m_outputDirectory).fileName();
}

void CompressViewModel::selectOutputDirectory() {
    if (!m_picker) return;
    m_picker->pickDirectory(
        "Select Output Directory",
        m_outputDirectory,
        [this](QString dir) {
            if (!dir.isEmpty())
                setOutputDirectory(dir);
        });
}

CompressViewModel::ViewState CompressViewModel::viewState() const {
    return m_viewState;
}

bool CompressViewModel::isProcessing() const {
    return m_isProcessing;
}

int CompressViewModel::currentJobIndex() const {
    return m_currentJobIndex;
}

int CompressViewModel::totalJobs() const {
    return m_totalJobs;
}

double CompressViewModel::overallProgress() const {
    return m_overallProgress;
}

const QVector<CompressJob*>& CompressViewModel::jobs() const {
    return m_jobs;
}

bool CompressViewModel::canStartProcessing() const {
    return !m_files.isEmpty() && !m_isProcessing;
}

void CompressViewModel::startProcessing() {
    if (!canStartProcessing()) return;

    if (m_outputDirectory.isEmpty()) {
        selectOutputDirectory();
        if (m_outputDirectory.isEmpty()) return;
    }

    CompressConfiguration config;
    config.encoder = m_encoder;
    config.quality = m_quality;
    config.contentType = m_contentType;
    config.bFrames = m_bFrames;
    config.longGOPEnabled = m_longGOPEnabled;

    qDeleteAll(m_jobs);
    m_jobs.clear();

    for (const VideoFile& file : m_files) {
        m_jobs.append(new CompressJob(file, config, m_outputDirectory, this));
    }

    m_viewState = ViewState::Processing;
    emit viewStateChanged();

    executeBatch();
}

void CompressViewModel::cancelProcessing() {
    m_cancellationRequested = true;
    if (m_currentProcess && m_currentProcess->state() == QProcess::Running) {
        m_currentProcess->kill();
    }
}

void CompressViewModel::returnToConfiguration() {
    if (m_isProcessing) return;
    m_viewState = ViewState::Configuration;
    emit viewStateChanged();
}

QString CompressViewModel::totalFileSize() const {
    qint64 total = 0;
    for (const auto& f : m_files) {
        total += f.fileSizeBytes;
    }
    return QLocale().formattedDataSize(total, 2, QLocale::DataSizeSIFormat);
}

QString CompressViewModel::totalDuration() const {
    double total = 0.0;
    bool hasVal = false;
    for (const auto& file : m_files) {
        if (file.durationSeconds.has_value()) {
            total += file.durationSeconds.value();
            hasVal = true;
        }
    }
    if (!hasVal) return QString();
    int hours = static_cast<int>(total) / 3600;
    int minutes = (static_cast<int>(total) % 3600) / 60;
    int seconds = static_cast<int>(total) % 60;
    return QString("%1:%2:%3")
        .arg(hours, 2, 10, QChar('0'))
        .arg(minutes, 2, 10, QChar('0'))
        .arg(seconds, 2, 10, QChar('0'));
}

QString CompressViewModel::batchSummary() const {
    return QString("%1 file%2 \u2022 %3 \u2022 %4")
        .arg(m_files.size())
        .arg(m_files.size() == 1 ? "" : "s")
        .arg(displayName(m_encoder))
        .arg(displayName(m_contentType));
}

int CompressViewModel::completedJobCount() const {
    int count = 0;
    for (const auto* job : m_jobs) {
        if (job->state == JobState::Completed) count++;
    }
    return count;
}

int CompressViewModel::failedJobCount() const {
    int count = 0;
    for (const auto* job : m_jobs) {
        if (job->state == JobState::Failed) count++;
    }
    return count;
}

bool CompressViewModel::allJobsFinished() const {
    if (m_jobs.isEmpty()) return false;
    for (const auto* job : m_jobs) {
        if (!isTerminal(job->state)) return false;
    }
    return true;
}

void CompressViewModel::executeBatch() {
    if (m_jobs.isEmpty()) return;

    m_isProcessing = true;
    m_totalJobs = m_jobs.size();
    m_currentJobIndex = 0;
    m_overallProgress = 0.0;
    m_cancellationRequested = false;

    SleepPreventer::preventSleep();
    emit viewStateChanged();

    executeNext();
}

void CompressViewModel::executeNext() {
    if (m_cancellationRequested || m_currentJobIndex >= m_jobs.size()) {
        SleepPreventer::allowSleep();
        m_isProcessing = false;
        m_currentJob = nullptr;
        m_currentProcess = nullptr;
        emit viewStateChanged();
        return;
    }

    m_currentJob = m_jobs[m_currentJobIndex];
    m_currentJobIndex++;

    executeJob(m_currentJob);
}

void CompressViewModel::executeJob(CompressJob* job) {
    DurationProbe::probeColorTransfer(job->file.filePath, [this, job](std::optional<QString> colorTransfer) {
        HDRMode hdr = (colorTransfer.has_value() && colorTransfer->contains("smpte2084")) ? HDRMode::HDR10 : HDRMode::SDR;
        job->hdrMode = hdr;

        QString ffmpeg = FFmpegLocator::ffmpegPath();
        if (!FFmpegLocator::isFFmpegExecutable()) {
            job->state = JobState::Failed;
            job->errorMessage = "FFmpeg binary not found or not executable.";
            job->endDate = QDateTime::currentDateTime();
            job->appendLog("❌ Error: " + job->errorMessage);
            emit jobProgressUpdated(job);
            executeNext();
            return;
        }

        QStringList arguments = CompressArgumentBuilder::build(
            job->file.filePath,
            job->outputPath,
            job->configuration,
            hdr
        );

        job->state = JobState::Running;
        job->progress = 0.0;
        job->startDate = QDateTime::currentDateTime();
        job->appendLog("$ ffmpeg " + arguments.join(" "));
        job->appendLog("HDR Detection: " + displayName(hdr));
        emit jobProgressUpdated(job);

        m_firstMetricWallDate = QDateTime();
        m_firstMetricTimeSeconds = -1.0;

        m_currentProcess = new QProcess(this);
        m_currentProcess->setProgram(ffmpeg);
        m_currentProcess->setArguments(arguments);
        m_currentProcess->setProcessEnvironment(FFmpegLocator::processEnvironment());
        job->processHandle = m_currentProcess;

        connect(m_currentProcess, &QProcess::readyReadStandardError, this, &CompressViewModel::onStderrReady);
        connect(m_currentProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &CompressViewModel::onProcessFinished);

        m_currentProcess->start();
        m_throttleTimer->start(100);
    });
}

void CompressViewModel::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    m_throttleTimer->stop();
    handleThrottledUpdates();

    if (m_currentJob) {
        m_currentJob->endDate = QDateTime::currentDateTime();
        m_currentJob->processHandle = nullptr;

        if (exitCode == 0 && exitStatus == QProcess::NormalExit) {
            m_currentJob->state = JobState::Completed;
            m_currentJob->progress = 1.0;
            m_currentJob->appendLog("✅ Compression completed successfully.");
        } else if (m_cancellationRequested || exitStatus == QProcess::CrashExit) {
            if (m_cancellationRequested) {
                m_currentJob->state = JobState::Cancelled;
                m_currentJob->appendLog("🛑 Compression cancelled by user.");
            } else {
                m_currentJob->state = JobState::Failed;
                m_currentJob->errorMessage = QString("FFmpeg crashed or exited with code %1").arg(exitCode);
                m_currentJob->appendLog("❌ Error: " + m_currentJob->errorMessage);
            }
        } else {
            m_currentJob->state = JobState::Failed;
            m_currentJob->errorMessage = QString("FFmpeg exited with code %1").arg(exitCode);
            m_currentJob->appendLog("❌ Error: " + m_currentJob->errorMessage);
        }

        emit jobProgressUpdated(m_currentJob);
    }

    if (m_currentProcess) {
        m_currentProcess->deleteLater();
        m_currentProcess = nullptr;
    }

    m_overallProgress = static_cast<double>(m_currentJobIndex) / static_cast<double>(m_totalJobs);
    executeNext();
}

void CompressViewModel::onStderrReady() {
    if (!m_currentProcess || !m_currentJob) return;

    QByteArray data = m_currentProcess->readAllStandardError();
    QString text = QString::fromUtf8(data);

    QStringList lines = text.split('\n', Qt::SkipEmptyParts);
    for (const QString& line : lines) {
        QString trimmed = line.trimmed();
        auto progOpt = FFmpegProgress::parse(trimmed);
        if (progOpt.has_value()) {
            FFmpegProgress prog = progOpt.value();
            m_pendFrame = prog.frame;
            m_pendTime = prog.time;
            m_pendFps = QString::number(prog.fps, 'f', 1);

            double mediaSeconds = prog.timeSeconds();
            m_pendProgress = mediaSeconds; // Temp hijack progress for timeSeconds

            double duration = m_currentJob->file.durationSeconds.value_or(0.0);
            if (duration > 0.0) {
                m_pendProgress = qMin(mediaSeconds / duration, 1.0);
            }
        } else {
            m_logBatch.append(trimmed);
        }
    }
}

void CompressViewModel::handleThrottledUpdates() {
    if (!m_currentJob) return;

    bool updated = false;

    if (m_pendFrame.has_value()) {
        m_currentJob->currentFrame = m_pendFrame.value();
        m_pendFrame = std::nullopt;
        updated = true;
    }
    if (m_pendTime.has_value()) {
        m_currentJob->currentTime = m_pendTime.value();
        m_pendTime = std::nullopt;
        updated = true;
    }
    if (m_pendFps.has_value()) {
        m_currentJob->fps = m_pendFps.value();
        m_pendFps = std::nullopt;
        updated = true;
    }
    if (m_pendProgress.has_value()) {
        double progVal = m_pendProgress.value();
        m_currentJob->progress = progVal;

        // Retrieve the current media time in seconds
        double duration = m_currentJob->file.durationSeconds.value_or(0.0);
        double mediaSeconds = progVal * duration;

        if (mediaSeconds > 0.0) {
            if (!m_firstMetricWallDate.isValid()) {
                m_firstMetricWallDate = QDateTime::currentDateTime();
                m_firstMetricTimeSeconds = mediaSeconds;
            } else {
                double elapsed = qMax(m_firstMetricWallDate.msecsTo(QDateTime::currentDateTime()) / 1000.0, 0.001);
                double mediaDelta = qMax(mediaSeconds - m_firstMetricTimeSeconds, 0.0);

                if (elapsed >= 0.35 && mediaDelta > 0.0) {
                    double speed = mediaDelta / elapsed;
                    m_currentJob->speed = QString("x%1").arg(speed, 0, 'f', 3);
                } else {
                    m_currentJob->speed = "warming...";
                }
            }
        }

        m_pendProgress = std::nullopt;
        updated = true;
    }

    if (!m_logBatch.isEmpty()) {
        for (const QString& log : m_logBatch) {
            m_currentJob->appendLog(log);
        }
        m_logBatch.clear();
        updated = true;
    }

    if (updated) {
        emit jobProgressUpdated(m_currentJob);
    }
}
