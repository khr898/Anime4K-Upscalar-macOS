#include "StreamOptimizeModels.h"
#include "../utils/HardwareDetector.h"
#include <QFileInfo>
#include <QDir>

// MARK: - Stream Encoder Helper Functions

QString displayName(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC: return "HEVC (NVIDIA RTX)";
        case StreamEncoder::H264_NVENC: return "H.264 (NVIDIA RTX)";
        case StreamEncoder::HEVC_AMF:   return "HEVC (AMD)";
        case StreamEncoder::H264_AMF:   return "H.264 (AMD)";
        case StreamEncoder::HEVC_QSV:   return "HEVC (Intel)";
        case StreamEncoder::H264_QSV:   return "H.264 (Intel)";
        case StreamEncoder::SVT_AV1:     return "AV1 (Software)";
    }
    return QString();
}

QString subtitle(StreamEncoder encoder) {
    DeviceHardwareProfile profile = DeviceHardwareProfile::detect();
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC: return QString("NVIDIA NVENC on %1 \u2014 Best balance of speed & quality").arg(profile.gpuName);
        case StreamEncoder::H264_NVENC: return QString("NVIDIA NVENC on %1 \u2014 Maximum device compatibility").arg(profile.gpuName);
        case StreamEncoder::HEVC_AMF:   return QString("AMD AMF on %1 \u2014 Best balance of speed & quality").arg(profile.gpuName);
        case StreamEncoder::H264_AMF:   return QString("AMD AMF on %1 \u2014 Maximum device compatibility").arg(profile.gpuName);
        case StreamEncoder::HEVC_QSV:   return QString("Intel QSV on %1 \u2014 Best balance of speed & quality").arg(profile.gpuName);
        case StreamEncoder::H264_QSV:   return QString("Intel QSV on %1 \u2014 Maximum device compatibility").arg(profile.gpuName);
        case StreamEncoder::SVT_AV1:     return QString("SVT-AV1 on %1-core CPU \u2014 Best compression for modern players").arg(profile.cpuCoreCount);
    }
    return QString();
}

QString symbolName(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::HEVC_QSV:
            return "bolt.fill";
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::H264_QSV:
            return "bolt";
        case StreamEncoder::SVT_AV1:
            return "cpu";
    }
    return QString();
}

int defaultQuality(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::HEVC_QSV:
        case StreamEncoder::H264_QSV:
            return 65;
        case StreamEncoder::SVT_AV1:
            return 28;
    }
    return 65;
}

int maxQuality(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::HEVC_QSV:
        case StreamEncoder::H264_QSV:
            return 100;
        case StreamEncoder::SVT_AV1:
            return 63;
    }
    return 100;
}

QString qualityLabel(StreamEncoder encoder) {
    if (encoder == StreamEncoder::SVT_AV1) {
        return "CRF (0\u201363, Lower = Better)";
    }
    return "Quality (0\u2013100, Higher = Better)";
}

bool usesCRF(StreamEncoder encoder) {
    return encoder == StreamEncoder::SVT_AV1;
}

// MARK: - Stream Profile Helper Functions

QString displayName(StreamProfile profile) {
    switch (profile) {
        case StreamProfile::Main10:   return "Main 10";
        case StreamProfile::Main:     return "Main";
        case StreamProfile::High:     return "High";
        case StreamProfile::Baseline: return "Baseline";
    }
    return QString();
}

QString subtitle(StreamProfile profile) {
    switch (profile) {
        case StreamProfile::Main10:   return "10-bit color depth \u2014 Best HDR & gradient quality";
        case StreamProfile::Main:     return "8-bit standard profile";
        case StreamProfile::High:     return "H.264 High \u2014 Best H.264 quality";
        case StreamProfile::Baseline: return "Maximum compatibility (older devices)";
    }
    return QString();
}

QString profileValue(StreamProfile profile) {
    switch (profile) {
        case StreamProfile::Main10:   return "main10";
        case StreamProfile::Main:     return "main";
        case StreamProfile::High:     return "high";
        case StreamProfile::Baseline: return "baseline";
    }
    return QString();
}

QVector<StreamProfile> availableProfiles(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::HEVC_QSV:
            return { StreamProfile::Main, StreamProfile::Main10 };
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::H264_QSV:
            return { StreamProfile::High, StreamProfile::Main, StreamProfile::Baseline };
        case StreamEncoder::SVT_AV1:
            return { StreamProfile::Main };
    }
    return {};
}

