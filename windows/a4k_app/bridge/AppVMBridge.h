#pragma once
#include <winrt/Microsoft.UI.Xaml.Data.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.Foundation.Collections.h>
#include "QtHost.h"
#include <QMetaObject>
#include <vector>
#include <memory>

namespace winrt::Anime4KUpscaler::implementation {

struct JobSnapshot {
    winrt::hstring fileName;
    double         progress = 0.0;
    winrt::hstring status;
    winrt::hstring details;
    bool           failed = false;
};

struct AppVMBridge : winrt::implements<AppVMBridge,
    winrt::Microsoft::UI::Xaml::Data::INotifyPropertyChanged>
{
    AppVMBridge(QtHost& qtHost, winrt::Microsoft::UI::Dispatching::DispatcherQueue dq);
    ~AppVMBridge();

    // INotifyPropertyChanged
    winrt::event_token PropertyChanged(
        winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler const& h);
    void PropertyChanged(winrt::event_token const& t) noexcept;

    // ---- View state (cached; read on WinUI thread) ----
    bool IsConfiguring()   const noexcept { return m_isConfiguring; }
    bool IsProcessing()    const noexcept { return m_isProcessing; }
    bool CanStart()        const noexcept { return m_canStart; }

    // ---- Dependency alert ----
    bool           ShowDependencyAlert() const noexcept { return m_showDependencyAlert; }
    winrt::hstring DependencyMessage()   const          { return m_dependencyMessage; }

    // ---- Summary ----
    winrt::hstring OutputDirectory() const { return m_outputDirectory; }
    winrt::hstring BatchSummary()    const { return m_batchSummary; }
    winrt::hstring TotalFileSize()   const { return m_totalFileSize; }
    winrt::hstring TotalDuration()   const { return m_totalDuration; }

    // ---- Job stats ----
    int32_t CompletedJobCount() const noexcept { return m_completedJobCount; }
    int32_t FailedJobCount()    const noexcept { return m_failedJobCount; }
    bool    AllJobsFinished()   const noexcept { return m_allJobsFinished; }

    // ---- Configuration (int mirrors of Qt enum values) ----
    int32_t Codec()        const noexcept { return m_codec; }
    int32_t Preset()       const noexcept { return m_preset; }
    int32_t Resolution()   const noexcept { return m_resolution; }
    int32_t QualityValue() const noexcept { return m_qualityValue; }
    int32_t BitrateValue() const noexcept { return m_bitrateValue; }
    bool    LongGOP()      const noexcept { return m_longGOP; }
    int32_t SvtPreset()    const noexcept { return m_svtPreset; }
    int32_t SelectedMode() const noexcept { return m_selectedMode; }

    // ---- File list (IObservableVector — ListView can bind to this) ----
    winrt::Windows::Foundation::Collections::IObservableVector<winrt::Windows::Foundation::IInspectable>
        FileNames() const { return m_fileNames; }

    // ---- Job snapshots (for ProcessingPanel code-behind) ----
    std::vector<JobSnapshot> GetJobSnapshots() const { return m_jobSnapshots; }

    // ---- Commands ----
    void StartProcessing();
    void CancelProcessing();
    void ReturnToConfiguration();
    void AddFiles();
    void RemoveSelectedFile();
    void RemoveAllFiles();
    void SelectOutputDirectory();
    void AddFilesFromPaths(std::vector<winrt::hstring> const& paths);

    // ---- Config setters (forwarded to Qt thread) ----
    void SetCodec(int32_t v);
    void SetPreset(int32_t v);
    void SetResolution(int32_t v);
    void SetQualityValue(int32_t v);
    void SetBitrateValue(int32_t v);
    void SetLongGOP(bool v);
    void SetSvtPreset(int32_t v);
    void SetSelectedMode(int32_t v);

private:
    void ConnectSignals();
    void RaisePropertyChanged(winrt::hstring const& name);
    void SnapshotViewState();
    void SnapshotConfig();
    void SnapshotFiles();
    void SnapshotOutput();
    void SnapshotDependencies();
    void SnapshotJobs();

    QtHost& m_qtHost;
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dq{ nullptr };
    winrt::event<winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler> m_propChanged;
    std::vector<QMetaObject::Connection> m_connections;

    // Cached WinUI-thread state
    bool           m_isConfiguring       = true;
    bool           m_isProcessing        = false;
    bool           m_canStart            = false;
    bool           m_showDependencyAlert = false;
    winrt::hstring m_dependencyMessage;
    winrt::hstring m_outputDirectory;
    winrt::hstring m_batchSummary;
    winrt::hstring m_totalFileSize;
    winrt::hstring m_totalDuration;
    int32_t        m_completedJobCount   = 0;
    int32_t        m_failedJobCount      = 0;
    bool           m_allJobsFinished     = false;
    int32_t        m_codec               = 0;
    int32_t        m_preset              = 0;
    int32_t        m_resolution          = 2;
    int32_t        m_qualityValue        = 68;
    int32_t        m_bitrateValue        = 45;
    bool           m_longGOP             = true;
    int32_t        m_svtPreset           = 6;
    int32_t        m_selectedMode        = 1;

    winrt::Windows::Foundation::Collections::IObservableVector<winrt::Windows::Foundation::IInspectable>
        m_fileNames = winrt::single_threaded_observable_vector<winrt::Windows::Foundation::IInspectable>();
    std::vector<JobSnapshot> m_jobSnapshots;
};

// ponytail: process-global — one AppViewModel per process, one WinUI window
AppVMBridge* CurrentAppBridge() noexcept;
void         SetCurrentAppBridge(AppVMBridge* b) noexcept;

} // namespace winrt::Anime4KUpscaler::implementation
