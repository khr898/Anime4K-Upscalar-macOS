#include "Models.h"
#include "../utils/HardwareDetector.h"
#include <QFileInfo>
#include <QDir>
#include <QLocale>
#include <QRegularExpression>
#include <QColor>

// MARK: - Device Hardware Profile

DeviceHardwareProfile DeviceHardwareProfile::detect() {
    return HardwareDetector::getHardwareProfile();
}

QString DeviceHardwareProfile::hqModeHeader() const {
    return "Anime4K (HQ)";
}

// MARK: - Anime4K Shader Files

QString shaderFileName(Anime4KShader shader) {
    switch (shader) {
        case Anime4KShader::ClampHighlights:         return "Anime4K_Clamp_Highlights.glsl";
        case Anime4KShader::RestoreCNN_VL:           return "Anime4K_Restore_CNN_VL.glsl";
        case Anime4KShader::RestoreCNN_M:            return "Anime4K_Restore_CNN_M.glsl";
        case Anime4KShader::RestoreCNN_S:            return "Anime4K_Restore_CNN_S.glsl";
        case Anime4KShader::RestoreCNNSoft_VL:       return "Anime4K_Restore_CNN_Soft_VL.glsl";
        case Anime4KShader::RestoreCNNSoft_M:        return "Anime4K_Restore_CNN_Soft_M.glsl";
        case Anime4KShader::RestoreCNNSoft_S:        return "Anime4K_Restore_CNN_Soft_S.glsl";
        case Anime4KShader::UpscaleCNN_x2_VL:        return "Anime4K_Upscale_CNN_x2_VL.glsl";
        case Anime4KShader::UpscaleCNN_x2_M:         return "Anime4K_Upscale_CNN_x2_M.glsl";
        case Anime4KShader::UpscaleCNN_x2_S:         return "Anime4K_Upscale_CNN_x2_S.glsl";
        case Anime4KShader::UpscaleDenoiseCNN_x2_VL: return "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl";
        case Anime4KShader::UpscaleDenoiseCNN_x2_M:  return "Anime4K_Upscale_Denoise_CNN_x2_M.glsl";
    }
    return QString();
}

bool isUpscaler(Anime4KShader shader) {
    switch (shader) {
        case Anime4KShader::UpscaleCNN_x2_VL:
        case Anime4KShader::UpscaleCNN_x2_M:
        case Anime4KShader::UpscaleCNN_x2_S:
        case Anime4KShader::UpscaleDenoiseCNN_x2_VL:
        case Anime4KShader::UpscaleDenoiseCNN_x2_M:
            return true;
        default:
            return false;
    }
}

// MARK: - Anime4K Processing Mode

QString displayName(Anime4KMode mode) {
    switch (mode) {
        case Anime4KMode::ModeA_HQ:         return "Mode A (HQ)";
        case Anime4KMode::ModeB_HQ:         return "Mode B (HQ)";
        case Anime4KMode::ModeC_HQ:         return "Mode C (HQ)";
        case Anime4KMode::ModeAA_HQ:        return "Mode A+A (HQ)";
        case Anime4KMode::ModeBB_HQ:        return "Mode B+B (HQ)";
        case Anime4KMode::ModeCA_HQ:        return "Mode C+A (HQ)";
        case Anime4KMode::ModeA_Fast:       return "Mode A (Fast)";
        case Anime4KMode::ModeB_Fast:       return "Mode B (Fast)";
        case Anime4KMode::ModeC_Fast:       return "Mode C (Fast)";
        case Anime4KMode::ModeAA_Fast:      return "Mode A+A (Fast)";
        case Anime4KMode::ModeBB_Fast:      return "Mode B+B (Fast)";
        case Anime4KMode::ModeCA_Fast:      return "Mode C+A (Fast)";
        case Anime4KMode::ModeAA_Fast_NoUp: return "Mode A+A (Fast) [No Upscale]";
        case Anime4KMode::ModeA_HQ_NoUp:    return "Mode A (HQ) [No Upscale]";
        case Anime4KMode::ModeAA_HQ_NoUp:   return "Mode A+A (HQ) [No Upscale]";
        case Anime4KMode::ESRGAN_Fast:      return "ESRGAN Fast";
        case Anime4KMode::ESRGAN_Quality:   return "ESRGAN Quality";
        case Anime4KMode::ESRGAN_General:   return "ESRGAN General";
        case Anime4KMode::SPECIAL_Fast:     return "SPECIAL: Fast";
        case Anime4KMode::SPECIAL_Quality:  return "SPECIAL: Quality";
        case Anime4KMode::SPECIAL_SDRescue: return "SPECIAL: SD Rescue";
        case Anime4KMode::SPECIAL_PiperSR_2x: return "SPECIAL: PiperSR 2x";
    }
    return QString();
}

