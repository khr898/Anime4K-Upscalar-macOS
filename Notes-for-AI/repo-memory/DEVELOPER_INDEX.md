# Anime4K Upscaler macOS — Developer Index

## High-Level Architecture

```
SwiftUI UI (ContentView) — 3 feature tabs
    ↓
AppViewModel (file list, job config, engine)  |  CompressViewModel  |  StreamOptimizeViewModel
    ↓
ProcessingEngine (FFmpeg subprocess, progress parsing, power management)
    ↓
FFmpeg (decode + encode, video codec handling)
    ↓
Anime4K Metal Pipeline (future Phase 4) or GLSL shaders (current via FFmpeg filter)
    ↓
Output video file
```

**Current State:** FFmpeg runs Anime4K GLSL shaders via `glsl-shaders=` filter flag. Phase 4 (in planning) replaces GLSL with native Metal + MPS convolution.

**Three Feature Modes:**
1. **Upscale** — Anime4K shader modes (15 modes: HQ/Fast/NoUpscale)
2. **Compress** — H.265/AV1 encoding with quality presets
3. **Stream Optimize** — Streaming-optimized transcoding (fast-start, keyframe intervals)

---

## File Index: Core Components

### App Entry & Routing
- **[Anime4K_UpscalerApp.swift](Anime4K-Upscaler/Anime4K_UpscalerApp.swift)** — App entry, 3 VMs in environment, window config
  - `Anime4K_UpscalerApp` — Main SwiftUI app struct, commands for file ops

- **[ContentView.swift](Anime4K-Upscaler/Views/ContentView.swift)** — Root TabView
  - Routes to UpscaleView, CompressView, StreamOptimizeView

### Models (Domain & Config)
- **[Models.swift](Anime4K-Upscaler/Models/Models.swift)** — Core types (800+ lines)
  - `Anime4KShader` enum (12 shaders: Restore/Upscale/Denoise variants VL/M/S + Clamp)
  - `Anime4KMode` enum (15 modes: HQ/Fast/NoUpscale with `.shaders` property mapping to pipeline)
  - `ModeCategory` enum (HQ, Fast, NoUpscale grouping)
  - `TargetResolution` enum (1x/2x/4x scaling)
  - `VideoCodec` enum (HEVC/AV1)
  - `CompressionMode` enum (visuallyLossless/balanced/customQuality)
  - `VideoFile` struct — metadata, duration probe results, output naming
  - `JobConfiguration` struct — mode + resolution + codec + compression + longGOP
  - `ProcessingJob` class — state, progress, logs, errorMessage
  - `ModeCategory` enum with `.modes` property for UI grouping
  - `SupportedVideoExtension` (mp4, mkv, mov, avi, webm, flv, ts)

- **[CompressModels.swift](Anime4K-Upscaler/Models/CompressModels.swift)**
  - `CompressEncoder` (hevcVideoToolbox, svtAV1) with quality defaults
  - `ContentType` (liveAction, anime) for HDR/quality heuristics
  - `CompressJob`, `CompressConfiguration` structs

- **[StreamOptimizeModels.swift](Anime4K-Upscaler/Models/StreamOptimizeModels.swift)**
  - `StreamEncoder` (hevcVideoToolbox/h264VideoToolbox/svtAV1)
  - `StreamProfile`, `StreamPixelFormat`, `StreamAudioMode`, `KeyframeInterval` enums
  - `StreamOptimizeConfiguration` struct

### ViewModels
- **[AppViewModel.swift](Anime4K-Upscaler/ViewModels/AppViewModel.swift)**
  - File list, selected file, configuration, job queue
  - `addFiles()`, `removeSelectedFile()`, `startProcessing()`, `cancelProcessing()`
  - FFmpeg/shader dependency validation
  - Owns `ProcessingEngine` (lifecycle management)

- **[ProcessingEngine.swift](Anime4K-Upscaler/ViewModels/ProcessingEngine.swift)** (core processing)
  - `executeBatch(jobs:)` — queue execution, power assertion
  - `executeJob(_:)` — FFmpeg process spawning, stderr parsing, progress calc
  - Progress tracking: `isProcessing`, `currentJobIndex`, `overallProgress`
  - IOKit power assertions (prevent sleep during processing)
  - Process pipe handlers (frame-rate & speed parsing from FFmpeg output)

