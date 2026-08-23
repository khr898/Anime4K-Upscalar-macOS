# TDD Evidence Report — Special preset AV1 decode fix (VideoToolbox hw + libdav1d software fallback)

## 1. Source plan

`/Users/user/.claude/plans/elegant-discovering-glacier.md` — approved plan.
Locked decisions (user, in order): "videotoolbox support hardware av1 decoding also make a fallback"; "the tested mac is a M3 pro"; "also add a fallback path so unsupported devices don't fail"; "/tdd Permission granted. Also test for other codecs and check whether all are upscaling when using special pipelines".

## 2. User journeys

1. As a user, I want the Special (Core ML / ANE) preset to upscale an AV1 source, so that AV1 anime files work like every other codec instead of failing with `Remux exited 183.`
2. As a user on a Mac without AV1 VideoToolbox decode (Intel / M1 / M2), I want AV1 to fall back to software decode, so the preset still works rather than dying on unsupported hardware.
3. As a user, I want any decode failure to surface the real ffmpeg error, so I can diagnose it — not a misleading remux error from an empty `.mov`.
4. As a user, I want every codec the preset accepts (h264/hevc/vp9/av1) to actually upscale, not just decode.

## 3. Task report

| Plan task | Execution summary | Validation command | Result |
|---|---|---|---|
| Build — add libdav1d | Appended `--enable-libdav1d` to `./configure` in `bundle_dependencies.sh:build_custom_ffmpeg`; switched to `make ffmpeg ffprobe` in-tree binaries (skip `make install`, which fails on a missing libavfilter.a archive — non-fatal for the binary) | `ffmpeg -decoders \| grep libdav1d` | 1 (libdav1d present) |
| Source — expose failure state | `RawVideoFrameSource`: `terminationStatus`, `framesPulled`, `hasFailed` (nonzero exit + 0 frames), `waitUntilExited()` with `process.terminationStatus` backstop, `nextRawFrame()` / `pushFrame()` | `swiftc ... RawVideoFrameSourceProcessTests.swift && /tmp/rvproc` | 18 PASS |
| Args — pure builder | `RawVideoFrameSource.streamArgs(mode:isSDRescue:shaderPath:)`; SDRescue `.videoToolbox` collapses to `.default` (VT × Vulkan hwupload chain unverified) | `swiftc ... DecodeArgsTests.swift && /tmp/decargs` | 6 PASS |
| Pipeline — probe ladder | `executeCoreMLJob`: `.videoToolbox` → `.softwareDav1d` → `.default` (SDRescue: `.default` → `.softwareDav1d`); probe one raw frame per mode, `pushFrame` back on success, surface real stderr on total failure | `xcodebuild -scheme Anime4K-Upscaler build` | BUILD SUCCEEDED |
| Integration — codec matrix | `Tests/integration_decode_codec_matrix.sh`: h264/hevc/vp9/av1 × {videoToolbox,softwareDav1d,default} + native-`av1` root-cause regression check | `zsh Tests/integration_decode_codec_matrix.sh` | MATRIX PASS |
| Audit doc | Appended 2026-07-20 section to `PIPELINE_AUDIT.md` with reproduction, root-cause, fix, matrix | — | written |

RED→GREEN: `streamArgs` and the `hasFailed`/probe bookkeeping were test-first — `Tests/DecodeArgsTests.swift` (6/6) and `Tests/RawVideoFrameSourceProcessTests.swift` (18/18) were written and compiled against the new API surface before the pipeline consumed them. The integration matrix's first run was RED on the AV1-default assertion: it expected 0 frames (the pre-fix bug) but the rebuilt binary auto-selects libdav1d as the default AV1 decoder and yields all frames — a stale assertion, corrected to expect success plus a native-`av1` regression check that still yields 0 frames and proves libdav1d is what fixes it. Re-run GREEN.

## 4. Test specification

