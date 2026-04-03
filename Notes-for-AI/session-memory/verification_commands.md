# Anime4K Upscaler — Verification Commands Reference

## Quick Summary
Project uses Swift + Xcode + XcodeGen for builds, FFmpeg/ffprobe for dependencies, and custom shell/Swift benchmark harness for quality gates.

---

## FAST SYNTAX/STATIC CHECKS (< 5 seconds)

### Dependency availability
```bash
# Check FFmpeg/ffprobe availability
which ffmpeg && which ffprobe

# Check XcodeGen installed
which xcodegen

# Validate FFmpeg + libplacebo (from bundle_dependencies.sh)
ffmpeg -hide_banner -v verbose -f lavfi -i color=size=16x16:rate=1:color=black \
  -vf libplacebo -frames:v 1 -f null - 2>&1 | grep -E 'libplacebo|version'
```

### Swift syntax check (no compilation)
```bash
# Check Swift syntax without building (if swiftc available)
cd /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS
swiftc -parse Anime4K-Upscaler/ViewModels/*.swift
swiftc -parse Anime4K-Upscaler/Models/*.swift
swiftc -parse Anime4K-Upscaler/Utilities/*.swift
```

---

## COMPILE/BUILD CHECKS (30-60 seconds)

### Generate Xcode project from YAML
```bash
cd /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS
xcodegen generate
```

### Build validation (no-codesign)
```bash
# Full build with no code signing (CI mode)
xcodebuild build \
  -scheme "Anime4K-Upscaler" \
  -project "Anime4K-Upscaler.xcodeproj" \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT=build

# OR debug config (faster)
xcodebuild build \
  -scheme "Anime4K-Upscaler" \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT=build
```

### Compile benchmark harness only (for testing Metal pipeline)
```bash
cd /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS
swiftc -O \
  -o /tmp/phase4_aahq_benchmark \
  Anime4K-Upscaler/Tools/phase4_aahq_benchmark.swift \
  Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift \
  Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift \
  Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift
```

### Check for Metal shader syntax (compile-verify phases 1-2)
```bash
# If metal compiler available
xcrun metal -Wall -Werror \
  Anime4K-Upscaler/Resources/metal_sources/Anime4K_Clamp_Highlights.metal \
  Anime4K-Upscaler/Resources/metal_sources/Anime4K_Restore_CNN_*.metal \
  -o /tmp/compiled.metal

# OR use swiftc to validate Swift wrapping
swiftc -typecheck \
  Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift \
  Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift
```

---

## BENCHMARK/QUALITY CHECKS (60+ seconds, depends on frame count)

### Full Phase 4 A+A HQ Quality Gate (RECOMMENDED)
```bash
cd /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS

# Run baseline vs trial with strict SSIM >= 0.999 quality gate
# Defaults: baseline=metal, trial=mps+neural_assist, 120 frames, 2x upscaling
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh \
  /path/to/test_video.mp4 \
  120

# Exit codes:
# 0 = quality PASS
# 3 = quality FAIL (SSIM < threshold)
```

### Custom benchmark configurations
```bash
# Test Metal vs Metal (baseline only)
A4K_BENCH_BASELINE_BACKEND=metal \
A4K_BENCH_OPT_BACKEND=metal \
A4K_BENCH_BASELINE_FRAMES=60 \
A4K_BENCH_USE_NEURAL_ASSIST=0 \
A4K_BENCH_OUTPUT_SCALE=2 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 60

# Test MPS vs Metal (MPS in trial)
A4K_BENCH_BASELINE_BACKEND=metal \
A4K_BENCH_OPT_BACKEND=mps \
A4K_BENCH_WORKERS=4 \
A4K_BENCH_USE_NEURAL_ASSIST=1 \
A4K_BENCH_SSIM_THRESHOLD=0.999 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 120

# Disable neural assist
A4K_BENCH_USE_NEURAL_ASSIST=0 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 30

# Change output scale (2x or 4x)
A4K_BENCH_OUTPUT_SCALE=4 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 30

# Custom SSIM threshold
SSIM_THRESHOLD=0.995 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 30

# Custom worker count
A4K_BENCH_OPT_WORKERS=6 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 60

# Custom threadgroup size
A4K_BENCH_OPT_TG_THREADS=256 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 60

# Custom metrics CSV output location
A4K_BENCH_METRICS_CSV=/tmp/custom_metrics.csv \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 60
```