- **[CompressViewModel.swift](Anime4K-Upscaler/ViewModels/CompressViewModel.swift)**
  - Similar to AppVM but for Compress: encoder/quality/contentType config
  - HDR detection, job spawning

- **[StreamOptimizeViewModel.swift](Anime4K-Upscaler/ViewModels/StreamOptimizeViewModel.swift)**
  - Source/destination directory scanning
  - Streaming config: encoder, keyframe intervals, faststart, SW fallback

- **[Anime4KOfflineProcessor.swift](Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift)**
  - `A4KComputeBackend` enum (metal, mps, coreml) — parse from env or defaults
  - `A4KCoreMLBackend` class — CoreML model loading + inference scaffold
  - ComputeUnits parsing (CPU-only, CPU+GPU, CPU+ANE)

- **[Anime4KRuntimePipeline.swift](Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift)**
  - `A4KShaderPass` struct — metadata for each pass (name, function, binds, save, sigma)
  - `parse()` — reads Metal source comments to extract shader pass definitions
  - Entry function name resolution, input/output texture name mapping

- **[Anime4KMPSConvolution.swift](Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift)**
  - `A4KMPSWeightLayout` enum (nhwc, nchw) — weight tensor layout
  - `A4KMPSWeightPackOrder` struct (custom axis ordering ohwi, etc.)
  - `A4KMPSEquivalenceInputMode` — how to bind first input texture
  - `A4KMPSPlannerConfig` — consolidates all MPS config from environment
  - Defaults: MPS disabled unless `A4K_ENABLE_MPS_CONV=1`

### Views
- **[UpscaleView.swift](Anime4K-Upscaler/Views/UpscaleView.swift)** — Main upscale UI
  - NavigationSplitView: file list (left) + detail (right)
  - Routes to ConfigurationPanel or ProcessingView based on `viewState`

- **[ConfigurationPanel.swift](Anime4K-Upscaler/Views/Detail/ConfigurationPanel.swift)**
  - Mode picker (15 Anime4K modes)
  - Resolution picker (1x/2x/4x)
  - Codec picker (HEVC/AV1)
  - Compression mode picker (presets)
  - Output directory selection, "Start" button

- **[ProcessingView.swift](Anime4K-Upscaler/Views/Detail/ProcessingView.swift)**
  - Job list with progress bars, speed/fps/time display
  - Cancel button, overall progress meter

- **[ProgressRow.swift](Anime4K-Upscaler/Views/Components/ProgressRow.swift)**
  - Per-job progress row (state icon, name, bar, metrics)

- **[ModePicker.swift](Anime4K-Upscaler/Views/Components/ModePicker.swift)**
  - Sectioned picker for 15 modes, grouped by category

- **CompressView, StreamOptimizeView** — Similar structure for compress & stream tabs

### Utilities
- **[FFmpegLocator.swift](Anime4K-Upscaler/Utilities/FFmpegLocator.swift)**
  - Static properties: `ffmpegURL`, `ffprobeURL`, `frameworksDirectoryURL`, `shaderDirectoryURL`
  - Metal source directory resolution (bundle path + dev fallbacks)
  - MoltenVK library location, Vulkan ICD JSON generation
  - `validateDependencies()` — check FFmpeg/shaders present on launch

- **[SecurityScopeManager.swift](Anime4K-Upscaler/Utilities/SecurityScopeManager.swift)**
  - Sandbox-safe file access: `startAccessing()`, `stopAccessing()`, bookmarks
  - Singleton pattern, thread-safe with NSLock
  - `presentVideoFilePicker()` for NSOpenPanel integration

- **[DurationProbe.swift](Anime4K-Upscaler/Utilities/DurationProbe.swift)**
  - `probe(url:)` — async ffprobe call to extract duration/resolution
  - Runs ffprobe in background, returns `ProbeResult` with width/height/duration

### Resources
- **[Anime4K_Upscaler.entitlements](Anime4K-Upscaler/Anime4K_Upscaler.entitlements)** — Sandbox config
  - App Sandbox enabled
  - File read-write (sandbox-safe)

