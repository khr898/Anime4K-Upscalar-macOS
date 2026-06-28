#pragma once
#include "IPickerService.h"

#include <QObject>
#include <QVector>
#include <QUuid>
#include <QMap>
#include <QTimer>
#include <QProcess>
#include <optional>
#include "../models/StreamOptimizeModels.h"

class StreamOptimizeViewModel : public QObject {
    Q_OBJECT
public:
    enum class ViewState { Configuration, Processing };

    explicit StreamOptimizeViewModel(QObject* parent = nullptr);
    ~StreamOptimizeViewModel();

    // Picker injection
    void setPickerService(IPickerService* picker);

    // Source & Destination Directories
    QString sourceDirectory() const;
    void setSourceDirectory(const QString& path);
    QString sourceDisplayName() const;
    void selectSourceDirectory();

    QString destinationDirectory() const;
    void setDestinationDirectory(const QString& path);
    QString destinationDisplayName() const;
    void selectDestinationDirectory();

    // Files
    const QVector<VideoFile>& files() const;

    // Config Properties
    StreamEncoder encoder() const;
    void setEncoder(StreamEncoder enc);
    int quality() const;
    void setQuality(int val);
    StreamProfile profile() const;
    void setProfile(StreamProfile prof);
    StreamPixelFormat pixelFormat() const;
    void setPixelFormat(StreamPixelFormat pixFmt);
    StreamAudioMode audioMode() const;
    void setAudioMode(StreamAudioMode mode);
    StreamSubtitleMode subtitleMode() const;
    void setSubtitleMode(StreamSubtitleMode mode);
    KeyframeInterval keyframeInterval() const;
    void setKeyframeInterval(KeyframeInterval interval);
    bool faststart() const;
    void setFaststart(bool val);
    bool allowSWFallback() const;
    void setAllowSWFallback(bool val);

    StreamOptimizeConfiguration currentConfiguration() const;
    void onEncoderChanged();
    void resetToDefaults();

    // Processing State
    ViewState viewState() const;
    bool isProcessing() const;
    int currentJobIndex() const;
    int totalJobs() const;
    double overallProgress() const;
    const QVector<StreamOptimizeJob*>& jobs() const;

    // Controls
    bool canStartProcessing() const;
    void startProcessing();
    void cancelProcessing();
    void returnToConfiguration();

    // Summaries
    QString totalFileSize() const;
    QString totalDuration() const;
    int completedJobCount() const;
    int failedJobCount() const;
    bool allJobsFinished() const;

signals:
    void filesChanged();
    void directoriesChanged();
    void configurationChanged();
    void viewStateChanged();
    void jobProgressUpdated(StreamOptimizeJob* job);

private:
    void scanSourceDirectory();
    void probeFiles();
    void executeBatch();
    void executeNext();
    void executeJob(StreamOptimizeJob* job);
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStderrReady();
    void handleThrottledUpdates();

    QString m_sourceDirectory;
    QString m_destinationDirectory;
    QVector<VideoFile> m_files;

    // Config
    StreamEncoder m_encoder = StreamEncoder::HEVC_NVENC;
    int m_quality = 65;
    StreamProfile m_profile = StreamProfile::Main10;
    StreamPixelFormat m_pixelFormat = StreamPixelFormat::P010LE;
    StreamAudioMode m_audioMode = StreamAudioMode::Copy;
    StreamSubtitleMode m_subtitleMode = StreamSubtitleMode::MovText;
    KeyframeInterval m_keyframeInterval = KeyframeInterval::TwoSeconds;
    bool m_faststart = true;
    bool m_allowSWFallback = true;

    // Processing State
    ViewState m_viewState = ViewState::Configuration;
    bool m_isProcessing = false;
    int m_currentJobIndex = 0;
    int m_totalJobs = 0;
    double m_overallProgress = 0.0;
    QVector<StreamOptimizeJob*> m_jobs;

    QProcess* m_currentProcess = nullptr;
    StreamOptimizeJob* m_currentJob = nullptr;
    bool m_cancellationRequested = false;
    QTimer* m_throttleTimer = nullptr;

    // Throttling
    std::optional<int> m_pendFrame;
    std::optional<QString> m_pendTime;
    std::optional<QString> m_pendFps;
    std::optional<double> m_pendProgress;
    QStringList m_logBatch;

    // Speed calculation
    QDateTime m_firstMetricWallDate;
    double m_firstMetricTimeSeconds = -1.0;
    IPickerService* m_picker = nullptr;
};
