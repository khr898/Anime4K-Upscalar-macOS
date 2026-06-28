#include "pch.h"
#include "bridge/CompressVMBridge.h"
#include "../src/viewmodels/CompressViewModel.h"
#include "../src/models/CompressModels.h"

namespace {

inline winrt::hstring toH(const QString& s) {
    return winrt::hstring{ reinterpret_cast<const wchar_t*>(s.utf16()),
                           static_cast<uint32_t>(s.size()) };
}

inline winrt::Windows::Foundation::IInspectable boxStr(const QString& s) {
    return winrt::box_value(toH(s));
}

static winrt::Anime4KUpscaler::implementation::CompressVMBridge* g_compressBridge = nullptr;

} // anonymous namespace

namespace winrt::Anime4KUpscaler::implementation {

CompressVMBridge* CurrentCompressBridge() noexcept  { return g_compressBridge; }
void SetCurrentCompressBridge(CompressVMBridge* b) noexcept { g_compressBridge = b; }

CompressVMBridge::CompressVMBridge(QtHost& qtHost,
                                   winrt::Microsoft::UI::Dispatching::DispatcherQueue dq)
    : m_qtHost(qtHost), m_dq(std::move(dq))
{
    m_qtHost.runOnQtThread([this] {
        SnapshotViewState();
        SnapshotConfig();
        SnapshotFiles();
        SnapshotOutput();
        ConnectSignals();
    });
}

CompressVMBridge::~CompressVMBridge() {
    if (g_compressBridge == this) g_compressBridge = nullptr;
    auto conns = std::move(m_connections);
    m_qtHost.postToQtThread([conns = std::move(conns)]() mutable {
        for (auto& c : conns) QObject::disconnect(c);
    });
}

winrt::event_token CompressVMBridge::PropertyChanged(
    winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventHandler const& h) {
    return m_propChanged.add(h);
}
void CompressVMBridge::PropertyChanged(winrt::event_token const& t) noexcept {
    m_propChanged.remove(t);
}

void CompressVMBridge::RaisePropertyChanged(winrt::hstring const& name) {
    m_propChanged(*this, winrt::Microsoft::UI::Xaml::Data::PropertyChangedEventArgs{ name });
}

// ---- Snapshots (called on Qt thread) ----

void CompressVMBridge::SnapshotViewState() {
    auto* vm   = m_qtHost.compressViewModel();
    bool  isCfg = vm->viewState() == CompressViewModel::ViewState::Configuration;
    bool  can   = vm->canStartProcessing();
    int   done  = vm->completedJobCount();
    int   fail  = vm->failedJobCount();
    bool  alld  = vm->allJobsFinished();
    auto  summ  = vm->batchSummary();
    auto  size  = vm->totalFileSize();
    auto  dur   = vm->totalDuration();

    auto self = get_strong();
    m_dq.TryEnqueue([self, isCfg, can, done, fail, alld, summ, size, dur]() {
        bool changed = (self->m_isConfiguring != isCfg) || (self->m_canStart != can);
        self->m_isConfiguring     = isCfg;
        self->m_isProcessing      = !isCfg;
        self->m_canStart          = can;
        self->m_completedJobCount = done;
        self->m_failedJobCount    = fail;
        self->m_allJobsFinished   = alld;
        self->m_batchSummary      = toH(summ);
        self->m_totalFileSize     = toH(size);
        self->m_totalDuration     = toH(dur);
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
    SnapshotJobs();
}

void CompressVMBridge::SnapshotConfig() {
    auto* vm  = m_qtHost.compressViewModel();
    int enc   = static_cast<int>(vm->encoder());
    int qual  = vm->quality();
    int ct    = static_cast<int>(vm->contentType());
    int bf    = vm->bFrames();
    bool lgop = vm->longGOPEnabled();

    auto self = get_strong();
    m_dq.TryEnqueue([self, enc, qual, ct, bf, lgop]() {
        self->m_encoder     = enc;
        self->m_quality     = qual;
        self->m_contentType = ct;
        self->m_bFrames     = bf;
        self->m_longGOP     = lgop;
        self->RaisePropertyChanged(L"Encoder");
        self->RaisePropertyChanged(L"Quality");
        self->RaisePropertyChanged(L"ContentType");
        self->RaisePropertyChanged(L"BFrames");
        self->RaisePropertyChanged(L"LongGOP");
    });
}

void CompressVMBridge::SnapshotFiles() {
    auto* vm = m_qtHost.compressViewModel();
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

void CompressVMBridge::SnapshotOutput() {
    auto dir  = m_qtHost.compressViewModel()->outputDirectory();
    auto self = get_strong();
    m_dq.TryEnqueue([self, dir]() {
        self->m_outputDirectory = toH(dir);
        self->RaisePropertyChanged(L"OutputDirectory");
    });
}

void CompressVMBridge::SnapshotJobs() {
    auto* vm = m_qtHost.compressViewModel();
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

void CompressVMBridge::ConnectSignals() {
    auto* vm = m_qtHost.compressViewModel();
    auto  weak = get_weak();
    m_connections = {
        QObject::connect(vm, &CompressViewModel::viewStateChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotViewState(); }),
        QObject::connect(vm, &CompressViewModel::filesChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotFiles(); }),
        QObject::connect(vm, &CompressViewModel::configurationChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotConfig(); }),
        QObject::connect(vm, &CompressViewModel::outputDirectoryChanged,
            [weak]{ if (auto b = weak.get()) b->SnapshotOutput(); }),
        QObject::connect(vm, &CompressViewModel::jobProgressUpdated,
            [weak](CompressJob*){ if (auto b = weak.get()) b->SnapshotJobs(); }),
    };
}

// ---- Commands ----

void CompressVMBridge::StartProcessing()      { m_qtHost.postToQtThread([this]{ m_qtHost.compressViewModel()->startProcessing(); }); }
void CompressVMBridge::CancelProcessing()     { m_qtHost.postToQtThread([this]{ m_qtHost.compressViewModel()->cancelProcessing(); }); }
void CompressVMBridge::ReturnToConfiguration(){ m_qtHost.postToQtThread([this]{ m_qtHost.compressViewModel()->returnToConfiguration(); }); }
void CompressVMBridge::AddFiles()         { m_qtHost.postToQtThread([this]{ m_qtHost.compressViewModel()->addFiles(); }); }
void CompressVMBridge::RemoveAllFiles()   { m_qtHost.postToQtThread([this]{ m_qtHost.compressViewModel()->removeAllFiles(); }); }
void CompressVMBridge::RemoveFileAtIndex(int32_t index) {
    m_qtHost.postToQtThread([this, index]{
        auto* vm = m_qtHost.compressViewModel();
        const auto& files = vm->files();
        if (index >= 0 && index < static_cast<int32_t>(files.size()))
            vm->removeFile(files[index].id);
    });
}
void CompressVMBridge::SelectOutputDirectory(){ m_qtHost.postToQtThread([this]{ m_qtHost.compressViewModel()->selectOutputDirectory(); }); }

void CompressVMBridge::AddFilesFromPaths(std::vector<winrt::hstring> const& paths) {
    QStringList qpaths;
    for (auto const& p : paths) qpaths << QString::fromWCharArray(p.c_str());
    m_qtHost.postToQtThread([this, qpaths = std::move(qpaths)]{
        m_qtHost.compressViewModel()->addFilesFromDrop(qpaths);
    });
}

// ---- Config setters ----

void CompressVMBridge::SetEncoder(int32_t v) {
    m_qtHost.postToQtThread([this, v]{
        m_qtHost.compressViewModel()->setEncoder(static_cast<CompressEncoder>(v));
    });
}
void CompressVMBridge::SetQuality(int32_t v) {
    m_qtHost.postToQtThread([this, v]{
        m_qtHost.compressViewModel()->updateQuality(v);
    });
}
void CompressVMBridge::SetContentType(int32_t v) {
    m_qtHost.postToQtThread([this, v]{
        m_qtHost.compressViewModel()->setContentType(static_cast<ContentType>(v));
    });
}
void CompressVMBridge::SetBFrames(int32_t v) {
    m_qtHost.postToQtThread([this, v]{
        m_qtHost.compressViewModel()->setBFrames(v);
    });
}
void CompressVMBridge::SetLongGOP(bool v) {
    m_qtHost.postToQtThread([this, v]{
        m_qtHost.compressViewModel()->setLongGOPEnabled(v);
    });
}

} // namespace winrt::Anime4KUpscaler::implementation
