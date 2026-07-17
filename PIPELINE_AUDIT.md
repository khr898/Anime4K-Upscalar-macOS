# Upscaling Pipeline Audit — macOS

**Date:** 2026-07-07
**Method:** Every macOS pipeline was driven end-to-end against a real 5 s
640×360 test clip (`testsrc2` + sine audio) using the *exact* argument arrays
the app builds (compiled from the app's own `Models.swift` / `CoreMLUpscaler.swift`
into a CLI harness), with a from-source ffmpeg 8.1 built against Homebrew
libplacebo + MoltenVK.

## Result summary

| Pipeline | Before | After fix | Evidence |
|---|---|---|---|
| GLSL Anime4K (modes 1–15) | **broken** — all 15 die at filter init | **OK** | 1280×720 (upscale) / 640×360 (no-up), 10-bit, audio kept |
| NeuralSR ESRGAN ncnn (modes 16–18) | OK | OK | esrgan_Fast: 1280×720, 120 frames, audio kept |
| Special ANE — PiperSR 2× (mode 22) | **OK** | OK | 128→256 on cpuOnly/ANE/GPU/all |
| Special ANE — ESRGAN Fast/Quality (19,20), SD-Rescue (21) | **broken** — SIGTRAP in libBNNS | **regenerated** | converted models were undefined-shape |
| Compress / Stream Optimize (ffmpeg encode) | depends on bundled ffmpeg | see self-containment | — |

## Fixes applied

### 1. GLSL: `hwdownload` failed — every Anime4K mode dead

`FilterGraphBuilder` produced `…,libplacebo=…,hwdownload,format=p010le`.
`hwdownload` can only download a hardware frame in **its own** `sw_format`;
libplacebo's Vulkan frames default to a format that is not the requested 10-bit
target, so ffmpeg aborted the whole graph at init:

```
[hwdownload] Invalid output format p010le for hwframe download.
[vf#0:0] Error reinitializing filters! ... -22 (Invalid argument)
```

Every one of the 15 GLSL modes failed before producing a single frame.

**Fix:** append `:format=<codec pixfmt>` to the **last** `libplacebo` stage so
the hardware frame already carries the target sw_format before `hwdownload`.
- `Anime4K-Upscaler/Models/Models.swift` (`FilterGraphBuilder.build`)

Verified after fix — all 15 modes:

```
mode 1  (Mode A (HQ)):        OK 1280,720,yuv420p10le audio=aac
… (2–12 identical: 1280×720) …
mode 13 (A+A Fast [No Up]):   OK 640,360,yuv420p10le audio=aac
mode 14 (A HQ [No Up]):       OK 640,360,yuv420p10le audio=aac
mode 15 (A+A HQ [No Up]):     OK 640,360,yuv420p10le audio=aac
```

### 2. Special ANE: two Real-ESRGAN CoreML models crashed in libBNNS

`realesr-animevideov3.mlpackage` and `realesrgan-x4plus-anime.mlpackage`
crashed with `EXC_BREAKPOINT` inside `libBNNS.dylib` on **every** compute unit
(cpuOnly, cpuAndNeuralEngine, cpuAndGPU, all). Root cause in
`Scripts/convert_models.py`: it declared an `ImageType` **output** together with
`EnumeratedShapes` **input**, so CoreML could not resolve a concrete output
image size (the saved model reported a 1×1 output constraint) and the runtime
crashed. PiperSR, a fixed 128×128→256×256 image model, always worked.

**Fix:** rewrote the conversion (`convert_models.py`) to use a single fixed
256×256 input tile (like PiperSR) and a wrapper that scales the network's
`[0,1]` output to the `0–255` range an RGB image output expects — concrete
input → concrete output → no crash. Regenerated both `.mlpackage`s.
Also hardened `CoreMLUpscaler.nativeScale`: never trust an output/input ratio
below 2× for a super-resolution model; fall back to the name-based scale.

### 3. Swift compile errors (blocked the whole macOS build)

- `ProcessingEngine.swift`: main-actor `cancellationRequested` read from a
  `@Sendable` closure (hard error, F1) — introduced a thread-safe
  `CancellationToken`; the off-actor cancel check now defaults to *not*
  cancelled (also removes a phantom-cancel path).
- `CoreMLUpscaler.swift`: `enumeratedImageSizes` treated as optional (it is not).

Typecheck now reports **0 errors**.

### 4. Self-containment: bundled ffmpeg was not actually self-contained

The shipped release DMG (`v1.1.07042026`) and the repo's vendored ffmpeg link
`/opt/homebrew/Cellar/ffmpeg/8.1_1/lib/libav*.dylib`; the `libav*`/`libsw*`
closure was never copied into `Contents/Frameworks` nor relinked. On any machine
without that exact Homebrew build, dyld kills ffmpeg at launch, which the
view-models mis-report as "cancelled by user" — i.e. **every** ffmpeg pipeline
is dead on a clean machine. Fixes in `Scripts/bundle_dependencies.sh`:
- removed a top-level `local` (F4) that would abort the script under `set -e`;
- added a **functional smoke test** (step 8b) that launches the bundled
  ffmpeg / ffprobe / realesrgan in a clean `env -i` — a dyld-broken bundle now
  fails the build instead of shipping.

## Residual risks / not changed

- `Anime4K-Upscaler/Resources/Shaders/`, `Anime4K-Upscaler/Resources/VendoredTools/` binaries and `screenshots/` were not touched.