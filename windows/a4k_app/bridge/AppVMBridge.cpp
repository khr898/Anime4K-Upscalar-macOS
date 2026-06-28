#include "pch.h"
#include "bridge/AppVMBridge.h"
#include "../src/viewmodels/AppViewModel.h"
#include "../src/models/Models.h"
#include "../src/viewmodels/ProcessingEngine.h"

namespace {

inline winrt::hstring toH(const QString& s) {
    return winrt::hstring{ reinterpret_cast<const wchar_t*>(s.utf16()),
                           static_cast<uint32_t>(s.size()) };
}

inline winrt::Windows::Foundation::IInspectable boxStr(const QString& s) {
    return winrt::box_value(toH(s));
}

static winrt::Anime4KUpscaler::implementation::AppVMBridge* g_currentBridge = nullptr;

} // anonymous namespace

namespace winrt::Anime4KUpscaler::implementation {

AppVMBridge* CurrentAppBridge() noexcept  { return g_currentBridge; }
void SetCurrentAppBridge(AppVMBridge* b) noexcept { g_currentBridge = b; }

// ---- Constructor / Destructor ----

AppVMBridge::AppVMBridge(QtHost& qtHost,
                         winrt::Microsoft::UI::Dispatching::DispatcherQueue dq)
    : m_qtHost(qtHost), m_dq(std::move(dq))
{
    m_qtHost.runOnQtThread([this] {
        SnapshotViewState();
        SnapshotConfig();
        SnapshotFiles();
        SnapshotOutput();
        SnapshotDependencies();
        ConnectSignals();
    });
}

AppVMBridge::~AppVMBridge() {
    if (g_currentBridge == this) g_currentBridge = nullptr;
    // ponytail: async disconnect avoids blocking destructor on Qt thread
    auto conns = std::move(m_connections);
    m_qtHost.postToQtThread([conns = std::move(conns)]() mutable {
        for (auto& c : conns) QObject::disconnect(c);
    });
}

// ---- INotifyPropertyChanged ----

winrt::event_token AppVMBridge::PropertyChanged(
    winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler const& h) {
    return m_propChanged.add(h);
}
void AppVMBridge::PropertyChanged(winrt::event_token const& t) noexcept {
    m_propChanged.remove(t);
}

void AppVMBridge::RaisePropertyChanged(winrt::hstring const& name) {
    m_propChanged(*this, winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventArgs{ name });
}

// ---- Snapshot helpers (called on Qt thread; marshal to WinUI) ----

void AppVMBridge::SnapshotViewState() {
    auto* vm = m_qtHost.appViewModel();
    bool isCfg    = vm->viewState() == AppViewModel::ViewState::Configuration;
    bool canStart = vm->canStartProcessing();
    int  done     = vm->completedJobCount();
    int  failed   = vm->failedJobCount();
    bool allDone  = vm->allJobsFinished();
    auto summary  = vm->batchSummary();
    auto size     = vm->totalFileSize();
    auto dur      = vm->totalDuration();

    auto self = get_strong();
    m_dq.TryEnqueue([self, isCfg, canStart, done, failed, allDone, summary, size, dur]() {
        bool changed = (self->m_isConfiguring != isCfg) || (self->m_canStart != canStart);
        self->m_isConfiguring    = isCfg;
        self->m_isProcessing     = !isCfg;
        self->m_canStart         = canStart;
        self->m_completedJobCount = done;
        self->m_failedJobCount   = failed;
        self->m_allJobsFinished  = allDone;
        self->m_batchSummary     = toH(summary);
        self->m_totalFileSize    = toH(size);
        self->m_totalDuration    = toH(dur);
        if (changed) {
            self->RaisePropertyChanged(L"IsConfiguring");
            self->RaisePropertyChanged(L"IsProcessing");
            self->RaisePropertyChanged(L"CanStart");
        }
        self->RaisePropertyChanged(L"BatchSummary");
        self->RaisePropertyChanged(L"CompletedJobCount");
        self->RaisePropertyChanged(L"FailedJobCount");
        self->RaisePropertyChanged(L"AllJobsFinished");
    });

    // Also snapshot jobs when view state changes
    SnapshotJobs();
}

void AppVMBridge::SnapshotConfig() {
    auto* vm = m_qtHost.appViewModel();
    const auto& cfg = vm->configuration();
    int codec  = static_cast<int>(cfg.codec);
    int preset = static_cast<int>(vm->compressionPreset());
    int res    = static_cast<int>(cfg.resolution);
    int qual   = vm->customQualityValue();
    int brate  = vm->customBitrateValue();
    bool lgop  = cfg.longGOPEnabled;
    int svt    = cfg.svtAV1Preset;
    int mode   = static_cast<int>(cfg.mode);

    auto self = get_strong();
    m_dq.TryEnqueue([self, codec, preset, res, qual, brate, lgop, svt, mode]() {
        self->m_codec        = codec;
        self->m_preset       = preset;
        self->m_resolution   = res;
        self->m_qualityValue = qual;
        self->m_bitrateValue = brate;
        self->m_longGOP      = lgop;
        self->m_svtPreset    = svt;
        self->m_selectedMode = mode;
        self->RaisePropertyChanged(L"Codec");
        self->RaisePropertyChanged(L"Preset");
        self->RaisePropertyChanged(L"Resolution");
        self->RaisePropertyChanged(L"QualityValue");
        self->RaisePropertyChanged(L"BitrateValue");
        self->RaisePropertyChanged(L"LongGOP");
        self->RaisePropertyChanged(L"SvtPreset");
        self->RaisePropertyChanged(L"SelectedMode");
    });
}

void AppVMBridge::SnapshotFiles() {
    auto* vm = m_qtHost.appViewModel();
    std::vector<QString> names;
    for (const auto& f : vm->files()) names.push_back(f.fileName);

    auto self = get_strong();
    m_dq.TryEnqueue([self, names = std::move(names)]() {
        self->m_fileNames.Clear();
        for (const auto& n : names)
            self->m_fileNames.Append(boxStr(n));
        self->RaisePropertyChanged(L"FileNames");
    });
}

void AppVMBridge::SnapshotOutput() {
    auto dir = m_qtHost.appViewModel()->outputDirectory();
    auto self = get_strong();
    m_dq.TryEnqueue([self, dir]() {
        self->m_outputDirectory = toH(dir);
        self->RaisePropertyChanged(L"OutputDirectory");
    });
}

void AppVMBridge::SnapshotDependencies() {
    auto* vm  = m_qtHost.appViewModel();
    bool show = vm->showDependencyAlert();
    auto msg  = vm->dependencyErrors().join(QStringLiteral("\n"));
    auto self = get_strong();
    m_dq.TryEnqueue([self, show, msg]() {
        self->m_showDependencyAlert = show;
        self->m_dependencyMessage   = toH(msg);
        self->RaisePropertyChanged(L"ShowDependencyAlert");
        self->RaisePropertyChanged(L"DependencyMessage");
    });
}

void AppVMBridge::SnapshotJobs() {
    auto* vm = m_qtHost.appViewModel();
    std::vector<JobSnapshot> snaps;
    for (const auto* job : vm->jobs()) {
        JobSnapshot s;
        s.fileName = toH(job->file.fileName);
        s.progress = job->progress;
        switch (job->state) {
        case JobState::Idle:       s.status = L"Waiting";    break;
        case JobState::Running:    s.status = L"Processing"; break;
        case JobState::Completed:  s.status = L"Done";       break;
        case JobState::Failed:     s.status = L"Failed"; s.failed = true; break;
        case JobState::Cancelled:  s.status = L"Cancelled";  break;
        default:                   s.status = L"";
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

// ---- Signal connections (called on Qt thread) ----

void AppVMBridge::ConnectSignals() {
    auto* vm = m_qtHost.appViewModel();
    auto  weak = get_weak();
    m_connections = {
        QObject::connect(vm, &AppViewModel::viewStateChanged,     [weak]{ if (auto b = weak.get()) b->SnapshotViewState(); }),
        QObject::connect(vm, &AppViewModel::filesChanged,         [weak]{ if (auto b = weak.get()) b->SnapshotFiles(); }),
        QObject::connect(vm, &AppViewModel::configurationChanged, [weak]{ if (auto b = weak.get()) b->SnapshotConfig(); }),
        QObject::connect(vm, &AppViewModel::outputDirectoryChanged,[weak]{ if (auto b = weak.get()) b->SnapshotOutput(); }),
        QObject::connect(vm, &AppViewModel::dependencyAlertChanged,[weak]{ if (auto b = weak.get()) b->SnapshotDependencies(); }),
        QObject::connect(vm->engine(), &ProcessingEngine::jobProgressUpdated, [weak](ProcessingJob*){ if (auto b = weak.get()) b->SnapshotJobs(); }),
    };
}

// ---- Commands ----

void AppVMBridge::StartProcessing()      { auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->startProcessing(); }); }
void AppVMBridge::CancelProcessing()     { auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->cancelProcessing(); }); }
void AppVMBridge::ReturnToConfiguration(){ auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->returnToConfiguration(); }); }
void AppVMBridge::AddFiles()             { auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->addFiles(); }); }
void AppVMBridge::RemoveSelectedFile()   { auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->removeSelectedFile(); }); }
void AppVMBridge::RemoveAllFiles()       { auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->removeAllFiles(); }); }
void AppVMBridge::SelectOutputDirectory(){ auto* vm = m_qtHost.appViewModel(); m_qtHost.postToQtThread([vm]{ vm->selectOutputDirectory(); }); }
void AppVMBridge::AddFilesFromPaths(std::vector<winrt::hstring> const& paths) {
    QStringList qpaths;
    for (auto const& p : paths) qpaths << QString::fromWCharArray(p.c_str());
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, qpaths = std::move(qpaths)]{
        vm->addFilesFromDrop(qpaths);
    });
}