### Verbose benchmark output
```bash
A4K_BENCH_VERBOSE=1 \
bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 30
```

### Direct benchmark binary (if pre-compiled)
```bash
# Manually compile first
swiftc -O \
  -o /tmp/phase4_bench \
  Anime4K-Upscaler/Tools/phase4_aahq_benchmark.swift \
  Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift \
  Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift \
  Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift

# Run with env vars (see phase4_aahq_benchmark.swift)
A4K_BENCH_BACKEND=mps \
A4K_BENCH_USE_MPS=1 \
A4K_BENCH_USE_NEURAL_ASSIST=1 \
A4K_BENCH_OUTPUT_SCALE=2 \
A4K_BENCH_WORKERS=3 \
/tmp/phase4_bench /path/to/video.mp4 120
```

### Extract quality metrics from benchmark run
```bash
# Metrics CSV generated after run
cat /tmp/a4k_phase4_metrics.csv

# Summary markdown generated
cat /tmp/a4k_phase4_aahq_summary.md

# Extract just SSIM/PSNR/FPS
tail -n 1 /tmp/a4k_phase4_metrics.csv | \
  awk -F',' '{print "SSIM="$16" PSNR="$17" STATUS="$18" FPS="$11}'
```

---

## DEPENDENCY FALLBACK COMMANDS

### If FFmpeg not found
```bash
# Install via Homebrew
brew install ffmpeg

# OR from source (slower)
# Download from https://ffmpeg.org/download.html
# ./configure --prefix=/opt/homebrew && make && make install

# Fallback: verify bundled version during build
# (bundle_dependencies.sh handles this automatically)
${SRCROOT}/Anime4K-Upscaler/Scripts/bundle_dependencies.sh
```

### If XcodeGen not available
```bash
# Install XcodeGen
brew install xcodegen

# OR skip project generation and use pre-generated .pbxproj
# (the repo already has Anime4K-Upscaler.xcodeproj)
xcodebuild build -project Anime4K-Upscaler.xcodeproj ...
```

### If Metal compiler not available (xcrun metal)
```bash
# Fallback: test by building full app
xcodebuild build \
  -scheme "Anime4K-Upscaler" \
  -configuration Release

# This will catch Metal syntax errors during Xcode build
```

### If ffprobe not found
```bash
# Install with ffmpeg
brew install ffmpeg

# Fallback: extract video dims with ffmpeg only
ffmpeg -i input.mp4 2>&1 | grep -E 'Stream.*Video'
```

### If benchmark test video not available
```bash
# Generate test pattern video (using ffmpeg only)
ffmpeg -f lavfi \
  -i "testsrc=size=1920x1080:duration=1:rate=24" \
  -f lavfi -i "sine=f=1000:d=1" \
  -pix_fmt yuv420p \
  -y test_pattern.mp4

# OR use a short clip (~120 frames)
ffmpeg -i /your/source.mp4 -vframes 120 test_clip.mp4
```

### If swiftc is missing but xcodebuild is available
```bash
# Use xcodebuild to compile benchmark
xcodebuild build \
  -target phase4_aahq_benchmark \
  -configuration Release \
  SYMROOT=/tmp/build_benchmark
```

---

## ENVIRONMENT VARIABLES FOR VERIFICATION

