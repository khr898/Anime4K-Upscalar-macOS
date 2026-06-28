#pragma once
#include "IPickerService.h"

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
    enum class MainTab { Upscale, Compress, StreamOptimize };

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

    // Picker injection
    void setPickerService(IPickerService* picker);

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

signals:
    void filesChanged();
    void selectedFileChanged();
    void configurationChanged();
    void viewStateChanged();
    void dependencyAlertChanged();
    void outputDirectoryChanged();
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

    ProcessingEngine* m_engine = nullptr;
    IPickerService* m_picker = nullptr;
};
