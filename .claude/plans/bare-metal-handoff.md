# Bare-metal handoff — phases VM can't verify

**Workflow:** Claude edits code on the Parallels VM (build-verifies compile via
`xcodebuild`). User runs the **Run on bare Mac** commands on a real Apple Silicon
Mac (ANE + Metal device) to verify runtime/fps/correctness. Paste output back;
Claude iterates.

**Why:** this VM (Parallels, VirtualMac2,1, M3 Pro Virtual) has no ANE passthrough
and a virtual GPU. Every CoreML model audits 100% CPU here (VM artifact, not a
config bug), and MetalFX / Metal compute output can't be visually verified. Build
+ unit tests work; ANE-placement + fps + visual gates do not. See
`.claude/plans/phase2-findings.md` for the full VM-vs-metal evidence.

Regenerate the Xcode project before any bare-metal build (sources glob is in
`project.yml`; `*.xcodeproj` is gitignored):

```bash
xcodegen && xcodebuild -version
```

---

## Phase 3 — remaining metal pieces

**VM done:** `TilePlanner` extracted + tested (28/28), IOSurface backing on
`makePixelBuffer`. Commits `bdca1b4`, `fb0eacd`.

**Metal-deferred (Claude writes on VM, you verify on bare Mac):**
1. `Anime4K-Upscaler/Utilities/MetalSRConvert.swift` — Metal compute shader
   `float16PlanarToBGRA8` (+ optional resize) to replace the `CIContext.render` +
   `CILanczosScaleTransform` tail of `CoreMLUpscaler.upscale`.
2. Full-frame TensorType single dispatch once Phase 2's reconverted
   `.mlpackage` models are promoted into `Resources/Models/`.

**Run on bare Mac (after Claude writes MetalSRConvert):**
```bash
xcodegen
xcodebuild build -project Anime4K-Upscaler.xcodeproj -scheme Anime4K-Upscaler \
  -configuration Debug -destination 'platform=macOS' 2>&1 | tee .claude/plans/phase3-metal-build.txt
# Visual: run the app on a 5s 1080p test clip with special_Fast, compare output
# to a CIContext.render baseline. No color shift / no banding vs the old path.
# Then the fps gate (Phase 6 harness, or a manual timed run) — expect the Metal
# convert path to remove the per-frame CIContext.render cost.
```

---

## Phase 4 — runANEEncode double-buffered ring (collaborative)

**Status:** blocked, paused 2026-08-05. Claude writes the ring + `FrameRing`
ordering unit test on VM; you run the build + integration decode matrix + a
visual spot-check on bare Mac to confirm no frame reorder stutter.

**Run on bare Mac (after Claude writes the ring):**
```bash
xcodegen
xcodebuild build -project Anime4K-Upscaler.xcodeproj -scheme Anime4K-Upscaler \
  -configuration Debug -destination 'platform=macOS' 2>&1 | tee .claude/plans/phase4-build.txt
# Unit: the FrameRing ordering test (Claude will give the swiftc line).
# Integration decode matrix — must stay green:
bash Tests/integration_decode_codec_matrix.sh 2>&1 | tee -a .claude/plans/phase4-build.txt
# Visual: process a 5s 1080p clip with special_Fast, PLAY the output .mov —
# confirm no frame reorder stutter / no dropped frames. Then timed fps vs the
# pre-ring baseline (expect decode ‖ ANE ‖ blit overlap to lift fps).
```

---

## Phase 5 — new presets (collaborative, paused 2026-08-05)

**Scope (Claude writes on VM):** 3 new presets — `special_MetalFX`
(MTLFXSpatialScaler, GPU), `special_Balanced` (animevideov3 2x ANE → MetalFX 2x
GPU), `special_Neural2x` (animevideov3 upscale=2). Skip `special_PiperSR_4x`
until Phase 6 benchmark on metal shows it beats `special_Fast` (YAGNI for now).

Files Claude will touch: `Models/Models.swift` (enum cases 23-25 + `isSpecial` +
`modelName` + `displayName` + `subtitle` + `category`), `Utilities/MetalFXUpscaler.swift`
(CREATE — `MTLFXSpatialScalerDescriptor`, `colorProcessingMode = .perceptual`,
BGRA8 sRGB, device-capability gate, encode per frame), `ViewModels/ProcessingEngine.swift`
(dispatch: MetalFX does NOT use `CoreMLUpscaler`; hybrid chains neural 2x → MetalFX).

