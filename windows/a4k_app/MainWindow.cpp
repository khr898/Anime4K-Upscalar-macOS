#include "pch.h"
#include "MainWindow.h"
#include "MainWindow.g.cpp"

namespace winrt::Anime4KUpscaler::implementation {

MainWindow::MainWindow(QtHost& qtHost) : m_qtHost(qtHost) {
    InitializeComponent();
    SetupBackdrop();
    SetupTitleBar();

    // ConnectBridge() needs the bridge to exist — it's created in App::OnLaunched
    // after Activate() is called. Subscribe one-shot on first Activated event.
    Activated([this, connected = false](
        winrt::Windows::Foundation::IInspectable const&,
        winrt::Microsoft::UI::Xaml::WindowActivatedEventArgs const&) mutable
    {
        if (connected) return;
        connected = true;
        ConnectBridge();
    });
}

void MainWindow::SetupBackdrop() {
    namespace SB = winrt::Microsoft::UI::Composition::SystemBackdrops;
    namespace XM = winrt::Microsoft::UI::Xaml::Media;
    // Mica on Windows 11+; Acrylic on Windows 10
    if (SB::MicaController::IsSupported())
        SystemBackdrop(XM::MicaBackdrop{});
    else
        SystemBackdrop(XM::DesktopAcrylicBackdrop{});
}

void MainWindow::SetupTitleBar() {
    auto titleBar = AppWindow().TitleBar();
    titleBar.ExtendsContentIntoTitleBar(true);
    titleBar.ButtonBackgroundColor(winrt::Windows::UI::Colors::Transparent());
    titleBar.ButtonInactiveBackgroundColor(winrt::Windows::UI::Colors::Transparent());
    // Hover/pressed backgrounds stay default — WinUI derives them from the backdrop tint
    SetTitleBar(AppTitleBar());
}

void MainWindow::ConnectBridge() {
    auto* b = CurrentAppBridge();
    if (!b) return;

    // Snapshot initial dependency state
    UpdateDependencyAlert(b->ShowDependencyAlert(), b->DependencyMessage());

    m_bridgeToken = b->PropertyChanged([this](auto&&, auto&& args) {
        auto name = args.PropertyName();
        if (name == L"ShowDependencyAlert" || name == L"DependencyMessage") {
            if (auto* b2 = CurrentAppBridge())
                UpdateDependencyAlert(b2->ShowDependencyAlert(), b2->DependencyMessage());
        }
    });

    Closed([this, b](auto&&, auto&&) {
        b->PropertyChanged(m_bridgeToken);
        m_bridgeToken = {};
    });
}

void MainWindow::OnDependencyInfoBarClosed(
    winrt::Windows::Foundation::IInspectable const&,
    winrt::Microsoft::UI::Xaml::Controls::InfoBarClosedEventArgs const&) {
    DependencyInfoBar().IsOpen(false);
}

void MainWindow::OnTabSelectionChanged(
    winrt::Windows::Foundation::IInspectable const&,
    winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    // ponytail: no per-tab activation needed
}

void MainWindow::UpdateDependencyAlert(bool show, winrt::hstring const& message) {
    auto weak = get_weak();
    DispatcherQueue().TryEnqueue([weak, show, message]() {
        if (auto self = weak.get()) {
            self->DependencyInfoBar().Message(message);
            self->DependencyInfoBar().IsOpen(show);
        }
    });
}

} // namespace winrt::Anime4KUpscaler::implementation
