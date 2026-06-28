#pragma once
#include "views/EmptyState.g.h"

namespace winrt::Anime4KUpscaler::views::implementation {
struct EmptyState : EmptyStateT<EmptyState> {
    EmptyState() { InitializeComponent(); }

    void OnAddClicked(winrt::Windows::Foundation::IInspectable const&,
                      winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnDragOver(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::DragEventArgs const& e);
    void OnDrop(winrt::Windows::Foundation::IInspectable const&,
                winrt::Microsoft::UI::Xaml::DragEventArgs const& e);
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct EmptyState : EmptyStateT<EmptyState, implementation::EmptyState> {};
}
