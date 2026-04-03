# Zero-Copy Decode/Process/Encode Pipeline Research

## Current Architecture & Copy Points

### 1. **CURRENT DATA FLOW (Pipe-Based)**
```
FFmpeg decode subprocess
  → Pipe: rawvideo BGRA (stdin to encode)
  
ProcessingEngine workers:
  → Data read from pipe (inputFrameBytes = W*H*4)
  → CPU Memory: Data allocation
  → GPU upload: texture.replace() copies BGRA bytes CPU→GPU
  → Metal processing (all on GPU, zero-copy within pass chain)
  → GPU readback: readbackTexture.getBytes() copies GPU→CPU (shared storage mode)
  → CPU Memory: Data write to encode pipe

FFmpeg encode subprocess
  → Pipe: processes BGRA frames from stdin
```

### 2. **EXPLICIT CPU READ/WRITE COPIES**

**Benchmark Phase (phase4_aahq_benchmark.swift):**
- Line ~180: `readExactly(handle: decodeReadHandle, byteCount: inputBytesPerFrame)` — **CPU ALLOC + READ**
- Line ~190: `inputFrames.append(frameData)` — **CPU STORE in vector**
- Line ~240: `makeBGRAInputTexture(frameData: frameData, ...)` with `texture.replace()` — **CPU→GPU COPY**
- Line ~270: `processTextureNoReadback()` — no readback (GPU internal)

**Export Pipeline (ProcessingEngine.swift):**
- Line ~310: `readExactly(handle: decodeOutputHandle, byteCount: inputFrameBytes)` — **CPU ALLOC + READ**
- Line ~379: `processors[workerIndex].processFrame(inputFrame: frameData, ...)` — **pass Data to worker**
- Line ~340: inside `processFrameInternal()`:
  - Line ~835: `inputFrame.withUnsafeBytes { ... inputTexture.replace(...) }` — **CPU→GPU COPY (shared stage texture)**
  - Line ~905: `readbackTexture.getBytes(base, bytesPerRow: ...)` — **GPU→CPU COPY (shared readback texture)**
- Line ~437: `encodeInputHandle.write(contentsOf: nextFrame)` — **CPU WRITE to encode pipe**

**COPY OVERHEAD SUMMARY:**
- Per-frame: ~3–4 major CPU↔GPU boundary crossings (decode→CPU, CPU→GPU, GPU→CPU, CPU→encode)
- For 1080p BGRA (4 bytes/pixel): ~8.3 MB per frame
- At 60 fps: ~500 MB/s of CPU memory traffic (added to system memory bus load)

### 3. **MEMORY ALLOCATION PATTERNS**
- `Data(count: inputBytesPerFrame)` — heap alloc per frame, freed after processing
- `Data(count: outputFrameBytes)` — heap alloc per frame, freed after writing
- TX overhead: malloc/free per frame, no pooling currently

### 4. **TEXTURE STORAGE MODES (Current)**
- Input texture: `.shared` storage mode (CPU/GPU accessible, slower)
- Readback texture: `.shared` storage mode
- Internal/processing textures: likely `.private` (GPU-only, fast)

### 5. **VIDEOTOOLBOX PARTIAL ADOPTION**
- Used **only for encode** via FFmpeg parameters (`-c:v hevc_videotoolbox`)
- NOT connected to Metal pipeline
- No decode-side VideoToolbox (FFmpeg handles decode via libavcodec)
- No CVMetalTextureCache or IOSurface bridge

### 6. **FFmpeg PIPE INTERACTION**
- Decode output: `pipe:1` (stdout) → ProcessingEngine reads via `Pipe()`
- Encode input: `pipe:0` (stdin) ← ProcessingEngine writes via `Pipe()`
- Both are **blocking I/O with buffer management**
- No direct GPU memory sharing with FFmpeg (impossible; FFmpeg is separate process)

---

## Architecture Options for Zero-Copy

