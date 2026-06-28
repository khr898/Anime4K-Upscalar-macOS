#include "pch.h"
#include "views/ConfigurationPanel.h"
#include "views/ConfigurationPanel.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;

static constexpr int32_t kCodecSVT_AV1   = 6;
static constexpr int32_t kPresetCustomQ  = 2;
static constexpr int32_t kPresetBitrate  = 3;

void ConfigurationPanel::OnLoaded(IInspectable const&, RoutedEventArgs const&) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    SyncFromBridge();
    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        if (args.PropertyName() == L"Config") SyncFromBridge();
    });
}

void ConfigurationPanel::OnUnloaded(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->PropertyChanged(m_propToken);
}

void ConfigurationPanel::SyncFromBridge() {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    m_suppress = true;

    int32_t res    = b->Resolution();
    int32_t codec  = b->Codec();
    int32_t preset = b->Preset();
    int32_t qual   = b->QualityValue();
    int32_t bit    = b->BitrateValue();
    int32_t svt    = b->SvtPreset();
    bool    longG  = b->LongGOP();
    auto    outDir = b->OutputDirectory();

    // Resolution radio
    ResOriginal().IsChecked(res == 0);
    ResDouble().IsChecked(res == 1);
    ResQuad().IsChecked(res == 2);

    CodecCombo().SelectedIndex(codec);
    PresetCombo().SelectedIndex(preset);

    QualitySlider().Value(qual);
    QualityValueLabel().Text(winrt::to_hstring(qual));
    BitrateSlider().Value(bit);
    BitrateValueLabel().Text(winrt::to_hstring(bit) + L" Mbps");
    SvtSlider().Value(svt);
    SvtValueLabel().Text(L"Preset " + winrt::to_hstring(svt));

    LongGOPCheck().IsChecked(longG);

    OutputDirLabel().Text(outDir.empty() ? L"(same as source)" : outDir);

    UpdatePresetVisibility(preset, codec);
    m_suppress = false;
}

void ConfigurationPanel::UpdatePresetVisibility(int32_t preset, int32_t codec) {
    using Visibility = winrt::Microsoft::UI::Xaml::Visibility;
    QualityContainer().Visibility(preset == kPresetCustomQ ? Visibility::Visible : Visibility::Collapsed);
    BitrateContainer().Visibility(preset == kPresetBitrate ? Visibility::Visible : Visibility::Collapsed);
    SvtContainer().Visibility(codec == kCodecSVT_AV1 ? Visibility::Visible : Visibility::Collapsed);
}

void ConfigurationPanel::OnResolutionChecked(IInspectable const& sender, RoutedEventArgs const&) {
    if (m_suppress) return;
    auto rb = sender.as<Controls::RadioButton>();
    int32_t idx = std::stoi(std::wstring(rb.Tag().as<winrt::hstring>().c_str()));
    if (auto* b = implementation::CurrentAppBridge()) b->SetResolution(idx);
}

void ConfigurationPanel::OnCodecChanged(IInspectable const&, Controls::SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    int32_t idx = CodecCombo().SelectedIndex();
    if (auto* b = implementation::CurrentAppBridge()) {
        b->SetCodec(idx);
        UpdatePresetVisibility(PresetCombo().SelectedIndex(), idx);
    }
}

void ConfigurationPanel::OnPresetChanged(IInspectable const&, Controls::SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    int32_t idx = PresetCombo().SelectedIndex();
    if (auto* b = implementation::CurrentAppBridge()) {
        b->SetPreset(idx);
        UpdatePresetVisibility(idx, CodecCombo().SelectedIndex());
    }
}

void ConfigurationPanel::OnQualityChanged(IInspectable const&,
    Controls::Primitives::RangeBaseValueChangedEventArgs const& e) {
    if (m_suppress) return;
    int32_t val = static_cast<int32_t>(e.NewValue());
    QualityValueLabel().Text(winrt::to_hstring(val));
    if (auto* b = implementation::CurrentAppBridge()) b->SetQualityValue(val);
}

void ConfigurationPanel::OnBitrateChanged(IInspectable const&,
    Controls::Primitives::RangeBaseValueChangedEventArgs const& e) {
    if (m_suppress) return;
    int32_t val = static_cast<int32_t>(e.NewValue());
    BitrateValueLabel().Text(winrt::to_hstring(val) + L" Mbps");
    if (auto* b = implementation::CurrentAppBridge()) b->SetBitrateValue(val);
}

void ConfigurationPanel::OnSvtChanged(IInspectable const&,
    Controls::Primitives::RangeBaseValueChangedEventArgs const& e) {
    if (m_suppress) return;
    int32_t val = static_cast<int32_t>(e.NewValue());
    SvtValueLabel().Text(L"Preset " + winrt::to_hstring(val));
    if (auto* b = implementation::CurrentAppBridge()) b->SetSvtPreset(val);
}

void ConfigurationPanel::OnLongGOPChanged(IInspectable const&, RoutedEventArgs const&) {
    if (m_suppress) return;
    bool val = LongGOPCheck().IsChecked().GetBoolean();
    if (auto* b = implementation::CurrentAppBridge()) b->SetLongGOP(val);
}

void ConfigurationPanel::OnBrowseOutput(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->SelectOutputDirectory();
}

}
