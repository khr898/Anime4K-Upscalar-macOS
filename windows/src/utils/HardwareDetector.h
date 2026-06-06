#pragma once

#include <QString>
#include <QVector>

// Forward declarations of models to avoid circular headers
enum class VideoCodec;
enum class CompressEncoder;
enum class StreamEncoder;
struct DeviceHardwareProfile;

class HardwareDetector {
public:
    struct GPUInfo {
        QString name;
        enum Vendor { NVIDIA, AMD, Intel, Unknown } vendor = Unknown;
        bool supportsNVENC = false;
        bool supportsAMF = false;
        bool supportsQSV = false;
    };

    static GPUInfo detectPrimaryGPU();
    static QVector<VideoCodec> availableCodecs();
    static QVector<CompressEncoder> availableCompressEncoders();
    static QVector<StreamEncoder> availableStreamEncoders();
    static DeviceHardwareProfile getHardwareProfile();
};
