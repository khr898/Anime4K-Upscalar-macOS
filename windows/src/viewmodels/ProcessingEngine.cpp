#include "ProcessingEngine.h"
#include "../models/Models.h"
#include "../utils/FFmpegLocator.h"
#include "../utils/SleepPreventer.h"

#include <QFileInfo>
#include <QDateTime>
#include <QDir>
#include <QRegularExpression>
#include <QDebug>
#include <algorithm>

ProcessingEngine::ProcessingEngine(QObject* parent) : QObject(parent) {
    m_throttleTimer = new QTimer(this);
    connect(m_throttleTimer, &QTimer::timeout, this, &ProcessingEngine::handleThrottledUpdates);
}

ProcessingEngine::~ProcessingEngine() {
    cancelAll();
}

void ProcessingEngine::executeBatch(QVector<ProcessingJob*> jobs) {
    if (jobs.isEmpty()) return;

    m_jobs = jobs;
    m_isProcessing = true;
    m_totalJobs = jobs.size();
    m_currentJobIndex = 0;
    m_overallProgress = 0.0;
    m_cancellationRequested = false;

    SleepPreventer::preventSleep();
    emit processingStateChanged();

    executeNext();
}

void ProcessingEngine::cancelAll() {
    m_cancellationRequested = true;
    if (m_currentProcess && m_currentProcess->state() == QProcess::Running) {
        m_currentProcess->kill();
    }
}

void ProcessingEngine::cancelJob(ProcessingJob* job) {
    if (job && job->processHandle && job->processHandle->state() == QProcess::Running) {
        job->processHandle->kill();
    }
}

bool ProcessingEngine::isProcessing() const {
    return m_isProcessing;
}

int ProcessingEngine::currentJobIndex() const {
    return m_currentJobIndex;
}

int ProcessingEngine::totalJobs() const {
    return m_totalJobs;
}

double ProcessingEngine::overallProgress() const {
    return m_overallProgress;
}

void ProcessingEngine::executeNext() {
    if (m_cancellationRequested || m_currentJobIndex >= m_jobs.size()) {
        SleepPreventer::allowSleep();
        m_isProcessing = false;
        m_currentJob = nullptr;
        m_currentProcess = nullptr;
        emit processingStateChanged();
        return;
    }

    m_currentJob = m_jobs[m_currentJobIndex];
    m_currentJobIndex++;

    executeJob(m_currentJob);
}

void ProcessingEngine::executeJob(ProcessingJob* job) {
    if (isNeuralSR(job->configuration.mode)) {
        m_tempRootPath = QDir::toNativeSeparators(QDir::tempPath() + "/Anime4KUpscaler_temp_" + job->id.toString().remove('{').remove('}'));
        m_tempFramesDir = m_tempRootPath + "/frames";
        m_tempUpscaledDir = m_tempRootPath + "/upscaled";
        QDir().mkpath(m_tempFramesDir);
        QDir().mkpath(m_tempUpscaledDir);

        job->state = JobState::Running;
        job->progress = 0.0;
        job->startDate = QDateTime::currentDateTime();
        
        m_currentStep = 1;
        executeNextStep();
        return;
    }

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

    QString shaderDir = FFmpegLocator::shaderDirectory();
    if (shaderDir.isEmpty() || !QFileInfo::exists(shaderDir)) {
        job->state = JobState::Failed;
        job->errorMessage = "Shader directory not found.";
        job->endDate = QDateTime::currentDateTime();
        job->appendLog("❌ Error: " + job->errorMessage);
        emit jobProgressUpdated(job);
        executeNext();
        return;
    }

    QStringList arguments = FFmpegArgumentBuilder::build(
        job->file.filePath,
        job->outputPath,
        job->configuration,
        shaderDir
    );

    job->state = JobState::Running;
    job->progress = 0.0;
    job->startDate = QDateTime::currentDateTime();
    job->appendLog("$ ffmpeg " + arguments.join(" "));
    emit jobProgressUpdated(job);

    m_currentStep = 0;
    m_firstMetricWallDate = QDateTime();
    m_firstMetricMediaSeconds = -1.0;

    m_currentProcess = new QProcess(this);
    m_currentProcess->setProgram(ffmpeg);
    m_currentProcess->setArguments(arguments);
    m_currentProcess->setProcessEnvironment(FFmpegLocator::processEnvironment());
    job->processHandle = m_currentProcess;

    connect(m_currentProcess, &QProcess::readyReadStandardError, this, &ProcessingEngine::onStderrReady);
    connect(m_currentProcess, &QProcess::readyReadStandardOutput, this, &ProcessingEngine::onStdoutReady);
    connect(m_currentProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &ProcessingEngine::onProcessFinished);

    m_currentProcess->start();
    m_throttleTimer->start(100);
}

