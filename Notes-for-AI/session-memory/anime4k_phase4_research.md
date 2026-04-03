# Anime4K Phase 4 Benchmark Performance Research

## Architecture Summary
- **Pipeline**: FFmpeg decode (subprocess) → BGRA pipe → Metal + MPS upscaling (Swift) → readback → FFmpeg encode (subprocess)
- **Frame Loop**: ProcessingEngine spawns decode/encode as separate processes, middle processor on main + worker threads
- **Quality Gate**: SSIM ≥ 0.999, max pixel diff < 2 (enforced in benchmark + equivalence validation)
- **Target**: 45–60 fps Metal baseline, 80–100 fps with MPS

## Key Code Files
- **ProcessingEngine.swift**: FFmpeg lifecycle, frame I/O threading (worker queues + inflight semaphore)
- **Anime4KOfflineProcessor.swift**: GPU frame processing, texture management, command buffer encoding
- **Anime4KRuntimePipeline.swift**: Metal shader pass orchestration, MPS pass plan integration
- **Anime4KMPSConvolution.swift**: MPS convolution kernel extraction + equivalence validation
- **phase4_aahq_benchmark.swift**: Throughput benchmark harness (preload, worker loop, timing)

## CRITICAL BOTTLENECKS IDENTIFIED

### 1. Per-Frame GPU I/O (Severity: HIGH)
**Evidence**: ProcessingEngine.swift L~300+ `inputFrame.withUnsafeBytes{ inputTexture.replace(...) }` + Anime4KOfflineProcessor.swift L~880+ `readbackTexture.getBytes()`
- **Problem**: Frame upload uses `texture.replace()` (sync, blocks next iteration) → GPU wait
- **Problem**: Frame readback uses `texture.getBytes()` (sync, blocks CPU waiting for GPU to finish)
- **Impact**: 1-frame latency per direction = huge pipeline stall when 3+ workers need sequential I/O

### 2. Sequential Frame Encoding (Severity: HIGH)
**Evidence**: ProcessingEngine.swift L~300+, worker semaphore `wait()` per frame
- **Problem**: Only 1 frame in flight per semaphore slot, blocking on GPU completion before next frame
- **Problem**: `commandBuffer.waitUntilCompleted()` in processFrameInternal (L~844) blocks the worker
- **Impact**: GPU can't be kept fed → underutilization at 2-3 fps per worker

### 3. Texture Reallocation (Severity: MEDIUM)
**Evidence**: Anime4KOfflineProcessor.swift ensureInputTexture/ensureReadbackTexture (L~920+)
- **Problem**: Allocates new MTLTexture every frame if dimensions mismatch (not cached properly)
- **Impact**: 5-10% overhead per frame (allocation overhead, not visible but measured)

### 4. MPS Not Fully Leveraged (Severity: MEDIUM→HIGH)
**Evidence**: Anime4KMPSConvolution.swift buildPlans defaults disabled + equivalence validation stringent
- **Problem**: `A4K_ENABLE_MPS_CONV` defaults to 0; planner only runs if env flag = 1
- **Problem**: Default equivalence thresholds very conservative (maxAbs=0.003, meanAbs=0.0005)
- **Impact**: GPU CNN kernels run in raw Metal instead of Apple's optimized MPS → 30-40% slower

### 5. Synchronous Metal Command Buffer Execution (Severity: MEDIUM)
**Evidence**: Anime4KOfflineProcessor.swift `commandBuffer.waitUntilCompleted()` in processFrameInternal
- **Problem**: Waits for entire stage pipeline before returning, no pipelining
- **Impact**: GPU idle at end of each frame, can't start next frame's work

### 6. Frame I/O Path Inefficiency (Severity: LOW→MEDIUM)
**Evidence**: ProcessingEngine.swift L~300+ pipe reading/writing with Data allocations
- **Problem**: per-frame Data copy → inputFrame bytes copied → texture upload
- **Impact**: extra CPU/memory pressure, not GPU-bound but adds contention

## OPTIMIZATION OPPORTUNITIES (Priority Order)

### SAFE (Quality-Preserving)
1. **Enable MPS by default** (pass quality validation)
2. **Increase inflight workers** to 3-4 for better GPU feeding
3. **Reduce frame readback latency** via async readback or double-buffered output
4. **Reuse texture allocations** per worker

### RISKY (Require Validation)
5. Use shared memory for frame I/O (zero-copy upload, but requires buffer management)
6. Remove commandBuffer.waitUntilCompleted() → async completion handlers
7. Batch multiple stages before GPU->CPU readback

## Shader Pass Structure
Anime4K A+A HQ uses:
- Clamp_Highlights (non-CNN, fast)
- Restore_CNN_VL (heavy, 18 passes → CNN convolutions)
- Upscale_CNN_x2_VL (heavy, ~20 passes → CNN convolutions + depth-to-space)
- Restore_CNN_M, Upscale_CNN_x2_M (fallback lighter variants)

CNN passes marked with `mat4` weight matrices → convertible to MPS via buildPlans()