StreamProfile defaultProfile(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::HEVC_QSV:
            return StreamProfile::Main10;
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::H264_QSV:
            return StreamProfile::High;
        case StreamEncoder::SVT_AV1:
            return StreamProfile::Main;
    }
    return StreamProfile::Main;
}

// MARK: - Stream Pixel Format Helper Functions

QString displayName(StreamPixelFormat pixFmt) {
    switch (pixFmt) {
        case StreamPixelFormat::P010LE:      return "P010LE (10-bit)";
        case StreamPixelFormat::NV12:        return "NV12 (8-bit HW)";
        case StreamPixelFormat::YUV420P:     return "YUV420P (8-bit)";
        case StreamPixelFormat::YUV420P10LE: return "YUV420P10LE (10-bit)";
    }
    return QString();
}

QString pixelFormatValue(StreamPixelFormat pixFmt) {
    switch (pixFmt) {
        case StreamPixelFormat::P010LE:      return "p010le";
        case StreamPixelFormat::NV12:        return "nv12";
        case StreamPixelFormat::YUV420P:     return "yuv420p";
        case StreamPixelFormat::YUV420P10LE: return "yuv420p10le";
    }
    return QString();
}

QVector<StreamPixelFormat> availablePixelFormats(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::HEVC_QSV:
            return { StreamPixelFormat::P010LE, StreamPixelFormat::NV12 };
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::H264_QSV:
            return { StreamPixelFormat::NV12, StreamPixelFormat::YUV420P };
        case StreamEncoder::SVT_AV1:
            return { StreamPixelFormat::YUV420P10LE, StreamPixelFormat::YUV420P };
    }
    return {};
}

StreamPixelFormat defaultPixelFormat(StreamEncoder encoder) {
    switch (encoder) {
        case StreamEncoder::HEVC_NVENC:
        case StreamEncoder::HEVC_AMF:
        case StreamEncoder::HEVC_QSV:
            return StreamPixelFormat::P010LE;
        case StreamEncoder::H264_NVENC:
        case StreamEncoder::H264_AMF:
        case StreamEncoder::H264_QSV:
            return StreamPixelFormat::NV12;
        case StreamEncoder::SVT_AV1:
            return StreamPixelFormat::YUV420P10LE;
    }
    return StreamPixelFormat::NV12;
}

// MARK: - Stream Audio Mode Helper Functions

QString displayName(StreamAudioMode mode) {
    switch (mode) {
        case StreamAudioMode::Copy:         return "Copy (Passthrough)";
        case StreamAudioMode::AACTranscode: return "AAC (Auto Bitrate)";
        case StreamAudioMode::AAC128:       return "AAC 128 kbps";
        case StreamAudioMode::AAC192:       return "AAC 192 kbps";
        case StreamAudioMode::AAC256:       return "AAC 256 kbps";
    }
    return QString();
}

QString subtitle(StreamAudioMode mode) {
    switch (mode) {
        case StreamAudioMode::Copy:         return "Fastest \u2014 keeps original audio untouched";
        case StreamAudioMode::AACTranscode: return "Re-encode to AAC with FFmpeg default bitrate";
        case StreamAudioMode::AAC128:       return "Good for spoken content & podcasts";
        case StreamAudioMode::AAC192:       return "Balanced quality for music & movies";
        case StreamAudioMode::AAC256:       return "High quality audio for critical listening";
    }
    return QString();
}

QString symbolName(StreamAudioMode mode) {
    switch (mode) {
        case StreamAudioMode::Copy:         return "arrow.right.circle";
        case StreamAudioMode::AACTranscode: return "waveform";
        case StreamAudioMode::AAC128:       return "speaker.wave.1";
        case StreamAudioMode::AAC192:       return "speaker.wave.2";
        case StreamAudioMode::AAC256:       return "speaker.wave.3";
    }
    return QString();
}

bool isCopy(StreamAudioMode mode) {
    return mode == StreamAudioMode::Copy;
}

// MARK: - Stream Subtitle Mode Helper Functions

