#pragma once

#include <QObject>
#include <QVector>
#include <QTimer>
#include <QProcess>
#include <QDateTime>
#include <QStringList>
#include <optional>

class ProcessingJob;

class ProcessingEngine : public QObject {
    Q_OBJECT
public:
    explicit ProcessingEngine(QObject* parent = nullptr);
    ~ProcessingEngine();

    void executeBatch(QVector<ProcessingJob*> jobs);
    void cancelAll();
    void cancelJob(ProcessingJob* job);

    bool isProcessing() const;
    int currentJobIndex() const;
    int totalJobs() const;
    double overallProgress() const;

signals:
    void processingStateChanged();
    void jobProgressUpdated(ProcessingJob* job);

private:
    void executeNext();
    void executeJob(ProcessingJob* job);
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStderrReady();
    void onStdoutReady();
    void handleThrottledUpdates();

    QProcess* m_currentProcess = nullptr;
    ProcessingJob* m_currentJob = nullptr;
    QVector<ProcessingJob*> m_jobs;

    bool m_isProcessing = false;
    bool m_cancellationRequested = false;
    int m_currentJobIndex = 0;
    int m_totalJobs = 0;
    double m_overallProgress = 0.0;

    QTimer* m_throttleTimer = nullptr;

    // Throttling state
    std::optional<int> m_pendFrame;
    std::optional<QString> m_pendTime;
    std::optional<QString> m_pendFps;
    std::optional<double> m_pendProgress;
    QStringList m_logBatch;

    // Speed metrics calculation
    QDateTime m_firstMetricWallDate;
    double m_firstMetricMediaSeconds = -1.0;

    // Multi-stage state machine
    int m_currentStep = 0;
    QString m_tempFramesDir;
    QString m_tempUpscaledDir;
    QString m_tempRootPath;
    int m_ncnnScale = 4;
    int m_ncnnTarget = 4;
    int m_expectedFrameCount = 0;

    void executeNextStep();
    void cleanupTempDirs();
};
