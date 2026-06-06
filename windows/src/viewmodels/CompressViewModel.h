#pragma once

#include <QObject>
#include <QVector>
#include <QUuid>
#include <QMap>
#include <QTimer>
#include <QProcess>
#include <optional>
#include "../models/CompressModels.h"

class CompressViewModel : public QObject {
    Q_OBJECT
public:
    enum class ViewState { Configuration, Processing };

    explicit CompressViewModel(QObject* parent = nullptr);
    ~CompressViewModel();

    // Files
    const QVector<VideoFile>& files() const;
    QUuid selectedFileID() const;
    void setSelectedFileID(const QUuid& id);
    VideoFile* selectedFile();

    // File Management
    void addFiles();
    void addFilesFromDrop(const QStringList& paths);
    void removeFile(const QUuid& id);
    void removeAllFiles();

    // Configuration
    CompressEncoder encoder() const;
    void setEncoder(CompressEncoder enc);
    int quality() const;
    void setQuality(int val);
    ContentType contentType() const;
    void setContentType(ContentType type);
    int bFrames() const;
    void setBFrames(int val);
    bool longGOPEnabled() const;
    void setLongGOPEnabled(bool val);

    void onEncoderChanged();
    void updateQuality(int value);

    // Output Directory
    QString outputDirectory() const;
    void setOutputDirectory(const QString& path);
    QString outputDirectoryDisplayName() const;
    void selectOutputDirectory();

    // Processing State
    ViewState viewState() const;
    bool isProcessing() const;
    int currentJobIndex() const;
    int totalJobs() const;
    double overallProgress() const;
    const QVector<CompressJob*>& jobs() const;

    // Control
    bool canStartProcessing() const;
    void startProcessing();
    void cancelProcessing();
    void returnToConfiguration();

    // Batch Summaries
    QString totalFileSize() const;
    QString totalDuration() const;
    QString batchSummary() const;
    int completedJobCount() const;
    int failedJobCount() const;
    bool allJobsFinished() const;

signals:
    void filesChanged();
    void selectedFileChanged();
    void configurationChanged();
    void viewStateChanged();
    void outputDirectoryChanged();
    void jobProgressUpdated(CompressJob* job);

private:
    void probeNewFiles();
    void executeBatch();
    void executeNext();
    void executeJob(CompressJob* job);
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStderrReady();
    void handleThrottledUpdates();

    QVector<VideoFile> m_files;
    QUuid m_selectedFileID;

    // Config
    CompressEncoder m_encoder = CompressEncoder::HEVC_NVENC;
    int m_quality = 68;
    ContentType m_contentType = ContentType::LiveAction;
    int m_bFrames = 3;
    bool m_longGOPEnabled = false;

    // Output
    QString m_outputDirectory;

    // Processing
    ViewState m_viewState = ViewState::Configuration;
    bool m_isProcessing = false;
    int m_currentJobIndex = 0;
    int m_totalJobs = 0;
    double m_overallProgress = 0.0;
    QVector<CompressJob*> m_jobs;

    QProcess* m_currentProcess = nullptr;
    CompressJob* m_currentJob = nullptr;
    bool m_cancellationRequested = false;
    QTimer* m_throttleTimer = nullptr;

    // Throttled states
    std::optional<int> m_pendFrame;
    std::optional<QString> m_pendTime;
    std::optional<QString> m_pendFps;
    std::optional<double> m_pendProgress;
    QStringList m_logBatch;

    // Speed calculation
    QDateTime m_firstMetricWallDate;
    double m_firstMetricTimeSeconds = -1.0;
};
