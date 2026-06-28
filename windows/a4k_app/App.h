#pragma once
#include "App.g.h"
#include "bridge/QtHost.h"
#include "bridge/AppVMBridge.h"
#include "bridge/CompressVMBridge.h"
#include "bridge/StreamOptimizeVMBridge.h"
#include "services/WinUiPickerService.h"
#include <memory>

namespace winrt::Anime4KUpscaler::implementation {

struct App : AppT<App> {
    App();

    void OnLaunched(winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs const&);

    QtHost& qtHost() { return *m_qtHost; }

private:
    std::unique_ptr<QtHost>              m_qtHost;
    std::unique_ptr<WinUiPickerService>  m_pickerService;
    winrt::Microsoft::UI::Xaml::Window   m_window{ nullptr };
    winrt::com_ptr<AppVMBridge>             m_bridge;
    winrt::com_ptr<CompressVMBridge>        m_compressBridge;
    winrt::com_ptr<StreamOptimizeVMBridge>  m_streamBridge;
};

} // namespace

namespace winrt::Anime4KUpscaler::factory_implementation {
struct App : AppT<App, implementation::App> {};
}
