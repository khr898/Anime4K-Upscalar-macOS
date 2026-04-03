# Evidence-Based Milestone Strategy: 1080p48/60 → 4K at 1x Speed (M3 Pro)
## Target: HQ A+A Quality with SSIM ≥ 0.999, Max Pixel Diff < 2

**Date**: April 3, 2026 | **Chip**: M3 Pro | **Quality Mode**: A+A HQ | **Quality Gate**: SSIM ≥ 0.999

---

## 1. CURRENT MEASURED BASELINE & GAP TO TARGETS

### Hardware Throughput Requirement
- **1080p48 → 4K**: 48 frames/sec × (1920×1080 input upscaled to 3840×2160 output) = **16.8M output pixels/sec**
- **1080p60 → 4K**: 60 frames/sec × (3840×2160) = **21.0M output pixels/sec**

### Established Performance Baselines (from Phase 4 design doc)
| Approach | Measured FPS | Notes | Feasibility for 1x Speed |
|----------|---------|-------|------------------------|
| **Current**: GLSL via FFmpeg filter | ~14 fps | baseline_backend=glsl (not Metal), too slow | **FAIL** (need 48–60) |
| **Phase 4 Metal (translated shaders)** | ~45–60 fps | Established theoretical max at lock step, no pipelining | ~48fps ceiling, 60fps marginal |
| **Phase 4 Metal + MPS CNNs (desired)** | ~80–100 fps | Theoretical with full optimization; requires MPS + 3x workers inflight | **PASS** (good headroom) |
| **Phase 4 Metal + MPS + triple buffering** | ~120–140+ fps | Best case with overlap, async I/O, and neurally-assisted layers | **STRONG PASS** |

### Current Code State Gap Analysis
**MPS Status** (from Anime4KMPSConvolution.swift):
- Default: `A4K_ENABLE_MPS_CONV` = 0 (disabled)
- Equivalence validation thresholds: `maxAbs=0.003, meanAbs=0.0005` (conservative)
- buildPlans() exists but not invoked by default

**GPU I/O Bottleneck** (from Anime4KOfflineProcessor.swift):
- Frame upload: `texture.replace()` (synchronous, blocks next iteration)
- Frame readback: `texture.getBytes()` (synchronous, blocks CPU waiting for GPU)
- No double-buffering or async readback path

**Inflight Depth** (from ProcessingEngine.swift):
- Current: `inflightSemaphore = DispatchSemaphore(value: workerCount)` (1 frame per worker max)
- No pipelining: `commandBuffer.waitUntilCompleted()` before returning to encode pipe
- Max workers default: 1–3 (depends on neural_assist)

**Gap Summary**:
```
Target: 48–60 fps (M3 Pro, 1080p48/60 → 4K, real-time)
Phase 4b Metal baseline: ~45–60 fps (meets 48 fps w/ 0-loss, 60 fps marginal/risky)
Current code: MPS disabled, GPU I/O sync'd, 1 frame inflight → limits 45 fps
→ GAP: 15–40 fps headroom needed to guarantee 48/60 fps with margin & quality validation overhead
```

---

## 2. PRIORITIZED MILESTONE LADDER WITH OBJECTIVE PASS/FAIL THRESHOLDS

**Quality Acceptance Criteria (All Milestones)**:
- SSIM ≥ 0.999 (compared to Metal baseline)
- Max pixel diff < 2
- Benchmark: `A4K_BENCH_SSIM_THRESHOLD=0.999` (enforced in run_phase4_aahq_benchmark.zsh)

### Milestone 1: MPS Baseline Equivalence Validation (CP1)
**Objective**: Verify MPS CNN passes produce mathematically identical output to hand-translated Metal shaders, with zero output delta under tight equivalence thresholds.

**What to do**:
1. Enable `A4K_ENABLE_MPS_CONV=1`
2. Run buildPlans() for A+A HQ modes (Restore_CNN_VL, Upscale_CNN_x2_VL, Upscale_CNN_x2_M, Restore_CNN_M)
3. Validate weight extraction & layout correctness (verify OHWI ordering, mat4 → float[] conversion)
4. Run equivalence tests with strict thresholds: `maxAbs ≤ 0.003, meanAbs ≤ 0.0005`

