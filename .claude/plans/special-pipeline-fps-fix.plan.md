# Plan: Special Pipeline FPS Fix (CoreML/ANE + MetalFX)

**Created:** 2026-07-22
**Target hardware:** Apple Silicon, primary reference = M3 Pro (18 TOPS ANE, 150 GB/s, macOS 26 Tahoe / Darwin 25.5)
**Goal:** Make Special upscale presets fast enough to be practical at 1080p→4K. Add new presets. Fix model + pipeline architecture.

---

## How to use this plan (READ FIRST — session-resilient)

This file is the single source of truth. Any AI session can resume by reading this section + the Phase Status table below.

**Resume protocol (run at the start of every session):**
1. Read this entire file.
2. Run the **State Check** commands in the *Phase Status* table to determine which phases are actually done on disk (do not trust the table blindly — verify).
3. Pick the lowest-numbered phase whose status is `pending` or `blocked`, read its *Steps* + *Validation*, and execute.
4. After a phase passes its **Done-when** gate, update its row in the *Phase Status* table: set status `done`, fill the *Evidence* cell with the validation command output or a file path/commit hash.
5. Do not skip the **Gate** of a phase — later phases depend on earlier gates being truly green.
6. Code/commit style: follow repo conventions (`conventional` commit prefixes, camelCase files, relative imports). Commit after each phase passes its gate.

**Caveman/ponytail plugins may be active in this repo.** They affect prose style only. Code, commits, plans, and security checks are written normally.

**Graphify hook:** `graphify query "..."` must run before grepping/reading source files (project rule). Run it at phase start to orient.

**Do not re-derive facts already in this plan.** Do not re-research the web numbers; they are cited in the *Research Appendix*. Only re-research if a validation result contradicts a stated number.

---

## Phase Status table (UPDATE THIS as phases complete)

| # | Phase | Status | Gate evidence | Notes |
|---|---|---|---|---|
| 0 | Probe VTFrameProcessor support on M3 Pro | done | `.claude/plans/phase0-vt-probe.txt` — high-quality isSupported=true, scaleFactors=[4], init OK @1920x1080x4 (video, modelStatus=0=DownloadRequired); low-latency maxDim 960x960 → empty scaleFactors @1080p/720p, [2.0]@640x480 | Low-latency unusable @1080p (expected). High-quality VT SR viable optional quality path @1080px4 (needs model download) → candidate special_VTSR in Phase 5. Proceed to Phase 1. |
| 1 | MLComputePlan audit of existing models | done | `.claude/plans/phase1-computeplan.txt` — ALL 3 models 0 ANE ops, 100% CPU compute. pipersr 138ops/32CPU/0ANE; animevideov3 195ops/42CPU/0ANE (ios17.prelu CPU); realesrgan 1043ops/280CPU/0ANE (ios17.leaky_relu/concat CPU) | Root cause worse than expected: even pipersr (ModelPiper 44fps on ANE) is 100% CPU here → conversion config broken, not just model size. ios17.prelu + ios17.leaky_relu = Phase 7 PReLU→SiLU targets. Phase 2 must fix conversion (deployment target / compute_units / FP16 / opset). |
| 2 | Re-convert models fixed-large-shape + TensorType | pending | | |
| 3 | CoreMLUpscaler full-frame + ring + IOSurface + Metal | pending | | |
| 4 | runANEEncode double-buffered pipeline | pending | | |
| 5 | Add new presets (MetalFX, Hybrid, Neural2x, PiperSR-2pass) | pending | | |
| 6 | Swift benchmark harness + MLComputePlan CI | pending | | |
| 7 | Op-placement + compute_precision audit fixes | pending | | |
| 8 | Optional: distill animevideov3 / RRDB prune | pending | | |

**Status values:** `pending` | `in_progress` | `done` | `blocked` | `skipped` (with reason).

---

## Problem statement & root cause

Special pipeline = modes 19-22 in `Models.swift` (`special_Fast`=19, `special_Quality`=20, `special_SDRescue`=21, `special_PiperSR_2x`=22). All route through `CoreMLUpscaler.upscale` → `runANEEncode`. Current throughput at 1080p→4K ≈ **1-3 fps**. Pure Anime4K (GLSL shader) beats it because Anime4K is a cheap GPU shader, not a 4x SR neural network.

