#include "CompressModels.h"
#include "../utils/HardwareDetector.h"
#include <QFileInfo>
#include <QDir>

// MARK: - Compress Encoder Helper Functions

QString displayName(CompressEncoder encoder) {
    switch (encoder) {
        case CompressEncoder::HEVC_NVENC: return "HEVC (NVIDIA RTX)";
        case CompressEncoder::HEVC_AMF:   return "HEVC (AMD)";
        case CompressEncoder::HEVC_QSV:   return "HEVC (Intel)";
        case CompressEncoder::SVT_AV1:     return "SVT-AV1 (Software)";
    }
    return QString();
}

QString subtitle(CompressEncoder encoder) {
    DeviceHardwareProfile profile = DeviceHardwareProfile::detect();
    switch (encoder) {
        case CompressEncoder::HEVC_NVENC: return QString("NVIDIA NVENC on %1 \u2014 Fastest encoding").arg(profile.gpuName);
        case CompressEncoder::HEVC_AMF:   return QString("AMD AMF on %1 \u2014 Fastest encoding").arg(profile.gpuName);
        case CompressEncoder::HEVC_QSV:   return QString("Intel QSV on %1 \u2014 Fastest encoding").arg(profile.gpuName);
        case CompressEncoder::SVT_AV1:     return QString("SVT-AV1 on %1-core CPU \u2014 Maximum storage saving").arg(profile.cpuCoreCount);
    }
    return QString();
}

QString symbolName(CompressEncoder encoder) {
    switch (encoder) {
        case CompressEncoder::HEVC_NVENC:
        case CompressEncoder::HEVC_AMF:
        case CompressEncoder::HEVC_QSV:
            return "bolt.fill";
        case CompressEncoder::SVT_AV1:
            return "cpu";
    }
    return QString();
}

int defaultQuality(CompressEncoder encoder) {
    switch (encoder) {
        case CompressEncoder::HEVC_NVENC:
        case CompressEncoder::HEVC_AMF:
        case CompressEncoder::HEVC_QSV:
            return 68;
        case CompressEncoder::SVT_AV1:
            return 24;
    }
    return 68;
}

QString qualityLabel(CompressEncoder encoder) {
    switch (encoder) {
        case CompressEncoder::HEVC_NVENC:
        case CompressEncoder::HEVC_AMF:
        case CompressEncoder::HEVC_QSV:
            return "Quality (0\u2013100, Higher = Better)";
        case CompressEncoder::SVT_AV1:
            return "CRF (0\u201363, Lower = Better)";
    }
    return QString();
}

int maxQuality(CompressEncoder encoder) {
    switch (encoder) {
        case CompressEncoder::HEVC_NVENC:
        case CompressEncoder::HEVC_AMF:
        case CompressEncoder::HEVC_QSV:
            return 100;
        case CompressEncoder::SVT_AV1:
            return 63;
    }
    return 100;
}

bool usesCRF(CompressEncoder encoder) {
    return encoder == CompressEncoder::SVT_AV1;
}

// MARK: - Content Type Helper Functions

QString displayName(ContentType type) {
    switch (type) {
        case ContentType::LiveAction: return "Live Action";
        case ContentType::Anime:      return "Anime / Animation";
    }
    return QString();
}

QString subtitle(ContentType type) {
    switch (type) {
        case ContentType::LiveAction: return "Standard live-action video encoding";
        case ContentType::Anime:      return "Enables B-Frames & Long GOP options";
    }
    return QString();
}

QString symbolName(ContentType type) {
    switch (type) {
        case ContentType::LiveAction: return "video";
        case ContentType::Anime:      return "sparkles.tv";
    }
    return QString();
}

// MARK: - HDR Mode Helper Functions

QString displayName(HDRMode mode) {
    switch (mode) {
        case HDRMode::SDR:   return "SDR (Rec.709)";
        case HDRMode::HDR10: return "HDR10 (Pass-through)";
    }
    return QString();
}

// MARK: - Compress Configuration

CompressConfiguration CompressConfiguration::defaultConfig() {
    return CompressConfiguration();
}

// MARK: - Compress Job

CompressJob::CompressJob(const VideoFile& f, const CompressConfiguration& c, const QString& outputDirectory, QObject* parent)
    : QObject(parent), file(f), configuration(c) {
    id = QUuid::createUuid();
    QString baseDir = outputDirectory.isEmpty() ? QFileInfo(file.filePath).absolutePath() : outputDirectory;
    QString outName = QString("%1_compressed.%2").arg(file.fileName).arg(file.fileExtension);
    outputPath = QDir(baseDir).filePath(outName);
}