### Benchmark Control (run_phase4_aahq_benchmark.zsh + phase4_aahq_benchmark)
- `A4K_BENCH_BACKEND` — compute backend: metal, mps, coreml
- `A4K_BENCH_USE_MPS` — legacy flag: 0 or 1 (uses metal if 0, mps if 1)
- `A4K_BENCH_USE_NEURAL_ASSIST` — enable ANE: 0 or 1 (default 0 for baseline)
- `A4K_BENCH_OUTPUT_SCALE` — upscaling factor: 2 or 4 (default 2)
- `A4K_BENCH_WORKERS` — worker thread count: 1–8 (default 3)
- `A4K_BENCH_BASELINE_FRAMES` — frames for baseline run (default 120)
- `A4K_BENCH_OPT_WORKERS` — workers for trial run
- `A4K_BENCH_OPT_TG_THREADS` — threadgroup threads count
- `A4K_BENCH_BASELINE_BACKEND` — explicit baseline backend (overrides A4K_BENCH_BACKEND)
- `A4K_BENCH_OPT_BACKEND` — explicit trial backend (overrides A4K_BENCH_BACKEND)
- `A4K_BENCH_METRICS_CSV` — output metrics CSV path
- `A4K_BENCH_VERBOSE` — verbose staging output: 0 or 1
- `SSIM_THRESHOLD` — quality gate threshold (default 0.999)
- `A4K_BENCH_FFMPEG` — custom ffmpeg path
- `A4K_BENCH_FFPROBE` — custom ffprobe path
- `A4K_BENCH_METAL_DIR` — custom metal_sources directory

### MPS-specific control (Anime4KMPSConvolution.swift)
- `A4K_ENABLE_MPS_CONV` — enable MPS convolution: 0 or 1
- `A4K_MPS_COMPUTE_UNITS` — compute units: all, cpu_only, cpu+gpu, cpu+ane
- `A4K_MPS_WEIGHT_LAYOUT` — weight ordering: nhwc, nchw
- `A4K_TARGET_THREADGROUP_THREADS` — threadgroup size (benchmark tuning)

### Backend selection (Anime4KOfflineProcessor.swift)
- `A4K_ENABLE_METAL` — enable Metal: 0 or 1
- `A4K_ENABLE_MPS_CONV` — enable MPS convolution
- `A4K_ENABLE_COREML` — enable CoreML backend
- `A4K_ENABLE_NEURAL_ASSIST` — use ANE acceleration

---

## CI/CD WORKFLOW (from .github/workflows/build.yml)

```bash
# Full build + DMG creation (as run in GitHub Actions)
brew install ffmpeg xcodegen
xcodegen generate
xcodebuild build \
  -scheme "Anime4K-Upscaler" \
  -project "Anime4K-Upscaler.xcodeproj" \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  SYMROOT=build

# Create DMG
mkdir -p build/dmg
cp -R "build/Release/Anime4K Upscaler.app" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Anime4K Upscaler v1.0.0" \
  -srcfolder build/dmg -ov -format UDZO \
  "build/Anime4K_Upscaler_v1.0.0_arm64.dmg"
```

---

## VERIFICATION MATRIX (By Goal)

| Goal | Fast | Medium | Thorough |
|------|------|--------|----------|
| **Syntax** | `swiftc -parse` || `xcodebuild build` |
| **Build** || `xcodegen && xcodebuild build Release` | + full debugging |
| **Metal shader** | `xcrun metal` (if avail) | compile app | + test on device |
| **Quality gate** || `run_phase4_aahq_benchmark.zsh` (120 frames) | + multiple configs |
| **Benchmark** || baseline vs trial (MPS) | + worker sweeps |
| **Full CI** | deps check | all above | + DMG creation |

---

## Notes
- All benchmark scripts assume ffmpeg/ffprobe in PATH or `/opt/homebrew/bin/`
- Quality gate SSIM threshold default is 0.999 (strict parity check)
- Benchmark output: CSV metrics + markdown summary in `/tmp/`
- Phase 4: Metal pipeline only; MPS convolution is opt-in via env flag
- CI: Project version comes from git tag (e.g., `v1.0.0` → MARKETING_VERSION=1.0.0)
