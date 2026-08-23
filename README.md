# Anime4K Upscaler

![macOS](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-green)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![Metal](https://img.shields.io/badge/Metal-Metal%204%20%7C%20Metal%203-purple)
![FFmpeg](https://img.shields.io/badge/FFmpeg-9.0-red)
![License](https://img.shields.io/badge/License-GPLv3-lightgrey)

A native macOS application for upscaling, compressing, and streaming-optimizing anime and video content using Anime4K shaders, Apple Neural Engine (ANE) Core ML networks, MetalFX GPU spatial scaling, and hardware-accelerated transcoding.

---

## Features

### Upscaling Studio
- **Apple Neural Engine (ANE) Core ML Acceleration**: In-memory, zero-disk-overhead streaming pipeline (`AVAssetReader` and `AVAssetWriter`) executing deep learning models directly on dedicated ANE cores for minimal power consumption and high throughput.
- **MetalFX GPU Spatial Scaler**: Real-time spatial upscaling powered by Apple MetalFX with support for Metal 4 and Metal 3 fallback.
- **Contrast-Gated Unsharp Masking**: Optional GPU compute shader pass after spatial upscaling that sharpens edges while leaving flat color areas untouched.
- **Vulkan-based Neural Super-Resolution**: Subprocess-based upscaling utilizing `realesrgan-ncnn-vulkan` and MoltenVK for GPU acceleration.
- **Anime4K GLSL Shaders**: High-quality (HQ) and Fast real-time edge-reconstruction shader pipelines dispatched via `libplacebo` and FFmpeg.
- **SD Rescue Mode**: Multi-stage pipeline combining Anime4K artifact-clearing shaders with neural super-resolution to restore low-bitrate and legacy SD media.

### Dedicated Video Compression (Compress Tab)
- **Visual Quality and Bitrate Tuning**: Preset-guided and custom quality controls with constant quality or target bitrate options.
- **Content-Aware Encoding Profiles**: Specialized tuning for animation, live action, and high-motion content.
- **Advanced GOP & B-Frame Controls**: Configurable B-frame insertion and long-GOP optimization for efficient storage.
- **HDR & Color Transfer Passthrough**: Automatic detection of HDR10 (SMPTE 2084 / PQ) color transfer characteristics and accurate color space preservation.

### Streaming Optimization (Stream Optimize Tab)
- **Faststart Web Optimization**: Automatically relocates the MP4/MOV `moov` atom header to the beginning of the file for instant web and streaming playback.
- **Keyframe Interval Alignment**: Configurable fixed GOP keyframe cadences (1s, 2s, 4s, 5s) tailored for HLS/DASH segment boundaries.
- **Profile and Pixel Format Enforcement**: Strict enforcement of Main10, Main, or Baseline profiles paired with 10-bit (`p010le`) or 8-bit (`yuv420p`) pixel formats.
- **Multi-Track Audio & Subtitle Handling**: Passthrough or transcode audio tracks and embed streaming-compatible subtitle streams.

### Batch Queue & Engine
- **Multi-Batch Queuing**: Stage different presets across different files and enqueue them into a centralized execution runner.
- **Add-While-Running Support**: Append new jobs or batches while the queue is actively processing.
- **Granular Cancellation**: Cancel individual jobs, running batches, or the entire queue with zero orphan processes and automatic system sleep assertion release.
- **Comprehensive Logging & Telemetry**: Live frame rate, processing speed multiplier, elapsed time, and standard error output streams.

### 100% Self-Contained Distribution
- **Zero External Dependencies**: All binaries, dynamic libraries, and assets (FFmpeg 9.0, libplacebo, MoltenVK, libdav1d, realesrgan, Core ML packages, and GLSL shaders) are fully bundled and codesigned within the application. End users do not need Homebrew or command-line tools installed.

---

## Upscaling Modes & Hardware Architecture

The 21 active upscaling modes are organized into four dedicated categories:

### 1. Special (Apple Silicon Optimized)
- **Neural 4x Fast**: Fast, high-quality `realesr-animevideov3` Core ML model on the Apple Neural Engine.
- **Neural 4x Quality**: Archival quality `realesrgan-x4plus-anime` (RRDB 6B) Core ML model on the Apple Neural Engine.
- **Neural SD Rescue**: Anime4K Restore VL shader pass followed by `realesr-animevideov3` on the Apple Neural Engine.
- **Neural 2x (PiperSR)**: Lightweight, real-time 2x super-resolution running natively on the Apple Neural Engine.
- **MetalFX (Restore + GPU)**: Anime4K Restore VL combined with Apple MetalFX spatial scaling on the GPU.
- **MetalFX + Sharpen**: Anime4K Restore VL, MetalFX spatial scaling, and contrast-gated unsharp mask compute pass.

### 2. Neural SR (Vulkan Acceleration)
- **ESRGAN Fast**: Compact anime video model (`realesr-animevideov3`) running through `realesrgan-ncnn-vulkan`.
- **ESRGAN Quality**: High-fidelity anime image model (`realesrgan-x4plus-anime`).
- **ESRGAN General**: General-purpose restoration model (`realesrgan-x4plus`) for live-action or non-anime content.

### 3. Anime4K (HQ)
- **Modes 1–6 (A, B, C, A+A, B+B, C+A)**: High-quality Anime4K shader chains combining perceptual deblurring, denoising, and 2x/4x CNN reconstruction shaders via `libplacebo`.

### 4. Anime4K (Fast)
- **Modes 7–12 (A, B, C, A+A, B+B, C+A)**: Lightweight Anime4K shader chains optimized for lower power consumption and high processing speeds.

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later
- **Architecture**: Apple Silicon (M1/M2/M3/M4 series recommended) or Intel x86_64 Mac with Metal support
- **Hardware Acceleration**: Apple Neural Engine (ANE) and Metal-compatible GPU

---

## Building from Source

### Prerequisites
- Xcode 15.0 or later with Command Line Tools
- Swift 5.9 or later
- Homebrew packages for build-time compilation:
  ```bash
  brew install libplacebo molten-vk dav1d pkg-config xcodegen
  ```

### Build Instructions
1. Clone the repository:
   ```bash
   git clone https://github.com/khr898/Anime4K-Upscalar-macOS.git
   cd Anime4K-Upscalar-macOS
   ```
2. Generate the Xcode project and bundle dependencies:
   ```bash
   xcodegen generate
   xcodebuild -project Anime4K-Upscaler.xcodeproj -scheme Anime4K-Upscaler -destination "platform=macOS" build
   ```

---

## Credits and Attributions

- **Anime4K**: Shader algorithms and restoration pipelines created by [bloc97](https://github.com/bloc97/Anime4K/).
- **Real-ESRGAN**: Deep learning architectures developed by [xinntao](https://github.com/xinntao/Real-ESRGAN).
- **realesrgan-ncnn-vulkan**: Vulkan-accelerated implementation by [nihui](https://github.com/nihui/realesrgan-ncnn-vulkan).
- **libplacebo**: GPU-accelerated video rendering and shader dispatch library by [haasn](https://github.com/haasn/libplacebo).
- **MoltenVK**: Vulkan implementation layered over Apple Metal by [The Khronos Group](https://github.com/KhronosGroup/MoltenVK).
- **FFmpeg**: Video decoding, filtering, and multiplexing libraries by [The FFmpeg Project](https://ffmpeg.org).
