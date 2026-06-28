#include "AppViewModel.h"
#include "ProcessingEngine.h"
#include "../utils/FFmpegLocator.h"
#include "../utils/DurationProbe.h"

#include <QFileInfo>
#include <QDir>
#include <QLocale>
#include <QThread>
#include <QTemporaryDir>
#include <QCoreApplication>
#include <QMetaObject>

// MARK: - QualityScanCandidate size formatting helper

QString AppViewModel::QualityScanCandidate::sizeLabel() const {
    return QLocale().formattedDataSize(outputSizeBytes, 2, QLocale::DataSizeSIFormat);
}

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

// MARK: - Quality Tune Implementations

struct ToolResult {
    int status;
    QString output;
};
static ToolResult runTool(const QString& program, const QStringList& arguments) {
    QProcess process;
    process.setProgram(program);
    process.setArguments(arguments);
    process.setProcessEnvironment(FFmpegLocator::processEnvironment());
    process.start();
    if (!process.waitForFinished(30000)) { // 30 seconds timeout
        process.kill();
        return {-1, "Timeout"};
    }
    return {process.exitCode(), QString::fromUtf8(process.readAllStandardError() + process.readAllStandardOutput())};
}

static std::optional<double> parseSSIM(const QString& output) {
    int idx = output.indexOf("All:", 0, Qt::CaseInsensitive);
    if (idx != -1) {
        int start = idx + 4;
        while (start < output.length() && output[start].isSpace()) {
            start++;
        }
        int end = start;
        while (end < output.length() && (output[end].isDigit() || output[end] == '.')) {
            end++;
        }
        bool ok;
        double val = output.mid(start, end - start).toDouble(&ok);
        if (ok) return val;
    }
    return std::nullopt;
}

static std::optional<double> parsePSNR(const QString& output) {
    int idx = output.indexOf("average:", 0, Qt::CaseInsensitive);
    if (idx != -1) {
        int start = idx + 8;
        while (start < output.length() && output[start].isSpace()) {
            start++;
        }
        int end = start;
        while (end < output.length() && (output[end].isDigit() || output[end] == '.')) {
            end++;
        }
        bool ok;
        double val = output.mid(start, end - start).toDouble(&ok);
        if (ok) return val;
    }
    return std::nullopt;
}

static std::optional<AppViewModel::QualityScanCandidate> pickBestQualityCandidate(const QVector<AppViewModel::QualityScanCandidate>& candidates, double targetSSIM) {
    QVector<AppViewModel::QualityScanCandidate> pass;
    for (const auto& c : candidates) {
        if (c.ssim >= targetSSIM) pass.append(c);
    }
    if (!pass.isEmpty()) {
        auto bestPassing = pass[0];
        for (int i = 1; i < pass.size(); ++i) {
            auto c = pass[i];
            if (c.outputSizeBytes != bestPassing.outputSizeBytes) {
                if (c.outputSizeBytes < bestPassing.outputSizeBytes) bestPassing = c;
            } else if (c.psnr != bestPassing.psnr) {
                if (c.psnr > bestPassing.psnr) bestPassing = c;
            } else if (c.ssim > bestPassing.ssim) {
                bestPassing = c;
            }
        }
        return bestPassing;
    }

    if (candidates.isEmpty()) return std::nullopt;
    auto best = candidates[0];
    for (int i = 1; i < candidates.size(); ++i) {
        auto c = candidates[i];
        if (c.ssim != best.ssim) {
            if (c.ssim > best.ssim) best = c;
        } else if (c.psnr != best.psnr) {
            if (c.psnr > best.psnr) best = c;
        } else if (c.outputSizeBytes < best.outputSizeBytes) {
            best = c;
        }
    }
    return best;
}

QString AppViewModel::qualityTuneInputPath() const {
    return m_qualityTuneInputPath;
}

