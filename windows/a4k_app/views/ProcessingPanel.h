#pragma once
#include "views/ProcessingPanel.g.h"
#include "bridge/AppVMBridge.h"

namespace winrt::Anime4KUpscaler::views::implementation {
struct ProcessingPanel : ProcessingPanelT<ProcessingPanel> {
    ProcessingPanel() { InitializeComponent(); }

    void OnLoaded(winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnUnloaded(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnCancelClicked(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnReturnClicked(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
private:
    void RebuildJobList();
    winrt::Microsoft::UI::Xaml::UIElement MakeJobRow(
        implementation::JobSnapshot const& snap);

    winrt::event_token m_propToken;
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct ProcessingPanel : ProcessingPanelT<ProcessingPanel, implementation::ProcessingPanel> {};
}