QString subtitle(Anime4KMode mode) {
    switch (mode) {
        case Anime4KMode::ModeA_HQ:         return "Restore \u2192 Upscale";
        case Anime4KMode::ModeB_HQ:         return "Soft Restore \u2192 Upscale";
        case Anime4KMode::ModeC_HQ:         return "Upscale + Denoise";
        case Anime4KMode::ModeAA_HQ:        return "Double Restore \u2192 Upscale";
        case Anime4KMode::ModeBB_HQ:        return "Double Soft \u2192 Upscale";
        case Anime4KMode::ModeCA_HQ:        return "Denoise \u2192 Restore \u2192 Upscale";
        case Anime4KMode::ModeA_Fast:       return "Restore \u2192 Upscale";
        case Anime4KMode::ModeB_Fast:       return "Soft Restore \u2192 Upscale";
        case Anime4KMode::ModeC_Fast:       return "Upscale + Denoise";
        case Anime4KMode::ModeAA_Fast:      return "Double Restore \u2192 Upscale";
        case Anime4KMode::ModeBB_Fast:      return "Double Soft \u2192 Upscale";
        case Anime4KMode::ModeCA_Fast:      return "Denoise \u2192 Restore \u2192 Upscale";
        case Anime4KMode::ModeAA_Fast_NoUp: return "Restore Only (Fast)";
        case Anime4KMode::ModeA_HQ_NoUp:    return "Restore Only (HQ)";
        case Anime4KMode::ModeAA_HQ_NoUp:   return "Double Restore Only (HQ)";
        case Anime4KMode::ESRGAN_Fast:      return "Anime compact model (realesr-animevideov3)";
        case Anime4KMode::ESRGAN_Quality:   return "High quality anime model (realesrgan-x4plus-anime)";
        case Anime4KMode::ESRGAN_General:   return "General / live-action model (realesrgan-x4plus)";
#ifdef Q_OS_MAC
        case Anime4KMode::SPECIAL_Fast:     return "Core ML realesr-animevideov3 on Neural Engine";
        case Anime4KMode::SPECIAL_Quality:  return "Core ML realesrgan-x4plus-anime on Neural Engine";
        case Anime4KMode::SPECIAL_SDRescue: return "Anime4K Restore VL \u2192 Core ML realesr-animevideov3";
        case Anime4KMode::SPECIAL_PiperSR_2x: return "Core ML PiperSR 2x ANE-native upscaler";
#else
        case Anime4KMode::SPECIAL_Fast:     return "Vulkan realesr-animevideov3 upscaler";
        case Anime4KMode::SPECIAL_Quality:  return "Vulkan realesrgan-x4plus-anime upscaler";
        case Anime4KMode::SPECIAL_SDRescue: return "Anime4K Restore VL \u2192 Vulkan realesr-animevideov3";
        case Anime4KMode::SPECIAL_PiperSR_2x: return "Vulkan realesr-animevideov3 upscaler (fallback)";
#endif
    }
    return QString();
}

ModeCategory category(Anime4KMode mode) {
    switch (mode) {
        case Anime4KMode::ModeA_HQ:
        case Anime4KMode::ModeB_HQ:
        case Anime4KMode::ModeC_HQ:
        case Anime4KMode::ModeAA_HQ:
        case Anime4KMode::ModeBB_HQ:
        case Anime4KMode::ModeCA_HQ:
            return ModeCategory::HQ;
        case Anime4KMode::ModeA_Fast:
        case Anime4KMode::ModeB_Fast:
        case Anime4KMode::ModeC_Fast:
        case Anime4KMode::ModeAA_Fast:
        case Anime4KMode::ModeBB_Fast:
        case Anime4KMode::ModeCA_Fast:
            return ModeCategory::Fast;
        case Anime4KMode::ModeAA_Fast_NoUp:
        case Anime4KMode::ModeA_HQ_NoUp:
        case Anime4KMode::ModeAA_HQ_NoUp:
            return ModeCategory::NoUpscale;
        case Anime4KMode::ESRGAN_Fast:
        case Anime4KMode::ESRGAN_Quality:
        case Anime4KMode::ESRGAN_General:
            return ModeCategory::NeuralSR;
        case Anime4KMode::SPECIAL_Fast:
        case Anime4KMode::SPECIAL_Quality:
        case Anime4KMode::SPECIAL_SDRescue:
        case Anime4KMode::SPECIAL_PiperSR_2x:
            return ModeCategory::Special;
    }
    return ModeCategory::HQ;
}

