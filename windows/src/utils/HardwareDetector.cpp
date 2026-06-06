#include "HardwareDetector.h"
#include "../models/Models.h"
#include "../models/CompressModels.h"
#include "../models/StreamOptimizeModels.h"

#include <QSettings>
#include <thread>

// Windows-specific DXGI headers
#include <windows.h>
#include <dxgi.h>

HardwareDetector::GPUInfo HardwareDetector::detectPrimaryGPU() {
    static GPUInfo cachedInfo;
    static bool detected = false;
    if (detected) return cachedInfo;

    cachedInfo.name = "Default GPU";
    cachedInfo.vendor = GPUInfo::Unknown;
    cachedInfo.supportsNVENC = false;
    cachedInfo.supportsAMF = false;
    cachedInfo.supportsQSV = false;

    IDXGIFactory1* pFactory = nullptr;
    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void**)&pFactory);
    if (SUCCEEDED(hr) && pFactory) {
        IDXGIAdapter1* pAdapter = nullptr;
        // Enum the primary adapter (index 0)
        if (SUCCEEDED(pFactory->EnumAdapters1(0, &pAdapter)) && pAdapter) {
            DXGI_ADAPTER_DESC1 desc;
            if (SUCCEEDED(pAdapter->GetDesc1(&desc))) {
                cachedInfo.name = QString::fromWCharArray(desc.Description);
                if (desc.VendorId == 0x10DE) {
                    cachedInfo.vendor = GPUInfo::NVIDIA;
                    cachedInfo.supportsNVENC = true;
                } else if (desc.VendorId == 0x1002 || desc.VendorId == 0x1022) {
                    cachedInfo.vendor = GPUInfo::AMD;
                    cachedInfo.supportsAMF = true;
                } else if (desc.VendorId == 0x8086) {
                    cachedInfo.vendor = GPUInfo::Intel;
                    cachedInfo.supportsQSV = true;
                }
            }
            pAdapter->Release();
        }
        pFactory->Release();
    }

    detected = true;
    return cachedInfo;
}

QVector<VideoCodec> HardwareDetector::availableCodecs() {
    GPUInfo gpu = detectPrimaryGPU();
    QVector<VideoCodec> codecs;

    if (gpu.supportsNVENC) {
        codecs.append(VideoCodec::HEVC_NVENC);
        codecs.append(VideoCodec::H264_NVENC);
    }
    if (gpu.supportsAMF) {
        codecs.append(VideoCodec::HEVC_AMF);
        codecs.append(VideoCodec::H264_AMF);
    }
    if (gpu.supportsQSV) {
        codecs.append(VideoCodec::HEVC_QSV);
        codecs.append(VideoCodec::H264_QSV);
    }

    // Software AV1 is always available
    codecs.append(VideoCodec::SVT_AV1);
    return codecs;
}

QVector<CompressEncoder> HardwareDetector::availableCompressEncoders() {
    GPUInfo gpu = detectPrimaryGPU();
    QVector<CompressEncoder> encoders;

    if (gpu.supportsNVENC) {
        encoders.append(CompressEncoder::HEVC_NVENC);
    }
    if (gpu.supportsAMF) {
        encoders.append(CompressEncoder::HEVC_AMF);
    }
    if (gpu.supportsQSV) {
        encoders.append(CompressEncoder::HEVC_QSV);
    }

    encoders.append(CompressEncoder::SVT_AV1);
    return encoders;
}

QVector<StreamEncoder> HardwareDetector::availableStreamEncoders() {
    GPUInfo gpu = detectPrimaryGPU();
    QVector<StreamEncoder> encoders;

    if (gpu.supportsNVENC) {
        encoders.append(StreamEncoder::HEVC_NVENC);
        encoders.append(StreamEncoder::H264_NVENC);
    }
    if (gpu.supportsAMF) {
        encoders.append(StreamEncoder::HEVC_AMF);
        encoders.append(StreamEncoder::H264_AMF);
    }
    if (gpu.supportsQSV) {
        encoders.append(StreamEncoder::HEVC_QSV);
        encoders.append(StreamEncoder::H264_QSV);
    }

    encoders.append(StreamEncoder::SVT_AV1);
    return encoders;
}

DeviceHardwareProfile HardwareDetector::getHardwareProfile() {
    DeviceHardwareProfile profile;

    // Detect CPU Name via Windows Registry
    QSettings settings("HKEY_LOCAL_MACHINE\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", QSettings::NativeFormat);
    profile.chipName = settings.value("ProcessorNameString").toString().trimmed();
    if (profile.chipName.isEmpty()) {
        profile.chipName = "Windows Device";
    }

    // Detect GPU
    GPUInfo gpu = detectPrimaryGPU();
    profile.gpuName = gpu.name;

    // Detect Cores
    profile.cpuCoreCount = static_cast<int>(std::thread::hardware_concurrency());
    if (profile.cpuCoreCount <= 0) {
        profile.cpuCoreCount = 4; // Default fallback
    }

    return profile;
}
