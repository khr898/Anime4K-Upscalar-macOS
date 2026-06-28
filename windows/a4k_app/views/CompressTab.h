#pragma once
#include "views/CompressTab.g.h"
#include "bridge/CompressVMBridge.h"

namespace winrt::Anime4KUpscaler::views::implementation {

struct CompressTab : CompressTabT<CompressTab> {
    CompressTab() { InitializeComponent(); }

    void OnLoaded(winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnUnloaded(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

    void OnDragOver(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::DragEventArgs const&);
    void OnDrop(winrt::Windows::Foundation::IInspectable const&,
                winrt::Microsoft::UI::Xaml::DragEventArgs const&);

    void OnAddClicked(winrt::Windows::Foundation::IInspectable const&,
                      winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnRemoveClicked(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnClearClicked(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnSelectionChanged(winrt::Windows::Foundation::IInspectable const&,
                            winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);

    void OnEncoderChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void OnQualityChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const&);
    void OnContentTypeChecked(winrt::Windows::Foundation::IInspectable const&,
                              winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnBFramesChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const&);
    void OnLongGOPChanged(winrt::Windows::Foundation::IInspectable const&,
                          winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnBrowseOutput(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

    void OnStartClicked(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnCancelClicked(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnReturnClicked(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    void UpdatePanelVisibility();
    void SyncFromBridge();
    void RebuildJobList();
    void UpdateButtonState();
    winrt::Microsoft::UI::Xaml::UIElement MakeJobRow(
        winrt::Anime4KUpscaler::implementation::JobSnapshot const& snap);

    bool m_suppress = false;
    winrt::event_token m_propToken;
};

} // namespace winrt::Anime4KUpscaler::views::implementation

namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct CompressTab : CompressTabT<CompressTab, implementation::CompressTab> {};
}