- **[metal_sources/](Anime4K-Upscaler/Resources/metal_sources/)** — 13 .metal files
  - Phase 1+2 translated Anime4K shaders (baseline for Phase 4 integration)
  - Names: Clamp_Highlights, Restore_CNN_*, Upscale_CNN_*, Upscale_Denoise_CNN_*

- **[Shaders/](Anime4K-Upscaler/Resources/Shaders/)** — 13 .glsl files (legacy, currently used)
  - Same names as metal_sources + .glsl extension

### Benchmarking & Tools
- **[phase4_aahq_benchmark.swift](Anime4K-Upscaler/Tools/phase4_aahq_benchmark.swift)** (main bench driver)
  - `Phase4BenchConfig` struct — parses args + env vars
  - Key env vars: `A4K_BENCH_BACKEND`, `A4K_BENCH_USE_MPS`, `A4K_BENCH_USE_NEURAL_ASSIST`, `A4K_BENCH_WORKERS`, `A4K_BENCH_OUTPUT_SCALE`
  - Runs baseline (Metal) vs trial (MPS+Neural), compares SSIM >= 0.999

- **[run_phase4_aahq_benchmark.zsh](Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh)** (orchestration)
  - Compiles benchmark binary from three Swift files
  - Extracts video dims, runs baseline + trial, computes SSIM/PSNR
  - Outputs metrics CSV: timestamp, backend, workers, fps, frames, SSIM, quality_status
  - Default: baseline=metal, trial=mps+neural_assist, ssim_threshold=0.999

---

## Processing Pipeline Deep Dive

### Anime4K Modes → Shader Chains
15 modes map to pipelines starting with Clamp_Highlights:

**HQ Modes (VL/M quality):**
- A→ Restore_VL → Upscale_2x_VL → Upscale_2x_M
- B→ Restore_Soft_VL → Upscale_2x_VL → Upscale_2x_M
- C→ Upscale_Denoise_2x_VL → Upscale_2x_M
- AA→ Restore_VL → Upscale_2x_VL → Restore_M → Upscale_2x_M
- BB→ (soft versions of AA)
- CA→ Upscale_Denoise_2x_VL → Restore_M → Upscale_2x_M

**Fast Modes (M/S quality):** — Same pattern with M+S instead of VL+M

**NoUpscale Modes (13–15):** — Restore only, no upscaling

### Resolution Scaling Logic
- Each 2x upscaler pass is gated by current scale vs target scale
- 1080p → 2x: only 1st upscaler → 2160p
- 1080p → 4x: both upscalers → 4320p
- NoUpscale modes ignore target resolution, skip all upscalers

---

## Dependency Map

```
Anime4K_UpscalerApp
  ├─ AppViewModel
  │   ├─ ProcessingEngine
  │   │   ├─ FFmpegLocator (ffmpeg/ffprobe paths)
  │   │   ├─ SecurityScopeManager (file access)
  │   │   └─ Process (subprocess handling)
  │   ├─ VideoFile (file metadata)
  │   ├─ JobConfiguration (config snapshot)
  │   └─ ProcessingJob (execution tracking)
  ├─ CompressViewModel
  │   ├─ CompressJob, CompressConfiguration
  │   └─ (similar engine + process logic)
  └─ StreamOptimizeViewModel
      ├─ StreamOptimizeConfiguration
      └─ (directory scan + transcode config)

Data Flow:
  User selects file → VideoFile created via DurationProbe.probe()
  User picks mode/codec → JobConfiguration created
  User clicks Start → ProcessingJob spawned, passed to ProcessingEngine.executeBatch()
  ProcessingEngine spawns FFmpeg subprocess, parses stderr for progress
  FFmpeg pipes GLSL shaders (current) or gets frames from Metal pipeline (future Phase 4)
  Output file written to outputDirectoryURL
```

---

## Benchmark & Quality Tooling Map

### Phase 4 Benchmark (run_phase4_aahq_benchmark.zsh)
**Entry Command:**
```bash
bash Tools/run_phase4_aahq_benchmark.zsh [input_video] [max_frames]
```

**Core Workflow:**
1. Compile `phase4_aahq_benchmark` binary from Swift files
2. Baseline run (default: Metal backend, no neural assist)
3. Trial run (default: MPS backend, 3 workers, neural assist enabled)
4. SSIM/PSNR comparison (threshold: >= 0.999 for PASS)
5. Output: CSV metrics + summary MD

