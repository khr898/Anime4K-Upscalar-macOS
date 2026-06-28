#pragma once
#include <viewmodels/IPickerService.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <functional>

class QtHost;

// IPickerService implementation using Windows App SDK FileOpenPicker / FolderPicker.
// Runs pickers on the UI thread; marshals results back to the Qt thread via QtHost.
class WinUiPickerService : public IPickerService {
public:
    explicit WinUiPickerService(winrt::Microsoft::UI::Xaml::Window const& window,
                                QtHost* qtHost);

    void pickFiles(const QString& title, const QString& filter,
                   std::function<void(QStringList)> done) override;

    void pickDirectory(const QString& title, const QString& startDir,
                       std::function<void(QString)> done) override;

private:
    winrt::Microsoft::UI::Xaml::Window m_window;
    QtHost* m_qtHost;
};