QString displayName(StreamSubtitleMode mode) {
    switch (mode) {
        case StreamSubtitleMode::MovText: return "MOV Text (MP4 Compatible)";
        case StreamSubtitleMode::Copy:    return "Copy (Passthrough)";
        case StreamSubtitleMode::Strip:   return "Strip All Subtitles";
    }
    return QString();
}

QString subtitle(StreamSubtitleMode mode) {
    switch (mode) {
        case StreamSubtitleMode::MovText: return "Converts subtitles to MP4-native text \u2014 Best for streaming";
        case StreamSubtitleMode::Copy:    return "Keeps original format \u2014 May fail in MP4 container";
        case StreamSubtitleMode::Strip:   return "Removes all subtitle tracks";
    }
    return QString();
}

QString symbolName(StreamSubtitleMode mode) {
    switch (mode) {
        case StreamSubtitleMode::MovText: return "text.bubble";
        case StreamSubtitleMode::Copy:    return "arrow.right.circle";
        case StreamSubtitleMode::Strip:   return "text.badge.minus";
    }
    return QString();
}

// MARK: - Keyframe Interval Helper Functions

int seconds(KeyframeInterval interval) {
    switch (interval) {
        case KeyframeInterval::OneSecond:    return 1;
        case KeyframeInterval::TwoSeconds:   return 2;
        case KeyframeInterval::ThreeSeconds: return 3;
        case KeyframeInterval::FiveSeconds:  return 5;
        case KeyframeInterval::TenSeconds:   return 10;
    }
    return 2;
}

QString displayName(KeyframeInterval interval) {
    switch (interval) {
        case KeyframeInterval::OneSecond:    return "1 second";
        case KeyframeInterval::TwoSeconds:   return "2 seconds";
        case KeyframeInterval::ThreeSeconds: return "3 seconds";
        case KeyframeInterval::FiveSeconds:  return "5 seconds";
        case KeyframeInterval::TenSeconds:   return "10 seconds";
    }
    return QString();
}

QString subtitle(KeyframeInterval interval) {
    switch (interval) {
        case KeyframeInterval::OneSecond:    return "Instant seeking \u2014 Larger file size";
        case KeyframeInterval::TwoSeconds:   return "Excellent seeking \u2014 Recommended for streaming";
        case KeyframeInterval::ThreeSeconds: return "Good seeking \u2014 Balanced";
        case KeyframeInterval::FiveSeconds:  return "Moderate seeking \u2014 Smaller file";
        case KeyframeInterval::TenSeconds:   return "Slow seeking \u2014 Smallest file";
    }
    return QString();
}

// MARK: - Stream Optimize Configuration

StreamOptimizeConfiguration StreamOptimizeConfiguration::defaultConfig() {
    return StreamOptimizeConfiguration();
}

// MARK: - Stream Optimize Job

StreamOptimizeJob::StreamOptimizeJob(const VideoFile& f, const StreamOptimizeConfiguration& c, const QString& destinationDirectory, QObject* parent)
    : QObject(parent), file(f), configuration(c) {
    id = QUuid::createUuid();
    outputPath = QDir(destinationDirectory).filePath(QString("%1_streaming.mp4").arg(file.fileName));
}

double StreamOptimizeJob::elapsedTime() const {
    if (!startDate.isValid()) return 0.0;
    QDateTime end = endDate.isValid() ? endDate : QDateTime::currentDateTime();
    return startDate.msecsTo(end) / 1000.0;
}

QString StreamOptimizeJob::formattedElapsedTime() const {
    double elapsed = elapsedTime();
    int hours = static_cast<int>(elapsed) / 3600;
    int minutes = (static_cast<int>(elapsed) % 3600) / 60;
    int seconds = static_cast<int>(elapsed) % 60;
    if (hours > 0) {
        return QString("%1:%2:%3")
            .arg(hours, 2, 10, QChar('0'))
            .arg(minutes, 2, 10, QChar('0'))
            .arg(seconds, 2, 10, QChar('0'));
    } else {
        return QString("%1:%2")
            .arg(minutes, 2, 10, QChar('0'))
            .arg(seconds, 2, 10, QChar('0'));
    }
}

void StreamOptimizeJob::appendLog(const QString& line) {
    logLines.append(line);
    int overflow = logLines.count() - 500;
    if (overflow > 0) {
        logLines.erase(logLines.begin(), logLines.begin() + overflow);
    }
}