**Key Environment Variables:**
- `A4K_BENCH_BASELINE_BACKEND=metal` — baseline compute backend
- `A4K_BENCH_OPT_BACKEND=mps` — trial backend
- `A4K_BENCH_USE_NEURAL_ASSIST=1` — enable ANE
- `A4K_BENCH_WORKERS=3` — worker threads for trial
- `A4K_BENCH_OUTPUT_SCALE=2` — upscaling factor (2 or 4)
- `A4K_BENCH_BASELINE_FRAMES=120` — frames for baseline
- `SSIM_THRESHOLD=0.999` — quality acceptance threshold
- `A4K_BENCH_METRICS_CSV=/path/to/metrics.csv` — output metrics file

**Metrics Output (CSV):**
```
timestamp_utc, baseline_backend, trial_backend, run_role, backend, neural_assist, 
workers, frames_requested, frames_processed, elapsed_s, fps, 
input_w, input_h, output_w, output_h, ssim_all, psnr_avg_db, quality_status, video
```

---

## Keyword Index (Semantic Search)

**Core Concepts:**
- anime upscaler, shader pipeline, metal graphics, convolution
- anime4k modes, restore denoise upscale, MPS optimization
- frame processing, video encoding, FFmpeg subprocess
- quality metric, SSIM threshold, benchmark

**Architecture:**
- SwiftUI ViewModel, observable state, environment
- tab view, navigation split view, configuration panel
- file picker, video file metadata, security scope
- FFmpeg process, subprocess, pipe streaming

**Quality & Performance:**
- performance benchmark, neural assist, ANE support
- quality lossless, SSIM PSNR, bitrate CRF
- long GOP keyframe, streaming optimization
- pixel format yuv420p10le p010le, profile hevc

**Technical:**
- Metal compute shader, texture binding, command buffer
- MPS convolution, weight layout, compute units
- sandbox entitlements, bookmark data, dylib loading
- CoreML inference, Core Video, pixel format

**Utility Functions:**
- FFmpeg locator bundle path, shader directory
- duration probe async, frame rate parsing
- job configuration default, compression preset
- process handle cancellation, power assertion IOKit

---

## Critical Code Paths: Common Tasks

### Performance Issue / Slow Upscaling
1. **Check:**
   - [ProcessingEngine.swift](Anime4K-Upscaler/ViewModels/ProcessingEngine.swift) — frame rate parsing + overall progress calc
   - [phase4_aahq_benchmark.swift](Anime4K-Upscaler/Tools/phase4_aahq_benchmark.swift) — measure actual FPS vs baseline
   - Benchmark: `bash Tools/run_phase4_aahq_benchmark.zsh <video> 120`
2. **Optimize:**
   - [Anime4KMPSConvolution.swift](Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift) — enable `A4K_ENABLE_MPS_CONV=1` for MPS paths
   - [Anime4KOfflineProcessor.swift](Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift) — switch `A4KComputeBackend` from `.metal` to `.mps`
   - Verify: SSIM >= 0.999 in benchmark CSV `quality_status`

### Quality Mismatch / Wrong Output
1. **Verify Mode Pipeline:**
   - [Models.swift](Anime4K-Upscaler/Models/Models.swift) line ~200: `Anime4KMode.shaders` property maps each mode to shader chain
   - Check selected mode in UI matches intended pipeline
2. **Check Shader Files:**
   - [FFmpegLocator.swift](Anime4K-Upscaler/Utilities/FFmpegLocator.swift) — `shaderDirectoryURL` points to bundled GLSL files
   - Verify metal_sources/ or Shaders/ have matching .metal/.glsl files
3. **Frame Format Mismatch:**
   - Check `VideoCodec.pixelFormat` ([Models.swift](Anime4K-Upscaler/Models/Models.swift) line ~360)
   - HEVC uses p010le, AV1 uses yuv420p10le
   - [StreamOptimizeModels.swift](Anime4K-Upscaler/Models/StreamOptimizeModels.swift) — verify pixel format enum