bool involvesUpscaling(Anime4KMode mode) {
    return category(mode) != ModeCategory::NoUpscale;
}

bool isNeuralSR(Anime4KMode mode) {
    return mode == Anime4KMode::ESRGAN_Fast || mode == Anime4KMode::ESRGAN_Quality || mode == Anime4KMode::ESRGAN_General
        || mode == Anime4KMode::SPECIAL_Fast || mode == Anime4KMode::SPECIAL_Quality || mode == Anime4KMode::SPECIAL_SDRescue || mode == Anime4KMode::SPECIAL_PiperSR_2x;
}

bool isSpecialANE(Anime4KMode mode) {
    return mode == Anime4KMode::SPECIAL_Fast || mode == Anime4KMode::SPECIAL_Quality || mode == Anime4KMode::SPECIAL_SDRescue || mode == Anime4KMode::SPECIAL_PiperSR_2x;
}

QString realesrganModelName(Anime4KMode mode) {
    switch (mode) {
        case Anime4KMode::ESRGAN_Fast:
        case Anime4KMode::SPECIAL_Fast:
        case Anime4KMode::SPECIAL_SDRescue:
        case Anime4KMode::SPECIAL_PiperSR_2x: return "realesr-animevideov3";
        case Anime4KMode::ESRGAN_Quality:
        case Anime4KMode::SPECIAL_Quality:    return "realesrgan-x4plus-anime";
        case Anime4KMode::ESRGAN_General:    return "realesrgan-x4plus";
        default:                              return QString();
    }
}

NcnnModel resolveNcnnModel(Anime4KMode mode, int target, const QString& modelsDir) {
    auto exists = [&](const QString& n){ return QFileInfo::exists(QDir(modelsDir).filePath(n + ".param")); };
    QString base = realesrganModelName(mode);
    if (base == "realesr-animevideov3") {
        int s = (target == 2 || target == 3 || target == 4) ? target : 4;
        QString ex = QString("realesr-animevideov3-x%1").arg(s);
        if (exists(ex)) return { ex, s };
        if (exists("realesr-animevideov3")) return { "realesr-animevideov3", s };
        return { ex, s };
    }
    return { base, 4 };  // x4plus[-anime] are 4x-only
}

QVector<Anime4KShader> shaderPipeline(Anime4KMode mode) {
    if (isNeuralSR(mode) || isSpecialANE(mode)) return {};
    switch (mode) {
        case Anime4KMode::ModeA_HQ:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_VL, Anime4KShader::UpscaleCNN_x2_VL, Anime4KShader::UpscaleCNN_x2_M };
        case Anime4KMode::ModeB_HQ:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNNSoft_VL, Anime4KShader::UpscaleCNN_x2_VL, Anime4KShader::UpscaleCNN_x2_M };
        case Anime4KMode::ModeC_HQ:
            return { Anime4KShader::ClampHighlights, Anime4KShader::UpscaleDenoiseCNN_x2_VL, Anime4KShader::UpscaleCNN_x2_M };
        case Anime4KMode::ModeAA_HQ:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_VL, Anime4KShader::UpscaleCNN_x2_VL, Anime4KShader::RestoreCNN_M, Anime4KShader::UpscaleCNN_x2_M };
        case Anime4KMode::ModeBB_HQ:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNNSoft_VL, Anime4KShader::UpscaleCNN_x2_VL, Anime4KShader::RestoreCNNSoft_M, Anime4KShader::UpscaleCNN_x2_M };
        case Anime4KMode::ModeCA_HQ:
            return { Anime4KShader::ClampHighlights, Anime4KShader::UpscaleDenoiseCNN_x2_VL, Anime4KShader::RestoreCNN_M, Anime4KShader::UpscaleCNN_x2_M };
        case Anime4KMode::ModeA_Fast:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_M, Anime4KShader::UpscaleCNN_x2_M, Anime4KShader::UpscaleCNN_x2_S };
        case Anime4KMode::ModeB_Fast:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNNSoft_M, Anime4KShader::UpscaleCNN_x2_M, Anime4KShader::UpscaleCNN_x2_S };
        case Anime4KMode::ModeC_Fast:
            return { Anime4KShader::ClampHighlights, Anime4KShader::UpscaleDenoiseCNN_x2_M, Anime4KShader::UpscaleCNN_x2_S };
        case Anime4KMode::ModeAA_Fast:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_M, Anime4KShader::UpscaleCNN_x2_M, Anime4KShader::RestoreCNN_S, Anime4KShader::UpscaleCNN_x2_S };
        case Anime4KMode::ModeBB_Fast:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNNSoft_M, Anime4KShader::UpscaleCNN_x2_M, Anime4KShader::RestoreCNNSoft_S, Anime4KShader::UpscaleCNN_x2_S };
        case Anime4KMode::ModeCA_Fast:
            return { Anime4KShader::ClampHighlights, Anime4KShader::UpscaleDenoiseCNN_x2_M, Anime4KShader::RestoreCNN_S, Anime4KShader::UpscaleCNN_x2_S };
        case Anime4KMode::ModeAA_Fast_NoUp:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_M, Anime4KShader::RestoreCNN_S };
        case Anime4KMode::ModeA_HQ_NoUp:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_VL };
        case Anime4KMode::ModeAA_HQ_NoUp:
            return { Anime4KShader::ClampHighlights, Anime4KShader::RestoreCNN_VL, Anime4KShader::RestoreCNN_M };
    }
    return {};
}

