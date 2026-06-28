#pragma once
#include "views/FileListPanel.g.h"
#include "bridge/AppVMBridge.h"

namespace winrt::Anime4KUpscaler::views::implementation {
struct FileListPanel : FileListPanelT<FileListPanel> {
    FileListPanel() { InitializeComponent(); }

    void OnLoaded(winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnUnloaded(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnSelectionChanged(winrt::Windows::Foundation::IInspectable const&,
                            winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void OnAddClicked(winrt::Windows::Foundation::IInspectable const&,
                      winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnRemoveClicked(winrt::Windows::Foundation::IInspectable const&,
                         winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnClearClicked(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnDragOver(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::DragEventArgs const& e);
    void OnDrop(winrt::Windows::Foundation::IInspectable const&,
                winrt::Microsoft::UI::Xaml::DragEventArgs const& e);
private:
    void UpdateButtonState();
    winrt::event_token m_propToken;
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct FileListPanel : FileListPanelT<FileListPanel, implementation::FileListPanel> {};
}
