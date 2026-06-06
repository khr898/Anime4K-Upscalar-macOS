#pragma once

#include "Models.h"
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QUuid>
#include <QDateTime>
#include <QProcess>

// MARK: - Stream Encoder

enum class StreamEncoder {
    HEVC_NVENC, H264_NVENC,     // NVIDIA
    HEVC_AMF, H264_AMF,         // AMD
    HEVC_QSV, H264_QSV,         // Intel
    SVT_AV1                      // Software
};

QString displayName(StreamEncoder encoder);
QString subtitle(StreamEncoder encoder);
QString symbolName(StreamEncoder encoder);
int defaultQuality(StreamEncoder encoder);
int maxQuality(StreamEncoder encoder);
QString qualityLabel(StreamEncoder encoder);
bool usesCRF(StreamEncoder encoder);

// MARK: - Stream Profile

enum class StreamProfile { Main10, Main, High, Baseline };

QString displayName(StreamProfile profile);
QString subtitle(StreamProfile profile);
QString profileValue(StreamProfile profile); // FFmpeg command-line string

QVector<StreamProfile> availableProfiles(StreamEncoder encoder);
StreamProfile defaultProfile(StreamEncoder encoder);

// MARK: - Stream Pixel Format

enum class StreamPixelFormat { P010LE, NV12, YUV420P, YUV420P10LE };

QString displayName(StreamPixelFormat pixFmt);
QString pixelFormatValue(StreamPixelFormat pixFmt); // FFmpeg command-line string

QVector<StreamPixelFormat> availablePixelFormats(StreamEncoder encoder);
StreamPixelFormat defaultPixelFormat(StreamEncoder encoder);

// MARK: - Stream Audio Mode

enum class StreamAudioMode { Copy, AACTranscode, AAC128, AAC192, AAC256 };

QString displayName(StreamAudioMode mode);
QString subtitle(StreamAudioMode mode);
QString symbolName(StreamAudioMode mode);
bool isCopy(StreamAudioMode mode);

// MARK: - Stream Subtitle Mode

enum class StreamSubtitleMode { MovText, Copy, Strip };

QString displayName(StreamSubtitleMode mode);
QString subtitle(StreamSubtitleMode mode);
QString symbolName(StreamSubtitleMode mode);

// MARK: - Keyframe Interval

enum class KeyframeInterval { OneSecond, TwoSeconds, ThreeSeconds, FiveSeconds, TenSeconds };

int seconds(KeyframeInterval interval);
QString displayName(KeyframeInterval interval);
QString subtitle(KeyframeInterval interval);

// MARK: - Stream Optimize Configuration

struct StreamOptimizeConfiguration {
    StreamEncoder encoder = StreamEncoder::HEVC_NVENC;
    int quality = 65;
    StreamProfile profile = StreamProfile::Main10;
    StreamPixelFormat pixelFormat = StreamPixelFormat::P010LE;
    StreamAudioMode audioMode = StreamAudioMode::Copy;
    StreamSubtitleMode subtitleMode = StreamSubtitleMode::MovText;
    KeyframeInterval keyframeInterval = KeyframeInterval::TwoSeconds;
    bool faststart = true;
    bool allowSWFallback = true;

    static StreamOptimizeConfiguration defaultConfig();
};

// MARK: - Stream Optimize Job

class StreamOptimizeJob : public QObject {
    Q_OBJECT
public:
    StreamOptimizeJob(const VideoFile& file, const StreamOptimizeConfiguration& configuration, const QString& destinationDirectory, QObject* parent = nullptr);

    QUuid id;
    VideoFile file;
    StreamOptimizeConfiguration configuration;

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

    QProcess* processHandle = nullptr;

    double elapsedTime() const;
    QString formattedElapsedTime() const;
    void appendLog(const QString& line);

signals:
    void stateChanged();
    void progressChanged();
};

// MARK: - Stream Optimize Argument Builder

class StreamOptimizeArgumentBuilder {
public:
    static QStringList build(
        const QString& inputPath,
        const QString& outputPath,
        const StreamOptimizeConfiguration& configuration
    );
};