**Pass Criteria**:
- Equivalence validation PASS on 64-sample test patches for each CNN pass
- SSIM ≥ 0.999 vs Metal baseline on full 1080p test frames
- Build succeeds, no type errors, no runtime crashes

**Fail Criteria**:
- Equivalence FAIL: Any pass rejects with maxAbs > 0.003
- SSIM < 0.999: Quality regression
- Crash on MPS plan creation or encode

**Benchmark Command** (CP1):
```bash
A4K_ENABLE_MPS_CONV=1 A4K_BENCH_BASELINE_BACKEND=metal \
  A4K_BENCH_OPT_BACKEND=mps A4K_BENCH_USE_NEURAL_ASSIST=0 \
  A4K_BENCH_WORKERS=1 A4K_BENCH_OUTPUT_SCALE=2 \
  bash Tools/run_phase4_aahq_benchmark.zsh <test_1080p.mp4> 120
# Expected: fps ≈ 45–55 (no throughput yet, but quality gates must PASS)
# Success: SSIM=0.999+, quality_status=PASS
```

**Estimated FPS Gain**: +0–5% (MPS plan overhead not yet amortized, no pipelining yet)

---

### Milestone 2: GPU I/O Optimization — Async Readback & Texture Reuse (CP2)
**Objective**: Eliminate synchronous GPU I/O stalls by decoupling readback from submission.

**What to do**:
1. Implement async readback buffer pool: pre-allocate 3 MTLBuffer instances, rotate per frame
2. Replace `texture.getBytes()` with `blitCommandEncoder.copy()` to MTLBuffer (non-blocking)
3. Pre-allocate input/output user textures per worker (avoid per-frame alloc)
4. Add fence handlers to signal readback completion without CPU wait

**Pass Criteria**:
- No `getBytes()` calls in hot path (benchmark should not show GPU stalI/O waits)
- SSIM ≥ 0.999 (must maintain quality)
- Texture allocation profiler shows zero per-frame new texture creations

**Fail Criteria**:
- Readback stall visible in GPU profiler
- SSIM regression
- Crash from fence/queue mismanagement

**Benchmark Command** (CP2):
```bash
A4K_ENABLE_MPS_CONV=1 A4K_BENCH_BASELINE_BACKEND=metal \
  A4K_BENCH_OPT_BACKEND=mps A4K_BENCH_USE_NEURAL_ASSIST=0 \
  A4K_BENCH_WORKERS=2 A4K_BENCH_GPU_INFLIGHT=3 A4K_BENCH_OUTPUT_SCALE=2 \
  bash Tools/run_phase4_aahq_benchmark.zsh <test_1080p.mp4> 120
# Expected: fps ≈ 55–65 (15–20% gain from I/O optimization)
# Success: SSIM=0.999+, quality_status=PASS
```

**Estimated FPS Gain**: +15–20% (I/O decoupling + buffer pool efficiency)

---

### Milestone 3: Inflight Pipelining & Worker Scaling (CP3)
**Objective**: Increase inflight depth from 1 to 3–4, allowing GPU to process frame N while frame N+1 is being decoded and frame N-1 is being encoded.

**What to do**:
1. Remove `commandBuffer.waitUntilCompleted()` from processFrameInternal
2. Use completion handlers + fence barriers instead
3. Raise `gpuInflightDepth` from 1 to 3 (benchmark: `A4K_BENCH_GPU_INFLIGHT=3`)
4. Scale workers to 3–4 for M3 Pro (hint: `A4K_INFLIGHT_WORKERS=3`)
5. Ensure ordering preserved on final readback via frame-index tracking

**Pass Criteria**:
- No GPU stalls in profiler (utilization > 85%)
- All 3 frames processed before stall
- SSIM ≥ 0.999 maintained
- Frame order preserved in output

**Fail Criteria**:
- GPU utilization < 70%
- Frame order mix-up
- SSIM regression
- Deadlock or fence timeout