### **Option A: Temp File + CVMetalTextureCache (Modest Gain)**
**Scope:** Replace pipe reads/writes with mmap'd temp files; use CVMetalTextureCache for GPU binding.

**Flow:**
```
FFmpeg decode → temp file (mmap)
  ↓
CVMetalTextureCache wraps IOSurface → GPU textures (zero-copy binding)
  ↓
Metal processing (unchanged)
  ↓
CVPixelBuffer w/ IOSurface → encode via FFmpeg mmap temp file
```

**Pros:**
- CVMetalTextureCache eliminates `texture.replace()` copies for decode frames
- IO surface GPU binding is zero-cross (same memory, GPU just remaps page table)
- Simpler than VideoToolbox decode integration
- Works with existing FFmpeg subprocess model

**Cons:**
- Still require CPU readback for encode (GPU→temp file)
- Temp file I/O overhead (SSD/disk latency)
- CVMetalTextureCache has thread safety cost
- Readback still bottleneck (not zero-copy)

**Est. Gain:** 10–20% (eliminates decode upload copy only)

---

### **Option B: VideoToolbox Decode + CVMetalTextureCache (Large Gain)**
**Scope:** Replace FFmpeg decode subprocess with VTDecompressionSession; bridge to Metal via IOSurface/CVMetalTextureCache.

**Flow:**
```
File I/O read → VTDecompression (hardware H.264/HEVC decode)
  ↓
CVPixelBuffer w/ IOSurface (GPU-backed)
  ↓
CVMetalTextureCache.makeTexture(pixelBuffer:) → MTLTexture (zero-copy)
  ↓
Metal processing pipeline
  ↓
readbackTexture.getBytes() → encode pipe
```

**Pros:**
- Eliminates FFmpeg decode subprocess (multi-process overhead gone)
- Eliminates CPU→GPU upload copy (CVMetalTextureCache maps IOSurface)
- VTDecompressionSession hardware decode (M3 Pro ANE/GPU assist)
- Pool CVPixelBuffer + IOSurface to amortize allocation cost
- Can set up render-to-texture directly if encode also supports CVPixelBuffer

**Cons:**
- Significant implementation: VTDecompressionSession queue, callback management
- Requires CVPixelBuffer pool (thread-safe ring buffer)
- Must still readback for encode (GPU→CPU path remains)
- VideoToolbox API complexity (error handling, hardware fallback)
- VTDecompression callbacks run on different dispatch queue (sync hazards)

**Est. Gain:** 30–50% (eliminate decode process + GPU upload copy)

---

### **Option C: VideoToolbox Decode + Encode + IOSurface Bridge (Zero-Copy End-to-End)**
**Scope:** Replace FFmpeg decode AND encode with VideoToolbox; bridge Metal pipeline via IOSurface chain.

**Flow:**
```
File I/O → VTDecompressionSession
  ↓
CVPixelBuffer w/ IOSurface → CVMetalTextureCache → Metal input texture
  ↓
Metal processing → CVPixelBuffer w/ IOSurface output
  ↓
VTCompressionSession (reads from IOSurface GPU buffer)
  ↓
Encoded bitstream → file write
```

**Pros:**
- Full zero-copy pipeline (decode output → Metal input → encode input all via IOSurface)
- Both decode + encode on GPU hardware (M3 Pro ANE/GPU)
- No CPU-GPU boundary crossings (except during Metal compute, which is necessary)
- Eliminate FFmpeg subprocess overhead entirely
- Potential for hardware-assisted filter passes if VTCompressionSession supports pass-through

**Cons:**
- Massive implementation (VTDecompression + VTCompression session management)
- Pool management for CVPixelBuffers, IOSurfaces (thread safety, memory lifecycle)
- VideoToolbox encode constraints (supported codecs: h264, hevc; AV1 NOT available in VideoToolbox on macOS)
- Container muxing loss (FFmpeg handles muxing; must replace with AVFoundation/custom muxing)
- Metadata/subtitle handling (FFmpeg does this; VideoToolbox does not)
- Error recovery more complex (hardware constraints, codec support fallback)

