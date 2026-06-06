# Anime4K Upscaler

A native application for upscaling anime and other animated content using Anime4K shaders and deep learning Neural Super-Resolution models.

## Description

This application provides a user-friendly graphical interface for video upscaling. It supports the lightweight Anime4K GLSL shader algorithms and high-quality Real-ESRGAN neural networks. The macOS version is built with SwiftUI and leverages Apple Neural Engine acceleration, while the Windows version is built with C++ and Qt6, using hardware-accelerated Vulkan subprocesses.

## Features

- **Hybrid Upscaling Engine**: Select between fast real-time Anime4K shader presets and high-fidelity deep learning models.
- **Apple Neural Engine (ANE) Acceleration**: Native macOS processing pipeline utilizing Core ML on dedicated ANE cores for low power draw and high throughput.
- **Vulkan-based Neural SR**: Subprocess-based upscaling using `realesrgan-ncnn-vulkan` for cross-platform compatibility on Windows and macOS.
- **SD Rescue Mode**: Pre-processes degraded or heavily compressed low-resolution sources with Anime4K artifact-removal shaders before upscaling them via the Neural Engine.
- **Advanced Encoding Controls**: Encode using H.264, HEVC, or AV1. Choose between visually lossless presets, target bitrates, and long-GOP optimization.
- **Drag-and-Drop Interface**: Easy queue management with real-time status reporting, frame rate tracking, and log output.

## Upscaling Presets and Hardware Acceleration

The upscaling presets are categorized into three groups based on their backend and hardware utilization:

### 1. Special (Recommended for Apple Silicon M-series Macs)
These modes run natively on macOS and are fully accelerated by the **Apple Neural Engine (ANE)**. They use a Swift pipeline (`AVAssetReader` + `AVAssetWriter`) to process frames in memory without creating temporary files on disk.
- **SPECIAL: Fast**: Uses the `realesr-animevideov3` Core ML model on the ANE. Best balance of speed and quality for clean HD anime.
- **SPECIAL: Quality**: Uses the larger `realesrgan-x4plus-anime` Core ML model on the ANE. Designed for high-fidelity archival upscales.
- **SPECIAL: SD Rescue**: Runs an initial preprocessing pass using the Anime4K Restore VL GLSL shader to eliminate compression noise, followed by `realesr-animevideov3` upscaling on the ANE. Recommended for old DVDs, SD television rips, or low-bitrate videos.
- **SPECIAL: PiperSR 2x**: Uses the ANE-optimized `PiperSR` model. It runs near real-time (up to 44 FPS) but is resolution-locked to 2x scale and intended only for clean source files.

### 2. Neural SR (Vulkan Acceleration)
These modes run via Vulkan and are available on both Windows and macOS. The pipeline performs a three-stage process: decoding frames to temporary PNGs, upscaling using `realesrgan-ncnn-vulkan`, and re-encoding with FFmpeg.
- **ESRGAN Fast**: Fast, compact anime video model (`realesr-animevideov3`).
- **ESRGAN Quality**: Larger, high-quality anime image model (`realesrgan-x4plus-anime`).
- **ESRGAN General**: General restoration model (`realesrgan-x4plus`) for live-action or non-anime content.

### 3. Legacy Modes (Anime4K Shaders)
Lightweight GLSL edge-reconstruction shaders running in real-time via `libplacebo` and FFmpeg. These run on the GPU and are extremely fast, making them ideal for older or lower-end hardware.

## How to Use

1. **Add Files**: Click the "Add Video Files..." button or drag and drop your video files into the application.
2. **Select a File**: Click on a file in the list to configure its individual processing options.
3. **Choose a Mode**: Select an upscaling mode from the picker.
4. **Set the Resolution & Codec**: Select your target scale (e.g., 2x) and output video codec.
5. **Configure Compression**: Select a preset or set a custom quality/bitrate.
6. **Choose Output Directory**: Select where the processed files will be saved.
7. **Start Processing**: Click the "Start Processing" button to begin.

## Building from Source

### macOS
- macOS 14.0 or later, Xcode 15.0 or later, and Swift 5.9 or later are required.
- Place compiled Core ML `.mlmodelc` directories in the app bundle resources.
- Run `bundle_dependencies.sh` to bundle `ffmpeg` and `ffprobe` binaries.

### Windows
- Windows 10/11, Visual Studio 2022 (MSVC), CMake, and Qt 6.5.3 or later are required.
- Run `windows/download_dependencies.py` to download the architecture-specific `ffmpeg` and `realesrgan-ncnn-vulkan` binaries.
- Configure and build the project using CMake:
  ```powershell
  cmake -B build-x64 -S windows -DCMAKE_BUILD_TYPE=Release
  cmake --build build-x64 --config Release
  ```

## Credits

- **Anime4K**: Shaders and algorithms are created by [bloc97](https://github.com/bloc97/Anime4K/).
- **Real-ESRGAN**: Neural network architectures and models are developed by [xinntao](https://github.com/xinntao/Real-ESRGAN).
- **realesrgan-ncnn-vulkan**: Vulkan-optimized portable wrapper by [nihui](https://github.com/nihui/realesrgan-ncnn-vulkan).
- **FFmpeg**: Used for video decoding, filtering, and encoding.