double CompressJob::elapsedTime() const {
    if (!startDate.isValid()) return 0.0;
    QDateTime end = endDate.isValid() ? endDate : QDateTime::currentDateTime();
    return startDate.msecsTo(end) / 1000.0;
}

QString CompressJob::formattedElapsedTime() const {
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

void CompressJob::appendLog(const QString& line) {
    logLines.append(line);
    int overflow = logLines.count() - 500;
    if (overflow > 0) {
        logLines.erase(logLines.begin(), logLines.begin() + overflow);
    }
}

// MARK: - Compress Argument Builder

QStringList CompressArgumentBuilder::build(
    const QString& inputPath,
    const QString& outputPath,
    const CompressConfiguration& configuration,
    HDRMode hdrMode
) {
    QStringList args;
    args.append({"-hide_banner", "-v", "error", "-stats"});
    args.append("-y");
    args.append({"-i", inputPath});

    // Stream maps
    args.append({"-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"});

    // Audio & Subs copy
    args.append({"-c:a", "copy", "-c:s", "copy"});

    // Encoder
    switch (configuration.encoder) {
        case CompressEncoder::SVT_AV1: {
            QString svtParams = "tune=0:";
            if (hdrMode == HDRMode::HDR10) {
                svtParams += "enable-hdr=1:";
            } else {
                svtParams += "enable-hdr=0:color-primaries=1:transfer-characteristics=1:matrix-coefficients=1:range=1:";
            }
            svtParams.chop(1); // remove trailing ':'

            args.append({"-c:v", "libsvtav1",
                         "-preset", "4",
                         "-crf", QString::number(configuration.quality),
                         "-pix_fmt", "yuv420p10le",
                         "-svtav1-params", svtParams});
            break;
        }

        case CompressEncoder::HEVC_NVENC:
            args.append({"-c:v", "hevc_nvenc",
                         "-preset", "p4",
                         "-tune", "hq",
                         "-rc", "vbr",
                         "-cq", QString::number(configuration.quality),
                         "-b:v", "0",
                         "-pix_fmt", "p010le"});
            if (hdrMode == HDRMode::HDR10) {
                args.append({"-color_primaries", "bt2020",
                             "-color_trc", "smpte2084",
                             "-colorspace", "bt2020nc"});
            } else {
                args.append({"-color_primaries", "bt709",
                             "-color_trc", "bt709",
                             "-colorspace", "bt709",
                             "-color_range", "tv"});
            }
            break;

        case CompressEncoder::HEVC_AMF:
            args.append({"-c:v", "hevc_amf",
                         "-quality", "quality",
                         "-rc", "cqp",
                         "-qp_i", QString::number(configuration.quality),
                         "-qp_p", QString::number(configuration.quality),
                         "-pix_fmt", "p010le"});
            if (hdrMode == HDRMode::HDR10) {
                args.append({"-color_primaries", "bt2020",
                             "-color_trc", "smpte2084",
                             "-colorspace", "bt2020nc"});
            } else {
                args.append({"-color_primaries", "bt709",
                             "-color_trc", "bt709",
                             "-colorspace", "bt709",
                             "-color_range", "tv"});
            }
            break;

        case CompressEncoder::HEVC_QSV:
            args.append({"-c:v", "hevc_qsv",
                         "-preset", "medium",
                         "-global_quality", QString::number(configuration.quality),
                         "-pix_fmt", "p010le"});
            if (hdrMode == HDRMode::HDR10) {
                args.append({"-color_primaries", "bt2020",
                             "-color_trc", "smpte2084",
                             "-colorspace", "bt2020nc"});
            } else {
                args.append({"-color_primaries", "bt709",
                             "-color_trc", "bt709",
                             "-colorspace", "bt709",
                             "-color_range", "tv"});
            }
            break;
    }

    // Anime-specific settings
    if (configuration.contentType == ContentType::Anime) {
        if (configuration.bFrames > 0) {
            args.append({"-bf", QString::number(configuration.bFrames)});
        }
        if (configuration.longGOPEnabled) {
            args.append({"-g", "240",
                         "-keyint_min", "240",
                         "-sc_threshold", "0"});
        }
    }

    args.append(outputPath);
    return args;
}