void AppViewModel::selectQualityTuneInputFile() {
    if (!m_picker) return;
    m_picker->pickFiles(
        "Select Quality Tune Input Video",
        "Video Files (*.mp4 *.mkv *.mov *.avi *.webm *.flv *.ts)",
        [this](QStringList paths) {
            if (!paths.isEmpty()) {
                m_qualityTuneInputPath = QDir::cleanPath(paths.first());
                emit qualityTuneStateChanged();
            }
        });
}

VideoCodec AppViewModel::qualityTuneCodec() const {
    return m_qualityTuneCodec;
}

void AppViewModel::setQualityTuneCodec(VideoCodec codec) {
    if (m_qualityTuneCodec != codec) {
        m_qualityTuneCodec = codec;
        onQualityTuneCodecChanged();
        emit qualityTuneStateChanged();
    }
}

void AppViewModel::onQualityTuneCodecChanged() {
    if (usesCRF(m_qualityTuneCodec)) {
        m_qualityTuneRangeStart = 20;
        m_qualityTuneRangeEnd = 36;
        m_qualityTuneStep = 2;
    } else {
        m_qualityTuneRangeStart = 56;
        m_qualityTuneRangeEnd = 80;
        m_qualityTuneStep = 4;
    }
    emit qualityTuneStateChanged();
}

bool AppViewModel::qualityTuneIsRunning() const {
    return m_qualityTuneIsRunning;
}

const QVector<AppViewModel::QualityScanCandidate>& AppViewModel::qualityTuneCandidates() const {
    return m_qualityTuneCandidates;
}

std::optional<AppViewModel::QualityScanCandidate> AppViewModel::qualityTuneBestCandidate() const {
    return m_qualityTuneBestCandidate;
}

QString AppViewModel::qualityTuneStatusText() const {
    return m_qualityTuneStatusText;
}

QString AppViewModel::qualityTuneErrorText() const {
    return m_qualityTuneErrorText;
}

