#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QMap>
#include <functional>
#include <optional>

struct ProbeResult {
    double durationSeconds = 0.0;
    int width = 0;
    int height = 0;
    double frameRate = 23.976;
};

class DurationProbe : public QObject {
    Q_OBJECT
public:
    static void probe(const QString& filePath, std::function<void(std::optional<ProbeResult>)> callback);
    static void batchProbe(const QStringList& filePaths, std::function<void(QMap<QString, std::optional<ProbeResult>>)> callback);
    static void probeColorTransfer(const QString& filePath, std::function<void(std::optional<QString>)> callback);
};