void ProcessingEngine::cleanupTempDirs() {
    if (!m_tempRootPath.isEmpty()) {
        QDir dir(m_tempRootPath);
        if (dir.exists()) {
            dir.removeRecursively();
        }
        m_tempRootPath.clear();
        m_tempFramesDir.clear();
        m_tempUpscaledDir.clear();
    }
}

void ProcessingEngine::executeNextStep() {
    if (m_cancellationRequested || !m_currentJob) {
        cleanupTempDirs();
        m_currentStep = 0;
        executeNext();
        return;
    }

    if (m_currentStep == 1) {
        m_currentJob->appendLog("Starting Stage 1/3: Decoding video to frames...");
        emit jobProgressUpdated(m_currentJob);

        QString ffmpeg = FFmpegLocator::ffmpegPath();
        QStringList arguments = {
            "-y",
            "-i", m_currentJob->file.filePath,
            "-qscale:v", "1",
            m_tempFramesDir + "/%08d.png"
        };

        m_currentJob->appendLog("$ ffmpeg " + arguments.join(" "));
        
        m_firstMetricWallDate = QDateTime();
        m_firstMetricMediaSeconds = -1.0;

        m_currentProcess = new QProcess(this);
        m_currentProcess->setProgram(ffmpeg);
        m_currentProcess->setArguments(arguments);
        m_currentProcess->setProcessEnvironment(FFmpegLocator::processEnvironment());
        m_currentJob->processHandle = m_currentProcess;

        connect(m_currentProcess, &QProcess::readyReadStandardError, this, &ProcessingEngine::onStderrReady);
        connect(m_currentProcess, &QProcess::readyReadStandardOutput, this, &ProcessingEngine::onStdoutReady);
        connect(m_currentProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ProcessingEngine::onProcessFinished);

        m_currentProcess->start();
        m_throttleTimer->start(100);
    }
    else if (m_currentStep == 2) {
        m_currentJob->appendLog("Starting Stage 2/3: Upscaling frames via Real-ESRGAN...");
        emit jobProgressUpdated(m_currentJob);

        QString realesrgan = FFmpegLocator::realesrganPath();
        if (!FFmpegLocator::isRealesrganExecutable()) {
            m_currentJob->state = JobState::Failed;
            m_currentJob->errorMessage = "Real-ESRGAN binary not found or not executable.";
            m_currentJob->appendLog("❌ Error: " + m_currentJob->errorMessage);
            cleanupTempDirs();
            m_currentStep = 0;
            executeNext();
            return;
        }

        QString modelName = realesrganModelName(m_currentJob->configuration.mode);
        QString modelsDir = FFmpegLocator::realesrganModelsDirectory();

        QStringList arguments = {
            "-i", m_tempFramesDir,
            "-o", m_tempUpscaledDir,
            "-n", modelName,
            "-m", modelsDir,
            "-s", "4",
            "-j", "1:2:2",
            "-t", "0"
        };

        m_currentJob->appendLog("$ realesrgan-ncnn-vulkan " + arguments.join(" "));
        
        m_firstMetricWallDate = QDateTime();
        m_firstMetricMediaSeconds = -1.0;

        m_currentProcess = new QProcess(this);
        m_currentProcess->setProgram(realesrgan);
        m_currentProcess->setArguments(arguments);
        m_currentProcess->setProcessEnvironment(FFmpegLocator::processEnvironment());
        m_currentJob->processHandle = m_currentProcess;

        connect(m_currentProcess, &QProcess::readyReadStandardError, this, &ProcessingEngine::onStderrReady);
        connect(m_currentProcess, &QProcess::readyReadStandardOutput, this, &ProcessingEngine::onStdoutReady);
        connect(m_currentProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ProcessingEngine::onProcessFinished);

        m_currentProcess->start();
        m_throttleTimer->start(100);
    }
    else if (m_currentStep == 3) {
        m_currentJob->appendLog("Starting Stage 3/3: Re-encoding upscaled frames to video...");
        emit jobProgressUpdated(m_currentJob);

        QString ffmpeg = FFmpegLocator::ffmpegPath();
        double fps = m_currentJob->file.frameRate.value_or(23.976);

        QStringList arguments;
        arguments.append("-y");
        arguments.append({"-r", QString::number(fps)});
        arguments.append({"-i", m_tempUpscaledDir + "/%08d.png"});
        arguments.append({"-i", m_currentJob->file.filePath});
        
        arguments.append({"-map", "0:v:0"});
        arguments.append({"-map", "1:a?"});
        arguments.append({"-map", "1:s?"});

        arguments.append({"-c:a", "copy"});
        arguments.append({"-c:s", "copy"});

        arguments.append({"-c:v", encoderName(m_currentJob->configuration.codec)});
        arguments.append({"-pix_fmt", pixelFormat(m_currentJob->configuration.codec)});

        VideoCodec codec = m_currentJob->configuration.codec;
        switch (codec) {
            case VideoCodec::HEVC_NVENC:
                arguments.append({"-profile:v", "main10"});
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                    arguments.append({"-minrate", QString("%1k").arg(static_cast<int>(mbps * 900))});
                    arguments.append({"-maxrate", QString("%1k").arg(static_cast<int>(mbps * 1100))});
                    arguments.append({"-bufsize", QString("%1k").arg(static_cast<int>(mbps * 1500))});
                } else {
                    int qVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-preset", "p4"});
                    arguments.append({"-tune", "hq"});
                    arguments.append({"-rc", "vbr"});
                    arguments.append({"-cq", QString::number(qVal)});
                    arguments.append({"-b:v", "0"});
                }
                break;

            case VideoCodec::HEVC_AMF:
                arguments.append({"-profile:v", "main10"});
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                } else {
                    int qVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-quality", "quality"});
                    arguments.append({"-rc", "cqp"});
                    arguments.append({"-qp_i", QString::number(qVal)});
                    arguments.append({"-qp_p", QString::number(qVal)});
                }
                break;

            case VideoCodec::HEVC_QSV:
                arguments.append({"-profile:v", "main10"});
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                } else {
                    int qVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-preset", "medium"});
                    arguments.append({"-global_quality", QString::number(qVal)});
                }
                break;

            case VideoCodec::H264_NVENC:
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                    arguments.append({"-minrate", QString("%1k").arg(static_cast<int>(mbps * 900))});
                    arguments.append({"-maxrate", QString("%1k").arg(static_cast<int>(mbps * 1100))});
                    arguments.append({"-bufsize", QString("%1k").arg(static_cast<int>(mbps * 1500))});
                } else {
                    int qVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-preset", "p4"});
                    arguments.append({"-tune", "hq"});
                    arguments.append({"-rc", "vbr"});
                    arguments.append({"-cq", QString::number(qVal)});
                    arguments.append({"-b:v", "0"});
                }
                break;

            case VideoCodec::H264_AMF:
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                } else {
                    int qVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-quality", "quality"});
                    arguments.append({"-rc", "cqp"});
                    arguments.append({"-qp_i", QString::number(qVal)});
                    arguments.append({"-qp_p", QString::number(qVal)});
                }
                break;

            case VideoCodec::H264_QSV:
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                } else {
                    int qVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-preset", "medium"});
                    arguments.append({"-global_quality", QString::number(qVal)});
                }
                break;

            case VideoCodec::SVT_AV1:
                arguments.append({"-preset", "6"});
                arguments.append({"-svtav1-params", "tune=0"});
                if (m_currentJob->configuration.compression.isFixedBitrate()) {
                    int mbps = m_currentJob->configuration.compression.bitrateMbps();
                    arguments.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                    arguments.append({"-maxrate", QString("%1k").arg(static_cast<int>(mbps * 1100))});
                    arguments.append({"-bufsize", QString("%1k").arg(static_cast<int>(mbps * 1500))});
                } else {
                    int crfVal = m_currentJob->configuration.compression.qualityValue(codec);
                    arguments.append({"-crf", QString::number(crfVal)});
                }
                break;
        }

        if (m_currentJob->configuration.longGOPEnabled) {
            arguments.append({"-g", "240"});
        }

        arguments.append({"-progress", "pipe:1"});
        arguments.append(m_currentJob->outputPath);

        m_currentJob->appendLog("$ ffmpeg " + arguments.join(" "));
        
        m_firstMetricWallDate = QDateTime();
        m_firstMetricMediaSeconds = -1.0;

        m_currentProcess = new QProcess(this);
        m_currentProcess->setProgram(ffmpeg);
        m_currentProcess->setArguments(arguments);
        m_currentProcess->setProcessEnvironment(FFmpegLocator::processEnvironment());
        m_currentJob->processHandle = m_currentProcess;

        connect(m_currentProcess, &QProcess::readyReadStandardError, this, &ProcessingEngine::onStderrReady);
        connect(m_currentProcess, &QProcess::readyReadStandardOutput, this, &ProcessingEngine::onStdoutReady);
        connect(m_currentProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &ProcessingEngine::onProcessFinished);

        m_currentProcess->start();
        m_throttleTimer->start(100);
    }
}