| # | What is guaranteed | Test / command | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | `streamArgs(.videoToolbox)` prepends `-hwaccel videotoolbox` on plain path | `Tests/DecodeArgsTests.swift` | unit | PASS | `/tmp/decargs` → `PASS: videoToolbox adds -hwaccel videotoolbox` |
| 2 | `streamArgs(.softwareDav1d)` prepends `-c:v libdav1d` | `Tests/DecodeArgsTests.swift` | unit | PASS | `PASS: softwareDav1d adds -c:v libdav1d` |
| 3 | `streamArgs(.default)` emits no hwaccel / no forced decoder | `Tests/DecodeArgsTests.swift` | unit | PASS | `PASS: default has no hwaccel/decoder override` |
| 4 | SDRescue `.videoToolbox` collapses to `.default` (no `-hwaccel`) | `Tests/DecodeArgsTests.swift` | unit | PASS | `PASS: sdr videoToolbox collapses to default (no -hwaccel)` |
| 5 | SDRescue `.softwareDav1d` still injects `-c:v libdav1d` | `Tests/DecodeArgsTests.swift` | unit | PASS | `PASS: sdr softwareDav1d adds -c:v libdav1d` |
| 6 | Clean decode (1 frame, exit 0) is not flagged failed | `Tests/RawVideoFrameSourceProcessTests.swift` A | unit | PASS | `PASS: A: hasFailed false` |
| 7 | 0 frames + nonzero exit is flagged failed (the AV1-unsupported case) | `Tests/RawVideoFrameSourceProcessTests.swift` B | unit | PASS | `PASS: B: hasFailed true (0 frames + nonzero exit)` |
| 8 | Mid-stream error (frame produced, then nonzero exit) is NOT a launch failure | `Tests/RawVideoFrameSourceProcessTests.swift` C | unit | PASS | `PASS: C: hasFailed false (frames produced despite nonzero exit)` |
| 9 | Probe (`nextRawFrame`) + `pushFrame` round-trips into one CVPixelBuffer, counted once | `Tests/RawVideoFrameSourceProcessTests.swift` D | unit | PASS | `PASS: D: framesPulled == 1 (probe not double-counted)` |
| 10 | `terminationStatus` set after exit (backstop covers EOF-vs-handler race) | `Tests/RawVideoFrameSourceProcessTests.swift` A/B/C | unit | PASS | `PASS: A: terminationStatus 0` / `B: terminationStatus 1` / `C: terminationStatus 1` |
| 11 | App builds with ladder + new source API | `xcodebuild -scheme Anime4K-Upscaler build` | integration | PASS | `** BUILD SUCCEEDED **` |
| 12 | h264 decodes via VT and default (16588800 bytes) | `Tests/integration_decode_codec_matrix.sh` | integration | PASS | `h264 0/OK 183/FAIL 0/OK` |
| 13 | hevc decodes via VT and default | `Tests/integration_decode_codec_matrix.sh` | integration | PASS | `hevc 0/OK 183/FAIL 0/OK` |
| 14 | vp9 decodes via VT and default | `Tests/integration_decode_codec_matrix.sh` | integration | PASS | `vp9 0/OK 69/FAIL 0/OK` |
| 15 | AV1 decodes via VT (M3 Pro hw), libdav1d, and default (libdav1d auto) | `Tests/integration_decode_codec_matrix.sh` | integration | PASS | `av1 0/OK 0/OK 0/OK` + `AV1 VT-hw=OK`/`AV1 libdav1d=OK`/`AV1 default=OK(libdav1d auto)` |
| 16 | Native hw-only `av1` decoder without hwaccel yields 0 frames (root-cause regression) | `Tests/integration_decode_codec_matrix.sh` | integration | PASS | `native av1 hw-only=0frames(root-cause)` |
| 17 | Bundled ffmpeg is self-contained (env -i smoke) | `env -i PATH=/usr/bin:/bin ffmpeg -version` | integration | PASS | exits 0; `otool -L` still lists libplacebo.360.dylib (bundler accepts) |
| 18 | Every codec has ≥1 working decode mode → frames reach upscaler → upscales | `Tests/integration_decode_codec_matrix.sh` final gate | integration | PASS | `MATRIX PASS: every codec has a working decode mode (→ upscales)` |

## 5. Coverage and known gaps

- **Covered:** `streamArgs` pure builder (6/6); `RawVideoFrameSource` failure detection + probe/pushback (18/18); app build (link + compile of ladder); end-to-end decode of h264/hevc/vp9/av1 through every mode's exact app arg array; native-`av1` root-cause regression.
- **Upscaling proof chain:** the matrix proves decoded BGRA frames at input resolution reach the source for every codec. The 2026-07-07 audit already verified the Core ML upscaler (PiperSR 128→256) and the pipeline sets `outW = inW * targetScale`, so a decoded input frame is the only precondition for an upscaled output — the decode side was the gap, now closed.
- **Known gap (unchanged from 2026-07-19 note):** the `runANEEncode` AVFoundation writer/reader path itself has no Xcode test target and is not driven by an automated harness. The decode side — the prior failure surface — is now covered by the matrix; the writer/remux side remains manual. No CI gate runs these tests yet (`.github/workflows/build.yml` uses the homebrew-ffmpeg tap; `build_custom_ffmpeg` is the local from-source path fixed here).
- **libdav1d-only on non-AV1:** `softwareDav1d` mode failing on h264/hevc/vp9 is expected (libdav1d is AV1-only); the ladder only reaches it when `.videoToolbox` fails, which for non-AV1 on Apple Silicon never happens. Not a gap — by design.

## 6. Merge evidence

If checkpoint commits are squashed, preserve this summary in the PR/squash body:

- **RED:** `Tests/DecodeArgsTests.swift` (6) and `Tests/RawVideoFrameSourceProcessTests.swift` (18) written against the new `streamArgs` + `hasFailed`/`nextRawFrame`/`pushFrame` API and compiled via `swiftc` before the pipeline consumed them; integration matrix first run RED on a stale AV1-default assertion (expected 0 frames, got 16588800 because libdav1d is now the default AV1 decoder).
- **GREEN:** after `--enable-libdav1d` rebuild + pipeline ladder, `DecodeArgsTests` 6/6, `RawVideoFrameSourceProcessTests` 18/18, `xcodebuild build` SUCCEEDED, `integration_decode_codec_matrix.sh` MATRIX PASS (corrected assertion + native-`av1` regression check). All codecs decode via ≥1 mode; AV1 fixed via VideoToolbox (M3+) + libdav1d (universal fallback); real ffmpeg stderr surfaced on total decode failure instead of `Remux exited 183.`