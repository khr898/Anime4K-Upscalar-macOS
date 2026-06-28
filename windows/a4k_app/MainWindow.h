#pragma once
#include "MainWindow.g.h"
#include "bridge/QtHost.h"
#include "bridge/AppVMBridge.h"

namespace winrt::Anime4KUpscaler::implementation {

struct MainWindow : MainWindowT<MainWindow> {
    explicit MainWindow(QtHost& qtHost);

    void OnDependencyInfoBarClosed(
        winrt::Windows::Foundation::IInspectable const&,
        winrt::Microsoft::UI::Xaml::Controls::InfoBarClosedEventArgs const&);

    void OnTabSelectionChanged(
        winrt::Windows::Foundation::IInspectable const&,
        winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);

    void UpdateDependencyAlert(bool show, winrt::hstring const& message);

private:
    void SetupBackdrop();
    void SetupTitleBar();
    void ConnectBridge();

    QtHost& m_qtHost;
    winrt::event_token m_bridgeToken;
};

}

namespace winrt::Anime4KUpscaler::factory_implementation {
struct MainWindow : MainWindowT<MainWindow, implementation::MainWindow> {};
}