void ProcessingEngine::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus) {
    m_throttleTimer->stop();
    handleThrottledUpdates(); // Flush last updates

    if (m_currentJob) {
        m_currentJob->processHandle = nullptr;

        if (exitCode == 0 && exitStatus == QProcess::NormalExit) {
            if (m_currentStep > 0) {
                m_currentJob->appendLog(QString("Stage %1 completed.").arg(m_currentStep));
                if (m_currentProcess) {
                    m_currentProcess->deleteLater();
                    m_currentProcess = nullptr;
                }
                m_currentStep++;
                if (m_currentStep <= 3) {
                    executeNextStep();
                    return;
                } else {
                    // All stages complete
                    cleanupTempDirs();
                    m_currentStep = 0;
                    m_currentJob->endDate = QDateTime::currentDateTime();
                    m_currentJob->state = JobState::Completed;
                    m_currentJob->progress = 1.0;
                    m_currentJob->appendLog("✅ Neural SR completed successfully.");
                }
            } else {
                m_currentJob->endDate = QDateTime::currentDateTime();
                m_currentJob->state = JobState::Completed;
                m_currentJob->progress = 1.0;
                m_currentJob->appendLog("✅ Processing completed successfully.");
            }
        } else {
            cleanupTempDirs();
            m_currentStep = 0;
            m_currentJob->endDate = QDateTime::currentDateTime();

            if (m_cancellationRequested || exitStatus == QProcess::CrashExit) {
                if (m_cancellationRequested) {
                    m_currentJob->state = JobState::Cancelled;
                    m_currentJob->appendLog("🛑 Processing cancelled by user.");
                } else {
                    m_currentJob->state = JobState::Failed;
                    m_currentJob->errorMessage = QString("Subprocess crashed or exited with code %1").arg(exitCode);
                    m_currentJob->appendLog("❌ Error: " + m_currentJob->errorMessage);
                }
            } else {
                m_currentJob->state = JobState::Failed;
                m_currentJob->errorMessage = QString("Subprocess exited with code %1").arg(exitCode);
                m_currentJob->appendLog("❌ Error: " + m_currentJob->errorMessage);
            }
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

void ProcessingEngine::onStderrReady() {
    if (!m_currentProcess || !m_currentJob) return;

    QByteArray data = m_currentProcess->readAllStandardError();
    QString text = QString::fromUtf8(data);

    QStringList lines = text.split('\n', Qt::SkipEmptyParts);
    for (const QString& line : lines) {
        QString trimmed = line.trimmed();
        
        if (m_currentStep == 2) {
            // realesrgan progress parsing
            static QRegularExpression percentRegex("(\\d+\\.\\d+)%");
            auto match = percentRegex.match(trimmed);
            if (match.hasMatch()) {
                double percent = match.captured(1).toDouble() / 100.0;
                m_pendProgress = 0.15 + 0.70 * percent;
                m_pendFps = "realesr";
                m_pendFrame = static_cast<int>(percent * 100.0);
            } else {
                m_logBatch.append(trimmed);
            }
            continue;
        }

        auto progOpt = FFmpegProgress::parse(trimmed);
        if (progOpt.has_value()) {
            FFmpegProgress prog = progOpt.value();
            m_pendFrame = prog.frame;
            m_pendTime = prog.time;
            m_pendFps = QString::number(prog.fps, 'f', 1);

            double duration = m_currentJob->file.durationSeconds.value_or(0.0);
            if (duration > 0.0) {
                if (m_currentStep == 1) {
                    m_pendProgress = 0.15 * std::min(prog.timeSeconds() / duration, 1.0);
                } else if (m_currentStep == 3) {
                    m_pendProgress = 0.85 + 0.15 * std::min(prog.timeSeconds() / duration, 1.0);
                } else {
                    m_pendProgress = std::min(prog.timeSeconds() / duration, 1.0);
                }
            }
        } else {
            m_logBatch.append(trimmed);
        }
    }
}

void ProcessingEngine::onStdoutReady() {
    if (!m_currentProcess) return;
    QByteArray data = m_currentProcess->readAllStandardOutput();
    QString text = QString::fromUtf8(data);

    QStringList lines = text.split('\n', Qt::SkipEmptyParts);
    for (const QString& line : lines) {
        QString trimmed = line.trimmed();
        if (trimmed.startsWith("out_time_us=") || trimmed.startsWith("out_time_ms=")) {
            bool ok;
            double us = trimmed.section('=', 1, 1).toDouble(&ok);
            if (ok) {
                double mediaSeconds = us / 1000000.0;
                double duration = m_currentJob ? m_currentJob->file.durationSeconds.value_or(0.0) : 0.0;
                if (duration > 0.0) {
                    if (m_currentStep == 1) {
                        m_pendProgress = 0.15 * std::min(mediaSeconds / duration, 1.0);
                    } else if (m_currentStep == 3) {
                        m_pendProgress = 0.85 + 0.15 * std::min(mediaSeconds / duration, 1.0);
                    } else {
                        m_pendProgress = std::min(mediaSeconds / duration, 1.0);
                    }
                }

                if (m_currentJob) {
                    if (!m_firstMetricWallDate.isValid() && mediaSeconds > 0.0) {
                        m_firstMetricWallDate = QDateTime::currentDateTime();
                        m_firstMetricMediaSeconds = mediaSeconds;
                    }

                    if (m_firstMetricWallDate.isValid() && m_firstMetricMediaSeconds >= 0.0) {
                        double elapsed = std::max(static_cast<double>(m_firstMetricWallDate.msecsTo(QDateTime::currentDateTime())) / 1000.0, 0.001);
                        double mediaDelta = std::max(mediaSeconds - m_firstMetricMediaSeconds, 0.0);

                        if (elapsed >= 0.35 && mediaDelta > 0.0) {
                            double speed = mediaDelta / elapsed;
                            m_currentJob->speed = QString("x%1").arg(speed, 0, 'f', 3);
                        } else {
                            m_currentJob->speed = "warming...";
                        }
                    }
                }
            }
        } else if (trimmed.startsWith("fps=")) {
            m_pendFps = trimmed.section('=', 1, 1).trimmed();
        } else if (trimmed.startsWith("frame=")) {
            bool ok;
            int f = trimmed.section('=', 1, 1).toInt(&ok);
            if (ok) m_pendFrame = f;
        }
    }
}

void ProcessingEngine::handleThrottledUpdates() {
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
        m_currentJob->progress = m_pendProgress.value();
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
