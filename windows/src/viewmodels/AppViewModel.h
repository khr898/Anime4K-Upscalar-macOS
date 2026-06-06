#pragma once

#include <QObject>
#include <QVector>
#include <QUuid>
#include <QMap>
#include <optional>
#include "../models/Models.h"

// Forward declaration
class ProcessingEngine;

class AppViewModel : public QObject {
    Q_OBJECT
public:
    enum class ViewState { Configuration, Processing };
    enum class MainTab { Upscale, Compress, StreamOptimize, QualityTune };

    struct QualityScanCandidate {
        QUuid id;
        int value;
        bool usesCRF;
        double ssim;
        double psnr;
        qint64 outputSizeBytes;

        QString valueLabel() const {
            return usesCRF ? QString("CRF %1").arg(value) : QString("Q %1").arg(value);
        }

        QString sizeLabel() const;
    };

    explicit AppViewModel(QObject* parent = nullptr);
    ~AppViewModel();

    // Tab state
    MainTab selectedMainTab() const;
    void setSelectedMainTab(MainTab tab);

    // Sidebar video files
    const QVector<VideoFile>& files() const;
    QUuid selectedFileID() const;
    void setSelectedFileID(const QUuid& id);
    VideoFile* selectedFile();

    // File Management
    void addFiles();
    void addFilesFromDrop(const QStringList& paths);
    void removeFile(const QUuid& id);
    void removeAllFiles();
    void removeSelectedFile();

    // Configuration
    const JobConfiguration& configuration() const;
    JobConfiguration& configurationRef();
    CompressionPreset compressionPreset() const;
    void setCompressionPreset(CompressionPreset preset);
    int customQualityValue() const;
    int customBitrateValue() const;
    void syncCompression();
    void updateCustomQuality(int value);
    void updateCustomBitrate(int value);
    void onCodecChanged();

    // Output Directory
    QString outputDirectory() const;
    void setOutputDirectory(const QString& path);
    QString outputDirectoryDisplayName() const;
    void selectOutputDirectory();

    // Dependency Validation
    const QStringList& dependencyErrors() const;
    bool showDependencyAlert() const;
    void setShowDependencyAlert(bool show);

    // View State
    ViewState viewState() const;
    const QVector<ProcessingJob*>& jobs() const;
    ProcessingEngine* engine() const;

    // Processing Control
    bool canStartProcessing() const;
    void startProcessing();
    void cancelProcessing();
    void returnToConfiguration();

    // Summary strings
    QString totalFileSize() const;
    QString totalDuration() const;
    QString batchSummary() const;
    int completedJobCount() const;
    int failedJobCount() const;
    bool allJobsFinished() const;

    // Quality Tune State & Actions
    QString qualityTuneInputPath() const;
    void selectQualityTuneInputFile();
    VideoCodec qualityTuneCodec() const;
    void setQualityTuneCodec(VideoCodec codec);
    void onQualityTuneCodecChanged();

    int qualityTuneRangeStart() const { return m_qualityTuneRangeStart; }
    void setQualityTuneRangeStart(int val) { m_qualityTuneRangeStart = val; }
    int qualityTuneRangeEnd() const { return m_qualityTuneRangeEnd; }
    void setQualityTuneRangeEnd(int val) { m_qualityTuneRangeEnd = val; }
    int qualityTuneStep() const { return m_qualityTuneStep; }
    void setQualityTuneStep(int val) { m_qualityTuneStep = val; }
    int qualityTuneSampleSeconds() const { return m_qualityTuneSampleSeconds; }
    void setQualityTuneSampleSeconds(int val) { m_qualityTuneSampleSeconds = val; }
    double qualityTuneTargetSSIM() const { return m_qualityTuneTargetSSIM; }
    void setQualityTuneTargetSSIM(double val) { m_qualityTuneTargetSSIM = val; }

    bool qualityTuneIsRunning() const;
    const QVector<QualityScanCandidate>& qualityTuneCandidates() const;
    std::optional<QualityScanCandidate> qualityTuneBestCandidate() const;
    QString qualityTuneStatusText() const;
    QString qualityTuneErrorText() const;
    void runQualityTuneScan();

signals:
    void filesChanged();
    void selectedFileChanged();
    void configurationChanged();
    void viewStateChanged();
    void dependencyAlertChanged();
    void outputDirectoryChanged();
    void qualityTuneStateChanged();
    void qualityTuneCandidatesChanged();

private:
    void validateDependencies();
    void probeNewFiles();

    MainTab m_selectedMainTab = MainTab::Upscale;
    QVector<VideoFile> m_files;
    QUuid m_selectedFileID;
    JobConfiguration m_configuration;
    QVector<ProcessingJob*> m_jobs;
    ViewState m_viewState = ViewState::Configuration;

    CompressionPreset m_compressionPreset = CompressionPreset::VisuallyLossless;
    int m_customQualityValue = 68;
    int m_customBitrateValue = 45;

    QStringList m_dependencyErrors;
    bool m_showDependencyAlert = false;
    QString m_outputDirectory;

    // Quality Tune state
    QString m_qualityTuneInputPath;
    VideoCodec m_qualityTuneCodec = VideoCodec::HEVC_NVENC;
    int m_qualityTuneRangeStart = 56;
    int m_qualityTuneRangeEnd = 80;
    int m_qualityTuneStep = 4;
    int m_qualityTuneSampleSeconds = 20;
    double m_qualityTuneTargetSSIM = 0.995;
    bool m_qualityTuneIsRunning = false;
    QVector<QualityScanCandidate> m_qualityTuneCandidates;
    std::optional<QualityScanCandidate> m_qualityTuneBestCandidate;
    QString m_qualityTuneStatusText;
    QString m_qualityTuneErrorText;

    ProcessingEngine* m_engine = nullptr;
};
