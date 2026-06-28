#include "WinUiPickerService.h"
#include "../bridge/QtHost.h"

#include <winrt/Microsoft.Windows.Storage.Pickers.h>
#include <winrt/Windows.Foundation.Collections.h>

using namespace winrt::Microsoft::Windows::Storage::Pickers;
using namespace winrt::Microsoft::UI::Xaml;

namespace {
// Parse "Video Files (*.mp4 *.mkv ...)" into individual extensions.
winrt::Windows::Foundation::Collections::IVector<winrt::hstring>
extensionsFromFilter(const QString& filter) {
    auto vec = winrt::single_threaded_vector<winrt::hstring>();
    int start = filter.indexOf('(');
    int end   = filter.lastIndexOf(')');
    if (start < 0 || end < 0) {
        vec.Append(L"*");
        return vec;
    }
    QString inner = filter.mid(start + 1, end - start - 1);
    for (const QString& tok : inner.split(' ', Qt::SkipEmptyParts)) {
        QString ext = tok.trimmed();
        if (ext.startsWith("*."))
            ext = ext.mid(1); // "*.mp4" -> ".mp4"
        if (!ext.isEmpty())
            vec.Append(winrt::hstring{ reinterpret_cast<const wchar_t*>(ext.utf16()),
                                       (uint32_t)ext.size() });
    }
    return vec;
}

inline winrt::hstring toHString(const QString& s) {
    return winrt::hstring{ reinterpret_cast<const wchar_t*>(s.utf16()), (uint32_t)s.size() };
}
inline QString fromHString(winrt::hstring const& s) {
    return QString::fromWCharArray(s.c_str(), (int)s.size());
}
} // namespace

WinUiPickerService::WinUiPickerService(Window const& window, QtHost* qtHost)
    : m_window(window), m_qtHost(qtHost) {}

void WinUiPickerService::pickFiles(const QString& title,
                                   const QString& filter,
                                   std::function<void(QStringList)> done) {
    FileOpenPicker picker(m_window.AppWindow().Id());
    picker.Title(toHString(title));
    picker.FileTypeFilter().ReplaceAll(extensionsFromFilter(filter));

    auto op = picker.PickMultipleFilesAsync();
    op.Completed([done = std::move(done), qtHost = m_qtHost]
        (auto const& asyncOp, auto) {
        QStringList paths;
        for (auto const& f : asyncOp.GetResults())
            paths << fromHString(f.Path());
        qtHost->postToQtThread([done = std::move(done), paths = std::move(paths)] {
            done(paths);
        });
    });
}

void WinUiPickerService::pickDirectory(const QString& /*title*/,
                                       const QString& /*startDir*/,
                                       std::function<void(QString)> done) {
    FolderPicker picker(m_window.AppWindow().Id());
    picker.FileTypeFilter().Append(L"*");

    auto op = picker.PickSingleFolderAsync();
    op.Completed([done = std::move(done), qtHost = m_qtHost]
        (auto const& asyncOp, auto) {
        auto folder = asyncOp.GetResults();
        QString path = folder ? fromHString(folder.Path()) : QString{};
        qtHost->postToQtThread([done = std::move(done), path = std::move(path)] {
            done(path);
        });
    });
}
