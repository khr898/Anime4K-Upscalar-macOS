#pragma once
#include "views/UpscaleTab.g.h"
#include "bridge/AppVMBridge.h"

namespace winrt::Anime4KUpscaler::views::implementation {
struct UpscaleTab : UpscaleTabT<UpscaleTab> {
    UpscaleTab() { InitializeComponent(); }

    void OnLoaded(winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnUnloaded(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnStartClicked(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
private:
    void UpdatePanelVisibility();

    winrt::event_token m_propToken;
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct UpscaleTab : UpscaleTabT<UpscaleTab, implementation::UpscaleTab> {};
}
