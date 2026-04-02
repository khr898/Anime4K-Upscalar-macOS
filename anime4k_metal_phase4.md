# Anime4K Metal — Phase 4: Anime4K Upscaler Integration + MPS Optimization

## Prerequisites

- Phase 1 & 2 complete — all `.metal` shaders translated, compile-verified, and SSIM-verified
- `benchmark_results.txt` from Phase 2 available (baseline GPU timings)
- Anime4K Upscaler repo open: `github.com/khr898/Anime4K-Upscalar-macOS`

---

## Current Architecture (what exists now)

```
SwiftUI UI
    ↓
FFmpeg process (spawned as subprocess)
    ↓  glsl-shaders= filter flag
GLSL Anime4K shaders (75.9% of codebase — bundled .glsl files)
    ↓
FFmpeg encode (H.264 / HEVC / AV1)
    ↓
Output file
```

The GLSL shaders run inside FFmpeg's video filter pipeline via the `--glsl-shaders` flag (same as mpv — FFmpeg shares the same shader hook system). FFmpeg handles both decode and encode. SwiftUI is only the frontend — it builds the FFmpeg command and spawns it as a subprocess.

This is a pure export pipeline — no playback, no IOSurface bridge. FFmpeg handles all decode and encode.

---

## Target Architecture (Phase 4)

```
SwiftUI UI
    ↓
FFmpeg decode (subprocess) → raw frames via pipe or temp file
    ↓
Metal + MPS upscaling pipeline (native Swift, replaces GLSL filter)
    ↓
FFmpeg encode (subprocess) ← processed frames via pipe or temp file
    ↓
Output file
```

FFmpeg stays for decode and encode — it handles container formats, codec support, and hardware encode (VideoToolbox for HEVC/H.264, AV1). The Anime4K shader step is lifted out of FFmpeg entirely and replaced with a native Metal + MPS Swift pipeline sitting between decode and encode.

---

## Step 1: Identify Which Shaders the App Uses

Do this **at the time of integration**, not before — modes may have changed.

1. Open `Anime4K-Upscaler/` source folder — find where the Anime4K mode list is defined (likely a Swift enum or array in a ViewModel or ProcessingManager file)
2. Find where FFmpeg commands are constructed — look for `glsl-shaders=` strings being built, which will reference specific `.glsl` filenames
3. Check the bundled GLSL files in the project — 75.9% of the repo is GLSL, so they are embedded directly

Collect the unique set of `.glsl` filenames referenced by the mode picker. Pull only those corresponding verified `.metal` files from the Phase 1+2 output library.

---

## Step 2: Frame Extraction from FFmpeg

Since FFmpeg is a subprocess, frames need to be passed to the Metal pipeline. Two options:

### Option A — Pipe (preferred, lower overhead)
```bash
ffmpeg -i input.mkv -vf scale=... -f rawvideo -pix_fmt bgra pipe:1 | [Metal pipeline]
```
Read raw BGRA frames from stdout into a `MTLBuffer`, wrap as `MTLTexture`, process, pipe processed frames back to a second FFmpeg subprocess for encode.

### Option B — Temp frames (simpler, more disk I/O)
Extract all frames to a temp folder as PNG/TIFF, process with Metal, re-encode from processed frames. Simpler to implement but slow for long videos.

**Recommended:** Start with Option B to validate correctness, then switch to Option A for performance.

---

## Step 3: Metal Pipeline Integration

For each frame received from FFmpeg decode:

1. Upload raw frame data to `MTLTexture` (input)
2. Allocate intermediate `MTLTexture` objects for each SAVE'd pass (allocate once, reuse per frame)
3. Encode the full Anime4K pass chain into a `MTLCommandBuffer` using the verified `.metal` shaders from Phase 1+2
4. Commit and wait for completion
5. Read processed `MTLTexture` back as raw frame data
6. Send to FFmpeg encode subprocess

The pass chain order and SAVE → BIND dependencies are documented in the header comments of each `.metal` file from Phase 1+2.

---

## Step 4: MPS Convolution Optimization (Final Target)

After basic Metal integration is working and SSIM-verified, replace CNN pass fragment shaders with `MPSCNNConvolution`. This is the primary performance goal.

### Performance Goal — Maximum Speed, Zero Quality Loss

**Quality is non-negotiable.** The Metal + MPS pipeline must produce output mathematically identical to the GLSL reference (SSIM ≥ 0.999, max pixel diff < 2). Speed improvements must never come at the cost of quality — do not use approximations, reduced precision, or skip passes to go faster.

**Speed target** — extract every fps possible from the hardware:

| Approach | Export speed |
|---|---|
| Current — GLSL via FFmpeg filter | ~14 fps |
| Phase 4 Metal translated shaders | ~45–60 fps |
| Phase 4 Metal + MPS convolutions | ~80–100 fps |

