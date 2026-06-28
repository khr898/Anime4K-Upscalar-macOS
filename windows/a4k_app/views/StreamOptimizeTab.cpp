#include "pch.h"
#include "views/StreamOptimizeTab.h"
#include "views/StreamOptimizeTab.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;
using IInsp = winrt::Windows::Foundation::IInspectable;
namespace impl = winrt::Anime4KUpscaler::implementation;

// ---- Lifecycle ----

void StreamOptimizeTab::OnLoaded(IInsp const&, RoutedEventArgs const&) {
    auto* b = impl::CurrentStreamBridge();
    if (!b) return;

    SyncFromBridge();
    UpdatePanelVisibility();

    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        auto name = args.PropertyName();
        if (name == L"IsConfiguring"   || name == L"IsProcessing"  ||
            name == L"CanStart"        || name == L"BatchSummary"  ||
            name == L"TotalFileSize"   || name == L"FileCount") {
            UpdatePanelVisibility();
        }
        if (name == L"SourceDirectory" || name == L"DestinationDirectory" ||
            name == L"FileCount") {
            SyncFromBridge();
        }
        if (name == L"Encoder"      || name == L"Quality"      ||
            name == L"Profile"      || name == L"PixelFormat"  ||
            name == L"AudioMode"    || name == L"SubtitleMode" ||
            name == L"KeyframeInterval" || name == L"Faststart"||
            name == L"AllowSWFallback") {
            SyncFromBridge();
        }
        if (name == L"Jobs" || name == L"AllJobsFinished") {
            RebuildJobList();
        }
    });
}

void StreamOptimizeTab::OnUnloaded(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentStreamBridge()) b->PropertyChanged(m_propToken);
}

// ---- Panel visibility ----

void StreamOptimizeTab::UpdatePanelVisibility() {
    auto* b = impl::CurrentStreamBridge();
    if (!b) return;

    bool isProcessing = b->IsProcessing();
    ConfigArea().Visibility(isProcessing    ? Visibility::Collapsed : Visibility::Visible);
    ProcessingArea().Visibility(isProcessing ? Visibility::Visible  : Visibility::Collapsed);

    SummaryLabel().Text(b->BatchSummary());
    FileSizeLabel().Text(b->TotalFileSize());
    StartButton().IsEnabled(b->CanStart());

    int cnt = b->FileCount();
    FileCountLabel().Text(cnt > 0
        ? winrt::hstring{ std::to_wstring(cnt) + L" file" + (cnt == 1 ? L"" : L"s") + L" found" }
        : winrt::hstring{ L"No video files found" });

    if (isProcessing) RebuildJobList();
}

// ---- Sync from bridge ----

void StreamOptimizeTab::SyncFromBridge() {
    auto* b = impl::CurrentStreamBridge();
    if (!b) return;
    m_suppress = true;

    auto src = b->SourceDirectory();
    SourceDirLabel().Text(src.empty() ? winrt::hstring{ L"Not selected" } : src);

    auto dst = b->DestinationDirectory();
    DestDirLabel().Text(dst.empty() ? winrt::hstring{ L"Not selected" } : dst);

    EncoderCombo().SelectedIndex(b->Encoder());

    QualitySlider().Value(b->Quality());
    QualityValueLabel().Text(winrt::hstring{ std::to_wstring(b->Quality()) });

    ProfileCombo().SelectedIndex(b->Profile());
    PixelFormatCombo().SelectedIndex(b->PixelFormat());
    AudioCombo().SelectedIndex(b->AudioMode());
    SubtitleCombo().SelectedIndex(b->SubtitleMode());
    KeyframeCombo().SelectedIndex(b->KeyframeInterval());

    FaststartCheck().IsChecked(b->Faststart());
    SWFallbackCheck().IsChecked(b->AllowSWFallback());

    m_suppress = false;
}

// ---- Job list ----

void StreamOptimizeTab::RebuildJobList() {
    auto* b = impl::CurrentStreamBridge();
    if (!b) return;

    auto snaps = b->GetJobSnapshots();
    int  done  = b->CompletedJobCount();
    int  fail  = b->FailedJobCount();
    int  total = static_cast<int>(snaps.size());

    ProcSummaryLabel().Text(winrt::hstring{
        std::to_wstring(done) + L" / " + std::to_wstring(total) + L" complete"
    });
    ProcStatsLabel().Text(fail > 0
        ? winrt::hstring{ std::to_wstring(fail) + L" failed" }
        : b->TotalDuration());

    double pct = total > 0 ? (static_cast<double>(done) / total) * 100.0 : 0.0;
    OverallProgressBar().Value(pct);

    StreamJobList().Children().Clear();
    for (auto const& snap : snaps)
        StreamJobList().Children().Append(MakeJobRow(snap));

    ReturnBtn().IsEnabled(b->AllJobsFinished());
}

