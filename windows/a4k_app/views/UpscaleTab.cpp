#include "pch.h"
#include "views/UpscaleTab.h"
#include "views/UpscaleTab.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Microsoft::UI::Xaml;

void UpscaleTab::OnLoaded(IInspectable const&, RoutedEventArgs const&) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    UpdatePanelVisibility();
    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        auto name = args.PropertyName();
        if (name == L"IsConfiguring" || name == L"IsProcessing" ||
            name == L"FileNames"    || name == L"BatchSummary"  ||
            name == L"TotalFileSize" || name == L"CanStart") {
            UpdatePanelVisibility();
        }
    });
}

void UpscaleTab::OnUnloaded(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->PropertyChanged(m_propToken);
}

void UpscaleTab::OnStartClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->StartProcessing();
}

void UpscaleTab::UpdatePanelVisibility() {
    using Vis = winrt::Microsoft::UI::Xaml::Visibility;
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;

    bool isProcessing  = b->IsProcessing();
    bool hasFiles      = b->FileNames().Size() > 0;

    // Left: EmptyState when no files, FileListPanel otherwise
    EmptyStateView().Visibility(hasFiles ? Vis::Collapsed : Vis::Visible);
    FileListView().Visibility(hasFiles  ? Vis::Visible    : Vis::Collapsed);

    // Right: ProcessingPanel during processing, config area otherwise
    ConfigArea().Visibility(isProcessing ? Vis::Collapsed : Vis::Visible);
    ProcessingView().Visibility(isProcessing ? Vis::Visible : Vis::Collapsed);

    // Footer
    SummaryLabel().Text(b->BatchSummary());
    FileSizeLabel().Text(b->TotalFileSize());
    StartButton().IsEnabled(b->CanStart());
}

}