// MARK: - Mode Category

QString displayName(ModeCategory cat) {
    switch (cat) {
        case ModeCategory::HQ:        return "Anime4K (HQ)";
        case ModeCategory::Fast:      return "Anime4K (Fast)";
        case ModeCategory::NoUpscale: return "Anime4K (No Upscale - Restore Only)";
        case ModeCategory::NeuralSR:  return "Neural Super Resolution (Real-ESRGAN)";
        case ModeCategory::Special:   return "\u26a1 Special (Apple Silicon Only)";
    }
    return QString();
}

QString symbolName(ModeCategory cat) {
    switch (cat) {
        case ModeCategory::HQ:        return "star.fill";
        case ModeCategory::Fast:      return "hare.fill";
        case ModeCategory::NoUpscale: return "arrow.uturn.backward";
        case ModeCategory::NeuralSR:  return "wand";
        case ModeCategory::Special:   return "bolt.fill";
    }
    return QString();
}

QVector<Anime4KMode> modesForCategory(ModeCategory cat) {
#ifndef Q_OS_MAC
    if (cat == ModeCategory::Special) return {};
#endif
    QVector<Anime4KMode> results;
    for (int i = 1; i <= 22; ++i) {
        Anime4KMode mode = static_cast<Anime4KMode>(i);
        if (category(mode) == cat) {
            results.append(mode);
        }
    }
    return results;
}

// MARK: - Target Resolution

QString displayName(TargetResolution res) {
    switch (res) {
        case TargetResolution::KeepOriginal: return "Original (1x)";
        case TargetResolution::Double:       return "2x Upscale";
        case TargetResolution::Quadruple:    return "4x Upscale";
    }
    return QString();
}

QString subtitle(TargetResolution res) {
    switch (res) {
        case TargetResolution::KeepOriginal: return "Keep original resolution";
        case TargetResolution::Double:       return "e.g., 1080p \u2192 4K";
        case TargetResolution::Quadruple:    return "e.g., 1080p \u2192 8K";
    }
    return QString();
}

QString symbolName(TargetResolution res) {
    switch (res) {
        case TargetResolution::KeepOriginal: return "equal.square";
        case TargetResolution::Double:       return "arrow.up.left.and.arrow.down.right";
        case TargetResolution::Quadruple:    return "arrow.up.left.and.arrow.down.right.circle";
    }
    return QString();
}

int scaleFactor(TargetResolution res) {
    return static_cast<int>(res);
}

// MARK: - Video Codec (Windows Specific)

QString displayName(VideoCodec codec) {
    switch (codec) {
        case VideoCodec::HEVC_NVENC: return "HEVC (NVIDIA RTX)";
        case VideoCodec::HEVC_AMF:   return "HEVC (AMD)";
        case VideoCodec::HEVC_QSV:   return "HEVC (Intel)";
        case VideoCodec::H264_NVENC: return "H.264 (NVIDIA RTX)";
        case VideoCodec::H264_AMF:   return "H.264 (AMD)";
        case VideoCodec::H264_QSV:   return "H.264 (Intel)";
        case VideoCodec::SVT_AV1:     return "AV1 (Software)";
    }
    return QString();
}

