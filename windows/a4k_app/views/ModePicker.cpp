#include "pch.h"
#include "views/ModePicker.h"
#include "views/ModePicker.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;

// mode value → {name, category_index}
struct ModeEntry { int32_t value; const wchar_t* name; int cat; };
static const ModeEntry s_modes[] = {
    {1,  L"Mode A (HQ)",                     0},
    {2,  L"Mode B (HQ)",                     0},
    {3,  L"Mode C (HQ)",                     0},
    {4,  L"Mode A+A (HQ)",                   0},
    {5,  L"Mode B+B (HQ)",                   0},
    {6,  L"Mode C+A (HQ)",                   0},
    {7,  L"Mode A (Fast)",                   1},
    {8,  L"Mode B (Fast)",                   1},
    {9,  L"Mode C (Fast)",                   1},
    {10, L"Mode A+A (Fast)",                 1},
    {11, L"Mode B+B (Fast)",                 1},
    {12, L"Mode C+A (Fast)",                 1},
    {13, L"Mode A+A (Fast) [No Upscale]",    2},
    {14, L"Mode A (HQ) [No Upscale]",        2},
    {15, L"Mode A+A (HQ) [No Upscale]",      2},
    {16, L"ESRGAN Fast",                     3},
    {17, L"ESRGAN Quality",                  3},
    {18, L"ESRGAN General",                  3},
    {19, L"SPECIAL: Fast",                   4},
    {20, L"SPECIAL: Quality",                4},
    {21, L"SPECIAL: SD Rescue",              4},
    {22, L"SPECIAL: PiperSR 2x",             4},
};

int ModePicker::CategoryForMode(int32_t mode) noexcept {
    for (auto const& e : s_modes) if (e.value == mode) return e.cat;
    return 0;
}

void ModePicker::OnLoaded(IInspectable const&, RoutedEventArgs const&) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    int32_t cur = b->SelectedMode();
    m_currentCategory = CategoryForMode(cur);
    PopulateCategory(m_currentCategory);
    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        if (args.PropertyName() == L"SelectedMode") {
            auto* bridge = implementation::CurrentAppBridge();
            if (!bridge) return;
            int32_t mode = bridge->SelectedMode();
            int cat = CategoryForMode(mode);
            if (cat != m_currentCategory) {
                m_currentCategory = cat;
                PopulateCategory(cat);
            } else {
                SyncSelection(mode);
            }
        }
    });
}

void ModePicker::OnUnloaded(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->PropertyChanged(m_propToken);
}

void ModePicker::OnCategoryChecked(IInspectable const& sender, RoutedEventArgs const&) {
    if (m_suppressEvents) return;
    auto rb = sender.as<winrt::Microsoft::UI::Xaml::Controls::RadioButton>();
    int cat = std::stoi(std::wstring(rb.Tag().as<winrt::hstring>().c_str()));
    m_currentCategory = cat;
    PopulateCategory(cat);
}

void ModePicker::OnModeSelected(IInspectable const&,
    Controls::SelectionChangedEventArgs const&) {
    if (m_suppressEvents) return;
    int idx = ModeList().SelectedIndex();
    if (idx < 0 || idx >= (int)m_currentModes.size()) return;
    if (auto* b = implementation::CurrentAppBridge())
        b->SetSelectedMode(m_currentModes[idx]);
}

void ModePicker::PopulateCategory(int cat) {
    m_suppressEvents = true;
    ModeList().Items().Clear();
    m_currentModes.clear();
    for (auto const& e : s_modes) {
        if (e.cat != cat) continue;
        ModeList().Items().Append(winrt::box_value(winrt::hstring(e.name)));
        m_currentModes.push_back(e.value);
    }
    if (auto* b = implementation::CurrentAppBridge())
        SyncSelection(b->SelectedMode());
    m_suppressEvents = false;
}

void ModePicker::SyncSelection(int32_t modeValue) {
    m_suppressEvents = true;
    ModeList().SelectedIndex(-1);
    for (int i = 0; i < (int)m_currentModes.size(); ++i) {
        if (m_currentModes[i] == modeValue) { ModeList().SelectedIndex(i); break; }
    }
    m_suppressEvents = false;
}

}
