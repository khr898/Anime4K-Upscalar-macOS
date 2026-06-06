#pragma once

#include "Models.h"
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QUuid>
#include <QDateTime>
#include <QProcess>

// MARK: - Compress Encoder

enum class CompressEncoder {
    HEVC_NVENC,   // NVIDIA
    HEVC_AMF,     // AMD
    HEVC_QSV,     // Intel
    SVT_AV1       // Software
};

QString displayName(CompressEncoder encoder);
QString subtitle(CompressEncoder encoder);
QString symbolName(CompressEncoder encoder);
int defaultQuality(CompressEncoder encoder);
QString qualityLabel(CompressEncoder encoder);
int maxQuality(CompressEncoder encoder);
bool usesCRF(CompressEncoder encoder);

// MARK: - Content Type

enum class ContentType { LiveAction, Anime };

QString displayName(ContentType type);
QString subtitle(ContentType type);
QString symbolName(ContentType type);

// MARK: - HDR Mode

enum class HDRMode { SDR, HDR10 };

QString displayName(HDRMode mode);

// MARK: - Compress Configuration

struct CompressConfiguration {
    CompressEncoder encoder = CompressEncoder::HEVC_NVENC;
    int quality = 68;
    ContentType contentType = ContentType::LiveAction;
    int bFrames = 3;
    bool longGOPEnabled = false;

    static CompressConfiguration defaultConfig();
};

// MARK: - Compress Job

class CompressJob : public QObject {
    Q_OBJECT
public:
    CompressJob(const VideoFile& file, const CompressConfiguration& configuration, const QString& outputDirectory = QString(), QObject* parent = nullptr);

    QUuid id;
    VideoFile file;
    CompressConfiguration configuration;

    JobState state = JobState::Idle;
    double progress = 0.0;
    int currentFrame = 0;
    QString currentTime = "00:00:00.00";
    QString speed = "0.0x";
    QString fps = "0";
    QString outputPath;
    QStringList logLines;
    QString errorMessage;
    QDateTime startDate;
    QDateTime endDate;
    HDRMode hdrMode = HDRMode::SDR;

    QProcess* processHandle = nullptr;

    double elapsedTime() const;
    QString formattedElapsedTime() const;
    void appendLog(const QString& line);

signals:
    void stateChanged();
    void progressChanged();
};

// MARK: - Compress Argument Builder

class CompressArgumentBuilder {
public:
    static QStringList build(
        const QString& inputPath,
        const QString& outputPath,
        const CompressConfiguration& configuration,
        HDRMode hdrMode
    );
};
