#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QUuid>
#include <QSet>
#include <QColor>
#include <QDateTime>
#include <optional>

// Forward declarations
class QProcess;

// MARK: - Device Hardware Profile

struct DeviceHardwareProfile {
    QString chipName;     // CPU brand string
    QString gpuName;      // GPU name
    int cpuCoreCount;     // Core count

    static DeviceHardwareProfile detect();
    QString hqModeHeader() const;
};

// MARK: - Anime4K Shader Files

enum class Anime4KShader {
    ClampHighlights,
    RestoreCNN_VL,
    RestoreCNN_M,
    RestoreCNN_S,
    RestoreCNNSoft_VL,
    RestoreCNNSoft_M,
    RestoreCNNSoft_S,
    UpscaleCNN_x2_VL,
    UpscaleCNN_x2_M,
    UpscaleCNN_x2_S,
    UpscaleDenoiseCNN_x2_VL,
    UpscaleDenoiseCNN_x2_M
};

QString shaderFileName(Anime4KShader shader);
bool isUpscaler(Anime4KShader shader);

// MARK: - Anime4K Processing Mode

enum class Anime4KMode {
    ModeA_HQ = 1,
    ModeB_HQ = 2,
    ModeC_HQ = 3,
    ModeAA_HQ = 4,
    ModeBB_HQ = 5,
    ModeCA_HQ = 6,
    ModeA_Fast = 7,
    ModeB_Fast = 8,
    ModeC_Fast = 9,
    ModeAA_Fast = 10,
    ModeBB_Fast = 11,
    ModeCA_Fast = 12,
    ModeAA_Fast_NoUp = 13,
    ModeA_HQ_NoUp = 14,
    ModeAA_HQ_NoUp = 15,
    ESRGAN_Fast = 16,
    ESRGAN_Quality = 17,
    ESRGAN_General = 18,
    SPECIAL_Fast = 19,
    SPECIAL_Quality = 20,
    SPECIAL_SDRescue = 21,
    SPECIAL_PiperSR_2x = 22
};

QString displayName(Anime4KMode mode);
QString subtitle(Anime4KMode mode);
enum class ModeCategory { HQ, Fast, NoUpscale, NeuralSR, Special };
ModeCategory category(Anime4KMode mode);
bool involvesUpscaling(Anime4KMode mode);
bool isNeuralSR(Anime4KMode mode);
bool isSpecialANE(Anime4KMode mode);
QString realesrganModelName(Anime4KMode mode);
QVector<Anime4KShader> shaderPipeline(Anime4KMode mode);

// MARK: - Mode Category

QString displayName(ModeCategory cat);
QString symbolName(ModeCategory cat);
QVector<Anime4KMode> modesForCategory(ModeCategory cat);

// MARK: - Target Resolution

enum class TargetResolution { KeepOriginal = 1, Double = 2, Quadruple = 4 };
QString displayName(TargetResolution res);
QString subtitle(TargetResolution res);
QString symbolName(TargetResolution res);
int scaleFactor(TargetResolution res);

// MARK: - Video Codec (Windows Specific)

enum class VideoCodec {
    HEVC_NVENC,     // hevc_nvenc (NVIDIA)
    HEVC_AMF,       // hevc_amf (AMD)
    HEVC_QSV,       // hevc_qsv (Intel)
    H264_NVENC,     // h264_nvenc (NVIDIA)
    H264_AMF,       // h264_amf (AMD)
    H264_QSV,       // h264_qsv (Intel)
    SVT_AV1         // libsvtav1 (Software)
};

QString displayName(VideoCodec codec);
QString subtitle(VideoCodec codec);
QString encoderName(VideoCodec codec);
QString pixelFormat(VideoCodec codec);
bool usesCRF(VideoCodec codec);
int maxQuality(VideoCodec codec);

// MARK: - Compression Mode

struct CompressionMode {
    enum Type { VisuallyLossless, Balanced, CustomQuality, FixedBitrate };
    Type type;
    int value; // Quality (0-100 or 0-63) or Bitrate (Mbps)

    static CompressionMode visuallyLossless();
    static CompressionMode balanced();
    static CompressionMode customQuality(int val);
    static CompressionMode fixedBitrate(int mbps);

    int qualityValue(VideoCodec codec) const;
    bool isFixedBitrate() const;
    int bitrateMbps() const;
    QString displayName() const;
    QString subtitle(VideoCodec codec) const;

    bool operator==(const CompressionMode& other) const {
        return type == other.type && value == other.value;
    }
};

// MARK: - Compression Preset

enum class CompressionPreset { VisuallyLossless, Balanced, CustomQuality, FixedBitrate };
QString displayName(CompressionPreset preset);
QString symbolName(CompressionPreset preset);

// MARK: - Job State

enum class JobState { Idle, Queued, Running, Completed, Failed, Cancelled };
QString displayName(JobState state);
QString symbolName(JobState state);
QColor tintColor(JobState state);
bool isTerminal(JobState state);

// MARK: - Video File

struct VideoFile {
    QUuid id;
    QString filePath;
    QString fileName;
    QString fileExtension;
    qint64 fileSizeBytes;
    std::optional<double> durationSeconds;
    std::optional<int> width;
    std::optional<int> height;
    std::optional<double> frameRate;

    static VideoFile fromPath(const QString& path);
    QString formattedFileSize() const;
    QString resolutionString() const;
    QString formattedDuration() const;
    QString outputFileName(Anime4KMode mode, TargetResolution scale) const;
    QString outputFilePath(Anime4KMode mode, TargetResolution scale, const QString& outputDir = QString()) const;

    bool operator==(const VideoFile& other) const {
        return id == other.id;
    }
};

// MARK: - Supported Video Extensions

const QSet<QString>& supportedVideoExtensions();

// MARK: - Job Configuration

struct JobConfiguration {
    Anime4KMode mode;
    TargetResolution resolution;
    VideoCodec codec;
    CompressionMode compression;
    bool longGOPEnabled;

    static JobConfiguration defaultConfig();

    bool operator==(const JobConfiguration& other) const {
        return mode == other.mode &&
               resolution == other.resolution &&
               codec == other.codec &&
               compression == other.compression &&
               longGOPEnabled == other.longGOPEnabled;
    }
};

// MARK: - Processing Job

class ProcessingJob : public QObject {
    Q_OBJECT
public:
    ProcessingJob(const VideoFile& file, const JobConfiguration& configuration, const QString& outputDirectory = QString(), QObject* parent = nullptr);

    QUuid id;
    VideoFile file;
    JobConfiguration configuration;

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

// MARK: - FFmpeg Progress Data

struct FFmpegProgress {
    int frame;
    double fps;
    QString size;
    QString time;
    QString bitrate;
    QString speed;

    double timeSeconds() const;
    static std::optional<FFmpegProgress> parse(const QString& line);
};

// MARK: - Filter Graph Builder

class FilterGraphBuilder {
public:
    static QString build(
        Anime4KMode mode,
        TargetResolution resolution,
        VideoCodec codec,
        const QString& shaderDirectory
    );
};

// MARK: - FFmpeg Argument Builder

class FFmpegArgumentBuilder {
public:
    static QStringList build(
        const QString& inputPath,
        const QString& outputPath,
        const JobConfiguration& configuration,
        const QString& shaderDirectory
    );
};