QString subtitle(VideoCodec codec) {
    DeviceHardwareProfile profile = DeviceHardwareProfile::detect();
    switch (codec) {
        case VideoCodec::HEVC_NVENC: return QString("NVIDIA NVENC on %1 \u2014 Fast hardware encoding").arg(profile.gpuName);
        case VideoCodec::HEVC_AMF:   return QString("AMD AMF on %1 \u2014 Fast hardware encoding").arg(profile.gpuName);
        case VideoCodec::HEVC_QSV:   return QString("Intel QSV on %1 \u2014 Fast hardware encoding").arg(profile.gpuName);
        case VideoCodec::H264_NVENC: return QString("NVIDIA NVENC on %1 \u2014 Maximum compatibility").arg(profile.gpuName);
        case VideoCodec::H264_AMF:   return QString("AMD AMF on %1 \u2014 Maximum compatibility").arg(profile.gpuName);
        case VideoCodec::H264_QSV:   return QString("Intel QSV on %1 \u2014 Maximum compatibility").arg(profile.gpuName);
        case VideoCodec::SVT_AV1:     return QString("SVT-AV1 on %1-core CPU \u2014 Best quality compression").arg(profile.cpuCoreCount);
    }
    return QString();
}

QString encoderName(VideoCodec codec) {
    switch (codec) {
        case VideoCodec::HEVC_NVENC: return "hevc_nvenc";
        case VideoCodec::HEVC_AMF:   return "hevc_amf";
        case VideoCodec::HEVC_QSV:   return "hevc_qsv";
        case VideoCodec::H264_NVENC: return "h264_nvenc";
        case VideoCodec::H264_AMF:   return "h264_amf";
        case VideoCodec::H264_QSV:   return "h264_qsv";
        case VideoCodec::SVT_AV1:     return "libsvtav1";
    }
    return QString();
}

QString pixelFormat(VideoCodec codec) {
    switch (codec) {
        case VideoCodec::HEVC_NVENC:
        case VideoCodec::HEVC_AMF:
        case VideoCodec::HEVC_QSV:
            return "p010le";
        case VideoCodec::H264_NVENC:
        case VideoCodec::H264_AMF:
        case VideoCodec::H264_QSV:
            return "nv12";
        case VideoCodec::SVT_AV1:
            return "yuv420p10le";
    }
    return "yuv420p";
}

bool usesCRF(VideoCodec codec) {
    return codec == VideoCodec::SVT_AV1;
}

int maxQuality(VideoCodec codec) {
    return codec == VideoCodec::SVT_AV1 ? 63 : 100;
}

// MARK: - Compression Mode

CompressionMode CompressionMode::visuallyLossless() {
    return { VisuallyLossless, 0 };
}

CompressionMode CompressionMode::balanced() {
    return { Balanced, 0 };
}

CompressionMode CompressionMode::customQuality(int val) {
    return { CustomQuality, val };
}

CompressionMode CompressionMode::fixedBitrate(int mbps) {
    return { FixedBitrate, mbps };
}

int CompressionMode::qualityValue(VideoCodec codec) const {
    switch (type) {
        case VisuallyLossless:
            return usesCRF(codec) ? 24 : 68;
        case Balanced:
            return usesCRF(codec) ? 30 : 65;
        case CustomQuality:
            return value;
        case FixedBitrate:
            return 0;
    }
    return 0;
}

bool CompressionMode::isFixedBitrate() const {
    return type == FixedBitrate;
}

int CompressionMode::bitrateMbps() const {
    return (type == FixedBitrate) ? value : 0;
}

QString CompressionMode::displayName() const {
    switch (type) {
        case VisuallyLossless: return "Visually Lossless";
        case Balanced:         return "Balanced";
        case CustomQuality:    return QString("Custom Quality (%1)").arg(value);
        case FixedBitrate:     return QString("Fixed Bitrate (%1 Mbps)").arg(value);
    }
    return QString();
}

QString CompressionMode::subtitle(VideoCodec codec) const {
    switch (type) {
        case VisuallyLossless:
            return usesCRF(codec) ? "CRF 24 (Recommended)" : "Quality 68 (Recommended)";
        case Balanced:
            return usesCRF(codec) ? "CRF 30" : "Quality 65";
        case CustomQuality:
            return usesCRF(codec) ? QString("CRF %1").arg(value) : QString("Quality %1").arg(value);
        case FixedBitrate:
            return QString("%1 Mbps (Predictable file size)").arg(value);
    }
    return QString();
}