**Run on bare Mac (after Claude writes Phase 5):**
```bash
xcodegen
xcodebuild build -project Anime4K-Upscaler.xcodeproj -scheme Anime4K-Upscaler \
  -configuration Debug -destination 'platform=macOS' 2>&1 | tee .claude/plans/phase5-build.txt
# Per-preset end-to-end on a 5s 1080p test clip (Done-when from plan):
#   special_MetalFX   : 1080p→4K, target ≥ 40 fps
#   special_Balanced  : 1080p→4K (2x ANE + 2x MetalFX), target ≥ 10 fps
#   special_Neural2x  : 1080p→2K, target ≥ 12 fps
# Confirm each preset appears in the UI picker and produces a correct-color
# output .mov (visual spot-check vs a known-good frame).
```

---

## Phase 6 — benchmark harness + MLComputePlan CI gate

**Run on bare Mac (after Claude writes the harness):**
```bash
xcodegen
# Real-pipeline fps per preset (closes the audit's known harness gap):
swift test --filter SpecialPipelineBenchmark 2>&1 | tee .claude/plans/phase6-bench.txt
# CI gate: assert 0 CPU-fallback ops on every neural model:
swift test --filter MLComputePlanGate 2>&1 | tee -a .claude/plans/phase6-bench.txt
# Per-preset fps gates (M3 Pro, 1080p→4K) — from plan Done-when:
#   special_Fast ≥ 3, special_Quality ≥ 1.5, special_SDRescue ≥ 3,
#   special_PiperSR_2x ≥ 12 @1080→2K, special_MetalFX ≥ 40,
#   special_Balanced ≥ 10, special_Neural2x ≥ 12 @1080→2K,
#   MLComputePlanGate: 0 CPU fallback on all neural models.
```
Note: `swift test` requires an SPM `Package.swift`; this repo is Xcode-only, so
Claude will adapt the harness to the repo's standalone `swiftc @main` test pattern
(like `Tests/MLComputePlanAudit.swift`) and give the exact compile+run line.

---

## Phase 7 — op-placement + compute_precision fixes

**Claude writes on VM:** `Scripts/convert_models.py` PReLU→SiLU swap (M3
LUT-native) + force `compute_precision = FLOAT16` where the `ImageWrapper`
clamp×255 leaks FP32. Regenerate models.

**Run on bare Mac:**
```bash
cd Anime4K-Upscaler/Scripts && python3 convert_models.py ../Resources/Models \
  2>&1 | tee ../../.claude/plans/phase7-convert.txt
# Confirm op changed (prelu -> silu) + FP16:
python3 -c "import coremltools as ct; m=ct.models.MLModel('../Resources/Models/realesr-animevideov3.mlpackage'); print(m.input_description, m.output_description)" 2>&1 | tee -a ../../.claude/plans/phase7-convert.txt
# THE KEY CHECK — only valid on bare metal (VM audits 100% CPU regardless):
swift test --filter MLComputePlanGate 2>&1 | tee .claude/plans/phase7-gate.txt
# Done-when: 0 CPU fallback, FP16 confirmed, Phase 6 gates still green.
```

---

## Phase 8 — optional distillation (only if Phase 6 gates missed)

Only if `special_Fast` < 3 fps or `special_Quality` < 1.5 fps after Phases 1-7.
Claude writes the pruning/fine-tune script; you run training on bare Mac (GPU).
Defer until Phase 6 numbers are in.

---

## Quick reference — repo's actual test pattern (not SPM)

No `Package.swift` / `swift test`. Standalone `@main` tests compiled with `swiftc`:
```bash
# Pattern (example: TilePlanner):
swiftc Anime4K-Upscaler/Utilities/<Util>.swift Tests/<Util>Tests.swift -o /tmp/<test> && /tmp/<test>
# Build the app:
xcodegen && xcodebuild build -project Anime4K-Upscaler.xcodeproj -scheme Anime4K-Upscaler -configuration Debug -destination 'platform=macOS'
# Integration decode matrix:
bash Tests/integration_decode_codec_matrix.sh
```