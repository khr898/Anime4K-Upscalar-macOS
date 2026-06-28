#include "pch.h"
#include "views/EmptyState.h"
#include "views/EmptyState.g.cpp"
#include "bridge/AppVMBridge.h"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::ApplicationModel::DataTransfer;
using namespace winrt::Microsoft::UI::Xaml;

void EmptyState::OnAddClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->AddFiles();
}

void EmptyState::OnDragOver(IInspectable const&, DragEventArgs const& e) {
    e.AcceptedOperation(DataPackageOperation::Copy);
    e.DragUIOverride().Caption(L"Add to upscale queue");
}

void EmptyState::OnDrop(IInspectable const&, DragEventArgs const& e) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    e.DataView().GetStorageItemsAsync().Completed(
        [b](auto const& result, auto) {
            std::vector<winrt::hstring> paths;
            for (auto const& item : result.GetResults())
                paths.push_back(item.Path());
            if (!paths.empty()) b->AddFilesFromPaths(paths);
        });
}

}
