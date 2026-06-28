#include "AppViewModel.h"
#include "ProcessingEngine.h"
#include "../utils/FFmpegLocator.h"
#include "../utils/DurationProbe.h"

#include <QFileInfo>
#include <QDir>
#include <QLocale>
// MARK: - AppViewModel Constructor & Destructor

AppViewModel::AppViewModel(QObject* parent) : QObject(parent) {
    m_engine = new ProcessingEngine(this);

    // Bubble up processing updates
    connect(m_engine, &ProcessingEngine::processingStateChanged, this, &AppViewModel::viewStateChanged);
    connect(m_engine, &ProcessingEngine::jobProgressUpdated, this, [this](ProcessingJob*) {
        emit viewStateChanged();
    });

    validateDependencies();
}

AppViewModel::~AppViewModel() {
    qDeleteAll(m_jobs);
}

void AppViewModel::setPickerService(IPickerService* picker) {
    m_picker = picker;
}

// MARK: - Tab state

AppViewModel::MainTab AppViewModel::selectedMainTab() const {
    return m_selectedMainTab;
}

void AppViewModel::setSelectedMainTab(MainTab tab) {
    if (m_selectedMainTab != tab) {
        m_selectedMainTab = tab;
        emit configurationChanged();
    }
}

// MARK: - Sidebar video files

const QVector<VideoFile>& AppViewModel::files() const {
    return m_files;
}

QUuid AppViewModel::selectedFileID() const {
    return m_selectedFileID;
}

void AppViewModel::setSelectedFileID(const QUuid& id) {
    if (m_selectedFileID != id) {
        m_selectedFileID = id;
        emit selectedFileChanged();
    }
}

VideoFile* AppViewModel::selectedFile() {
    for (auto& file : m_files) {
        if (file.id == m_selectedFileID) return &file;
    }
    return nullptr;
}

// MARK: - File Management

void AppViewModel::addFiles() {
    if (!m_picker) return;
    m_picker->pickFiles(
        "Select Video Files",
        "Video Files (*.mp4 *.mkv *.mov *.avi *.webm *.flv *.ts)",
        [this](QStringList paths) {
            if (!paths.isEmpty())
                addFilesFromDrop(paths);
        });
}

void AppViewModel::addFilesFromDrop(const QStringList& paths) {
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

void AppViewModel::removeFile(const QUuid& id) {
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

void AppViewModel::removeAllFiles() {
    m_files.clear();
    m_selectedFileID = QUuid();
    emit selectedFileChanged();
    emit filesChanged();
}

void AppViewModel::removeSelectedFile() {
    if (!m_selectedFileID.isNull()) {
        removeFile(m_selectedFileID);
    }
}

// MARK: - Metadata Probing

void AppViewModel::probeNewFiles() {
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
                        file.frameRate = res->frameRate;
                    }
                }
            }
        }
        emit filesChanged();
        emit selectedFileChanged();
    });
}

// MARK: - Configuration

const JobConfiguration& AppViewModel::configuration() const {
    return m_configuration;
}

JobConfiguration& AppViewModel::configurationRef() {
    return m_configuration;
}

CompressionPreset AppViewModel::compressionPreset() const {
    return m_compressionPreset;
}

void AppViewModel::setCompressionPreset(CompressionPreset preset) {
    if (m_compressionPreset != preset) {
        m_compressionPreset = preset;
        syncCompression();
    }
}

int AppViewModel::customQualityValue() const {
    return m_customQualityValue;
}

int AppViewModel::customBitrateValue() const {
    return m_customBitrateValue;
}

void AppViewModel::syncCompression() {
    switch (m_compressionPreset) {
        case CompressionPreset::VisuallyLossless:
            m_configuration.compression = CompressionMode::visuallyLossless();
            break;
        case CompressionPreset::Balanced:
            m_configuration.compression = CompressionMode::balanced();
            break;
        case CompressionPreset::CustomQuality:
            m_configuration.compression = CompressionMode::customQuality(m_customQualityValue);
            break;
        case CompressionPreset::FixedBitrate:
            m_configuration.compression = CompressionMode::fixedBitrate(m_customBitrateValue);
            break;
    }
    emit configurationChanged();
}

void AppViewModel::updateCustomQuality(int value) {
    int maxVal = m_configuration.codec == VideoCodec::SVT_AV1 ? 63 : 100;
    m_customQualityValue = qBound(0, value, maxVal);
    syncCompression();
}

void AppViewModel::updateCustomBitrate(int value) {
    m_customBitrateValue = qBound(1, value, 200);
    syncCompression();
}