**Root cause (three compounding bugs, confirmed in code + web):**

1. **Tiling kills ANE throughput.** Models converted at fixed 128×128 (PiperSR) / 256×256 (ESRGAN). `upscale` chops each 1080p frame into 240 (PiperSR) / 45 (ESRGAN) tiles, one `model.prediction` per tile. `CoreMLUpscaler.swift:108` documents it: "240 tiles × ~10ms ANE per-call overhead ≈ 2.4s/frame = 0.4fps". ANE dispatch overhead dominates compute. `inferConcurrency=8` does not help — ANE is one engine, 8 queued tiny tiles serialize on hardware.

2. **Serial per-frame pipeline, no hardware overlap.** `runANEEncode` (`ProcessingEngine.swift:845-867`) pulls one frame, runs crop→infer→blit→`CILanczosScaleTransform` fully serial inside `requestMediaDataWhenReady`, then asks for next. CPU/ANE/GPU never overlap. The final `CILanczosScaleTransform` is an extra full-frame GPU pass when `targetScale != nativeScale` (`CoreMLUpscaler.swift:198-208`).

3. **Conversion risks ANE placement failure.** `convert_models.py` uses `ct.ImageType` output + fixed tiny tile (the libBNNS-crash fix). Plus: animevideov3 is **621K params — below the ~1M Core ML scheduler threshold** where ANE dispatch is worth it; scheduler may place it on CPU even with `.cpuAndNeuralEngine`. `EnumeratedShapes` (the obvious flexible fix) is documented to create dynamic tensors → CPU fallback (`coremltools` #2370, #1909, #1764). Python `coremltools` `predict()` is CPU-only on macOS — cannot validate ANE from Python (explains why prior audits missed this).

**M3 Pro physics (hard ceiling for true neural 4x SR):** ANE is bandwidth-bound, M3 Pro has 150 GB/s (1/6 of V100's 900 GB/s, 1/3 of M4 Max's ~400). V100 does animevideov3 1080p 4x = 10 fps. M3 Pro ANE ≈ 3-6 fps model-time for neural 4x after SRAM amortization. **100 fps @ 1080p→4K is only reachable via GPU spatial upscaling (MetalFX), not neural SR.** This is physics, not a bug. The plan therefore adds MetalFX as a fast path and keeps neural SR as the quality path.

---

## Per-preset target FPS (M3 Pro, 1080p→4K)

| Preset (existing/new) | Model | Scale | Path | Est. fps | Quality | True SR? |
|---|---|---|---|---|---|---|
| special_Fast (19) existing | realesr-animevideov3 | 4x | neural full-frame | **3-6** | high | yes |
| special_Quality (20) existing | realesrgan-x4plus-anime (RRDB 6B) | 4x | neural large-tile | **1.5-3** | best | yes |
| special_SDRescue (21) existing | animevideov3 + Anime4K Restore VL | 4x | neural + GPU prepass | **3-5** | high | yes |
| special_PiperSR_2x (22) existing | pipersr | 2x | neural (1080→2K) | **12-20** | high (2x) | yes |
| **special_MetalFX (new)** | MetalFX spatial | 4x | GPU spatial | **40-90** | game-grade | no |
| **special_Balanced (new)** | animevideov3 2x + MetalFX 2x | 4x | hybrid | **10-18** | medium-high | half |
| **special_Neural2x (new)** | animevideov3 upscale=2 | 2x | neural (1080→2K) | **12-20** | high (2x) | yes |
| **special_PiperSR_4x (new, conditional)** | 2× pipersr | 4x | neural 2-pass | **4-8** | medium | yes (ship only if beats Fast) |

Targets are gates. A preset that misses its target is not "done" — investigate before marking done.

---

## Research Appendix (all levers found, folded into phases)

### A. Model conversion / ANE placement
- **Fixed concrete shape, NOT EnumeratedShapes.** EnumeratedShapes (mlprogram) creates dynamic tensors → CPU fallback; even a single conv→relu hit it; only the default shape used ANE (30 vs 370 it/s). Sources: coremltools #2370, #1909, #1764. → Phase 2 uses fixed shape, tiles the frame into that fixed shape.
- **Static/baked weights.** Fixed shape → static graph → 2.82× faster than dynamic (ModelPiper). → Phase 2.
- **TensorType output, NOT ImageType.** The original libBNNS crash was `ImageType` output + flexible input. TensorType resolves output size from input symbolically and avoids the crash class. Swift converts tensor→CVPixelBuffer. → Phase 2.
- **`MLComputePlan` runtime placement (macOS 14.4+).** Only way to prove per-op ANE placement. Python predict() is CPU-only on macOS. ~1M-param scheduler threshold: below it, Core ML may pick CPU even for 100%-eligible models. → Phase 1 audit + Phase 6 CI gate. Source: Meridian blog.
- **`compute_precision`, not `compute_units`.** FP32 bars ANE (no FP32 units). Hybrid `Float16ComputePrecision()` keeps FP32 for accum-heavy ops only. SR conv = FP16 throughout. Verify `ImageWrapper` clamp×255 did not leak FP32. → Phase 7. Source: coremltools Typed Execution.
- **Pre-compile + ship `.mlmodelc`.** App currently caches compiled in App Support; ship pre-compiled in bundle → no on-device ANE compiler hang on first run. → Phase 2.

### B. Pipeline overlap
- **Double-buffered ring, ≥2 deep.** CPU (convertIn BGRA→Float16) / ANE (predict) / GPU (convertOut Metal) overlap across frames. fps = max(stage), not sum. 2-deep ping-pong prevents ANE async read/write races (ANEMLL). → Phase 4. Source: ModelPiper.
- **IOSurface zero-copy output.** Back ANE output CVPixelBuffer/MLMultiArray with IOSurface + Metal-compat keys → eliminate `blitMemcpy` CPU→GPU copy. → Phase 3. Source: CoreML-LLM survey.
- **Metal compute shader for float16→BGRA.** 1.3 ms vs 7.6 ms CPU (5.8×). Replaces `CILanczosScaleTransform` when native==target, and does the resize when native!=target. → Phase 3. Source: ModelPiper.
- **Pre-allocated buffers, dedicated DispatchQueue.** Zero per-frame heap alloc; dedicated queue bypasses Swift cooperative pool (3-5 ms jitter). → Phase 4. Source: ModelPiper.
- **`.cpuAndNeuralEngine`, NOT `.all`.** `.all` is 23.6% slower (GPU misrouting). App already uses `.cpuAndNeuralEngine` — keep. Source: ModelPiper.

### C. Apple official upscaling (macOS 26 has all)
- **MetalFX `MTLFXSpatialScaler`** (WWDC22/25). GPU spatial upscaler, 1080p→4K, game-grade, fast (40-90 fps est). One `encode(commandBuffer:)` pass. Create scaler once at launch (expensive). Place after tone mapping, perceptual color mode. → Phase 5 new preset `special_MetalFX`. Source: Apple MetalFX docs.
- **MetalFX `MTLFXTemporalScaler`** — needs motion vectors + depth per frame. N/A for static video file upscaling (no motion vectors). Skip unless a future frame-interp mode derives them.
- **VTFrameProcessor high-quality SR** (`VTSuperResolutionScalerConfiguration`, macOS 15.4+). Apple neural SR, up to 1920×1080 input, configurable scale, not real-time, requires model download. fps unpublished (est 2-5). → Phase 0 probe; if usable, optional quality path. Source: WWDC25 Session 300.
- **VTFrameProcessor low-latency SR** (`VTLowLatencySuperResolutionScalerConfiguration`). Real-time, but forums report 1080p/720p return empty scale factors on tested devices (640×480 → [2.0]). → Phase 0 probe; low expectation at 1080p.

### D. Model tweaks (less compromise)
- **animevideov3 2x variant.** Same SRVGGNetCompact weights support upscale=1/2/3/4; convert a fixed 2x variant for 1080→2K (1/4 output bandwidth of 4x → 4× faster). Zero quality compromise (same weights). → Phase 2.
- **PReLU→SiLU if CPU fallback.** M3 adds LUT activations (SiLU/GELU native). If `MLComputePlan` shows PReLU on CPU, swap to SiLU + brief fine-tune. → Phase 7 conditional.
- **PiperSR at fixed 1080p.** ModelPiper ships PiperSR resolution-locked to 640×360; other resolutions fall to tiled 5-10 fps. Convert at fixed 1920×1080 (pure conv, supports any concrete shape). Fine-tune on 1080p tiles to avoid unseen-resolution quality drop. → Phase 2.
- **2-pass PiperSR 4x.** 1080→2160→4320, two full-frame dispatches. Ship only if it beats animevideov3 4x in Phase 6 benchmark. → Phase 5 conditional.
- **RRDB 6B large-tile, not full-frame.** Dense 64ch feature maps at 1080p exceed ANE SRAM. Convert with the largest fixed tile the ANE accepts (probe 540/720/960). Optional prune 6→4 RRDB blocks + fine-tune if <2 fps. → Phase 2.
- **BN/`ImageWrapper` fusion.** coremltools auto-fuses `fuse_conv_bias`, `fuse_conv_batchnorm`. animevideov3 has no BN. Verify `ImageWrapper` clamp×255 is fused/ANE-native `mul`+`clamp`, not CPU. → Phase 7.
- **Skip INT8/quantization for SR.** Small models fit SRAM; quantization adds dequant overhead at every layer for zero gain (ModelPiper). Not used.

### E. SDRescue specifics
- Anime4K Restore VL GLSL shader runs in the ffmpeg decode filter chain (GPU). The ring pipeline overlaps GPU-restore of frame N+1 with ANE-upscale of frame N — decode stage is already separate from ANE stage. → Phase 4 handles this automatically; no extra work beyond using the B1 animevideov3 model.

---

## Phase 0 — Probe VTFrameProcessor support on M3 Pro

**Goal:** Determine if Apple's native neural SR is usable at 1080p before investing in CoreML rebuild. Cheap, decisive.

**Files:**
- `Tests/VTFrameProcessorProbe.swift` (CREATE) — `@Test` Swift Testing case, `#if canImport(VideoToolbox)`.

**Steps:**
1. `graphify query "VTFrameProcessor super resolution probe"` to orient.
2. Write a Swift test that, on first run, queries and prints:
   - `VTLowLatencySuperResolutionScalerConfiguration.isSupported`
   - `VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(frameWidth: 1920, frameHeight: 1080)` — and 1280×720, 640×480.
   - `VTSuperResolutionScalerConfiguration.isSupported` + its supported scale factors / max dimensions.
3. Run on the M3 Pro target. Record results in the Phase Status evidence cell.

**Validation:**
```bash
swift test --filter VTFrameProcessorProbe 2>&1 | tee .claude/plans/phase0-vt-probe.txt
```

**Done-when:** Probe output captured. Decision recorded: which VT tiers (if any) are usable at 1080p. If low-latency returns `[4.0]` for 1080p → add a `special_VTLowLatency` preset in Phase 5 and skip neural rebuild for the fast path. If empty (expected) → proceed to Phase 1.

---

## Phase 1 — MLComputePlan audit of existing models

**Goal:** Prove whether the existing converted models actually run on ANE or silently fall back to CPU. This likely explains part of the current slowness (animevideov3 is 621K params, below the ~1M scheduler threshold).

**Files:**
- `Tests/MLComputePlanAudit.swift` (CREATE) — loads each `.mlmodelc`, builds `MLComputePlan` (macOS 14.4+), enumerates per-op `computeUnit` and `device`.

**Steps:**
1. Confirm compiled `.mlmodelc` exists in App Support (`~/Library/Application Support/CompiledModels/`) or compile a `.mlpackage` via `MLModel.compileModel`.
2. For each model (`pipersr`, `realesr-animevideov3`, `realesrgan-x4plus-anime`): load with `.cpuAndNeuralEngine`, build `MLComputePlan`, iterate `MLComputePlan.program.ops` (or the program's MIL ops exposed via the plan), print each op's assigned compute unit.
3. Summarize: % ops on ANE vs CPU vs GPU. Flag any CPU op as a blocker.

**Validation:**
```bash
swift test --filter MLComputePlanAudit 2>&1 | tee .claude/plans/phase1-computeplan.txt
```

**Done-when:** Per-model placement table captured. Any CPU/GPU fallback op listed with op name. This is the baseline — Phase 2/7 must show 0 CPU fallback on the rebuilt models.

---

## Phase 2 — Re-convert models: fixed large shape + TensorType + FP16 + ship .mlmodelc

**Goal:** ANE-native models with few large dispatches, static weights, no dynamic tensors.

**Files:**
- `Anime4K-Upscaler/Scripts/convert_models.py` (UPDATE)
- `Anime4K-Upscaler/Resources/Models/*.mlpackage` (REGENERATE)
- Pre-compiled `.mlmodelc` shipped into bundle (UPDATE bundle script if needed)

**Per-model steps:**

**B1 — realesr-animevideov3 (Fast + SDRescue), 4x:**
- Convert at **fixed 1920×1080** (or the largest fixed shape the ANE accepts — probe). `ct.TensorType` output (name `output`), `ct.ImageType` input with fixed shape (concrete, not Enumerated). `scale=1/255`, `color_layout=RGB`.
- `convert_to="mlprogram"`, `compute_units=ct.ComputeUnit.CPU_AND_NE`, `minimum_deployment_target=ct.target.macOS14`.
- Keep `ImageWrapper` clamp×255 in FP16. Verify `compute_precision` default FP16 (no FP32 leak).
- Also convert a **2x variant** (same weights, `upscale=2`).

**B2 — realesrgan-x4plus-anime (Quality), 4x RRDB 6B:**
- Probe largest ANE-accepted fixed tile (540/720/960). Convert at that fixed tile (not full-frame — RRDB dense feature maps exceed SRAM at 1080p).
- Same `TensorType` output, FP16, `CPU_AND_NE`, macOS14.

**B3 — pipersr (2x + new 2-pass 4x), fixed 1080p:**
- Convert PiperSR at fixed 1920×1080 (currently 640×360-locked). Pure conv arch accepts any concrete shape.
- Fine-tune on 1080p tiles to avoid quality drop at unseen resolution (or accept the drop and measure PSNR in Phase 6).

**Validation:**
```bash
cd Anime4K-Upscaler/Scripts && python3 convert_models.py ../Resources/Models 2>&1 | tee ../../.claude/plans/phase2-convert.txt
# Verify each model loads + has TensorType output + fixed input:
python3 -c "import coremltools as ct; m=ct.models.MLModel('../Resources/Models/realesr-animevideov3.mlpackage'); print(m.input_description, m.output_description)" 2>&1 | tee -a ../../.claude/plans/phase2-convert.txt
```

**Done-when:** All models reconverted, TensorType output, fixed input shape confirmed, `.mlmodelc` pre-compiled into bundle. Phase 1 audit re-run on new models shows 0 CPU fallback (record in evidence).

**Risk:** Fixed full-frame 1080p may exceed ANE SRAM → internal retile (still 1 dispatch but slower). If Phase 6 shows full-frame slower than large-tile, switch to the largest fixed tile that fits and tile the frame into it. Keep the tile code path as fallback.

---

## Phase 3 — CoreMLUpscaler full-frame + ring + IOSurface + Metal

**Goal:** Replace tiled serial crop/infer/blit/Lanczos with full-frame single dispatch, zero-copy output, Metal float16→BGRA.

**Files:**
- `Anime4K-Upscaler/ViewModels/CoreMLUpscaler.swift` (UPDATE)
- `Anime4K-Upscaler/Utilities/MetalSRConvert.swift` (CREATE) — Metal compute shader `float16PlanarToBGRA8` + optional resize, ported from ModelPiper pattern.

**Steps:**
1. Add a full-frame path: when model fixed input shape == frame size (or frame is tiled into the largest fixed shape), single `model.prediction` dispatch. Keep the existing tile loop only as fallback for frames larger than the model's max fixed shape.
2. Switch I/O to `MLMultiArray` (TensorType) — read output tensor directly, convert to `CVPixelBuffer` via the Metal shader (no `CIContext.render`, no `CILanczosScaleTransform` when native==target).
3. Back the output `CVPixelBuffer` with IOSurface + Metal-compat keys (`kCVPixelBufferIOSurfacePropertiesKey`, `kCVPixelBufferMetalCompatibilityKey`) → zero-copy handoff to GPU blit/encode.
4. When `targetScale != nativeScale`, do the resize in the Metal compute pass (one pass), not `CILanczosScaleTransform`.
5. Pre-allocate output buffers; no per-frame allocation.

**Validation:**
```bash
swift build 2>&1 | tee .claude/plans/phase3-build.txt
# Typecheck 0 errors. Existing unit tests still pass:
swift test --filter CoreML 2>&1 | tee -a .claude/plans/phase3-build.txt
```

**Done-when:** Build green, no `CIContext.render`/`CILanczosScaleTransform` on the full-frame path, IOSurface-backed output, Metal shader compiles. Existing `Tests/FrameAccumulatorTests.swift` etc. still pass.

---

## Phase 4 — runANEEncode double-buffered pipeline

**Goal:** Overlap decode / ANE / GPU-blit across frames via a ≥2-deep ring.

**Files:**
- `Anime4K-Upscaler/ViewModels/ProcessingEngine.swift` (UPDATE `runANEEncode`)

**Steps:**
1. Replace the single `requestMediaDataWhenReady` body with a ring of 2-3 `FrameSession` buffers (pre-allocated, IOSurface-backed).
2. Pipeline: frame N+1 decode (ffmpeg stdout → BGRA, CPU) ‖ frame N ANE predict ‖ frame N-1 Metal blit + writer append.
3. Dedicated `DispatchQueue` (not Swift cooperative pool) for the ANE stage.
4. Preserve strict PTS/append order — the writer must append frames in decode order. Use the ring index to maintain order, not unbounded async.
5. SDRescue: the Anime4K Restore VL GLSL prepass runs in ffmpeg decode (GPU) — already the decode stage, automatically overlapped. No extra work.
6. Keep cancel propagation (`CancellationToken`); the ring must drain on cancel.

**Validation:**
```bash
swift build 2>&1 | tee .claude/plans/phase4-build.txt
swift test 2>&1 | tee -a .claude/plans/phase4-build.txt
# Integration decode matrix still green:
bash Tests/integration_decode_codec_matrix.sh 2>&1 | tee -a .claude/plans/phase4-build.txt
```

**Done-when:** Build + all tests green, decode matrix green, frames appended in order (visual spot-check: output plays correctly, no frame reorder stutter).

---

## Phase 5 — Add new presets to Models.swift

**Goal:** Expose MetalFX fast path, hybrid, neural 2x, and conditional 2-pass PiperSR as presets.

**Files:**
- `Anime4K-Upscaler/Models/Models.swift` (UPDATE — add cases, `modelName`, `displayName`, `description`, `pipeline` classification)
- `Anime4K-Upscaler/ViewModels/ProcessingEngine.swift` (UPDATE — dispatch MetalFX/hybrid paths)
- `Anime4K-Upscaler/Utilities/MetalFXUpscaler.swift` (CREATE — wraps `MTLFXSpatialScaler`)

**New cases (proposed enum values, follow existing numbering):**
- `special_MetalFX` — 1080p→4K GPU spatial via `MTLFXSpatialScaler`. Create scaler once; per-frame `encode(commandBuffer:)`. Target 40-90 fps.
- `special_Balanced` — animevideov3 2x (1080→2K, ANE) then MetalFX spatial 2x (2K→4K, GPU). Target 10-18 fps.
- `special_Neural2x` — animevideov3 upscale=2 (1080→2K). Target 12-20 fps. (May overlap with `special_PiperSR_2x` — keep both if models differ, else alias.)
- `special_PiperSR_4x` — 2-pass PiperSR (1080→2160→4320). **Ship only if Phase 6 benchmark beats `special_Fast`**; otherwise leave in code gated off.

**Steps:**
1. Add enum cases + metadata (mirror existing `special_*` style at `Models.swift:102-156`).
2. `MetalFXUpscaler`: `MTLFXSpatialScalerDescriptor` with `colorProcessingMode = .perceptual`, input/output textures BGRA8 sRGB, create once, encode per frame. Needs an `MTLDevice` + command queue. Integrate with the writer (output texture → CVPixelBuffer via IOSurface shared).
3. Hybrid path: chain the neural 2x output into the MetalFX 2x input (both IOSurface-backed, zero-copy if possible).
4. ProcessingEngine dispatch: route new presets to the right runner (MetalFX does not use `CoreMLUpscaler`).

**Validation:**
```bash
swift build 2>&1 | tee .claude/plans/phase5-build.txt
swift test 2>&1 | tee -a .claude/plans/phase5-build.txt
```

**Done-when:** All new presets selectable in UI, build green, each runs end-to-end on a 5s 1080p test clip producing a 4K (or 2K for Neural2x) output.

---

## Phase 6 — Swift benchmark harness + MLComputePlan CI

**Goal:** Measure real `runANEEncode`/MetalFX fps per preset (closes the audit's known harness gap — prior audits used a CLI reimplementation, not the real AVFoundation path). Gate op placement per commit.

**Files:**
- `Tests/SpecialPipelineBenchmark.swift` (CREATE) — drives the real `ProcessingEngine`/`runANEEncode` path over a 5s 1080p test clip per preset, logs fps + per-stage timing.
- `Tests/MLComputePlanGate.swift` (CREATE) — re-runs Phase 1 audit as a CI assertion: 0 CPU-fallback ops for neural models.

**Steps:**
1. Benchmark harness uses the real `runANEEncode` (or MetalFX runner), not a parallel CLI. Measure decode / ANE / blit / total. Log to `.claude/plans/benchmark-<preset>.txt`.
2. CI gate: assert every neural model's `MLComputePlan` shows 0 CPU ops. Fail the test if any.
3. Compare `special_PiperSR_4x` vs `special_Fast` — only ship PiperSR-4x if it wins.

**Validation:**
```bash
swift test --filter SpecialPipelineBenchmark 2>&1 | tee .claude/plans/phase6-bench.txt
swift test --filter MLComputePlanGate 2>&1 | tee -a .claude/plans/phase6-bench.txt
```

**Done-when (per-preset gates, M3 Pro 1080p→4K):**
- special_Fast ≥ 3 fps (target 3-6)
- special_Quality ≥ 1.5 fps (target 1.5-3, opt-in)
- special_SDRescue ≥ 3 fps (target 3-5)
- special_PiperSR_2x ≥ 12 fps at 1080→2K
- special_MetalFX ≥ 40 fps
- special_Balanced ≥ 10 fps
- special_Neural2x ≥ 12 fps at 1080→2K
- MLComputePlanGate: 0 CPU fallback on all neural models

A preset missing its gate → keep its phase `in_progress`, investigate, do not mark done.

---

## Phase 7 — Op-placement + compute_precision audit fixes

**Goal:** Close any CPU-fallback found in Phase 1/6 and verify FP16 throughout.

**Files:** `Scripts/convert_models.py`, `CoreMLUpscaler.swift`, models (regenerate if changed).

**Steps:**
1. If `MLComputePlan` shows PReLU on CPU → swap PReLU→SiLU (M3 LUT-native) + brief fine-tune; reconvert.
2. If `ImageWrapper` clamp×255 leaks FP32 → force `compute_precision=ct.precision.FLOAT16` or `Float16ComputePrecision()` selectively; reconvert.
3. Re-run Phase 6 gate → 0 CPU ops.

**Validation:**
```bash
swift test --filter MLComputePlanGate 2>&1 | tee .claude/plans/phase7-gate.txt
```

**Done-when:** 0 CPU fallback, FP16 confirmed, Phase 6 gates still green.

---

## Phase 8 — Optional model distillation (only if gates still missed)

**Goal:** If `special_Fast` < 3 fps or `special_Quality` < 1.5 fps after all of the above, shrink the model.

**Steps:**
1. animevideov3: reduce conv count 18→10, fine-tune on DIV2K-anime, measure PSNR drop.
2. RRDB 6B: prune 6→4 RRDB blocks, fine-tune.
3. Re-run Phase 6 gates.

**Done-when:** Gates met, PSNR drop documented (< 0.5 dB ideal). Skip this phase if Phase 6 already green.

---

## Validation summary (whole plan)

```bash
# Full green bar:
swift build && swift test
bash Tests/integration_decode_codec_matrix.sh
# Per-preset benchmarks + placement gate:
swift test --filter SpecialPipelineBenchmark
swift test --filter MLComputePlanGate
swift test --filter VTFrameProcessorProbe
swift test --filter MLComputePlanAudit
```

---

## Risks (consolidated)

| Risk | Phase | Mitigation |
|---|---|---|
| Full-frame 1080p exceeds ANE SRAM → internal retile (slower) | 2,3 | Use largest fixed tile that fits; keep tile loop fallback; Phase 6 decides |
| TensorType + flexible input crashes (old libBNNS class) | 2 | Fixed concrete shape (not flexible) → concrete output; TensorType not ImageType |
| PReLU CPU fallback | 7 | MLComputePlan gate; SiLU swap + fine-tune |
| EnumeratedShapes dynamic-tensor CPU fallback | 2 | Do NOT use EnumeratedShapes — fixed shape only |
| RRDB full-frame OOM | 2 | Large-tile path by design (B2) |
| PiperSR quality drop at unseen 1080p res | 2 | Fine-tune on 1080p tiles; measure PSNR Phase 6 |
| MetalFX scaler creation cost / IOSurface texture sharing | 5 | Create scaler once at launch; IOSurface-backed CVPixelBuffer for MTLTexture sharing |
| VT low-latency unsupported at 1080p | 0 | Probe; fall back to MetalFX / neural |
| 2-pass PiperSR slower than single 4x | 5,6 | Ship only if benchmark wins |
| Ring reorder/PTS bug | 4 | Strict ring-index append order; bounded ring; existing PTS logic kept |
| Python predict() CPU-only → can't benchmark ANE from Python | 6 | Swift harness mandatory (already planned) |

---

## Acceptance

- [ ] All phases in Status table `done` or `skipped` (with reason).
- [ ] Every existing + new preset passes its Phase 6 fps gate on M3 Pro.
- [ ] MLComputePlanGate: 0 CPU fallback on all neural models.
- [ ] Decode codec matrix green.
- [ ] No tile seams, no color regression (full-frame has none by construction; MetalFX perceptual mode validated).
- [ ] Swift benchmark harness committed (closes audit's known harness gap).
- [ ] PIPELINE_AUDIT.md updated with a dated entry for this work.

---

## Sources (key)

- ModelPiper 44fps ANE pipeline + ANE-native op set + static weights 2.82× + double-buffer + Metal float16→BGRA: https://modelpiper.com/blog/pipersr-44fps-video-upscale-apple-neural-engine
- ModelPiper PiperSR open-source: https://github.com/ModelPiper/PiperSR
- Real-ESRGAN official benchmark (animevideov3 1080p = 10fps V100): https://github.com/xinntao/Real-ESRGAN/blob/master/docs/anime_video_model.md
- coremltools #2370 EnumeratedShapes ANE regression: https://github.com/apple/coremltools/issues/2370
- coremltools #1909 LayerNorm/EnumeratedShapes CPU fallback: https://github.com/apple/coremltools/issues/1909
- coremltools #1764 flexible shapes drop ANE: https://github.com/apple/coremltools/issues/1764
- coremltools flexible-inputs guide (EnumeratedShapes 128 max): https://apple.github.io/coremltools/docs-guides/source/flexible-inputs.html
- Meridian: ANE eligibility vs placement + MLComputePlan + ~1M-param threshold: https://ask-meridian.uk/blog/apple-neural-engine-eligibility-vs-placement/
- coremltools Typed Execution (compute_precision, FP32 bars ANE): https://coremltools.readme.io/v6.3/docs/typed-execution
- CoreML-LLM ANE survey (IOSurface zero-copy, ping-pong, pre-compile, 123 MIL passes): https://github.com/john-rocky/CoreML-LLM/blob/main/docs/ANE_OPTIMIZATION_SURVEY.md
- Apple M3 Pro ANE 18 TOPS, 150 GB/s, LUT activations: https://www.notebookcheck.net/Apple-M3-Pro-12-Core-Processor-Benchmarks-and-Specs.781711.0.html
- M3 Neural Engine INT4/INT2 in-SRAM: https://asplos.dev/wiki/m3-chip-explainer/neural-engine/index.html
- Apple MetalFX docs: https://developer.apple.com/documentation/metalfx
- WWDC22 MetalFX upscaling (1080p→4K demos): https://developer.apple.com/videos/play/wwdc2022/10103/
- WWDC25 Metal 4 (Denoised Temporal Upscaler, Frame Interpolation): https://developer.apple.com/videos/play/wwdc2025/205/
- WWDC25 Session 300 VTFrameProcessor ML video SR: https://developer.apple.com/videos/play/wwdc2025/300/
- Apple Forums VT low-latency empty for 1080p: https://developer.apple.com/forums/thread/821701
- Ron Regev Real-ESRGAN CoreML conversion on Mac: https://medium.com/@ronregev/optimized-ai-image-video-upscaling-on-macs-with-apple-silicon-m1-m2-m3-m4-a248e128cdc6