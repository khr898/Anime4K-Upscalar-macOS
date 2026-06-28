#pragma once
#include <functional>
#include <thread>
#include <mutex>
#include <condition_variable>

class AppViewModel;
class CompressViewModel;
class StreamOptimizeViewModel;
class IPickerService;

// Owns the dedicated Qt worker thread + QCoreApplication.
// All Qt objects (viewmodels, QProcess, QTimer) live on this thread.
class QtHost {
public:
    QtHost();
    ~QtHost();

    // Start the Qt thread; block until QCoreApplication is running.
    void start();

    // Stop the Qt event loop and join the thread.
    void stop();

    // Post a task onto the Qt thread and return immediately.
    void postToQtThread(std::function<void()> fn);

    // Post a task and block until it completes.
    void runOnQtThread(std::function<void()> fn);

    // Viewmodels — constructed on the Qt thread during start().
    AppViewModel*             appViewModel()            const { return m_appVM; }
    CompressViewModel*        compressViewModel()       const { return m_compressVM; }
    StreamOptimizeViewModel*  streamOptimizeViewModel() const { return m_streamVM; }

private:
    void threadMain();

    std::thread               m_thread;
    std::mutex                m_startMutex;
    std::condition_variable   m_startCv;
    bool                      m_started = false;

    AppViewModel*             m_appVM      = nullptr;
    CompressViewModel*        m_compressVM = nullptr;
    StreamOptimizeViewModel*  m_streamVM   = nullptr;
};