At 14fps a 1-hour video takes ~2 hours to export. The MPS target brings that to ~20 minutes. This is the minimum acceptable outcome — push beyond it if the hardware allows. Profile every pass with Metal GPU counters and eliminate all remaining bottlenecks. The ceiling is what the M-series GPU can physically do with MPS-optimized CNN kernels and full pipeline overlap.

### What MPS Is
`MetalPerformanceShaders` provides Apple-optimized GPU kernels tuned per chip generation. The CNN passes in Anime4K are 3×3 convolutions with baked float weights. `MPSCNNConvolution` replaces the hand-translated Metal shader math with Apple's implementation, leveraging dedicated ML accelerators on M-series chips.

### How to Apply MPS
Each CNN pass has the form (3×3 kernel, 4-channel in/out):

```swift
let desc = MPSCNNConvolutionDescriptor(
    kernelWidth: 3,
    kernelHeight: 3,
    inputFeatureChannels: 4,
    outputFeatureChannels: 4
)

// Weights extracted from the baked mat4 literals in the .metal file
let dataSource = Anime4KWeightSource(weights: weights, descriptor: desc)
let conv = MPSCNNConvolution(device: device, weights: dataSource)
conv.encode(commandBuffer: commandBuffer,
            sourceImage: inputMPSImage,
            destinationImage: outputMPSImage)
```

Replace each CNN pass's fragment shader with an `MPSCNNConvolution` call using the same baked weights. Non-CNN passes (Clamp, AutoDownscale) stay as translated Metal fragment shaders.

### Triple-Buffering for Export Throughput
For export, pipeline 3 frames simultaneously — while Metal processes frame N, FFmpeg is decoding frame N+1 and encoding frame N-1. `MPSCNNConvolution` supports this natively. This alone adds ~30% throughput on top of the MPS speedup.

```swift
let inflightSemaphore = DispatchSemaphore(value: 3)

for frame in frames {
    inflightSemaphore.wait()
    let commandBuffer = commandQueue.makeCommandBuffer()!
    // encode MPS passes for this frame
    commandBuffer.addCompletedHandler { _ in
        inflightSemaphore.signal()
    }
    commandBuffer.commit()
}
```

---

## Step 5: MPS Verification — Quality Gate

Speed improvements are only accepted if they pass the quality gate. After replacing CNN passes with MPS, re-run the Phase 2 SSIM test against the original GLSL/FFmpeg reference output. **Do not ship if this fails.**

```bash
# Generate reference with original FFmpeg + GLSL
ffmpeg -i input.png -vf glsl-shaders=Anime4K_Restore_CNN_VL.glsl ... reference.png
```

```python
# Same verification script from Phase 2
score = ssim(ref, out, channel_axis=2, data_range=255)
max_diff = np.max(np.abs(ref - out))
print("PASS" if score >= 0.999 and max_diff < 2 else "FAIL")
```

Compare GPU timings against `benchmark_results.txt` from Phase 2 to confirm speedup.

---

## Notes
- FFmpeg stays for decode and encode — do not replace it. VideoToolbox hardware encode (HEVC/H.264) and AV1 are FFmpeg's job
- The SwiftUI frontend and job queue do not need significant changes — only the processing step between decode and encode changes
- CNN weights are `mat4` float literals baked into the GLSL — extract them directly from the translated `.metal` files from Phase 1+2 for the `MPSCNNConvolutionDataSource`
- Pixel format: ensure FFmpeg outputs BGRA frames and Metal uses matching `MTLPixelFormat.bgra8Unorm` — mismatches corrupt output silently with no error

---

## Clarification: .metal Files Are Not Modified for MPS

Same principle as Phase 3 — **the translated `.metal` files require no changes.**

### Pass split for the Upscaler

The Upscaler uses the same shader files as Glass Player. The split is identical:
- **Metal fragment shaders:** Clamp_Highlights passes, depth-to-space passes
- **MPS:** All CNN convolution passes (~95% of GPU work)

### Weight extraction
Same build-time Swift script approach as Phase 3. Since both apps share a Swift package (`Anime4KMetal`), the weight extraction script and the generated `Anime4KWeights.swift` live in the package — not duplicated per app.

### Pixel format reminder for MPS in the Upscaler
`MPSCNNConvolution` expects `MPSImage` input, not raw `MTLTexture`. The frame pipeline for the Upscaler is:

```
FFmpeg rawvideo pipe (bgra bytes)
    → MTLBuffer (zero-copy on UMA via shared memory)
    → MPSImage (wraps the MTLTexture)
    → MPSCNNConvolution passes
    → MPSImage output
    → MTLTexture
    → read back as bgra bytes
    → FFmpeg encode pipe
```

The `bgra` pixel format must be consistent end-to-end. `MPSImage` uses `MTLPixelFormat.bgra8Unorm` — confirm FFmpeg outputs `bgra` not `rgba` or `yuv420p` before the first frame enters the Metal pipeline.
