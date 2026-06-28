#include "pch.h"
#include "views/FileListPanel.h"
#include "views/FileListPanel.g.cpp"

namespace winrt::Anime4KUpscaler::views::implementation {

using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::ApplicationModel::DataTransfer;
using namespace winrt::Microsoft::UI::Xaml;

void FileListPanel::OnLoaded(IInspectable const&, RoutedEventArgs const&) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    FileListView().ItemsSource(b->FileNames());
    m_propToken = b->PropertyChanged([this](auto&&, auto&& args) {
        auto name = args.PropertyName();
        if (name == L"FileNames") {
            auto count = FileListView().Items().Size();
            HeaderLabel().Text(L"Video Files (" + winrt::to_hstring(count) + L")");
            ClearButton().IsEnabled(count > 0);
        }
    });
}

void FileListPanel::OnUnloaded(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->PropertyChanged(m_propToken);
}

void FileListPanel::OnSelectionChanged(IInspectable const&,
    Controls::SelectionChangedEventArgs const&) {
    RemoveButton().IsEnabled(FileListView().SelectedIndex() >= 0);
}

void FileListPanel::OnAddClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->AddFiles();
}
void FileListPanel::OnRemoveClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->RemoveSelectedFile();
}
void FileListPanel::OnClearClicked(IInspectable const&, RoutedEventArgs const&) {
    if (auto* b = implementation::CurrentAppBridge()) b->RemoveAllFiles();
}

void FileListPanel::OnDragOver(IInspectable const&, DragEventArgs const& e) {
    e.AcceptedOperation(DataPackageOperation::Copy);
}
void FileListPanel::OnDrop(IInspectable const&, DragEventArgs const& e) {
    auto* b = implementation::CurrentAppBridge();
    if (!b) return;
    e.DataView().GetStorageItemsAsync().Completed([b](auto const& r, auto) {
        std::vector<winrt::hstring> paths;
        for (auto const& item : r.GetResults()) paths.push_back(item.Path());
        if (!paths.empty()) b->AddFilesFromPaths(paths);
    });
}

void FileListPanel::UpdateButtonState() {
    bool hasItems = FileListView().Items().Size() > 0;
    ClearButton().IsEnabled(hasItems);
}

}
