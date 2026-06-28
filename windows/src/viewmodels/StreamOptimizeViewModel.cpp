#include "StreamOptimizeViewModel.h"
#include "../utils/FFmpegLocator.h"
#include "../utils/DurationProbe.h"
#include "../utils/SleepPreventer.h"

#include <QFileInfo>
#include <QDir>
#include <QLocale>
#include <QThread>
#include <QCoreApplication>
#include <QMetaObject>

StreamOptimizeViewModel::StreamOptimizeViewModel(QObject* parent) : QObject(parent) {
    m_throttleTimer = new QTimer(this);
    connect(m_throttleTimer, &QTimer::timeout, this, &StreamOptimizeViewModel::handleThrottledUpdates);
}

StreamOptimizeViewModel::~StreamOptimizeViewModel() {
    cancelProcessing();
    qDeleteAll(m_jobs);
}

void StreamOptimizeViewModel::setPickerService(IPickerService* picker) {
    m_picker = picker;
}

QString StreamOptimizeViewModel::sourceDirectory() const {
    return m_sourceDirectory;
}

void StreamOptimizeViewModel::setSourceDirectory(const QString& path) {
    if (m_sourceDirectory != path) {
        m_sourceDirectory = QDir::cleanPath(path);
        emit directoriesChanged();
        scanSourceDirectory();
    }
}

QString StreamOptimizeViewModel::sourceDisplayName() const {
    if (m_sourceDirectory.isEmpty()) return "Not selected";
    return QFileInfo(m_sourceDirectory).fileName();
}

void StreamOptimizeViewModel::selectSourceDirectory() {
    if (!m_picker) return;
    m_picker->pickDirectory(
        "Select Source Directory",
        m_sourceDirectory,
        [this](QString dir) {
            if (!dir.isEmpty())
                setSourceDirectory(dir);
        });
}

QString StreamOptimizeViewModel::destinationDirectory() const {
    return m_destinationDirectory;
}

void StreamOptimizeViewModel::setDestinationDirectory(const QString& path) {
    if (m_destinationDirectory != path) {
        m_destinationDirectory = QDir::cleanPath(path);
        emit directoriesChanged();
    }
}

QString StreamOptimizeViewModel::destinationDisplayName() const {
    if (m_destinationDirectory.isEmpty()) return "Not selected";
    return QFileInfo(m_destinationDirectory).fileName();
}

void StreamOptimizeViewModel::selectDestinationDirectory() {
    if (!m_picker) return;
    m_picker->pickDirectory(
        "Select Destination Directory",
        m_destinationDirectory,
        [this](QString dir) {
            if (!dir.isEmpty())
                setDestinationDirectory(dir);
        });
}

const QVector<VideoFile>& StreamOptimizeViewModel::files() const {
    return m_files;
}

StreamEncoder StreamOptimizeViewModel::encoder() const {
    return m_encoder;
}

void StreamOptimizeViewModel::setEncoder(StreamEncoder enc) {
    if (m_encoder != enc) {
        m_encoder = enc;
        onEncoderChanged();
        emit configurationChanged();
    }
}

int StreamOptimizeViewModel::quality() const {
    return m_quality;
}

void StreamOptimizeViewModel::setQuality(int val) {
    if (m_quality != val) {
        m_quality = val;
        emit configurationChanged();
    }
}

StreamProfile StreamOptimizeViewModel::profile() const {
    return m_profile;
}

void StreamOptimizeViewModel::setProfile(StreamProfile prof) {
    if (m_profile != prof) {
        m_profile = prof;
        emit configurationChanged();
    }
}

StreamPixelFormat StreamOptimizeViewModel::pixelFormat() const {
    return m_pixelFormat;
}

void StreamOptimizeViewModel::setPixelFormat(StreamPixelFormat pixFmt) {
    if (m_pixelFormat != pixFmt) {
        m_pixelFormat = pixFmt;
        emit configurationChanged();
    }
}

StreamAudioMode StreamOptimizeViewModel::audioMode() const {
    return m_audioMode;
}

void StreamOptimizeViewModel::setAudioMode(StreamAudioMode mode) {
    if (m_audioMode != mode) {
        m_audioMode = mode;
        emit configurationChanged();
    }
}

