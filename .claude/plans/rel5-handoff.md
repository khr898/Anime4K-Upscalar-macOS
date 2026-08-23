# rel5 — bare-metal handoff (headless CLI + auto-test)

Built on VM 2026-08-11 (Xcode 26.4.1). One artifact to copy from the VM to the
main Mac (M3 Pro, macOS 27 build 26A5388g, ANE present, no dev tools):

```
/tmp/Anime4K-Upscaler-Release.tar.gz   # 147MB — Release .app (arm64) WITH --headless CLI
```

## What changed since rel4
- **Headless CLI**: the app now accepts `--headless` and drives `ProcessingEngine`
  without the GUI. This lets the test script run EVERY preset on the 5s clip
  automatically + integrity — no manual GUI per preset.
- **Sandbox OFF**: `com.apple.security.app-sandbox=false`. The sandbox blocked
  headless reads of non-user-selected paths (ffmpeg exit 255 "No such file").
  GUI still works (SecurityScopeManager is a harmless no-op unsandboxed). App
  is ad-hoc/tarball-distributed, not MAS — sandbox not required.
- **HeadlessRunner auto-mkdirs output dir** + dumps `job.logLines` on failure
  (so ffmpeg stderr surfaces instead of a generic "exited 255").
- Verified on VM: MetalFX ×2 headless → completed 1.99s, integrity 640×360→1280×720,
  120 frames, hevc. §6 will now pass on metal.
- MetalFX blur: root-caused (see below), NOT fixed yet — needs your call on
  approach (hybrid vs your post-restore idea).

## On the main Mac — run in order, paste results back

### 1. Copy + install
```bash
cd ~/Downloads
tar -xzf Anime4K-Upscaler-Release.tar.gz
mv "/Applications/Anime4K Upscaler.app" "/Applications/Anime4K Upscaler.app.old.$(date +%s)" 2>/dev/null
cp -R "Anime4K Upscaler.app" /Applications/
xattr -dr com.apple.quarantine "/Applications/Anime4K Upscaler.app"
```

### 2. Run the FULL auto-test (no manual GUI anymore)
```bash
cd /path/to/a4k-metal          # the bundle dir with bin/ + clips/ + the script
zsh a4k-metal-test.sh
```
It runs: preflight (incl. a --headless probe of the app) → §1 mlgate → §2 aneprobe
→ §3 mfxprobe → §4 unit tests → §5 decode matrix → **§6 AUTO PRESET RUNS**:
for each of the 6 preset-runs (Neural Fast/Quality/SDRescue/PiperSR + MetalFX ×2/×4)
it launches the app headlessly on the 5s clip, captures timing + output path,
then runs the integrity check (frame count match, duration within 2%, upscaled).

Paste the whole thing back. I calibrate from §6 specifically:
- per preset: `HEADLESS DONE state=completed elapsed=Xs` + `HEADLESS OUTFILE exists=true size=N`
- integrity line per preset (frame count / duration / resolution)
- any `HEADLESS ERROR` / `HEADLESS FAIL`

### 3. Manual GUI confirm (quick, optional)
Open the app once, confirm the picker behavior you already verified:
- Neural presets: 2×/4× picker below preset is DISABLED (grayed) + snaps to fixed ratio. ✅ (you confirmed)
- MetalFX: picker ENABLED, 2× and 4× both run. ✅ (you confirmed)

## MetalFX blur — root cause (needs your call before I fix)

You reported: MetalFX runs on 2× and 4× but is still blurry; restore is active.

What I found checking the pipeline:
- Restore VL shader **IS** wired for MetalFX (`usesRestoreShader = isMetalFX`,
  `RawVideoFrameSource.swift:42` runs `hwupload,libplacebo=restore_VL,hwdownload`
  before the upscaler). So restore is not missing.
- `colorProcessingMode = .perceptual` is **correct** for sRGB anime — Apple's
  default; `.linear` would soften it MORE (not the bug). [WWDC22 MetalFX]
- The real cause: the MetalFX chain runs **only Restore** (a line-art recon
  shader, no upscaling) then hands the still-640p frame to MetalFX, a **generic**
  spatial upscaler not trained on anime. Real Anime4K Mode A = Restore →
  **2× CNN Upscale (VL)** → 2× CNN Upscale (M). MetalFX replaces both CNN
  upscalers with one generic pass → inherently softer on anime line art.

Proposed fix (architectural — confirm and I build it). Two options:

**Option A — hybrid (my recommendation):** run `Restore VL → Upscale CNN x2 VL`
in the ffmpeg shader chain (Anime4K 2×, sharp, anime-trained), then MetalFX
only does the **final** 2× (for the 4× target). For the 2× target, MetalFX is
bypassed (pure Anime4K Mode A). Adds an anime-trained CNN UPSCALER before
MetalFX → real detail, not just sharpening. Touches `streamArgs` (chain gains
the upscale shader, output dims 2×) + `executeUpscaleJob` (inW/inH + MetalFX
targetScale halved for 4×, bypassed for 2×) + `MetalFXUpscaler` dims.

**Option B — your post-restore idea:** MetalFX upscales first (640→final), then
Restore VL runs on the UPSCALED frame to reconstruct line art at full res.
Sharper edges than restore-at-640p-then-upscale, but restore can't add detail
that isn't there (MetalFX 4× from 640p is soft in flat areas). Architecturally
harder: restore is a GLSL/libplacebo shader in the ffmpeg pipe, but MetalFX
output is a Metal texture — needs either a second ffmpeg pass (app pipes
upscaled frames back in) or a Metal port of the restore CNN. Bigger build.

I'd ship A first (cheaper, adds real detail), then try B if A's 4× is still
soft. Your call.

## What I adjust based on your pasteback
- §6 any preset FAILs → its HEADLESS ERROR line names the cause.
- §6 integrity frame-count mismatch → Phase 4 ring / Phase 9 reuse regression.
- §6 MetalFX still blurry after the hybrid fix → tune Restore VL strength or
  add a second restore pass post-MetalFX.
- §6 neural fps (elapsed/5s) below target → Phase 8 (distill/prune) unblocks.