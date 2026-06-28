#include "pch.h"
#include "views/CompressTab.h"
#include "views/CompressTab.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;
using IInsp = winrt::Windows::Foundation::IInspectable;
namespace impl = winrt::Anime4KUpscaler::implementation;

// ---- Lifecycle ----

void CompressTab::OnLoaded(IInsp const&, RoutedEventArgs const&) {
    auto* b = impl::CurrentCompressBridge();
    if (!b) return;

    CmpFileListView().ItemsSource(b->FileNames());

    SyncFromBridge();
    UpdatePanelVisibility();

    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        auto name = args.PropertyName();
        if (name == L"IsConfiguring" || name == L"IsProcessing" ||
            name == L"FileNames"     || name == L"BatchSummary"  ||
            name == L"TotalFileSize" || name == L"CanStart") {
            UpdatePanelVisibility();
        }
        if (name == L"Encoder"    || name == L"Quality"  ||
            name == L"ContentType"|| name == L"BFrames"  ||
            name == L"LongGOP"    || name == L"OutputDirectory") {
            SyncFromBridge();
        }
        if (name == L"Jobs" || name == L"AllJobsFinished") {
            RebuildJobList();
        }
    });
}

void CompressTab::OnUnloaded(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->PropertyChanged(m_propToken);
}

// ---- Panel visibility ----

void CompressTab::UpdatePanelVisibility() {
    auto* b = impl::CurrentCompressBridge();
    if (!b) return;

    bool hasFiles     = b->FileNames().Size() > 0;
    bool isProcessing = b->IsProcessing();

    EmptyStatePanel().Visibility(hasFiles ? Visibility::Collapsed : Visibility::Visible);
    FileListPanel().Visibility(hasFiles   ? Visibility::Visible   : Visibility::Collapsed);

    ConfigArea().Visibility(isProcessing    ? Visibility::Collapsed : Visibility::Visible);
    ProcessingArea().Visibility(isProcessing ? Visibility::Visible  : Visibility::Collapsed);

    SummaryLabel().Text(b->BatchSummary());
    FileSizeLabel().Text(b->TotalFileSize());
    StartButton().IsEnabled(b->CanStart());

    auto cnt = b->FileNames().Size();
    FileCountLabel().Text(winrt::hstring{
        std::to_wstring(cnt) + L" file" + (cnt == 1 ? L"" : L"s")
    });

    UpdateButtonState();
    if (isProcessing) RebuildJobList();
}

// ---- Sync config controls from bridge ----

void CompressTab::SyncFromBridge() {
    auto* b = impl::CurrentCompressBridge();
    if (!b) return;
    m_suppress = true;

    EncoderCombo().SelectedIndex(b->Encoder());

    QualitySlider().Value(b->Quality());
    QualityValueLabel().Text(winrt::hstring{ std::to_wstring(b->Quality()) });

    if (b->ContentType() == 0)
        LiveActionRadio().IsChecked(true);
    else
        AnimeRadio().IsChecked(true);

    BFramesSlider().Value(b->BFrames());
    BFramesValueLabel().Text(winrt::hstring{ std::to_wstring(b->BFrames()) });

    LongGOPCheck().IsChecked(b->LongGOP());

    auto outDir = b->OutputDirectory();
    OutputDirLabel().Text(outDir.empty() ? winrt::hstring{ L"Same as source" } : outDir);

    m_suppress = false;
}

// ---- Button state ----

void CompressTab::UpdateButtonState() {
    auto* b    = impl::CurrentCompressBridge();
    bool hasF  = b && b->FileNames().Size() > 0;
    CmpClearBtn().IsEnabled(hasF);
    CmpRemoveBtn().IsEnabled(CmpFileListView().SelectedIndex() >= 0);
    if (b) ReturnBtn().IsEnabled(b->AllJobsFinished());
}

// ---- Job list ----

void CompressTab::RebuildJobList() {
    auto* b = impl::CurrentCompressBridge();
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

    CmpJobList().Children().Clear();
    for (auto const& snap : snaps)
        CmpJobList().Children().Append(MakeJobRow(snap));

    UpdateButtonState();
}

UIElement CompressTab::MakeJobRow(impl::JobSnapshot const& snap) {
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

// ---- File management ----

void CompressTab::OnDragOver(IInsp const&, DragEventArgs const& e) {
    e.AcceptedOperation(winrt::Windows::ApplicationModel::DataTransfer::DataPackageOperation::Copy);
}

void CompressTab::OnDrop(IInsp const&, DragEventArgs const& e) {
    auto* b = impl::CurrentCompressBridge();
    if (!b) return;
    e.DataView().GetStorageItemsAsync().Completed(
        [b](auto&& op, auto&&) {
            std::vector<winrt::hstring> paths;
            for (auto const& item : op.GetResults())
                paths.push_back(item.Path());
            b->AddFilesFromPaths(paths);
        });
}

void CompressTab::OnAddClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->AddFiles();
}

void CompressTab::OnRemoveClicked(IInsp const&, RoutedEventArgs const&) {
    auto* b = impl::CurrentCompressBridge();
    if (!b) return;
    auto idx = static_cast<int32_t>(CmpFileListView().SelectedIndex());
    if (idx >= 0) b->RemoveFileAtIndex(idx);
}

void CompressTab::OnClearClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->RemoveAllFiles();
}

void CompressTab::OnSelectionChanged(IInsp const&, SelectionChangedEventArgs const&) {
    UpdateButtonState();
}

// ---- Configuration ----

void CompressTab::OnEncoderChanged(IInsp const&, SelectionChangedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentCompressBridge())
        b->SetEncoder(static_cast<int32_t>(EncoderCombo().SelectedIndex()));
}

void CompressTab::OnQualityChanged(IInsp const&,
    Controls::Primitives::RangeBaseValueChangedEventArgs const& e) {
    auto val = static_cast<int32_t>(e.NewValue());
    QualityValueLabel().Text(winrt::hstring{ std::to_wstring(val) });
    if (m_suppress) return;
    if (auto* b = impl::CurrentCompressBridge()) b->SetQuality(val);
}

void CompressTab::OnContentTypeChecked(IInsp const& sender, RoutedEventArgs const&) {
    if (m_suppress) return;
    auto* b = impl::CurrentCompressBridge();
    if (!b) return;
    auto tag = winrt::unbox_value<winrt::hstring>(sender.as<RadioButton>().Tag());
    b->SetContentType(std::stoi(std::wstring{ tag }));
}

void CompressTab::OnBFramesChanged(IInsp const&,
    Controls::Primitives::RangeBaseValueChangedEventArgs const& e) {
    auto val = static_cast<int32_t>(e.NewValue());
    BFramesValueLabel().Text(winrt::hstring{ std::to_wstring(val) });
    if (m_suppress) return;
    if (auto* b = impl::CurrentCompressBridge()) b->SetBFrames(val);
}

void CompressTab::OnLongGOPChanged(IInsp const&, RoutedEventArgs const&) {
    if (m_suppress) return;
    if (auto* b = impl::CurrentCompressBridge())
        b->SetLongGOP(LongGOPCheck().IsChecked().GetBoolean());
}

void CompressTab::OnBrowseOutput(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->SelectOutputDirectory();
}

// ---- Processing ----

void CompressTab::OnStartClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->StartProcessing();
}

void CompressTab::OnCancelClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->CancelProcessing();
}

void CompressTab::OnReturnClicked(IInsp const&, RoutedEventArgs const&) {
    if (auto* b = impl::CurrentCompressBridge()) b->ReturnToConfiguration();
}

} // namespace winrt::Anime4KUpscaler::views::implementation