**Est. Gain:** 50–70% (full zero-copy + eliminate subprocess + hardware decode+encode)
**Risk:** Very high; full rewrite of decode/encode pipeline

---

### **Option D: Hybrid — Keep Streaming, Use Temp IOSurface Buffer**
**Scope:** Use temp IOSurface + CVMetalTextureCache layer without changing FFmpeg subprocess.

**Flow:**
```
FFmpeg decode → RAW BGRA write to IOSurface-backed buffer
  ↓
CVMetalTextureCache binds IOSurface → GPU texture (zero-copy)
  ↓
Metal processing (unchanged)
  ↓
Readback → IOSurface-backed buffer
  ↓
FFmpeg encode reads from IOSurface buffer
```

**Pros:**
- Minimal change to existing ProcessingEngine
- Zero-copy GPU binding (CVMetalTextureCache)
- Can keep FFmpeg for flexibility (codec changes, filters)
- IOSurface buffer lifecycle simpler than full VideoToolbox

**Cons:**
- Decode still CPU-bound (FFmpeg→system RAM→IOSurface still has copy via pipe)
- Does not reduce FFmpeg process overhead
- IOSurface allocation/management adds complexity
- CVMetalTextureCache thread-safety cost

**Est. Gain:** 15–25%

---

## RECOMMENDED PATH: **Modified Option B + Staged Rollout**

### **Rationale:**
1. **Large gain** (30–50%) with **manageable scope**
2. VideoToolbox decode is stable, well-documented macOS API
3. CVMetalTextureCache is proven, low-overhead zero-copy bridge
4. Can **fall back to FFmpeg** if VideoToolbox fails (via backend selector)
5. **Encode stays with FFmpeg** initially (handles muxing, metadata, AV1 support)
6. No container/muxing rewrite needed
7. Benchmark infrastructure already in place (ProcessingEngine can test both paths)

### **Staged Implementation Path:**

**Stage 1: CVMetalTextureCache Layer (Weeks 1–2)**
- Create `A4KCVMetalTextureCache` wrapper
- Allocate/pool CVPixelBuffer + IOSurface pairs (ring buffer)
- Implement thread-safe makeTexture() call
- Unit tests: makeTexture(), pixelBuffer reuse, no leaks
- Fallback: if cache init fails, use legacy `texture.replace()`
- **Feature flag:** `A4K_USE_CVMETAL_TEXTURE_CACHE=0/1` (default=0)

**Stage 2: VideoToolbox Decompress Bridge (Weeks 3–5)**
- Implement `A4KVideoToolboxDecoder` class (VTDecompressionSession)
- Wrap decoder in DispatchQueue callback model
- CVPixelBuffer pool management + IOSurface binding
- Fallback to FFmpeg decode if VT decoder init fails
- Unit tests: decode h264/hevc, output CVPixelBuffer streams, no hangs
- **Feature flag:** `A4K_USE_VT_DECODE=0/1` (default=0)
- **Benchmark:** test decode throughput vs FFmpeg

**Stage 3: Integration into ProcessingEngine (Weeks 6–7)**
- Add `A4K_DECODE_BACKEND` env var (ffmpeg|videotoolbox, default=ffmpeg)
- Route through ProcessingEngine based on backend + format
- Benchmark: full pipeline (1080p 60fps animation test case)
- Quality gate: SSIM >= 0.999 vs baseline FFmpeg
- **Fallback path:** if VT decode fails, revert to FFmpeg + CVMetalTextureCache only

**Stage 4: Encode Bridge + IOSurface Output (Weeks 8–10) [Optional/Future]**
- `A4KVideoToolboxEncoder` (VTCompressionSession for h264/hevc)
- Requires custom muxing (AVFoundation or libav C-binding)
- Full zero-copy pipeline if attempted
- **High risk, high reward** — defer unless significant gain empirically shown in Stage 3

---

## Integration Points in Existing Code

### **File: [Anime4KOfflineProcessor.swift](Anime4KOfflineProcessor.swift)**