StreamSubtitleMode StreamOptimizeViewModel::subtitleMode() const {
    return m_subtitleMode;
}

void StreamOptimizeViewModel::setSubtitleMode(StreamSubtitleMode mode) {
    if (m_subtitleMode != mode) {
        m_subtitleMode = mode;
        emit configurationChanged();
    }
}

KeyframeInterval StreamOptimizeViewModel::keyframeInterval() const {
    return m_keyframeInterval;
}

void StreamOptimizeViewModel::setKeyframeInterval(KeyframeInterval interval) {
    if (m_keyframeInterval != interval) {
        m_keyframeInterval = interval;
        emit configurationChanged();
    }
}

bool StreamOptimizeViewModel::faststart() const {
    return m_faststart;
}

void StreamOptimizeViewModel::setFaststart(bool val) {
    if (m_faststart != val) {
        m_faststart = val;
        emit configurationChanged();
    }
}

bool StreamOptimizeViewModel::allowSWFallback() const {
    return m_allowSWFallback;
}

void StreamOptimizeViewModel::setAllowSWFallback(bool val) {
    if (m_allowSWFallback != val) {
        m_allowSWFallback = val;
        emit configurationChanged();
    }
}

StreamOptimizeConfiguration StreamOptimizeViewModel::currentConfiguration() const {
    StreamOptimizeConfiguration config;
    config.encoder = m_encoder;
    config.quality = m_quality;
    config.profile = m_profile;
    config.pixelFormat = m_pixelFormat;
    config.audioMode = m_audioMode;
    config.subtitleMode = m_subtitleMode;
    config.keyframeInterval = m_keyframeInterval;
    config.faststart = m_faststart;
    config.allowSWFallback = m_allowSWFallback;
    return config;
}

void StreamOptimizeViewModel::onEncoderChanged() {
    m_quality = defaultQuality(m_encoder);
    m_profile = defaultProfile(m_encoder);
    m_pixelFormat = defaultPixelFormat(m_encoder);
}

void StreamOptimizeViewModel::resetToDefaults() {
    StreamOptimizeConfiguration d;
    m_encoder = d.encoder;
    m_quality = d.quality;
    m_profile = d.profile;
    m_pixelFormat = d.pixelFormat;
    m_audioMode = d.audioMode;
    m_subtitleMode = d.subtitleMode;
    m_keyframeInterval = d.keyframeInterval;
    m_faststart = d.faststart;
    m_allowSWFallback = d.allowSWFallback;
    emit configurationChanged();
}

StreamOptimizeViewModel::ViewState StreamOptimizeViewModel::viewState() const {
    return m_viewState;
}

bool StreamOptimizeViewModel::isProcessing() const {
    return m_isProcessing;
}

int StreamOptimizeViewModel::currentJobIndex() const {
    return m_currentJobIndex;
}

int StreamOptimizeViewModel::totalJobs() const {
    return m_totalJobs;
}

double StreamOptimizeViewModel::overallProgress() const {
    return m_overallProgress;
}

const QVector<StreamOptimizeJob*>& StreamOptimizeViewModel::jobs() const {
    return m_jobs;
}

bool StreamOptimizeViewModel::canStartProcessing() const {
    return !m_files.isEmpty() && !m_isProcessing && !m_destinationDirectory.isEmpty();
}

void StreamOptimizeViewModel::scanSourceDirectory() {
    if (m_sourceDirectory.isEmpty()) {
        m_files.clear();
        emit filesChanged();
        return;
    }

    QThread* thread = QThread::create([this]() {
        QDir dir(m_sourceDirectory);
        QStringList nameFilters;
        // Stream Optimize only scans for mkv, mp4, webm
        nameFilters << "*.mkv" << "*.mp4" << "*.webm";

        QFileInfoList list = dir.entryInfoList(nameFilters, QDir::Files, QDir::Name);
        QVector<VideoFile> scanned;
        for (const QFileInfo& fi : list) {
            scanned.append(VideoFile::fromPath(fi.absoluteFilePath()));
        }

        QMetaObject::invokeMethod(QCoreApplication::instance(), [this, scanned]() {
            m_files = scanned;
            emit filesChanged();
            probeFiles();
        });
    });

    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}

void StreamOptimizeViewModel::probeFiles() {
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
    });
}

