#pragma once
#include "views/ConfigurationPanel.g.h"
#include "bridge/AppVMBridge.h"

namespace winrt::Anime4KUpscaler::views::implementation {
struct ConfigurationPanel : ConfigurationPanelT<ConfigurationPanel> {
    ConfigurationPanel() { InitializeComponent(); }

    void OnLoaded(winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnUnloaded(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnResolutionChecked(winrt::Windows::Foundation::IInspectable const& sender,
                             winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnCodecChanged(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void OnPresetChanged(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void OnQualityChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const&);
    void OnBitrateChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const&);
    void OnSvtChanged(winrt::Windows::Foundation::IInspectable const&,
                      winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const&);
    void OnLongGOPChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnBrowseOutput(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
private:
    void SyncFromBridge();
    void UpdatePresetVisibility(int32_t preset, int32_t codec);

    bool               m_suppress = false;
    winrt::event_token m_propToken;
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct ConfigurationPanel : ConfigurationPanelT<ConfigurationPanel, implementation::ConfigurationPanel> {};
}