// MARK: - Stream Optimize Argument Builder

QStringList StreamOptimizeArgumentBuilder::build(
    const QString& inputPath,
    const QString& outputPath,
    const StreamOptimizeConfiguration& configuration
) {
    QStringList args;
    args.append({"-nostdin", "-hide_banner", "-v", "error", "-stats"});
    args.append("-y");
    args.append({"-i", inputPath});

    // Subtitle mapping
    if (configuration.subtitleMode == StreamSubtitleMode::Strip) {
        args.append({"-map", "0:v:0", "-map", "0:a?"});
    } else {
        args.append({"-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"});
    }

    // Video Encoder
    switch (configuration.encoder) {
        case StreamEncoder::HEVC_NVENC:
            args.append({"-c:v", "hevc_nvenc",
                         "-preset", "p4",
                         "-tune", "hq",
                         "-rc", "vbr",
                         "-cq", QString::number(configuration.quality),
                         "-b:v", "0",
                         "-profile:v", profileValue(configuration.profile),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat)});
            break;

        case StreamEncoder::H264_NVENC:
            args.append({"-c:v", "h264_nvenc",
                         "-preset", "p4",
                         "-tune", "hq",
                         "-rc", "vbr",
                         "-cq", QString::number(configuration.quality),
                         "-b:v", "0",
                         "-profile:v", profileValue(configuration.profile),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat)});
            break;

        case StreamEncoder::HEVC_AMF:
            args.append({"-c:v", "hevc_amf",
                         "-quality", "quality",
                         "-rc", "cqp",
                         "-qp_i", QString::number(configuration.quality),
                         "-qp_p", QString::number(configuration.quality),
                         "-profile:v", profileValue(configuration.profile),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat)});
            break;

        case StreamEncoder::H264_AMF:
            args.append({"-c:v", "h264_amf",
                         "-quality", "quality",
                         "-rc", "cqp",
                         "-qp_i", QString::number(configuration.quality),
                         "-qp_p", QString::number(configuration.quality),
                         "-profile:v", profileValue(configuration.profile),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat)});
            break;

        case StreamEncoder::HEVC_QSV:
            args.append({"-c:v", "hevc_qsv",
                         "-preset", "medium",
                         "-global_quality", QString::number(configuration.quality),
                         "-profile:v", profileValue(configuration.profile),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat)});
            break;

        case StreamEncoder::H264_QSV:
            args.append({"-c:v", "h264_qsv",
                         "-preset", "medium",
                         "-global_quality", QString::number(configuration.quality),
                         "-profile:v", profileValue(configuration.profile),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat)});
            break;

        case StreamEncoder::SVT_AV1:
            args.append({"-c:v", "libsvtav1",
                         "-preset", "6",
                         "-crf", QString::number(configuration.quality),
                         "-pix_fmt", pixelFormatValue(configuration.pixelFormat),
                         "-svtav1-params", "tune=0"});
            break;
    }

    // Keyframe interval forced
    int kfSec = seconds(configuration.keyframeInterval);
    args.append({"-force_key_frames", QString("expr:gte(t,n_forced*%1)").arg(kfSec)});

    // Audio encoding
    switch (configuration.audioMode) {
        case StreamAudioMode::Copy:
            args.append({"-c:a", "copy"});
            break;
        case StreamAudioMode::AACTranscode:
            args.append({"-c:a", "aac"});
            break;
        case StreamAudioMode::AAC128:
            args.append({"-c:a", "aac", "-b:a", "128k"});
            break;
        case StreamAudioMode::AAC192:
            args.append({"-c:a", "aac", "-b:a", "192k"});
            break;
        case StreamAudioMode::AAC256:
            args.append({"-c:a", "aac", "-b:a", "256k"});
            break;
    }

    // Subtitle encoding
    switch (configuration.subtitleMode) {
        case StreamSubtitleMode::MovText:
            args.append({"-c:s", "mov_text"});
            break;
        case StreamSubtitleMode::Copy:
            args.append({"-c:s", "copy"});
            break;
        case StreamSubtitleMode::Strip:
            break;
    }

    // Streaming optimization
    if (configuration.faststart) {
        args.append({"-movflags", "+faststart"});
    }

    args.append(outputPath);
    return args;
}