**Current texture creation (line ~1068):**
```swift
func ensureInputTexture(width: Int, height: Int) -> MTLTexture? {
  // ...
  desc.storageMode = .shared
  // ...
}
```

**New code injection point (processFrameInternal, line ~835):**
```swift
// BEFORE: texture.replace() with CPU data
inputFrame.withUnsafeBytes { raw in
  inputTexture.replace(region: ..., withBytes: raw.baseAddress, ...)
}

// AFTER: CVMetalTextureCache.makeTexture(pixelBuffer) if available
if let cvCache = self.cvMetalTextureCache,
   let pixelBuffer = makePixelBufferFromData(inputFrame),
   let cachedTexture = cvCache.makeTexture(pixelBuffer) {
  // Use cachedTexture (zero-copy)
} else {
  // Fallback to replace()
}
```

**New class properties (near line ~500):**
```swift
private var cvMetalTextureCache: CVMetalTextureCache?
private var pixelBufferPool: [CVPixelBuffer] = []
private let poolLock = NSLock()
```

### **File: [ProcessingEngine.swift](ProcessingEngine.swift)**

**Current decode approach (line ~300):**
```swift
let decodeArguments = Self.buildDecodeArguments(inputURL: job.file.url)
// FFmpeg decode subprocess
```

**New code injection (executeJob, post-probe stage):**
```swift
let decoder: A4KVideoToolboxDecoder?
let useVTDecode = (environment["A4K_USE_VT_DECODE"] ?? "0") == "1"

if useVTDecode {
  decoder = try? A4KVideoToolboxDecoder(
    width: streamInfo.width,
    height: streamInfo.height,
    codecType: codeTypeFromStreamInfo(streamInfo)
  )
}

if let decoder = decoder {
  // Use VT decode path (Stage 2/3)
} else {
  // Use FFmpeg decode path (existing)
}
```

### **File: [FFmpegLocator.swift](FFmpegLocator.swift)**

**Add env resolution (near line ~50):**
```swift
static var useVideoToolboxDecode: Bool {
  ProcessInfo.processInfo.environment["A4K_USE_VT_DECODE"] == "1"
}

static var cvMetalTextureCacheEnabled: Bool {
  ProcessInfo.processInfo.environment["A4K_USE_CVMETAL_TEXTURE_CACHE"] == "1"
}
```

---

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|-----------|
| VT decoder unsupported format (e.g., H.265 10-bit edge case) | Medium | Crash/hang | Fallback to FFmpeg; test all target formats in Stage 2 |
| CVPixelBuffer pool memory leak | High | Gradual perf degrade | Instrument with Allocations; add pool drain method |
| IOSurface GPU sync failures | Low | GPU hang | Validate sync state before Metal use; timeout limits |
| CVMetalTextureCache thread contention | Medium | FPS stutter | Profile with Instruments; consider lock-free ring if needed |
| VT decoder latency (H.265 decode loop) | Medium | Lower throughput initially | Async callback model; batch decode; tune queue priority |
| Encode readback still bottleneck after Stage 2 | High | Limited gain | Documented as Stage 4 work; set expectations |

---

## Testing Requirements

### **Stage 1: CVMetalTextureCache**
1. Unit test: allocate/release 100 CVPixelBuffer + IOSurface pairs, no leaks
2. Unit test: makeTexture() race condition (10 concurrent threads, 1000 calls)
3. Benchmark: texture creation latency (legacy vs CVMetalTextureCache)
4. Visual test: output image SSIM >= 0.999 vs baseline

### **Stage 2: VideoToolbox Decode**
1. Unit test: decode h264 + hevc sample clips (short, long, HDR if available)
2. Unit test: CVPixelBuffer output matches FFmpeg BGRA output (byte-compare first frame)
3. Benchmark: throughput (fps) vs FFmpeg decode subprocess
4. Integration test: Full pipeline with VT decode + Metal + existing encode, SSIM >=0.999
5. Fallback test: VT decode fails → auto-fallback to FFmpeg, no user-visible error

