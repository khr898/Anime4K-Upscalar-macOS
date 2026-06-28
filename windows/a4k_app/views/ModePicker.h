#pragma once
#include "views/ModePicker.g.h"
#include "bridge/AppVMBridge.h"
#include <vector>

namespace winrt::Anime4KUpscaler::views::implementation {
struct ModePicker : ModePickerT<ModePicker> {
    ModePicker() { InitializeComponent(); }

    void OnLoaded(winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnUnloaded(winrt::Windows::Foundation::IInspectable const&,
                    winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnCategoryChecked(winrt::Windows::Foundation::IInspectable const& sender,
                           winrt::Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OnModeSelected(winrt::Windows::Foundation::IInspectable const&,
                        winrt::Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
private:
    void PopulateCategory(int cat);
    void SyncSelection(int32_t modeValue);
    static int CategoryForMode(int32_t mode) noexcept;

    std::vector<int32_t> m_currentModes;
    int                  m_currentCategory = 0;
    bool                 m_suppressEvents  = false;
    winrt::event_token   m_propToken;
};
}
namespace winrt::Anime4KUpscaler::views::factory_implementation {
struct ModePicker : ModePickerT<ModePicker, implementation::ModePicker> {};
}