void AppViewModel::onCodecChanged() {
    if (m_configuration.codec == VideoCodec::SVT_AV1) {
        if (m_compressionPreset == CompressionPreset::CustomQuality && m_customQualityValue > 63) {
            m_customQualityValue = 24;
        }
    } else {
        if (m_compressionPreset == CompressionPreset::CustomQuality && m_customQualityValue > 100) {
            m_customQualityValue = 68;
        }
    }
    syncCompression();
}

// MARK: - Output Directory

QString AppViewModel::outputDirectory() const {
    return m_outputDirectory;
}

void AppViewModel::setOutputDirectory(const QString& path) {
    if (m_outputDirectory != path) {
        m_outputDirectory = QDir::cleanPath(path);
        emit outputDirectoryChanged();
    }
}

QString AppViewModel::outputDirectoryDisplayName() const {
    if (m_outputDirectory.isEmpty()) return "Not selected";
    return QFileInfo(m_outputDirectory).fileName();
}

void AppViewModel::selectOutputDirectory() {
    if (!m_picker) return;
    m_picker->pickDirectory(
        "Select Output Directory",
        m_outputDirectory,
        [this](QString dir) {
            if (!dir.isEmpty())
                setOutputDirectory(dir);
        });
}

// MARK: - Dependency Validation

void AppViewModel::validateDependencies() {
    m_dependencyErrors = FFmpegLocator::validateDependencies();
    m_showDependencyAlert = !m_dependencyErrors.isEmpty();
}

const QStringList& AppViewModel::dependencyErrors() const {
    return m_dependencyErrors;
}

bool AppViewModel::showDependencyAlert() const {
    return m_showDependencyAlert;
}

void AppViewModel::setShowDependencyAlert(bool show) {
    if (m_showDependencyAlert != show) {
        m_showDependencyAlert = show;
        emit dependencyAlertChanged();
    }
}

// MARK: - Processing Control

AppViewModel::ViewState AppViewModel::viewState() const {
    return m_viewState;
}

const QVector<ProcessingJob*>& AppViewModel::jobs() const {
    return m_jobs;
}

ProcessingEngine* AppViewModel::engine() const {
    return m_engine;
}

bool AppViewModel::canStartProcessing() const {
    return !m_files.isEmpty() && !m_engine->isProcessing();
}

void AppViewModel::startProcessing() {
    if (!canStartProcessing()) return;

    if (m_outputDirectory.isEmpty()) {
        selectOutputDirectory();
        if (m_outputDirectory.isEmpty()) return;
    }

    syncCompression();

    qDeleteAll(m_jobs);
    m_jobs.clear();

    for (const VideoFile& file : m_files) {
        m_jobs.append(new ProcessingJob(file, m_configuration, m_outputDirectory, this));
    }

    m_viewState = ViewState::Processing;
    emit viewStateChanged();

    m_engine->executeBatch(m_jobs);
}

void AppViewModel::cancelProcessing() {
    m_engine->cancelAll();
}

void AppViewModel::returnToConfiguration() {
    if (m_engine->isProcessing()) return;
    m_viewState = ViewState::Configuration;
    emit viewStateChanged();
}

// MARK: - Summaries

QString AppViewModel::totalFileSize() const {
    qint64 total = 0;
    for (const auto& file : m_files) {
        total += file.fileSizeBytes;
    }
    return QLocale().formattedDataSize(total, 2, QLocale::DataSizeSIFormat);
}

QString AppViewModel::totalDuration() const {
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

QString AppViewModel::batchSummary() const {
    QString modeStr = displayName(m_configuration.mode);
    QString scaleStr = displayName(m_configuration.resolution);
    QString codecStr = displayName(m_configuration.codec);
    return QString("%1 file%2 \u2022 %3 \u2022 %4 \u2022 %5")
        .arg(m_files.size())
        .arg(m_files.size() == 1 ? "" : "s")
        .arg(modeStr)
        .arg(scaleStr)
        .arg(codecStr);
}

int AppViewModel::completedJobCount() const {
    int count = 0;
    for (const auto* job : m_jobs) {
        if (job->state == JobState::Completed) count++;
    }
    return count;
}

int AppViewModel::failedJobCount() const {
    int count = 0;
    for (const auto* job : m_jobs) {
        if (job->state == JobState::Failed) count++;
    }
    return count;
}

bool AppViewModel::allJobsFinished() const {
    if (m_jobs.isEmpty()) return false;
    for (const auto* job : m_jobs) {
        if (!isTerminal(job->state)) return false;
    }
    return true;
}

