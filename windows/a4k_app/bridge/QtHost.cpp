#include "QtHost.h"
#include <viewmodels/AppViewModel.h>
#include <viewmodels/CompressViewModel.h>
#include <viewmodels/StreamOptimizeViewModel.h>

#include <QCoreApplication>
#include <QMetaObject>

QtHost::QtHost() = default;

QtHost::~QtHost() {
    stop();
}

void QtHost::start() {
    m_thread = std::thread([this] { threadMain(); });
    std::unique_lock<std::mutex> lock(m_startMutex);
    m_startCv.wait(lock, [this] { return m_started; });
}

void QtHost::stop() {
    if (m_thread.joinable()) {
        QMetaObject::invokeMethod(qApp, [] { QCoreApplication::quit(); }, Qt::QueuedConnection);
        m_thread.join();
    }
}

void QtHost::postToQtThread(std::function<void()> fn) {
    QMetaObject::invokeMethod(qApp, std::move(fn), Qt::QueuedConnection);
}

void QtHost::runOnQtThread(std::function<void()> fn) {
    std::mutex mtx;
    std::condition_variable cv;
    bool done = false;
    QMetaObject::invokeMethod(qApp, [&] {
        fn();
        std::unique_lock<std::mutex> lk(mtx);
        done = true;
        cv.notify_one();
    }, Qt::QueuedConnection);
    std::unique_lock<std::mutex> lk(mtx);
    cv.wait(lk, [&] { return done; });
}

void QtHost::threadMain() {
    int argc = 0;
    QCoreApplication app(argc, nullptr);

    // Construct all viewmodels on this thread so QProcess/QTimer are owned here.
    m_appVM      = new AppViewModel();
    m_compressVM = new CompressViewModel();
    m_streamVM   = new StreamOptimizeViewModel();

    {
        std::unique_lock<std::mutex> lock(m_startMutex);
        m_started = true;
    }
    m_startCv.notify_one();

    app.exec();

    // Cleanup on Qt thread before thread exits.
    delete m_appVM;      m_appVM      = nullptr;
    delete m_compressVM; m_compressVM = nullptr;
    delete m_streamVM;   m_streamVM   = nullptr;
}
