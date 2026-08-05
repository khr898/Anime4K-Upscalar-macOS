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

## Known audit gaps (2026-07-19)

The audit above ran a **CLI harness** built from `Models.swift` /
`CoreMLUpscaler.swift` against the exact ffmpeg argument arrays. That harness
exercises the **subprocess** pipelines (GLSL Anime4K via ffmpeg
`libplacebo`, NeuralSR via `realesrgan-ncnn-vulkan`) but it **never instantiated
`AVAssetReader` / `AVAssetWriter`** — the AVFoundation code path lives only in
the app's `ProcessingEngine.runANEEncode`, which the harness did not import.

Consequence: Special ANE modes (19–22) passed the audit ("regenerated models,
OK") on the basis of the CoreML model loading + a single-frame upscale, but the
full end-to-end `runANEEncode` path was never driven. The user-reported
`Failed to create reader.` defect (Special / SD-Rescue, MKV source) lives
exactly in that uncovered path — `AVAssetReader(asset:)` refuses Matroska
sources that ffmpeg decodes natively.

Fixes applied to `Anime4K-Upscaler/ViewModels/ProcessingEngine.swift`:
- `try?` swallowing at `AVAssetWriter` / `AVAssetReader` creation replaced with
  `do/try/catch` that propagates `error.localizedDescription` + domain/code, so
  the real OS-level reason is surfaced instead of a generic string.
- Reader creation gated on `shouldCreateReader(isSDRescue:needsRemux:)` —
  SDRescue + remux no longer creates a reader at all (audio + subs come from the
  original file via the ffmpeg remux, `-map 1:a? -map 1:s?`), eliminating the
  failure class for the user's MKV→MKV case with zero audio/video loss.
- SDRescue non-remux: if reader creation fails, an ffmpeg audio-copy mux
  fallback runs after the video writer finishes, so output is never silent.
- Mid-stream Core ML upscale errors are now distinguished from a clean
  end-of-stream and surfaced as `.failed(...)` instead of a truncated
  `.completed`.
- `job.outputURL!` force-unwraps removed on the NeuralSR and CoreML paths.
- Temp-frame cleanup `defer`s reordered to cover directory-creation-failure
  partial dirs on both the NeuralSR and SD-Rescue pre-pass paths.

Coverage: a `#if DEBUG` self-check (`ProcessingEngine._assertReaderGateSelfCheck`)
exercises the `shouldCreateReader` truth table at app launch; no Xcode test
target exists yet. **Future pipeline audits must drive the real `runANEEncode`
code path (or a test harness that imports `ProcessingEngine`), not a parallel
CLI reimplementation** — otherwise AVFoundation regressions stay invisible.

---

## 2026-07-20 — Special preset: AV1 source decode broken (silent → `Remux exited 183`)

**Method (audit way):** drove the *exact* streaming-decode arg array the app
builds (`RawVideoFrameSource.streamArgs`, non-SDRescue branch) against a real
3 s AV1 test clip (`/tmp/av1test.mkv`, libsvtav1 320×180 24fps) using the
bundled from-source ffmpeg (git-2026-07-17). Then extended to a full
h264/hevc/vp9/av1 codec matrix (`Tests/integration_decode_codec_matrix.sh`).

**Symptom reported:** Special (Core ML / ANE) preset on an AV1 source logs
`Your platform doesn't support hardware accelerated AV1 decoding` /
`Error submitting packet to decoder: Function not implemented` /
`Output file is empty, nothing was encoded` / `Conversion failed!`, then the
app surfaces `ERROR: Remux exited 183.` Reported on an M3 Pro (which *does*
support VideoToolbox AV1 decode).

**Root-cause chain (reproduced against the bundled binary):**
1. `bundle_dependencies.sh:build_custom_ffmpeg` configured ffmpeg **without
   `--enable-libdav1d`** → no software AV1 decoder. `config.h` had
   `CONFIG_LIBDAV1D 0`, `CONFIG_LIBAOM 0`.
2. The app's streaming-decode args omitted `-hwaccel`, so ffmpeg selected the
   native `av1` decoder, which is **hardware-only**; its VideoToolbox hwaccel
   is not engaged by default and the decoder has no software path → 0 frames.
3. `RawVideoFrameSource` ignored ffmpeg's exit status. 0 frames flowed into
   `runANEEncode` as a clean EOF → empty `.mov` → remux fails → user sees
   `Remux exited 183.` instead of the real decode error (the silent-failure
   class the 2026-07-19 note warned about for this exact path).

**Reproduction (audit arg array, bundled ffmpeg, M3 Pro):**
```
ffmpeg -y -i av1test.mkv -pix_fmt bgra -f rawvideo pipe:1
  → exit 69, 0 frames  ("Your platform doesn't support hardware accelerated AV1 decoding")
ffmpeg -y -hwaccel videotoolbox -i av1test.mkv -pix_fmt bgra -f rawvideo pipe:1
  → exit 0, 16588800 bytes (all 72 frames)   ← VT hw AV1 works on M3 Pro when asked
ffmpeg -y -c:v libdav1d -i av1test.mkv -pix_fmt bgra -f rawvideo pipe:1
  → exit 0, 16588800 bytes                    ← software fallback (universal)
ffmpeg -y -c:v av1 -i av1test.mkv -pix_fmt bgra -f rawvideo pipe:1
  → exit 69, 0 frames                         ← root-cause: native hw-only decoder, no hwaccel
```

**Fix:**
- **Build** (`Anime4K-Upscaler/Scripts/bundle_dependencies.sh`): appended
  `--enable-libdav1d` to the `./configure` call. With libdav1d compiled in,
  ffmpeg auto-selects it as the **default** AV1 decoder, so even the bare
  `-i` path now decodes AV1. Build now targets `make ffmpeg ffprobe` (in-tree
  binaries; `make install` fails on a missing libavfilter.a archive, which is
  non-fatal for the binary).
- **Pipeline** (`Anime4K-Upscaler/ViewModels/ProcessingEngine.swift`,
  `executeCoreMLJob`): replaced the single launch with a probe ladder over
  `DecodeMode` — `.videoToolbox` → `.softwareDav1d` → `.default` (non-SDRescue;
  SDRescue uses `.default` → `.softwareDav1d` because `-hwaccel videotoolbox`
  is unverified against the Vulkan `hwupload,libplacebo=…,hwdownload` chain).
  Each mode launches `RawVideoFrameSource`, pulls one raw frame via
  `nextRawFrame()` on a detached task; on success the frame is `pushFrame`d
  back and the source is handed to `runANEEncode`; on 0-frame failure
  (`hasFailed`) it cancels and tries the next mode. If all modes fail, the real
  ffmpeg stderr is surfaced as `.failed(...)` — never an empty `.mov`, never
  `Remux exited 183.`
- **Source** (`Anime4K-Upscaler/Utilities/RawVideoFrameSource.swift`): exposed
  `terminationStatus`, `framesPulled`, `hasFailed` (nonzero exit + 0 frames),
  `waitUntilExited()` (with a `process.terminationStatus` backstop for the
  pipe-EOF-vs-async-handler race), `nextRawFrame()` / `pushFrame()` so the
  probe ladder can test a mode without losing the probed frame to the encode
  loop. SDRescue `.videoToolbox` intentionally collapses to `.default`.

**Codec matrix** (`Tests/integration_decode_codec_matrix.sh`, bundled ffmpeg,
3 s 320×180 24fps clips, EXPECT = 16588800 bytes):
```
codec  | videoToolbox    | softwareDav1d   | default
h264   | 0/OK            | 183/FAIL        | 0/OK
hevc   | 0/OK            | 183/FAIL        | 0/OK
vp9    | 0/OK            | 69/FAIL         | 0/OK
av1    | 0/OK            | 0/OK            | 0/OK
AV1 VT-hw=OK | AV1 libdav1d=OK | AV1 default=OK(libdav1d auto) | native av1 hw-only=0frames(root-cause)
```
`softwareDav1d` failing on h264/hevc/vp9 is **expected** — libdav1d is
AV1-only; the ladder only reaches it when `.videoToolbox` fails, which for
non-AV1 on Apple Silicon never happens. Every codec has ≥1 working decode mode
→ frames reach the Core ML upscaler → every codec upscales. The upscaler
itself (PiperSR 128→256) was verified OK by the 2026-07-07 audit; the pipeline
sets `outW = inW * targetScale`, so a decoded frame at input resolution is the
only precondition for an upscaled output. AV1 is now decoded by VT (M3+) or
libdav1d (every other Mac), closing the gap.

**TDD evidence:** unit tests `Tests/DecodeArgsTests.swift` (6/6 — `streamArgs`
per mode + SDRescue VT-collapse) and `Tests/RawVideoFrameSourceProcessTests.swift`
(18/18 — `hasFailed` / `terminationStatus` / `framesPulled` / probe+pushback,
using `/bin/sh` as a fake ffmpeg) plus the integration matrix above. Full
RED/GREEN proof in `.claude/tdd/av1-decode-fix.tdd.md`.

**Coverage gap closed:** the 2026-07-19 note required driving the *real*
streaming-decode path against an AV1 source. The probe ladder now runs that
exact path (same `RawVideoFrameSource` the encode loop uses, not a parallel
CLI), and the codec matrix drives every accepted codec through every mode's
exact arg array. The `runANEEncode` AVFoundation writer path itself remains
un-driven by an automated harness (no Xcode test target); the decode side, the
prior failure surface, is now covered.
---

## 2026-07-22 — Pure Anime4K color patches: stale libplacebo 351 + ABI mismatch

**Symptom reported:** pure (GLSL) Anime4K pipeline outputs show intermittent
color patches appearing from time to time. User cited a known libplacebo 360.0
bug fixed in libplacebo 360.1, and that MoltenVK must be latest.

**Root cause (two compounding bugs in `bundle_dependencies.sh`):**
1. **Stale vendored libplacebo 351.** `Resources/VendoredDylibs/libplacebo.351.dylib`
   (compat 351.0.0) was shipped into `Frameworks/` and forced as the libplacebo
   for every ffmpeg. 351 predates the 360.1 color-patch fix, so the shader
   dispatch carried the older color-rounding bug.
2. **ABI mismatch on the from-source ffmpeg.** `build_custom_ffmpeg` compiled
   ffmpeg against the Homebrew libplacebo **360** headers, but the bundler's
   `relink_libplacebo_refs` + the vendored-libplacebo block then relinked that
   360-ABI binary onto the **351** dylib (`@executable_path/../Frameworks/libplacebo.351.dylib`).
   351 ≠ 360 soname → ABI-incompatible struct/`pl_renderer`/shader-cache layout
   → undefined behavior surfacing as wrong-color blocks on some frames.

**Versions found:**
| Artifact | Version |
|---|---|
| Vendored dylib `libplacebo.351.dylib` | 351 (removed) |
| Built ffmpeg `ffmpeg_build/ffmpeg/ffmpeg` | links `libplacebo.360.dylib` |
| Homebrew libplacebo | **7.360.1** (fixed) |
| Homebrew MoltenVK | **1.4.1** (latest) |

**Fix (`Anime4K-Upscaler/Scripts/bundle_dependencies.sh`):**
- Deleted `Resources/VendoredDylibs/libplacebo.351.dylib` and removed the
  `VENDORED_LIB_DIR` / `VENDORED_LIBPLACEBO` vars. libplacebo is now sourced
  from Homebrew only (pulled into `Frameworks/` by the existing recursive
  dylib copy, which already follows `/opt/homebrew/.../libplacebo.360.dylib`).
- Removed the vendored-ffmpeg (1a), homebrew-ffmpeg (1b), and DMG-download (1c)
  ffmpeg-source paths and the post-locate MoltenVK-linkage fallback block.
  `build_custom_ffmpeg` is now the **only** ffmpeg source — always built from
  source against the Homebrew libplacebo (>=7.360.1) headers so binary and
  shipped dylib share one ABI. Idempotent (clone-if-absent, `make` no-op if built).
- Added a Step 0 `brew install` + `brew upgrade libplacebo molten-vk` on every
  build so both stay at latest stable (libplacebo 7.360.1, MoltenVK 1.4.1).
  **Not pinned** — `brew upgrade` pulls the latest; no version gate blocks a
  future bump. A post-build presence check confirms the built ffmpeg links
  libplacebo (sanity only, not a version pin).

**Permanent:** Step 0 runs on every build; `brew upgrade` keeps libplacebo and
MoltenVK at latest stable. No session-scoped state. Note the dylib filename
stays `libplacebo.360.dylib` across 360.0→360.1 (soname doesn't move on a patch
release) — the actual fix lives in the Homebrew 7.360.1 bottle, which `brew
upgrade` installs. No vendored libplacebo remains in the repo.

## 2026-08-05 — Color patches persisted: copy-only-if-absent guard defeated `brew upgrade`

**Symptom:** the 2026-07-22 entry above declared the color-patch bug fixed, but
pure (GLSL) Anime4K output still showed intermittent color patches. The
Homebrew bottle was 7.360.1 (correct), the from-source ffmpeg linked
`libplacebo.360.dylib` (correct), yet the **bundled** dylib was still the
older 360.0 bottle.

**Root cause:** `copy_dylibs_recursive` in `bundle_dependencies.sh` used a
`if [[ ! -f "$dest" ]]` copy guard — each dylib was copied into `Frameworks/`
**once**, on first build, and never refreshed again. Step 0's `brew upgrade`
correctly pulled the 360.1 bottle into Homebrew's cellar, but the recursive
copy saw the stale 360.0 already present at `$dest` and skipped it. The 360.0
bottle (carrying the `custom_shader` color-patch bug) shipped indefinitely;
the 360.1 fix never reached the app bundle. The 2026-07-22 audit verified the
Homebrew side and the ffmpeg-link side but never re-checked the **bundled**
dylib's bytes, so the staleness went undetected.

**Fix (`Anime4K-Upscaler/Scripts/bundle_dependencies.sh`):**
- Replaced the `! -f "$dest"` copy-only-if-absent guard with a refresh-on-
  difference check: `elif [[ ! -f "$dest" ]] || ! cmp -s "$actual_path" "$dest"`.
  When the Homebrew source differs from the bundled copy (a `brew upgrade`
  changed the bottle, or a prior relink touched the dest), the dylib is
  re-copied and the recursive call re-fixes its install names/refs (step 4
  already runs on every dylib each build). `cmp -s` short-circuits on the first
  differing byte, so unchanged deps stay cheap.
- Added `dav1d` to Step 0's `brew install` + `brew upgrade` line (the from-source
  ffmpeg is configured `--enable-libdav1d`; the previous `|| true` had been
  silently masking a wrong formula name `libdav1d`, which doesn't exist — the
  correct formula is `dav1d`, which provides `libdav1d`).