void AppViewModel::runQualityTuneScan() {
    if (m_qualityTuneIsRunning) return;
    if (m_qualityTuneInputPath.isEmpty()) {
        m_qualityTuneErrorText = "Choose an input video first.";
        emit qualityTuneStateChanged();
        return;
    }

    QString ffmpeg = FFmpegLocator::ffmpegPath();
    if (!FFmpegLocator::isFFmpegExecutable()) {
        m_qualityTuneErrorText = "Bundled FFmpeg was not found.";
        emit qualityTuneStateChanged();
        return;
    }

    m_qualityTuneIsRunning = true;
    m_qualityTuneCandidates.clear();
    m_qualityTuneBestCandidate = std::nullopt;
    m_qualityTuneErrorText.clear();
    m_qualityTuneStatusText = "Running quality scan...";

    emit qualityTuneStateChanged();
    emit qualityTuneCandidatesChanged();

    int start = m_qualityTuneRangeStart;
    int end = m_qualityTuneRangeEnd;
    int step = m_qualityTuneStep;
    int sampleSeconds = m_qualityTuneSampleSeconds;
    double targetSSIM = m_qualityTuneTargetSSIM;
    VideoCodec codec = m_qualityTuneCodec;
    QString inputPath = m_qualityTuneInputPath;

    QThread* thread = QThread::create([this, start, end, step, sampleSeconds, targetSSIM, codec, inputPath, ffmpeg]() {
        QTemporaryDir tempDir;
        QString tempPath = tempDir.path();

        QVector<QualityScanCandidate> list;

        try {
            for (int value = start; value <= end; value += step) {
                if (!m_qualityTuneIsRunning) break;

                QString outFilename = QDir(tempPath).filePath(QString("sample_%1.mp4").arg(value));

                QStringList encodeArgs = {
                    "-hide_banner", "-v", "error", "-stats",
                    "-y",
                    "-t", QString::number(sampleSeconds),
                    "-i", inputPath,
                    "-map", "0:v:0",
                    "-an", "-sn",
                    "-c:v", encoderName(codec)
                };

                if (codec == VideoCodec::HEVC_NVENC || codec == VideoCodec::H264_NVENC) {
                    encodeArgs.append({"-preset", "p4", "-tune", "hq", "-rc", "vbr", "-cq", QString::number(value), "-b:v", "0", "-pix_fmt", pixelFormat(codec)});
                } else if (codec == VideoCodec::HEVC_AMF || codec == VideoCodec::H264_AMF) {
                    encodeArgs.append({"-quality", "quality", "-rc", "cqp", "-qp_i", QString::number(value), "-qp_p", QString::number(value), "-pix_fmt", pixelFormat(codec)});
                } else if (codec == VideoCodec::HEVC_QSV || codec == VideoCodec::H264_QSV) {
                    encodeArgs.append({"-preset", "medium", "-global_quality", QString::number(value), "-pix_fmt", pixelFormat(codec)});
                } else if (codec == VideoCodec::SVT_AV1) {
                    encodeArgs.append({"-preset", "6", "-crf", QString::number(value), "-pix_fmt", pixelFormat(codec), "-svtav1-params", "tune=0"});
                }

                encodeArgs.append(outFilename);

                auto encRes = runTool(ffmpeg, encodeArgs);
                if (encRes.status != 0) {
                    throw std::runtime_error(QString("Encoding failed for value %1: %2").arg(value).arg(encRes.output).toStdString());
                }

                qint64 size = QFileInfo(outFilename).size();

                // Compute SSIM
                QStringList ssimArgs = {
                    "-hide_banner", "-nostats",
                    "-t", QString::number(sampleSeconds),
                    "-i", inputPath,
                    "-t", QString::number(sampleSeconds),
                    "-i", outFilename,
                    "-lavfi", "ssim=shortest=1",
                    "-f", "null", "-"
                };
                auto ssimRes = runTool(ffmpeg, ssimArgs);
                double ssim = parseSSIM(ssimRes.output).value_or(0.0);

                // Compute PSNR
                QStringList psnrArgs = {
                    "-hide_banner", "-nostats",
                    "-t", QString::number(sampleSeconds),
                    "-i", inputPath,
                    "-t", QString::number(sampleSeconds),
                    "-i", outFilename,
                    "-lavfi", "psnr=shortest=1",
                    "-f", "null", "-"
                };
                auto psnrRes = runTool(ffmpeg, psnrArgs);
                double psnr = parsePSNR(psnrRes.output).value_or(0.0);

                QualityScanCandidate c;
                c.id = QUuid::createUuid();
                c.value = value;
                c.usesCRF = usesCRF(codec);
                c.ssim = ssim;
                c.psnr = psnr;
                c.outputSizeBytes = size;

                list.append(c);

                QMetaObject::invokeMethod(QCoreApplication::instance(), [this, list]() {
                    m_qualityTuneCandidates = list;
                    m_qualityTuneStatusText = QString("Evaluated %1 candidate%2...").arg(list.size()).arg(list.size() == 1 ? "" : "s");
                    emit qualityTuneCandidatesChanged();
                    emit qualityTuneStateChanged();
                });
            }

            auto best = pickBestQualityCandidate(list, targetSSIM);

            QMetaObject::invokeMethod(QCoreApplication::instance(), [this, best]() {
                m_qualityTuneBestCandidate = best;
                m_qualityTuneIsRunning = false;
                if (best.has_value()) {
                    m_qualityTuneStatusText = QString("Best %1: SSIM %2, PSNR %3 dB, %4")
                        .arg(best->valueLabel())
                        .arg(QString::number(best->ssim, 'f', 4))
                        .arg(QString::number(best->psnr, 'f', 2))
                        .arg(best->sizeLabel());
                } else {
                    m_qualityTuneStatusText = "No valid candidate found.";
                }
                emit qualityTuneStateChanged();
            });

        } catch (const std::exception& e) {
            QString err = QString::fromStdString(e.what());
            QMetaObject::invokeMethod(QCoreApplication::instance(), [this, err]() {
                m_qualityTuneErrorText = err;
                m_qualityTuneIsRunning = false;
                m_qualityTuneStatusText = "Scan failed.";
                emit qualityTuneStateChanged();
            });
        }
    });

    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}