**Benchmark Command** (CP3):
```bash
A4K_ENABLE_MPS_CONV=1 A4K_BENCH_BASELINE_BACKEND=metal \
  A4K_BENCH_OPT_BACKEND=mps A4K_BENCH_USE_NEURAL_ASSIST=1 \
  A4K_BENCH_WORKERS=3 A4K_BENCH_GPU_INFLIGHT=3 A4K_BENCH_OUTPUT_SCALE=2 \
  bash Tools/run_phase4_aahq_benchmark.zsh <test_1080p.mp4> 120
# Expected: fps ≈ 70–85 (25–30% gain from pipelining + neural assist)
# Success: SSIM=0.999+, quality_status=PASS
```

**Estimated FPS Gain**: +25–30% (pipelining + neural-assisted MPS ops)

---

### Milestone 4: Threadgroup Size Tuning & GPU Utilization (CP4)
**Objective**: Tune Metal threadgroup size (512 → optimal for A+A HQ CNN) and verify full M3 Pro GPU utilization.

**What to do**:
1. Profile with Xcode Metal GPU counters to find optimal threadgroup threads
2. Sweep `A4K_TARGET_THREADGROUP_THREADS` from 256 to 1024 (step 128)
3. Measure FPS per value, flag regressions
4. Lock to best value (likely 512–768 for M3 Pro)
5. Enable occupancy boost flags if available in Metal context

**Pass Criteria**:
- Threadgroup sweep complete, optimal value locked
- FPS ≥ 85 at optimal value (no regression from CP3)
- Metal GPU utilization ≥ 90%
- SSIM ≥ 0.999 maintained

**Fail Criteria**:
- Occupancy < 70%
- Regression from CP3 baseline
- SSIM regression

**Benchmark Command** (CP4 — Threadgroup Sweep):
```bash
for TG in 256 384 512 640 768 896 1024; do
  A4K_ENABLE_MPS_CONV=1 A4K_TARGET_THREADGROUP_THREADS=$TG \
    A4K_BENCH_BASELINE_BACKEND=metal \
    A4K_BENCH_OPT_BACKEND=mps A4K_BENCH_USE_NEURAL_ASSIST=1 \
    A4K_BENCH_WORKERS=3 A4K_BENCH_GPU_INFLIGHT=3 A4K_BENCH_OUTPUT_SCALE=2 \
    bash Tools/run_phase4_aahq_benchmark.zsh <test_1080p.mp4> 60 2>&1 | grep "fps=" | tail -1
done
```

**Estimated FPS Gain**: +5–10% (threadgroup tuning edge case)

---

### Milestone 5: 1080p48 → 4K Real-Time Threshold (CP5-48)
**Objective**: Validate sustained 48 fps on M3 Pro for continuous 1080p48 input → 4K output, with quality margin.

**What to do**:
1. Prepare a continuous 1080p48 test video (10+ minutes for stability test)
2. Run benchmark with 240+ frames (48 fps × 5 sec = 240 frames)
3. Measure average FPS over sustained run (not just initial burst)
4. Validate SSIM ≥ 0.999 maintained throughout
5. Monitor GPU/CPU temps to ensure no thermal throttling

**Pass Criteria**:
- Sustained FPS ≥ 48.0 (averaged over 240+ frames, no drops below 45)
- SSIM ≥ 0.999 on all comparison frames
- No thermal throttling (GPU ≤ 85°C after warmup)
- CPU idle time available (not 100% pegged)

**Fail Criteria**:
- Sustained FPS < 48
- Thermal throttling
- SSIM < 0.999
- Frame drops or stutters

**Benchmark Command** (CP5-48):
```bash
A4K_ENABLE_MPS_CONV=1 A4K_BENCH_BASELINE_BACKEND=metal \
  A4K_BENCH_OPT_BACKEND=mps A4K_BENCH_USE_NEURAL_ASSIST=1 \
  A4K_BENCH_WORKERS=3 A4K_BENCH_GPU_INFLIGHT=3 A4K_BENCH_OUTPUT_SCALE=2 \
  bash Tools/run_phase4_aahq_benchmark.zsh <test_1080p48_10min.mp4> 240
# Expected: fps = 48.0 ± 1.0 (sustained, no stutters)
# Success: quality_status=PASS, no thermal throttle
```