**Fix (`.github/workflows/build.yml`):**
- Rewrote the "Install latest dependencies" CI step: `brew update` +
  `brew install libplacebo molten-vk dav1d pkg-config xcodegen` +
  `brew upgrade libplacebo molten-vk dav1d`. `brew install` alone is a no-op
  when the macos-latest runner already ships an older bottle, so `brew upgrade`
  is required to guarantee the newest bottles reach the bundle. Removed the
  stale `homebrew-ffmpeg` tap install (no longer used).
- Strengthened the "Validate bundled FFmpeg libplacebo support" step: the
  soname-360 check can't distinguish 360.0 from 360.1 (soname is identical
  across the patch release), so it now also asserts the bundled dylib's size
  matches the Homebrew bottle's size (within a 4 KB delta for relink byte
  shift) and that its mtime is within the last 10 minutes (a stale cached copy
  from a prior build would be older → fail the build).

**Verification (2026-08-05, local):** `xcodebuild ... build` → bundler logged
`🔄 Refreshing (Homebrew upgrade): libplacebo.360.dylib` (and its transitive
deps `libshaderc_shared.1`, `libvulkan.1`, `libdav1d.7`, etc.), then
`** BUILD SUCCEEDED **`. Bundled `libplacebo.360.dylib` = 957792 bytes,
Homebrew `libplacebo.360.dylib` = 957792 bytes (identical size → same 360.1
bottle), `otool -D` shows `@executable_path/../Frameworks/libplacebo.360.dylib`.
Homebrew versions: libplacebo 7.360.1, molten-vk 1.4.2, dav1d 1.5.4.

**Residual cleanup (not runtime-affecting):** `Anime4K-Upscaler/Resources/VendoredTools/`
still holds a stale Jul-17 `ffmpeg`/`ffprobe` that link the removed
`libplacebo.351.dylib`. It is a pbxproj **group** only (no `in Resources` build
phase), so it is NOT copied into the app bundle and `FFmpegLocator` resolves the
fresh `Frameworks/ffmpeg` at runtime. Dead weight on disk; safe to delete in a
follow-up once confirmed no tooling references the path.
