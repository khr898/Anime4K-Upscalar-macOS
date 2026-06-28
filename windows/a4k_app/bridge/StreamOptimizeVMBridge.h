#pragma once
#include <winrt/Microsoft.UI.Xaml.Data.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.Foundation.Collections.h>
#include "QtHost.h"
#include "AppVMBridge.h"
#include <QMetaObject>
#include <vector>

namespace winrt::Anime4KUpscaler::implementation {

struct StreamOptimizeVMBridge : winrt::implements<StreamOptimizeVMBridge,
    winrt::Microsoft::UI::Xaml::Data::INotifyPropertyChanged>
{
    StreamOptimizeVMBridge(QtHost& qtHost, winrt::Microsoft::UI::Dispatching::DispatcherQueue dq);
    ~StreamOptimizeVMBridge();

    winrt::event_token PropertyChanged(
        winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler const& h);
    void PropertyChanged(winrt::event_token const& t) noexcept;

    bool IsProcessing()  const noexcept { return m_isProcessing; }
    bool IsConfiguring() const noexcept { return m_isConfiguring; }
    bool CanStart()      const noexcept { return m_canStart; }

    winrt::hstring SourceDirectory()      const { return m_sourceDirectory; }
    winrt::hstring DestinationDirectory() const { return m_destinationDirectory; }
    winrt::hstring TotalFileSize()        const { return m_totalFileSize; }
    winrt::hstring TotalDuration()        const { return m_totalDuration; }
    winrt::hstring BatchSummary()         const { return m_batchSummary; }

    int32_t Encoder()          const noexcept { return m_encoder; }
    int32_t Quality()          const noexcept { return m_quality; }
    int32_t Profile()          const noexcept { return m_profile; }
    int32_t PixelFormat()      const noexcept { return m_pixelFormat; }
    int32_t AudioMode()        const noexcept { return m_audioMode; }
    int32_t SubtitleMode()     const noexcept { return m_subtitleMode; }
    int32_t KeyframeInterval() const noexcept { return m_keyframeInterval; }
    bool    Faststart()        const noexcept { return m_faststart; }
    bool    AllowSWFallback()  const noexcept { return m_allowSWFallback; }

    int32_t FileCount()         const noexcept { return m_fileCount; }
    int32_t CompletedJobCount() const noexcept { return m_completedJobCount; }
    int32_t FailedJobCount()    const noexcept { return m_failedJobCount; }
    bool    AllJobsFinished()   const noexcept { return m_allJobsFinished; }

    winrt::Windows::Foundation::Collections::IObservableVector<winrt::Windows::Foundation::IInspectable>
        FileNames() const { return m_fileNames; }

    std::vector<JobSnapshot> GetJobSnapshots() const { return m_jobSnapshots; }

    void StartProcessing();
    void CancelProcessing();
    void ReturnToConfiguration();
    void SelectSourceDirectory();
    void SelectDestinationDirectory();

    void SetEncoder(int32_t v);
    void SetQuality(int32_t v);
    void SetProfile(int32_t v);
    void SetPixelFormat(int32_t v);
    void SetAudioMode(int32_t v);
    void SetSubtitleMode(int32_t v);
    void SetKeyframeInterval(int32_t v);
    void SetFaststart(bool v);
    void SetAllowSWFallback(bool v);

private:
    void ConnectSignals();
    void RaisePropertyChanged(winrt::hstring const& name);
    void SnapshotViewState();
    void SnapshotConfig();
    void SnapshotFiles();
    void SnapshotDirectories();
    void SnapshotJobs();

    QtHost& m_qtHost;
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dq{ nullptr };
    winrt::event<winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler> m_propChanged;
    std::vector<QMetaObject::Connection> m_connections;

    bool           m_isProcessing      = false;
    bool           m_isConfiguring     = true;
    bool           m_canStart          = false;
    winrt::hstring m_sourceDirectory;
    winrt::hstring m_destinationDirectory;
    winrt::hstring m_totalFileSize;
    winrt::hstring m_totalDuration;
    winrt::hstring m_batchSummary;
    int32_t        m_encoder           = 0;
    int32_t        m_quality           = 65;
    int32_t        m_profile           = 0;
    int32_t        m_pixelFormat       = 0;
    int32_t        m_audioMode         = 0;
    int32_t        m_subtitleMode      = 0;
    int32_t        m_keyframeInterval  = 1;
    bool           m_faststart         = true;
    bool           m_allowSWFallback   = true;
    int32_t        m_fileCount         = 0;
    int32_t        m_completedJobCount = 0;
    int32_t        m_failedJobCount    = 0;
    bool           m_allJobsFinished   = false;

    winrt::Windows::Foundation::Collections::IObservableVector<winrt::Windows::Foundation::IInspectable>
        m_fileNames = winrt::single_threaded_observable_vector<winrt::Windows::Foundation::IInspectable>();
    std::vector<JobSnapshot> m_jobSnapshots;
};

StreamOptimizeVMBridge* CurrentStreamBridge() noexcept;
void                    SetCurrentStreamBridge(StreamOptimizeVMBridge* b) noexcept;

} // namespace winrt::Anime4KUpscaler::implementation
