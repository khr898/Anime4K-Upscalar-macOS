#include "pch.h"
#include "views/ProcessingPanel.h"
#include "views/ProcessingPanel.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;

void ProcessingPanel::OnLoaded(IInspectable const&, RoutedEventArgs const&) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    RebuildJobList();
    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        auto name = args.PropertyName();
        if (name == L"Jobs" || name == L"BatchSummary") RebuildJobList();
        if (name == L"AllJobsFinished") {
            bool done = implementation::CurrentAppBridge() &&
                        implementation::CurrentAppBridge()->AllJobsFinished();
            ReturnBtn().IsEnabled(done);
            CancelBtn().IsEnabled(!done);
        }
    });
}

void ProcessingPanel::OnUnloaded(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->PropertyChanged(m_propToken);
}

void ProcessingPanel::OnCancelClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->CancelProcessing();
}

void ProcessingPanel::OnReturnClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->ReturnToConfiguration();
}

void ProcessingPanel::RebuildJobList() {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;

    SummaryLabel().Text(b->BatchSummary());
    StatsLabel().Text(L"Completed: " + winrt::to_hstring(b->CompletedJobCount()) +
                      L"  Failed: " + winrt::to_hstring(b->FailedJobCount()));
    DurationLabel().Text(b->TotalDuration());

    auto snaps = b->GetJobSnapshots();
    uint32_t total    = static_cast<uint32_t>(snaps.size());
    uint32_t finished = static_cast<uint32_t>(b->CompletedJobCount() + b->FailedJobCount());
    OverallProgress().Value(total > 0 ? (finished * 100.0 / total) : 0.0);

    JobList().Children().Clear();
    for (auto const& snap : snaps)
        JobList().Children().Append(MakeJobRow(snap));
}

UIElement ProcessingPanel::MakeJobRow(JobSnapshot const& snap) {
    auto border = Border();
    border.Background(
        Application::Current().Resources()
            .Lookup(winrt::box_value(L"CardBackgroundFillColorDefaultBrush"))
            .as<winrt::Microsoft::UI::Xaml::Media::Brush>());
    border.CornerRadius({4, 4, 4, 4});
    border.Padding({12, 8, 12, 8});
    border.Margin({0, 0, 0, 0});

    auto grid = Grid();
    grid.ColumnSpacing(8);
    grid.ColumnDefinitions().Append([] { ColumnDefinition c; GridLength g; g.GridUnitType=GridUnitType::Star; g.Value=1; c.Width(g); return c; }());
    grid.ColumnDefinitions().Append([] { ColumnDefinition c; GridLength g; g.GridUnitType=GridUnitType::Auto; c.Width(g); return c; }());

    auto panel = StackPanel();
    panel.Spacing(4);

    auto nameText = TextBlock();
    nameText.Text(snap.fileName);
    nameText.Style(Application::Current().Resources()
        .Lookup(winrt::box_value(L"BodyStrongTextBlockStyle")).as<Style>());
    nameText.TextTrimming(TextTrimming::CharacterEllipsis);

    auto progBar = ProgressBar();
    progBar.Minimum(0); progBar.Maximum(100);
    progBar.Value(snap.progress * 100.0);

    auto detailText = TextBlock();
    detailText.Text(snap.details);
    detailText.Style(Application::Current().Resources()
        .Lookup(winrt::box_value(L"CaptionTextBlockStyle")).as<Style>());
    detailText.Foreground(Application::Current().Resources()
        .Lookup(winrt::box_value(L"TextFillColorSecondaryBrush"))
        .as<winrt::Microsoft::UI::Xaml::Media::Brush>());

    panel.Children().Append(nameText);
    panel.Children().Append(progBar);
    panel.Children().Append(detailText);

    auto badge = TextBlock();
    badge.Text(snap.status);
    badge.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(badge, 1);

    grid.Children().Append(panel);
    grid.Children().Append(badge);
    border.Child(grid);
    return border;
}

}