### Encode/Decode Failures
1. **FFmpeg Not Found:**
   - [FFmpegLocator.swift](Anime4K-Upscaler/Utilities/FFmpegLocator.swift) — `validateDependencies()`
   - Check Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")
   - Fallback: frameworksDirectoryURL + "ffmpeg"
2. **File Format Unsupported:**
   - [SupportedVideoExtension](Anime4K-Upscaler/Models/Models.swift) line ~625 — mp4/mkv/mov/avi/webm/flv/ts only
3. **Process Output Parsing:**
   - [ProcessingEngine.swift](Anime4K-Upscaler/ViewModels/ProcessingEngine.swift) — stderr pipe handler parses frame/fps/time
   - Check regex patterns: `frame=`, `fps=`, `time=`

### Mode/Shader Mapping Issues
1. **Current Modes:**
   - [Models.swift](Anime4K-Upscaler/Models/Models.swift) line ~50–200: `Anime4KMode.shaders` property
   - 15 hardcoded pipelines (HQ 1–6, Fast 7–12, NoUpscale 13–15)
2. **Phase 4 Integration (future):**
   - [Anime4KRuntimePipeline.swift](Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift) — reads .metal comment metadata to resolve pass chain
   - [Anime4KOfflineProcessor.swift](Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift) — selects Metal vs MPS vs CoreML backend

### Sandbox / File Access Issues
1. **Check Entitlements:**
   - [Anime4K_Upscaler.entitlements](Anime4K-Upscaler/Anime4K_Upscaler.entitlements) — must have `com.apple.security.files.user-selected.read-write`
2. **Security Scope Lifecycle:**
   - [SecurityScopeManager.swift](Anime4K-Upscaler/Utilities/SecurityScopeManager.swift) — `startAccessing()` on file pick, `stopAccessingAll()` on app close
   - [Anime4K_UpscalerApp.swift](Anime4K-Upscaler/Anime4K_UpscalerApp.swift) — calls `stopAccessingAll()` in `onDisappear`

---

## Notable Architecture Decisions

1. **ProcessingEngine is a `let`, not @Observable property** in AppViewModel
   - Prevents spurious view invalidations when unrelated properties change
   - Views still observe through ProcessingEngine's own @Observable conformance

2. **Phase 1–2 Metal Shaders Exist**
   - [metal_sources/](Anime4K-Upscaler/Resources/metal_sources/) contains verified .metal translations
   - Phase 4 will lift Anime4K logic out of FFmpeg subprocess into native Metal pipeline
   - SSIM >= 0.999 quality guardrail ensures no approximations

3. **15 Hardcoded Anime4K Modes**
   - Modes labeled 1–15 with fixed shader chains
   - HQ (VL/M), Fast (M/S), NoUpscale categories
   - Resolution scaling gated: upscalers only run if currentScale < targetScale

4. **Three Independent Feature VMs**
   - AppViewModel (upscaling), CompressViewModel, StreamOptimizeViewModel
   - Each has own config, file list, processing logic
   - Share ProcessingEngine pattern but separate state

5. **Sandbox-Safe FFmpeg / Bun
dled Binaries**
   - FFmpeg bundled in Frameworks (post-build script)
   - File access via security scopes + bookmarks
   - Subprocess spawning, stderr pipe for progress

---

## Build & Deployment

**Project Config:**
- [project.yml](project.yml) — XcodeGen, macOS 14.0+, Xcode 15+
- Post-build script: [Scripts/bundle_dependencies.sh](Anime4K-Upscaler/Scripts/bundle_dependencies.sh)
  - Bundles ffmpeg/ffprobe to Frameworks/ directory
  - Ensures binaries are signed + sandboxed

**Build from Source:**
```bash
xcodegen generate  # generates .pbxproj from project.yml
xcodebuild build -scheme Anime4K-Upscaler
```

---

## Phase 4 Integration Roadmap (From anime4k_metal_phase4.md)

1. **Frame Extraction:** FFmpeg decode → raw frame pipes to Metal
2. **Metal Pipeline:** Upload frames → process via shader chain → read output
3. **MPS Optimization:** Replace CNN fragment shaders with MPSCNNConvolution
4. **Quality Gate:** SSIM >= 0.999, max pixel diff < 2
5. **Performance Target:** Maximize speed without sacrificing quality

Current GLSL shaders stay until Metal path is production-ready.
