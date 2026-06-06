#include "DurationProbe.h"
#include "FFmpegLocator.h"
#include <QProcess>
#include <QThread>
#include <QCoreApplication>
#include <QMetaObject>
#include <QPair>

static QString runFFprobe(const QStringList& arguments) {
    QProcess process;
    process.setProgram(FFmpegLocator::ffprobePath());
    process.setArguments(arguments);
    process.setProcessEnvironment(FFmpegLocator::processEnvironment());
    process.start();
    if (!process.waitForFinished(10000)) { // 10 seconds timeout
        process.kill();
        return QString();
    }
    if (process.exitCode() != 0) {
        return QString();
    }
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
}

static std::optional<double> probeDuration(const QString& filePath) {
    QStringList args = {"-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", filePath};
    QString out = runFFprobe(args);
    if (out.isEmpty()) return std::nullopt;
    bool ok;
    double val = out.toDouble(&ok);
    if (!ok) return std::nullopt;
    return val;
}

static std::optional<double> probeFrameRate(const QString& filePath) {
    QStringList args = {"-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", filePath};
    QString out = runFFprobe(args);
    if (out.isEmpty()) return std::nullopt;
    QStringList parts = out.split('/');
    if (parts.size() == 2) {
        bool ok1, ok2;
        double num = parts[0].toDouble(&ok1);
        double den = parts[1].toDouble(&ok2);
        if (ok1 && ok2 && den > 0.0) {
            return num / den;
        }
    } else {
        bool ok;
        double val = out.toDouble(&ok);
        if (ok && val > 0.0) return val;
    }
    return std::nullopt;
}

static std::optional<QPair<int, int>> probeStreams(const QString& filePath) {
    QStringList args = {"-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", filePath};
    QString out = runFFprobe(args);
    if (out.isEmpty()) return std::nullopt;
    QStringList parts = out.split('x');
    if (parts.size() != 2) return std::nullopt;
    bool ok1, ok2;
    int w = parts[0].toInt(&ok1);
    int h = parts[1].toInt(&ok2);
    if (!ok1 || !ok2) return std::nullopt;
    return qMakePair(w, h);
}
void DurationProbe::probe(const QString& filePath, std::function<void(std::optional<ProbeResult>)> callback) {
    QThread* thread = QThread::create([filePath, callback]() {
        auto durOpt = probeDuration(filePath);
        auto streamOpt = probeStreams(filePath);
        auto fpsOpt = probeFrameRate(filePath);

        std::optional<ProbeResult> result;
        if (durOpt.has_value()) {
            ProbeResult pr;
            pr.durationSeconds = durOpt.value();
            if (streamOpt.has_value()) {
                pr.width = streamOpt.value().first;
                pr.height = streamOpt.value().second;
            }
            if (fpsOpt.has_value()) {
                pr.frameRate = fpsOpt.value();
            }
            result = pr;
        }

        // Thread-safe dispatch back to main thread
        QMetaObject::invokeMethod(QCoreApplication::instance(), [callback, result]() {
            callback(result);
        });
    });

    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}

void DurationProbe::batchProbe(const QStringList& filePaths, std::function<void(QMap<QString, std::optional<ProbeResult>>)> callback) {
    QThread* thread = QThread::create([filePaths, callback]() {
        QMap<QString, std::optional<ProbeResult>> results;
        for (const QString& filePath : filePaths) {
            auto durOpt = probeDuration(filePath);
            auto streamOpt = probeStreams(filePath);
            auto fpsOpt = probeFrameRate(filePath);

            std::optional<ProbeResult> result;
            if (durOpt.has_value()) {
                ProbeResult pr;
                pr.durationSeconds = durOpt.value();
                if (streamOpt.has_value()) {
                    pr.width = streamOpt.value().first;
                    pr.height = streamOpt.value().second;
                }
                if (fpsOpt.has_value()) {
                    pr.frameRate = fpsOpt.value();
                }
                result = pr;
            }
            results.insert(filePath, result);
        }

        // Thread-safe dispatch back to main thread
        QMetaObject::invokeMethod(QCoreApplication::instance(), [callback, results]() {
            callback(results);
        });
    });

    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}

void DurationProbe::probeColorTransfer(const QString& filePath, std::function<void(std::optional<QString>)> callback) {
    QThread* thread = QThread::create([filePath, callback]() {
        QStringList args = {"-v", "error", "-select_streams", "v:0", "-show_entries", "stream=color_transfer", "-of", "csv=p=0", filePath};
        QString out = runFFprobe(args);

        std::optional<QString> result;
        if (!out.isEmpty()) {
            result = out;
        }

        // Thread-safe dispatch back to main thread
        QMetaObject::invokeMethod(QCoreApplication::instance(), [callback, result]() {
            callback(result);
        });
    });

    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}