**Estimated FPS Gain**: Not applicable (achievement milestone, no new optimization)

---

### Milestone 6: 1080p60 → 4K Real-Time Threshold (CP5-60) [OPTIONAL STRETCH GOAL]
**Objective**: Stretch: validate 60 fps if M3 Pro + optimized MPS allows headroom.

**What to do**:
1. Prepare continuous 1080p60 test video (10+ minutes)
2. Run same benchmark with 300+ frames (60 fps × 5 sec)
3. Measure sustained FPS and quality
4. If FPS < 60, analyze GPU saturation and defer to post-48-approval phase

**Pass Criteria**:
- Sustained FPS ≥ 60.0 (or ≥ 58 with acceptable headroom)
- SSIM ≥ 0.999
- Thermal OK
- CPU headroom available

**Fail Criteria**:
- FPS < 56 (insufficient headroom for 60 fps target)
- Defer 60 fps to Phase 5 if 48 fps passes cleanly

**Benchmark Command** (CP5-60):
```bash
A4K_ENABLE_MPS_CONV=1 A4K_BENCH_BASELINE_BACKEND=metal \
  A4K_BENCH_OPT_BACKEND=mps A4K_BENCH_USE_NEURAL_ASSIST=1 \
  A4K_BENCH_WORKERS=3 A4K_BENCH_GPU_INFLIGHT=4 A4K_BENCH_OUTPUT_SCALE=2 \
  bash Tools/run_phase4_aahq_benchmark.zsh <test_1080p60_10min.mp4> 300
# Expected: fps = 60.0 ± 1.5 (achieved if Phase 1–4 have sufficient gains)
# Success: quality_status=PASS
```

**Estimated FPS Gain**: N/A (stretch goal — depends on CP1–4 combined gains)

---

## 3. BENCHMARK COMMAND SETS PER MILESTONE

| Milestone | Backend | Workers | GPU Inflight | TG Threads | Neural Assist | Frames | FPS Target | Command |
|-----------|---------|---------|--------------|------------|---------------|--------|-----------|---------|
| **CP1** | MPS | 1 | 1 | 512 | 0 | 120 | ≥45 | `A4K_ENABLE_MPS_CONV=1 A4K_BENCH_BACKEND=mps ... bash run_phase4_aahq_benchmark.zsh <vid> 120` |
| **CP2** | MPS | 2 | 3 | 512 | 0 | 120 | ≥55 | `A4K_BENCH_GPU_INFLIGHT=3 A4K_BENCH_WORKERS=2 ...` |
| **CP3** | MPS | 3 | 3 | 512 | 1 | 120 | ≥70 | `A4K_BENCH_USE_NEURAL_ASSIST=1 A4K_BENCH_WORKERS=3 ...` |
| **CP4** | MPS | 3 | 3 | {256…1024} | 1 | 60 | Sweep | For TG in {256,384,512,640,768,896,1024}; benchmark with each |
| **CP5-48** | MPS | 3 | 3 | Best | 1 | 240 | ≥48 | `bash run_phase4_aahq_benchmark.zsh <1080p48> 240` |
| **CP5-60** | MPS | 3 | 4 | Best | 1 | 300 | ≥60 | `bash run_phase4_aahq_benchmark.zsh <1080p60> 300` |

---

## 4. WHAT TO DEFER VS. INCLUDE TO MAXIMIZE QUICK HIT

### INCLUDE (Critical Path to 1x Speed)
1. ✅ **MPS convolution enabling** (CP1) — ~30–40% of total speedup
2. ✅ **GPU I/O async + buffer pool** (CP2) — ~15–20% of speedup
3. ✅ **Inflight pipelining + worker scaling** (CP3) — ~25–30% of speedup
4. ✅ **Threadgroup tuning** (CP4) — ~5–10% marginal
5. ✅ **Quality validation** (all CPs) — SSIM ≥ 0.999 locked