// MARK: - Compression Preset

QString displayName(CompressionPreset preset) {
    switch (preset) {
        case CompressionPreset::VisuallyLossless: return "Visually Lossless";
        case CompressionPreset::Balanced:         return "Balanced";
        case CompressionPreset::CustomQuality:    return "Custom Quality";
        case CompressionPreset::FixedBitrate:     return "Custom Bitrate";
    }
    return QString();
}

QString symbolName(CompressionPreset preset) {
    switch (preset) {
        case CompressionPreset::VisuallyLossless: return "eye";
        case CompressionPreset::Balanced:         return "scalemass";
        case CompressionPreset::CustomQuality:    return "slider.horizontal.3";
        case CompressionPreset::FixedBitrate:     return "gauge.with.dots.needle.67percent";
    }
    return QString();
}

// MARK: - Job State

QString displayName(JobState state) {
    switch (state) {
        case JobState::Idle:      return "Ready";
        case JobState::Queued:    return "Queued";
        case JobState::Running:   return "Processing";
        case JobState::Completed: return "Completed";
        case JobState::Failed:    return "Failed";
        case JobState::Cancelled: return "Cancelled";
    }
    return QString();
}

QString symbolName(JobState state) {
    switch (state) {
        case JobState::Idle:      return "circle";
        case JobState::Queued:    return "clock";
        case JobState::Running:   return "circle.dashed";
        case JobState::Completed: return "checkmark.circle.fill";
        case JobState::Failed:    return "xmark.circle.fill";
        case JobState::Cancelled: return "stop.circle.fill";
    }
    return QString();
}

QColor tintColor(JobState state) {
    switch (state) {
        case JobState::Idle:      return QColor(142, 142, 147); // secondary / gray
        case JobState::Queued:    return QColor(255, 149, 0);   // orange
        case JobState::Running:   return QColor(0, 122, 255);   // blue
        case JobState::Completed: return QColor(52, 199, 89);   // green
        case JobState::Failed:    return QColor(255, 59, 48);   // red
        case JobState::Cancelled: return QColor(255, 204, 0);   // yellow
    }
    return QColor(142, 142, 147);
}

bool isTerminal(JobState state) {
    return state == JobState::Completed || state == JobState::Failed || state == JobState::Cancelled;
}

// MARK: - Video File

VideoFile VideoFile::fromPath(const QString& path) {
    QFileInfo fileInfo(path);
    VideoFile vf;
    vf.id = QUuid::createUuid();
    vf.filePath = fileInfo.absoluteFilePath();
    vf.fileName = fileInfo.completeBaseName();
    vf.fileExtension = fileInfo.suffix().toLower();
    vf.fileSizeBytes = fileInfo.size();
    vf.durationSeconds = std::nullopt;
    vf.width = std::nullopt;
    vf.height = std::nullopt;
    vf.frameRate = std::nullopt;
    return vf;
}

QString VideoFile::formattedFileSize() const {
    return QLocale().formattedDataSize(fileSizeBytes, 2, QLocale::DataSizeSIFormat);
}

QString VideoFile::resolutionString() const {
    if (!width.has_value() || !height.has_value()) return QString();
    return QString("%1\u00d7%2").arg(width.value()).arg(height.value());
}

