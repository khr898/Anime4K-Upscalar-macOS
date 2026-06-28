#include "pch.h"
#include "App.h"
#include "MainWindow.h"

#include <MddBootstrap.h>

namespace winrt::Anime4KUpscaler::implementation {

App::App() {
    HRESULT hr = MddBootstrapInitialize(
        WINDOWSAPPSDK_RELEASE_MAJORMINOR,
        WINDOWSAPPSDK_RELEASE_VERSION_TAG_W,
        WINDOWSAPPSDK_RUNTIME_VERSION_UINT64);
    winrt::check_hresult(hr);

    m_qtHost = std::make_unique<QtHost>();
    m_qtHost->start();

#if defined _DEBUG && !defined DISABLE_XAML_GENERATED_BREAK_ON_UNHANDLED_EXCEPTION
    UnhandledException([](IInspectable const&,
                          winrt::Microsoft::UI::Xaml::UnhandledExceptionEventArgs const& e) {
        if (IsDebuggerPresent()) DebugBreak();
        e.Handled(true);
    });
#endif
}

void App::OnLaunched(winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs const&) {
    m_window = make<MainWindow>(*m_qtHost);

    // Create bridges BEFORE Activate() so the MainWindow::Activated handler
    // finds them ready via CurrentXxxBridge() globals.
    auto dq = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();
    m_bridge = winrt::make_self<AppVMBridge>(*m_qtHost, dq);
    SetCurrentAppBridge(m_bridge.get());
    m_compressBridge = winrt::make_self<CompressVMBridge>(*m_qtHost, dq);
    SetCurrentCompressBridge(m_compressBridge.get());
    m_streamBridge = winrt::make_self<StreamOptimizeVMBridge>(*m_qtHost, dq);
    SetCurrentStreamBridge(m_streamBridge.get());

    m_window.Activate();

    m_pickerService = std::make_unique<WinUiPickerService>(m_window, m_qtHost.get());
    m_qtHost->runOnQtThread([this] {
        m_qtHost->appViewModel()->setPickerService(m_pickerService.get());
        m_qtHost->compressViewModel()->setPickerService(m_pickerService.get());
        m_qtHost->streamOptimizeViewModel()->setPickerService(m_pickerService.get());
    });
}

} // namespace
