#include "pch.h"
#include "bridge/StreamOptimizeVMBridge.h"
#include "../src/viewmodels/StreamOptimizeViewModel.h"
#include "../src/models/StreamOptimizeModels.h"

namespace {

inline winrt::hstring toH(const QString& s) {
    return winrt::hstring{ reinterpret_cast<const wchar_t*>(s.utf16()),
                           static_cast<uint32_t>(s.size()) };
}

inline winrt::Windows::Foundation::IInspectable boxStr(const QString& s) {
    return winrt::box_value(toH(s));
}

static winrt::Anime4KUpscaler::implementation::StreamOptimizeVMBridge* g_streamBridge = nullptr;

} // anonymous namespace

namespace winrt::Anime4KUpscaler::implementation {

StreamOptimizeVMBridge* CurrentStreamBridge() noexcept  { return g_streamBridge; }
void SetCurrentStreamBridge(StreamOptimizeVMBridge* b) noexcept { g_streamBridge = b; }

StreamOptimizeVMBridge::StreamOptimizeVMBridge(QtHost& qtHost,
                                               winrt::Microsoft::UI::Dispatching::DispatcherQueue dq)
    : m_qtHost(qtHost), m_dq(std::move(dq))
{
    m_qtHost.runOnQtThread([this] {
        SnapshotViewState();
        SnapshotConfig();
        SnapshotFiles();
        SnapshotDirectories();
        ConnectSignals();
    });
}

StreamOptimizeVMBridge::~StreamOptimizeVMBridge() {
    if (g_streamBridge == this) g_streamBridge = nullptr;
    auto conns = std::move(m_connections);
    m_qtHost.postToQtThread([conns = std::move(conns)]() mutable {
        for (auto& c : conns) QObject::disconnect(c);
    });
}

winrt::event_token StreamOptimizeVMBridge::PropertyChanged(
    winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler const& h) {
    return m_propChanged.add(h);
}
void StreamOptimizeVMBridge::PropertyChanged(winrt::event_token const& t) noexcept {
    m_propChanged.remove(t);
}

void StreamOptimizeVMBridge::RaisePropertyChanged(winrt::hstring const& name) {
    m_propChanged(*this, winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventArgs{ name });
}

// ---- Snapshots ----

void StreamOptimizeVMBridge::SnapshotViewState() {
    auto* vm   = m_qtHost.streamOptimizeViewModel();
    bool  isCfg = vm->viewState() == StreamOptimizeViewModel::ViewState::Configuration;
    bool  can   = vm->canStartProcessing();
    int   done  = vm->completedJobCount();
    int   fail  = vm->failedJobCount();
    bool  alld  = vm->allJobsFinished();
    auto  size  = vm->totalFileSize();
    auto  dur   = vm->totalDuration();
    int   total = vm->totalJobs();
    int   cur   = vm->currentJobIndex();

    auto self = get_strong();
    m_dq.TryEnqueue([self, isCfg, can, done, fail, alld, size, dur, total, cur]() {
        bool changed = (self->m_isConfiguring != isCfg) || (self->m_canStart != can);
        self->m_isConfiguring     = isCfg;
        self->m_isProcessing      = !isCfg;
        self->m_canStart          = can;
        self->m_completedJobCount = done;
        self->m_failedJobCount    = fail;
        self->m_allJobsFinished   = alld;
        self->m_totalFileSize     = toH(size);
        self->m_totalDuration     = toH(dur);
        // Build batch summary from job counts
        if (total > 0) {
            self->m_batchSummary = winrt::hstring{
                std::to_wstring(done) + L"/" + std::to_wstring(total) + L" files"
            };
        } else {
            self->m_batchSummary = L"";
        }
        if (changed) {
            self->RaisePropertyChanged(L"IsConfiguring");
            self->RaisePropertyChanged(L"IsProcessing");
            self->RaisePropertyChanged(L"CanStart");
        }
        self->RaisePropertyChanged(L"BatchSummary");
        self->RaisePropertyChanged(L"TotalFileSize");
        self->RaisePropertyChanged(L"TotalDuration");
        self->RaisePropertyChanged(L"CompletedJobCount");
        self->RaisePropertyChanged(L"FailedJobCount");
        self->RaisePropertyChanged(L"AllJobsFinished");
    });
    SnapshotJobs();
}

void StreamOptimizeVMBridge::SnapshotConfig() {
    auto* vm = m_qtHost.streamOptimizeViewModel();
    int enc  = static_cast<int>(vm->encoder());
    int qual = vm->quality();
    int prof = static_cast<int>(vm->profile());
    int pxfm = static_cast<int>(vm->pixelFormat());
    int amod = static_cast<int>(vm->audioMode());
    int smod = static_cast<int>(vm->subtitleMode());
    int kfi  = static_cast<int>(vm->keyframeInterval());
    bool fs  = vm->faststart();
    bool sw  = vm->allowSWFallback();

    auto self = get_strong();
    m_dq.TryEnqueue([self, enc, qual, prof, pxfm, amod, smod, kfi, fs, sw]() {
        self->m_encoder          = enc;
        self->m_quality          = qual;
        self->m_profile          = prof;
        self->m_pixelFormat      = pxfm;
        self->m_audioMode        = amod;
        self->m_subtitleMode     = smod;
        self->m_keyframeInterval = kfi;
        self->m_faststart        = fs;
        self->m_allowSWFallback  = sw;
        self->RaisePropertyChanged(L"Encoder");
        self->RaisePropertyChanged(L"Quality");
        self->RaisePropertyChanged(L"Profile");
        self->RaisePropertyChanged(L"PixelFormat");
        self->RaisePropertyChanged(L"AudioMode");
        self->RaisePropertyChanged(L"SubtitleMode");
        self->RaisePropertyChanged(L"KeyframeInterval");
        self->RaisePropertyChanged(L"Faststart");
        self->RaisePropertyChanged(L"AllowSWFallback");
    });
}

void StreamOptimizeVMBridge::SnapshotFiles() {
    auto* vm = m_qtHost.streamOptimizeViewModel();
    std::vector<QString> names;
    for (const auto& f : vm->files()) names.push_back(f.fileName);
    int cnt = static_cast<int>(names.size());

    auto self = get_strong();
    m_dq.TryEnqueue([self, names = std::move(names), cnt]() {
        self->m_fileNames.Clear();
        for (const auto& n : names)
            self->m_fileNames.Append(boxStr(n));
        self->m_fileCount = cnt;
        self->RaisePropertyChanged(L"FileNames");
        self->RaisePropertyChanged(L"FileCount");
    });
}

void StreamOptimizeVMBridge::SnapshotDirectories() {
    auto* vm = m_qtHost.streamOptimizeViewModel();
    auto  src  = vm->sourceDisplayName();
    auto  dest = vm->destinationDisplayName();

    auto self = get_strong();
    m_dq.TryEnqueue([self, src, dest]() {
        self->m_sourceDirectory      = toH(src);
        self->m_destinationDirectory = toH(dest);
        self->RaisePropertyChanged(L"SourceDirectory");
        self->RaisePropertyChanged(L"DestinationDirectory");
    });
}

void StreamOptimizeVMBridge::SnapshotJobs() {
    auto* vm = m_qtHost.streamOptimizeViewModel();
    std::vector<JobSnapshot> snaps;
    for (const auto* job : vm->jobs()) {
        JobSnapshot s;
        s.fileName = toH(job->file.fileName);
        s.progress = job->progress;
        switch (job->state) {
        case JobState::Idle:      s.status = L"Waiting";    break;
        case JobState::Running:   s.status = L"Processing"; break;
        case JobState::Completed: s.status = L"Done";       break;
        case JobState::Failed:    s.status = L"Failed"; s.failed = true; break;
        case JobState::Cancelled: s.status = L"Cancelled";  break;
        default:                  s.status = L"";
        }
        s.details = toH(job->currentTime + QStringLiteral(" | ") + job->fps + QStringLiteral(" fps"));
        snaps.push_back(std::move(s));
    }
    auto self = get_strong();
    m_dq.TryEnqueue([self, snaps = std::move(snaps)]() {
        self->m_jobSnapshots = snaps;
        self->RaisePropertyChanged(L"Jobs");
    });
}

// ---- Signal connections ----

void StreamOptimizeVMBridge::ConnectSignals() {
    auto* vm = m_qtHost.streamOptimizeViewModel();
    auto  weak = get_weak();
    m_connections = {
        QObject::connect(vm, &StreamOptimizeViewModel::viewStateChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotViewState(); }),
        QObject::connect(vm, &StreamOptimizeViewModel::filesChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotFiles(); }),
        QObject::connect(vm, &StreamOptimizeViewModel::configurationChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotConfig(); }),
        QObject::connect(vm, &StreamOptimizeViewModel::directoriesChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotDirectories(); }),
        QObject::connect(vm, &StreamOptimizeViewModel::jobProgressUpdated,
            [weak](StreamOptimizeJob*){ if (auto b = weak.get()) b->SnapshotJobs(); }),
    };
}