QString VideoFile::formattedDuration() const {
    if (!durationSeconds.has_value()) return QString();
    double dur = durationSeconds.value();
    int hours = static_cast<int>(dur) / 3600;
    int minutes = (static_cast<int>(dur) % 3600) / 60;
    int seconds = static_cast<int>(dur) % 60;
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

QString VideoFile::outputFileName(Anime4KMode mode, TargetResolution scale) const {
    return QString("%1_Mode%2_%3x.%4")
        .arg(fileName)
        .arg(static_cast<int>(mode))
        .arg(scaleFactor(scale))
        .arg(fileExtension);
}

QString VideoFile::outputFilePath(Anime4KMode mode, TargetResolution scale, const QString& outputDir) const {
    QString dir = outputDir.isEmpty() ? QFileInfo(filePath).absolutePath() : outputDir;
    return QDir(dir).filePath(outputFileName(mode, scale));
}

// MARK: - Supported Video Extensions

const QSet<QString>& supportedVideoExtensions() {
    static const QSet<QString> extensions = {"mp4", "mkv", "mov", "avi", "webm", "flv", "ts"};
    return extensions;
}

// MARK: - Job Configuration

JobConfiguration JobConfiguration::defaultConfig() {
    return {
        Anime4KMode::ModeA_HQ,
        TargetResolution::Double,
        VideoCodec::HEVC_NVENC,
        CompressionMode::visuallyLossless(),
        true,
        6
    };
}

// MARK: - FFmpeg Progress Data

double FFmpegProgress::timeSeconds() const {
    QStringList parts = time.split(':');
    if (parts.size() != 3) return 0.0;
    bool okH, okM, okS;
    double h = parts[0].toDouble(&okH);
    double m = parts[1].toDouble(&okM);
    double s = parts[2].toDouble(&okS);
    if (!okH || !okM || !okS) return 0.0;
    return h * 3600.0 + m * 60.0 + s;
}

std::optional<FFmpegProgress> FFmpegProgress::parse(const QString& line) {
    if (!line.contains("frame=") || !line.contains("time=")) return std::nullopt;

    auto extract = [](const QString& key, const QString& s, const QString& fallback = "") -> QString {
        int idx = s.indexOf(key);
        if (idx == -1) return fallback;
        int valStart = idx + key.length();
        while (valStart < s.length() && s[valStart].isSpace()) {
            valStart++;
        }
        int valEnd = valStart;
        while (valEnd < s.length() && !s[valEnd].isSpace()) {
            valEnd++;
        }
        if (valStart == valEnd) return fallback;
        return s.mid(valStart, valEnd - valStart);
    };

    QString frameStr = extract("frame=", line, "0");
    QString fpsStr = extract("fps=", line, "0");

    bool ok1, ok2;
    int frame = frameStr.toInt(&ok1);
    double fps = fpsStr.toDouble(&ok2);
    if (!ok1 || !ok2) return std::nullopt;

    FFmpegProgress progress;
    progress.frame = frame;
    progress.fps = fps;
    progress.size = extract("size=", line, "0kB");
    progress.time = extract("time=", line, "00:00:00.00");
    progress.bitrate = extract("bitrate=", line, "0kbits/s");
    progress.speed = extract("speed=", line, "0x");
    return progress;
}

// MARK: - Filter Graph Builder

QString FilterGraphBuilder::build(
    Anime4KMode mode,
    TargetResolution resolution,
    VideoCodec codec,
    const QString& shaderDirectory
) {
    QStringList filterComponents;
    int currentScale = 1;

    for (Anime4KShader shader : shaderPipeline(mode)) {
        QString shaderPath = QDir(shaderDirectory).filePath(shaderFileName(shader));
        // Escape single quotes for FFmpeg filter paths
        QString escapedPath = shaderPath;
        escapedPath.replace("'", "'\\''");

        if (isUpscaler(shader)) {
            if (currentScale < scaleFactor(resolution)) {
                filterComponents.append(
                    QString("libplacebo=w=iw*2:h=ih*2:custom_shader_path='%1'").arg(escapedPath)
                );
                currentScale *= 2;
            }
        } else {
            filterComponents.append(
                QString("libplacebo=custom_shader_path='%1'").arg(escapedPath)
            );
        }
    }

    if (!filterComponents.isEmpty()) {
        filterComponents.prepend("hwupload");
        filterComponents.append("hwdownload");
    }

    filterComponents.append(QString("format=%1").arg(pixelFormat(codec)));
    return filterComponents.join(",");
}

// MARK: - FFmpeg Argument Builder

QStringList FFmpegArgumentBuilder::build(
    const QString& inputPath,
    const QString& outputPath,
    const JobConfiguration& configuration,
    const QString& shaderDirectory
) {
    QString filterGraph = FilterGraphBuilder::build(
        configuration.mode,
        configuration.resolution,
        configuration.codec,
        shaderDirectory
    );

    QStringList args;
    args.append({"-init_hw_device", "vulkan=vk:0", "-filter_hw_device", "vk"});
    args.append("-y");
    args.append({"-threads", "0"});
    args.append({"-i", inputPath});

    // Video filter graph
    args.append({"-vf", filterGraph});

    // Video codec
    args.append({"-c:v", encoderName(configuration.codec)});

    // Stream mapping: first video, all audio, all subtitles
    args.append({"-map", "0:v:0"});
    args.append({"-map", "0:a?"});
    args.append({"-map", "0:s?"});

    // Copy audio and subtitle streams
    args.append({"-c:a", "copy"});
    args.append({"-c:s", "copy"});

    // Codec specific arguments
    VideoCodec codec = configuration.codec;
    switch (codec) {
        case VideoCodec::HEVC_NVENC:
            args.append({"-profile:v", "main10"});
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                args.append({"-minrate", QString("%1k").arg(static_cast<int>(mbps * 900))});
                args.append({"-maxrate", QString("%1k").arg(static_cast<int>(mbps * 1100))});
                args.append({"-bufsize", QString("%1k").arg(static_cast<int>(mbps * 1500))});
            } else {
                int qVal = configuration.compression.qualityValue(codec);
                args.append({"-preset", "p4"});
                args.append({"-tune", "hq"});
                args.append({"-rc", "vbr"});
                args.append({"-cq", QString::number(qVal)});
                args.append({"-b:v", "0"});
            }
            break;

        case VideoCodec::HEVC_AMF:
            args.append({"-profile:v", "main10"});
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
            } else {
                int qVal = configuration.compression.qualityValue(codec);
                args.append({"-quality", "quality"});
                args.append({"-rc", "cqp"});
                args.append({"-qp_i", QString::number(qVal)});
                args.append({"-qp_p", QString::number(qVal)});
            }
            break;

        case VideoCodec::HEVC_QSV:
            args.append({"-profile:v", "main10"});
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
            } else {
                int qVal = configuration.compression.qualityValue(codec);
                args.append({"-preset", "medium"});
                args.append({"-global_quality", QString::number(qVal)});
            }
            break;

        case VideoCodec::H264_NVENC:
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                args.append({"-minrate", QString("%1k").arg(static_cast<int>(mbps * 900))});
                args.append({"-maxrate", QString("%1k").arg(static_cast<int>(mbps * 1100))});
                args.append({"-bufsize", QString("%1k").arg(static_cast<int>(mbps * 1500))});
            } else {
                int qVal = configuration.compression.qualityValue(codec);
                args.append({"-preset", "p4"});
                args.append({"-tune", "hq"});
                args.append({"-rc", "vbr"});
                args.append({"-cq", QString::number(qVal)});
                args.append({"-b:v", "0"});
            }
            break;

        case VideoCodec::H264_AMF:
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
            } else {
                int qVal = configuration.compression.qualityValue(codec);
                args.append({"-quality", "quality"});
                args.append({"-rc", "cqp"});
                args.append({"-qp_i", QString::number(qVal)});
                args.append({"-qp_p", QString::number(qVal)});
            }
            break;

        case VideoCodec::H264_QSV:
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
            } else {
                int qVal = configuration.compression.qualityValue(codec);
                args.append({"-preset", "medium"});
                args.append({"-global_quality", QString::number(qVal)});
            }
            break;

        case VideoCodec::SVT_AV1:
            args.append({"-preset", QString::number(configuration.svtAV1Preset)});
            args.append({"-svtav1-params", "tune=0"});
            if (configuration.compression.isFixedBitrate()) {
                int mbps = configuration.compression.bitrateMbps();
                args.append({"-b:v", QString("%1k").arg(mbps * 1000)});
                args.append({"-maxrate", QString("%1k").arg(static_cast<int>(mbps * 1100))});
                args.append({"-bufsize", QString("%1k").arg(static_cast<int>(mbps * 1500))});
            } else {
                int crfVal = configuration.compression.qualityValue(codec);
                args.append({"-crf", QString::number(crfVal)});
            }
            break;
    }

    if (configuration.longGOPEnabled) {
        args.append({"-g", "240"});
    }

    args.append({"-progress", "pipe:1"});
    args.append(outputPath);

    return args;
}

// MARK: - Processing Job Implementation

ProcessingJob::ProcessingJob(const VideoFile& f, const JobConfiguration& c, const QString& outputDirectory, QObject* parent)
    : QObject(parent), file(f), configuration(c) {
    id = QUuid::createUuid();
    outputPath = file.outputFilePath(configuration.mode, configuration.resolution, outputDirectory);
}

double ProcessingJob::elapsedTime() const {
    if (!startDate.isValid()) return 0.0;
    QDateTime end = endDate.isValid() ? endDate : QDateTime::currentDateTime();
    return startDate.msecsTo(end) / 1000.0;
}

QString ProcessingJob::formattedElapsedTime() const {
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

void ProcessingJob::appendLog(const QString& line) {
    logLines.append(line);
    int overflow = logLines.count() - 500;
    if (overflow > 0) {
        logLines.erase(logLines.begin(), logLines.begin() + overflow);
    }
}