### **Stage 3: Integration**
1. End-to-end benchmark: 1080p 60fps anime clip, full upscale + encode, FPS & memory
2. SSIM quality gate: passes >= 0.999 (existing test infrastructure works)
3. Regression test: existing FFmpeg path still works (A4K_USE_VT_DECODE=0)
4. Stress test: 100 frames rapid-fire, monitor GPU memory, CPU load

### **Benchmark Metrics:**
- Baseline: FFmpeg decode → CPU pipe → Metal → shared texture readback → encode (current)
- Trial 1: FFmpeg decode → CVMetalTextureCache (Stage 1)
- Trial 2: VideoToolbox decode → CVMetalTextureCache (Stage 2)
- Trial 3: VT decode + VT encode (Stage 4, future)

**Expected Results:**
- Stage 1: +10–15% FPS (eliminate replace() overhead)
- Stage 2: +25–40% FPS (eliminate decode subprocess + replace())
- Stage 3 (combined 1+2): +35–50% FPS

---

## Throughput Gain Range

### **Conservative Estimate (Stage 1+2 combined):**
- **6–8 gigabits/sec** saved on CPU↔GPU boundary (reduced from ~500 MB/s peak load)
- **Current baseline** (1080p 60fps anime): ~50× ops/sec × 4 frames inflight ≈ 48 MB/sec throughput
  - With 2× upscale: ~192 MB/sec
  - With 4× upscale: ~768 MB/sec
- **Zero-copy impact:** ~15–25% of wall-clock time spent on CPU copies (estimated; varies by system)
  - 1080p→2160p: ~8–12% gain (already fast)
  - 720p→2880p: ~15–20% gain (more data, higher relative cost)
  - 480p→4320p: ~20–25% gain (extreme case)

### **Optimistic Estimate (with Stage 4 encode):**
- Full zero-copy: ~35–50% FPS gain (eliminates all CPU↔GPU boundaries + subprocess overhead)
- Requires AVFoundation or custom muxing (high implementation cost)

### **Realistic M3 Pro Target:**
- **Current:** 40–60 fps on 1080p→4x upscale (estimated from code structure)
- **After Stage 1+2:** 50–85 fps (25% uplift)
- **After Stage 4:** 60–120 fps (50% uplift; speculative without custom encode testing)

---

## Feature Flags & Fallback Strategy

```bash
# Stage 1 (CVMetalTextureCache)
export A4K_USE_CVMETAL_TEXTURE_CACHE=1  # default=0

# Stage 2 (VideoToolbox Decode)
export A4K_USE_VT_DECODE=1               # default=0

# Encoder selection (future)
export A4K_ENCODE_BACKEND=ffmpeg         # ffmpeg | videotoolbox (default=ffmpeg)

# Diagnostics
export A4K_CVMETAL_DIAG=1               # log CVMetalTextureCache perf
export A4K_VT_DECODE_DIAG=1             # log VTDecompression stats
```

**Fallback Chain:**
1. User requests VT decode + CVMetalTextureCache
2. Init CVMetalTextureCache → if fail, log warning, disable
3. Init VTDecompressionSession → if fail, log warning, disable, use FFmpeg
4. If both disabled, pipeline runs with legacy pipe + texture.replace()
5. Logger emits `[A4KPipeline] backends: cvmetal=<yes|no>, vt_decode=<yes|no>, encoding=ffmpeg`

---

## Summary

**Recommended: Modified Option B (VT Decode + CVMetalTextureCache)**
- **Implementation phases:** 4 (1-2 weeks each, staged with fallbacks)
- **Expected gain:** 25–50% FPS improvement
- **Risk level:** Medium–High (VideoToolbox complexity, callback threading)
- **Fallback safety:** High (all flags, env vars, legacy path maintained)
- **Quality gate:** SSIM >= 0.999 all stages
- **Scope to recommend:** Phase 4 Agent A (runtime optimization) after MPS planner correctness baseline
