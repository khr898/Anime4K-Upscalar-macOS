#pragma once
#include <winrt/Microsoft.UI.Xaml.Data.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.Foundation.Collections.h>
#include "QtHost.h"
#include "AppVMBridge.h"
#include <QMetaObject>
#include <vector>

namespace winrt::Anime4KUpscaler::implementation {

struct CompressVMBridge : winrt::implements<CompressVMBridge,
    winrt::Microsoft::UI::Xaml::Data::INotifyPropertyChanged>
{
    CompressVMBridge(QtHost& qtHost, winrt::Microsoft::UI::Dispatching::DispatcherQueue dq);
    ~CompressVMBridge();

    winrt::event_token PropertyChanged(
        winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler const& h);
    void PropertyChanged(winrt::event_token const& t) noexcept;

    bool IsProcessing()  const noexcept { return m_isProcessing; }
    bool IsConfiguring() const noexcept { return m_isConfiguring; }
    bool CanStart()      const noexcept { return m_canStart; }

    winrt::hstring OutputDirectory() const { return m_outputDirectory; }
    winrt::hstring BatchSummary()    const { return m_batchSummary; }
    winrt::hstring TotalFileSize()   const { return m_totalFileSize; }
    winrt::hstring TotalDuration()   const { return m_totalDuration; }

    int32_t Encoder()     const noexcept { return m_encoder; }
    int32_t Quality()     const noexcept { return m_quality; }
    int32_t ContentType() const noexcept { return m_contentType; }
    int32_t BFrames()     const noexcept { return m_bFrames; }
    bool    LongGOP()     const noexcept { return m_longGOP; }

    int32_t CompletedJobCount() const noexcept { return m_completedJobCount; }
    int32_t FailedJobCount()    const noexcept { return m_failedJobCount; }
    bool    AllJobsFinished()   const noexcept { return m_allJobsFinished; }

    winrt::Windows::Foundation::Collections::IObservableVector<winrt::Windows::Foundation::IInspectable>
        FileNames() const { return m_fileNames; }

    std::vector<JobSnapshot> GetJobSnapshots() const { return m_jobSnapshots; }

    void StartProcessing();
    void CancelProcessing();
    void ReturnToConfiguration();
    void AddFiles();
    void RemoveFileAtIndex(int32_t index);
    void RemoveAllFiles();
    void SelectOutputDirectory();
    void AddFilesFromPaths(std::vector<winrt::hstring> const& paths);

    void SetEncoder(int32_t v);
    void SetQuality(int32_t v);
    void SetContentType(int32_t v);
    void SetBFrames(int32_t v);
    void SetLongGOP(bool v);

private:
    void ConnectSignals();
    void RaisePropertyChanged(winrt::hstring const& name);
    void SnapshotViewState();
    void SnapshotConfig();
    void SnapshotFiles();
    void SnapshotOutput();
    void SnapshotJobs();

    QtHost& m_qtHost;
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dq{ nullptr };
    winrt::event<winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler> m_propChanged;
    std::vector<QMetaObject::Connection> m_connections;

    bool           m_isProcessing      = false;
    bool           m_isConfiguring     = true;
    bool           m_canStart          = false;
    winrt::hstring m_outputDirectory;
    winrt::hstring m_batchSummary;
    winrt::hstring m_totalFileSize;
    winrt::hstring m_totalDuration;
    int32_t        m_encoder           = 0;
    int32_t        m_quality           = 68;
    int32_t        m_contentType       = 0;
    int32_t        m_bFrames           = 3;
    bool           m_longGOP           = false;
    int32_t        m_completedJobCount = 0;
    int32_t        m_failedJobCount    = 0;
    bool           m_allJobsFinished   = false;

    winrt::Windows::Foundation::Collections::IObservableVector<winrt::Windows::Foundation::IInspectable>
        m_fileNames = winrt::single_threaded_observable_vector<winrt::Windows::Foundation::IInspectable>();
    std::vector<JobSnapshot> m_jobSnapshots;
};

CompressVMBridge* CurrentCompressBridge() noexcept;
void              SetCurrentCompressBridge(CompressVMBridge* b) noexcept;

} // namespace winrt::Anime4KUpscaler::implementation