### DEFER (Post-48fps Approval)
1. ❌ **Core ML / Neural Engine explicit routing** — ANE assists via MPS, pure CoreML integration can come later
2. ❌ **Advanced memory management** (MTLHeap recycling, purgeable state tracking) — simple free-list sufficient for 48fps
3. ❌ **Multi-format pixel support** (RGBA, YUV420, etc.) — BGRA-only for first milestone
4. ❌ **Real-time playback preview mode** — export/offline pipeline only for Phase 4
5. ❌ **4x upscaling (1080p → 4320p)** — 2x upscaling only for 48fps target
6. ❌ **60 fps support** (CP5-60) — Stretch goal; approve 48 fps first, then attempt
7. ❌ **Argument buffer optimization** (Metal 3 feature) — Not critical for baseline
8. ❌ **Custom convolution kernel hand-tuning** — Use Apple MPS as-is

---

## 5. FINAL ACCEPTANCE DEFINITION

### For 1080p48 → 4K HQ Profile
**Pass Acceptance**:
1. ✅ Sustained real-time FPS: **≥ 48.0 fps** (averaged over ≥ 240 frames / 5 sec continuous)
2. ✅ Quality gate: **SSIM ≥ 0.999** vs. Metal baseline (all comparison frames)
3. ✅ Max pixel diff: **< 2** across test samples
4. ✅ No thermal throttling: GPU temp ≤ 85°C after warmup
5. ✅ Frame order preserved: Output frames in same sequence as input
6. ✅ Build succeeds: No Swift compile errors, Metal shader validation passes
7. ✅ All prior checkpoints passed: CP1, CP2, CP3, CP4 all PASS

**FAIL Conditions**:
- ❌ Sustained FPS < 48
- ❌ SSIM < 0.999 or pixel diff ≥ 2
- ❌ Thermal throttle (GPU > 87°C sustained)
- ❌ Frame order corruption
- ❌ Build failure

**Sign-Off**: 1080p48 → 4K profile locked; ready for 60fps stretch goal attempt.

---

### For 1080p60 → 4K HQ Profile (Stretch Goal)
**Pass Acceptance** (if attempted):
1. ✅ Sustained real-time FPS: **≥ 60.0 fps** (averaged over ≥ 300 frames / 5 sec continuous)
2. ✅ Quality gate: **SSIM ≥ 0.999**
3. ✅ Max pixel diff: **< 2**
4. ✅ Thermal OK: GPU ≤ 85°C
5. ✅ Frame order preserved
6. ✅ CP5-60 checkpoint passed

**FAIL / DEFER Condition**:
- If FPS ≥ 56 but < 60: "Marginal 60fps; defer high-frequency workloads to post-Phase 4 tuning"
- If FPS < 56: "Insufficient GPU headroom; 60fps not achievable without alternative approach (e.g., reduced quality, scale-down, different chip); freeze 48fps as lock-in, revisit Phase 5"

**Sign-Off** (if passes): 1080p60 → 4K profile locked.

---

## Summary Roadmap Timeline

| Phase | Objective | FPS Target | Quality Gate | Owner | Duration |
|-------|-----------|-----------|--------------|-------|----------|
| **CP1** | MPS baseline equivalence | 45–55 | SSIM ≥ 0.999 | Agent A (MPS planner) | 1–2 days |
| **CP2** | GPU I/O async + pool | 55–65 | SSIM ≥ 0.999 | Agent A (I/O refactor) | 1–2 days |
| **CP3** | Inflight pipelining + workers | 70–85 | SSIM ≥ 0.999 | Agent A (pipeline sync) | 1–2 days |
| **CP4** | Threadgroup tuning | 85–90 | SSIM ≥ 0.999 | Agent A + Agent B (profiling) | 1 day |
| **CP5-48** | 1x speed validation (48 fps) | **≥ 48** | **SSIM ≥ 0.999** | Agent B (QA) | 1 day |
| **CP5-60** | Stretch: 60 fps (optional) | **≥ 60** | **SSIM ≥ 0.999** | Agent A + B | 1 day (if attempted) |

**Total estimated timeline**: 6–8 days (5 critical path + 1 optional stretch + buffer)