// ---- Config setters ----

void AppVMBridge::SetCodec(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{
        vm->configurationRef().codec = static_cast<VideoCodec>(v);
        vm->onCodecChanged();
    });
}
void AppVMBridge::SetPreset(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{
        vm->setCompressionPreset(static_cast<CompressionPreset>(v));
    });
}
void AppVMBridge::SetResolution(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{
        vm->configurationRef().resolution = static_cast<TargetResolution>(v);
        vm->configurationChanged();
    });
}
void AppVMBridge::SetQualityValue(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{ vm->updateCustomQuality(v); });
}
void AppVMBridge::SetBitrateValue(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{ vm->updateCustomBitrate(v); });
}
void AppVMBridge::SetLongGOP(bool v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{
        vm->configurationRef().longGOPEnabled = v;
        vm->configurationChanged();
    });
}
void AppVMBridge::SetSvtPreset(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{
        vm->configurationRef().svtAV1Preset = v;
        vm->configurationChanged();
    });
}
void AppVMBridge::SetSelectedMode(int32_t v) {
    auto* vm = m_qtHost.appViewModel();
    m_qtHost.postToQtThread([vm, v]{
        vm->configurationRef().mode = static_cast<Anime4KMode>(v);
        vm->configurationChanged();
    });
}

} // namespace winrt::Anime4KUpscaler::implementation