void StreamOptimizeViewModel::startProcessing() {
    if (!canStartProcessing()) return;

    StreamOptimizeConfiguration config = currentConfiguration();

    qDeleteAll(m_jobs);
    m_jobs.clear();

    for (const VideoFile& file : m_files) {
        m_jobs.append(new StreamOptimizeJob(file, config, m_destinationDirectory, this));
    }

    m_viewState = ViewState::Processing;
    emit viewStateChanged();

    executeBatch();
}

void StreamOptimizeViewModel::cancelProcessing() {
    m_cancellationRequested = true;
    if (m_currentProcess && m_currentProcess->state() == QProcess::Running) {
        m_currentProcess->kill();
    }
}

void StreamOptimizeViewModel::returnToConfiguration() {
    if (m_isProcessing) return;
    m_viewState = ViewState::Configuration;
    emit viewStateChanged();
}

QString StreamOptimizeViewModel::totalFileSize() const {
    qint64 total = 0;
    for (const auto& f : m_files) {
        total += f.fileSizeBytes;
    }
    return QLocale().formattedDataSize(total, 2, QLocale::DataSizeSIFormat);
}

QString StreamOptimizeViewModel::totalDuration() const {
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

int StreamOptimizeViewModel::completedJobCount() const {
    int count = 0;
    for (const auto* job : m_jobs) {
        if (job->state == JobState::Completed) count++;
    }
    return count;
}

int StreamOptimizeViewModel::failedJobCount() const {
    int count = 0;
    for (const auto* job : m_jobs) {
        if (job->state == JobState::Failed) count++;
    }
    return count;
}

bool StreamOptimizeViewModel::allJobsFinished() const {
    if (m_jobs.isEmpty()) return false;
    for (const auto* job : m_jobs) {
        if (!isTerminal(job->state)) return false;
    }
    return true;
}

void StreamOptimizeViewModel::executeBatch() {
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

void StreamOptimizeViewModel::executeNext() {
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

void StreamOptimizeViewModel::executeJob(StreamOptimizeJob* job) {
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

    QStringList arguments = StreamOptimizeArgumentBuilder::build(
        job->file.filePath,
        job->outputPath,
        job->configuration
    );

    job->state = JobState::Running;
    job->progress = 0.0;
    job->startDate = QDateTime::currentDateTime();
    job->appendLog("$ ffmpeg " + arguments.join(" "));
    emit jobProgressUpdated(job);

    m_firstMetricWallDate = QDateTime();
    m_firstMetricTimeSeconds = -1.0;

    m_currentProcess = new QProcess(this);
    m_currentProcess->setProgram(ffmpeg);
    m_currentProcess->setArguments(arguments);
    m_currentProcess->setProcessEnvironment(FFmpegLocator::processEnvironment());
    job->processHandle = m_currentProcess;

    connect(m_currentProcess, &QProcess::readyReadStandardError, this, &StreamOptimizeViewModel::onStderrReady);
    connect(m_currentProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &StreamOptimizeViewModel::onProcessFinished);

    m_currentProcess->start();
    m_throttleTimer->start(100);
}

void StreamOptimizeViewModel::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    m_throttleTimer->stop();
    handleThrottledUpdates();

    if (m_currentJob) {
        m_currentJob->endDate = QDateTime::currentDateTime();
        m_currentJob->processHandle = nullptr;

        if (exitCode == 0 && exitStatus == QProcess::NormalExit) {
            m_currentJob->state = JobState::Completed;
            m_currentJob->progress = 1.0;
            m_currentJob->appendLog("✅ Stream optimization completed successfully.");
        } else if (m_cancellationRequested || exitStatus == QProcess::CrashExit) {
            if (m_cancellationRequested) {
                m_currentJob->state = JobState::Cancelled;
                m_currentJob->appendLog("🛑 Stream optimization cancelled by user.");
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

void StreamOptimizeViewModel::onStderrReady() {
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
            m_pendProgress = mediaSeconds; // Hijacked for progress

            double duration = m_currentJob->file.durationSeconds.value_or(0.0);
            if (duration > 0.0) {
                m_pendProgress = qMin(mediaSeconds / duration, 1.0);
            }
        } else {
            m_logBatch.append(trimmed);
        }
    }
}

void StreamOptimizeViewModel::handleThrottledUpdates() {
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
