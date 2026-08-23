# rel4 — final bare-metal handoff (all VM-buildable phases)

Built on VM 2026-08-11. Two artifacts to copy from the VM to the main Mac
(M3 Pro, macOS 27 build 26A5388g, ANE present, no dev tools / no `swiftc`):

```
/tmp/Anime4K-Upscaler-Release.tar.gz   # 147MB — the Release .app (arm64)
/tmp/mlgate                            # compiled Phase 6 MLComputePlan gate (arm64, no swiftc needed)
```

## Phase status shipped in this build
- ✅ Phase 2 — batch reconvert @192/128 + preset rename
- ✅ Phase 4 — double-buffered ring (FrameChannel, decode‖infer‖write overlap)
- ✅ Phase 5 — MetalFX preset (Restore VL → MetalFX, 2×/4× selector); ratio picker fix
- ✅ Phase 6 — MLComputePlan CI gate (compiled binary ships; run on metal)
- ✅ Phase 7 — FP16 + PReLU/SiLU (bare-metal baseline moot; gate confirms on metal)
- ✅ Phase 9 — temporal redundancy skip (16×9 luma signature, dup = reuse last upscaled)
- ⏭ Phase 3 — dropped YAGNI (MetalSRConvert; CoreML ImageType returns BGRA directly)
- ⏸ Phase 8 — blocked-conditional (only if Phase 6 fps < target on metal)
- ⏸ Phases 10-13 — deferred (Metal 4 GPU-timeline, frame interp, VSR, Real-CUGAN)

## On the main Mac — run in order, paste results back

### 1. Copy the two artifacts off the VM
(whatever your VM-share path is — e.g. shared folder, scp, USB)
```
# both files land somewhere on the main Mac, e.g. ~/Downloads
```

### 2. Unpack the app + install
```bash
cd ~/Downloads
tar -xzf Anime4K-Upscaler-Release.tar.gz
# move the old app aside first if present:
mv "/Applications/Anime4K Upscaler.app" "/Applications/Anime4K Upscaler.app.old.$(date +%s)" 2>/dev/null
cp -R "Anime4K Upscaler.app" /Applications/
# first launch: strip quarantine so Gatekeeper doesn't block the ad-hoc signed app
xattr -dr com.apple.quarantine "/Applications/Anime4K Upscaler.app"
open "/Applications/Anime4K Upscaler.app"
```
Paste: does the app launch? Window show? Pipeline picker populated with the
renamed presets (Neural 4× Fast / Quality / SD Rescue / 2× PiperSR / MetalFX)?

### 3. Phase 6 gate — MLComputePlan 0-CPU-fallback (THE throughput CI signal)
```bash
# point the gate at the bundled .mlmodelc inside the app (always present):
MODELS_DIR="/Applications/Anime4K Upscaler.app/Contents/Resources" ~/Downloads/mlgate
echo "GATE_EXIT=$?"
```
Expected on metal with ANE: 3 PASS, exit 0 — every conv/prelu/silu/clip lands on
ANE/GPU, only the ImageWrapper `mul`+`cast` tail + shape ops on CPU.
If any model FAILs (unexpected CPU op), paste the REGRESSIONS block — that op
fell off the ANE and caps fps.

### 4. Per-preset smoke + quality (the real benchmark — folded into this handoff)
For EACH preset below: drop a short test clip (a few seconds, 480p or 720p anime),
run, note wall-clock vs source duration for fps, and eyeball output quality.

| Preset | Expect | Quality target |
|--------|--------|----------------|
| Neural 4× Fast (animevideov3) | fastest neural, ratio picker locked 4× | clean |
| Neural 4× Quality (RRDB) | slowest, locked 4× | sharpest |
| Neural SD Rescue (restore + 4×) | slow, restore-shader decode chain, locked 4× | best on degraded source (≈ Anime4K A+A) |
| Neural 2× (PiperSR) | fast, locked 2× | clean |
| MetalFX (Restore + GPU) | fast, 2×/4× selector ACTIVE | Restore VL → MetalFX ≈ Anime4K Mode A (single restore) |

Paste per preset: (a) fps or wall-clock, (b) any error/log, (c) one-line quality
vs the old build. Specifically confirm:
- MetalFX preset no longer looks soft/blurry (Restore VL preprocess active).
- Neural fixed-ratio presets: the 2×/4× picker below is DISABLED (grayed) + snaps to the fixed ratio.
- MetalFX: the picker is ENABLED and 2× vs 4× both work.

### 5. Phase 4 + 9 integrity (no reorder, no dropped frames)
Play any output .mov from step 4 in QuickTime — confirm:
- smooth motion (no frame reorder stutter — the FrameChannel FIFO order),
- no frozen frames where motion should be (redundancy reuse is signature-based, not a black-frame detector),
- duration matches source (no dropped/added frames).

## What I adjust based on your pastebacks
- Gate FAILs on metal → which op fell to CPU → convert fix (Phase 8 may unblock).
- MetalFX still soft → tune Restore VL shader strength / MetalFX colorProcessingMode.
- fps below target → Phase 8 (distill/prune) or tile-size retune.
- Any reorder/freeze → FrameChannel capacity or redundancy threshold tuning.