UIElement StreamOptimizeTab::MakeJobRow(impl::JobSnapshot const& snap) {
    auto border = Border();
    border.Background(unbox_value<winrt::Microsoft::UI::Xaml::Media::Brush>(
        Application::Current().Resources().Lookup(
            box_value(winrt::hstring{ L"CardBackgroundFillColorDefaultBrush" }))));
    border.CornerRadius(CornerRadius{ 4,4,4,4 });
    border.Padding(Thickness{ 8,6,8,6 });
    border.Margin(Thickness{ 0,0,0,2 });

    auto grid = Grid();
    auto c0 = ColumnDefinition();
    c0.Width(GridLengthHelper::FromValueAndType(1, GridUnitType::Star));
    auto c1 = ColumnDefinition();
    c1.Width(GridLengthHelper::Auto());
    grid.ColumnDefinitions().Append(c0);
    grid.ColumnDefinitions().Append(c1);

    auto stack = StackPanel();
    stack.Spacing(2);

    auto nameText = TextBlock();
    nameText.Text(snap.fileName);
    nameText.Style(unbox_value<Style>(Application::Current().Resources().Lookup(
        box_value(winrt::hstring{ L"BodyStrongTextBlockStyle" }))));
    nameText.TextTrimming(TextTrimming::CharacterEllipsis);
    stack.Children().Append(nameText);

    auto pb = ProgressBar();
    pb.Minimum(0); pb.Maximum(100);
    pb.Value(snap.progress * 100.0);
    stack.Children().Append(pb);

    auto detail = TextBlock();
    detail.Text(snap.details);
    detail.Style(unbox_value<Style>(Application::Current().Resources().Lookup(
        box_value(winrt::hstring{ L"CaptionTextBlockStyle" }))));
    detail.Foreground(unbox_value<winrt::Microsoft::UI::Xaml::Media::Brush>(
        Application::Current().Resources().Lookup(
            box_value(winrt::hstring{ L"TextFillColorSecondaryBrush" }))));
    stack.Children().Append(detail);

    Grid::SetColumn(stack, 0);
    grid.Children().Append(stack);

    auto badge = TextBlock();
    badge.Text(snap.status);
    badge.Style(unbox_value<Style>(Application::Current().Resources().Lookup(
        box_value(winrt::hstring{ L"CaptionTextBlockStyle" }))));
    badge.VerticalAlignment(VerticalAlignment::Center);
    badge.Margin(Thickness{ 8,0,0,0 });
    if (snap.failed)
        badge.Foreground(unbox_value<winrt::Microsoft::UI::Xaml::Media::Brush>(
            Application::Current().Resources().Lookup(
                box_value(winrt::hstring{ L"SystemFillColorCriticalBrush" }))));
    Grid::SetColumn(badge, 1);
    grid.Children().Append(badge);

    border.Child(grid);
    return border;
}

// ---- Directory pickers ----

void StreamOptimizeTab::OnBrowseSource(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentStreamBridge()) b->SelectSourceDirectory();
}

void StreamOptimizeTab::OnBrowseDest(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentStreamBridge()) b->SelectDestinationDirectory();
}

// ---- Configuration ----

void StreamOptimizeTab::OnEncoderChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetEncoder(static_cast<int32_t>(EncoderCombo().SelectedIndex()));
}

void StreamOptimizeTab::OnQualityChanged(IInsp const&,
    Controls::Primitives::RangeBaseValueChangedEventArgs const& e) {
    auto val = static_cast<int32_t>(e.NewValue());
    QualityValueLabel().Text(winrt::hstring{ std::to_wstring(val) });
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge()) b->SetQuality(val);
}

void StreamOptimizeTab::OnProfileChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetProfile(static_cast<int32_t>(ProfileCombo().SelectedIndex()));
}

void StreamOptimizeTab::OnPixelFormatChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetPixelFormat(static_cast<int32_t>(PixelFormatCombo().SelectedIndex()));
}

void StreamOptimizeTab::OnAudioModeChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetAudioMode(static_cast<int32_t>(AudioCombo().SelectedIndex()));
}

void StreamOptimizeTab::OnSubtitleModeChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetSubtitleMode(static_cast<int32_t>(SubtitleCombo().SelectedIndex()));
}

void StreamOptimizeTab::OnKeyframeChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetKeyframeInterval(static_cast<int32_t>(KeyframeCombo().SelectedIndex()));
}

void StreamOptimizeTab::OnFaststartChanged(IInsp const&, RoutedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetFaststart(FaststartCheck().IsChecked().GetBoolean());
}

void StreamOptimizeTab::OnSWFallbackChanged(IInsp const&, RoutedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentStreamBridge())
        b->SetAllowSWFallback(SWFallbackCheck().IsChecked().GetBoolean());
}

// ---- Processing ----

void StreamOptimizeTab::OnStartClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentStreamBridge()) b->StartProcessing();
}

void StreamOptimizeTab::OnCancelClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentStreamBridge()) b->CancelProcessing();
}

void StreamOptimizeTab::OnReturnClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentStreamBridge()) b->ReturnToConfiguration();
}

} // namespace winrt::Anime4KUpscaler::views::implementation