// ---- Commands ----

void StreamOptimizeVMBridge::StartProcessing()       { m_qtHost.postToQtThread([this]{ m_qtHost.streamOptimizeViewModel()->startProcessing(); }); }
void StreamOptimizeVMBridge::CancelProcessing()      { m_qtHost.postToQtThread([this]{ m_qtHost.streamOptimizeViewModel()->cancelProcessing(); }); }
void StreamOptimizeVMBridge::ReturnToConfiguration() { m_qtHost.postToQtThread([this]{ m_qtHost.streamOptimizeViewModel()->returnToConfiguration(); }); }
void StreamOptimizeVMBridge::SelectSourceDirectory() { m_qtHost.postToQtThread([this]{ m_qtHost.streamOptimizeViewModel()->selectSourceDirectory(); }); }
void StreamOptimizeVMBridge::SelectDestinationDirectory() { m_qtHost.postToQtThread([this]{ m_qtHost.streamOptimizeViewModel()->selectDestinationDirectory(); }); }

// ---- Config setters ----

void StreamOptimizeVMBridge::SetEncoder(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setEncoder(static_cast<StreamEncoder>(v)); });
}
void StreamOptimizeVMBridge::SetQuality(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setQuality(v); });
}
void StreamOptimizeVMBridge::SetProfile(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setProfile(static_cast<StreamProfile>(v)); });
}
void StreamOptimizeVMBridge::SetPixelFormat(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setPixelFormat(static_cast<StreamPixelFormat>(v)); });
}
void StreamOptimizeVMBridge::SetAudioMode(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setAudioMode(static_cast<StreamAudioMode>(v)); });
}
void StreamOptimizeVMBridge::SetSubtitleMode(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setSubtitleMode(static_cast<StreamSubtitleMode>(v)); });
}
void StreamOptimizeVMBridge::SetKeyframeInterval(int32_t v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setKeyframeInterval(static_cast<KeyframeInterval>(v)); });
}
void StreamOptimizeVMBridge::SetFaststart(bool v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setFaststart(v); });
}
void StreamOptimizeVMBridge::SetAllowSWFallback(bool v) {
    m_qtHost.postToQtThread([this, v]{ m_qtHost.streamOptimizeViewModel()->setAllowSWFallback(v); });
}

} // namespace winrt::Anime4KUpscaler::implementation
