## Plan: M3 Pro Realtime 4K HQ A+A

Reach sustained 1080p to 4K realtime with HQ A+A by unblocking parity-safe MPS CNN substitution first, then removing decode-to-GPU copy overhead through a VideoToolbox plus CVMetalTextureCache path, and finally tuning inflight scheduling on M3 Pro. 4K48 is required for acceptance; 4K60 is stretch after 4K48 lock.

**Steps**
1. Phase 1 - Lock Baseline and Instrumentation
2. Add fixed benchmark profiles and milestone tagging in /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh and /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/Tools/phase4_aahq_benchmark.swift so every run records backend, workers, inflight depth, threadgroup target, and quality gate result. This is the reference for all later pass/fail decisions.
3. Capture M3 Pro baseline at 1080p48 and 1080p60 inputs for 2x upscale (output 4K) over at least 240 frames each; keep CSV and summary artifacts as locked baseline checkpoints. *depends on 1*
4. Phase 2 - MPS Parity Unblock (Critical Path)
5. In /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift, complete parity correctness work: default convolution offset handling, weight layout and packing correctness, kernel flip handling, and explicit equivalence input domain selection, with per-pass diagnostics.
6. Add deterministic equivalence validation inputs in planner validation (edges, ramps, checkerboards in addition to random) so spatial misalignment and channel transposition are detected before runtime benchmarks. *depends on 5*
7. Add per-pass acceptance reporting and fail reasons in planner logs so rejected passes can be fixed one by one instead of broad tuning guesses. *parallel with 6*
8. Run parity calibration sweeps for layout, pack order, offset, flip, and input mode; lock the winning default configuration for M3 Pro only after SSIM >= 0.999 holds in full benchmark runs. *depends on 6 and 7*
9. Phase 3 - Runtime Throughput on Current Architecture
10. In /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift and /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift, complete command-buffer and texture reuse tuning (inflight depth, texture pooling, reduced blocking waits, pass-level timing visibility).
11. In /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/ProcessingEngine.swift, keep ordered encode semantics but reduce scheduling overhead and enforce M3 Pro tuned worker/inflight defaults for benchmark mode. *parallel with 10*
12. Re-sweep workers, inflight depth, and threadgroup target on M3 Pro; lock best profile for 4K48 gate while preserving quality gate. *depends on 10 and 11*
13. Phase 4 - Major Refactor: Zero-Copy Decode Bridge
14. Introduce a feature-flagged VideoToolbox decode path in /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/ProcessingEngine.swift that delivers CVPixelBuffer frames, with automatic fallback to current FFmpeg decode path on failure.
15. Integrate CVMetalTextureCache-backed texture binding in /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift to avoid repeated CPU-to-GPU frame uploads where decode source is CVPixelBuffer. *depends on 14*
16. Keep encode path unchanged initially (FFmpeg subprocess) to control risk; only consider encode-path replacement after 4K48 is achieved and bottleneck evidence confirms encode stage dominates.
17. Phase 5 - Acceptance and Stretch
18. 4K48 Required Gate: sustained >= 48 fps over long runs (>= 240 frames), SSIM >= 0.999, stable output order, successful build and no regressions in existing modes. *depends on 8, 12, 15*
19. 4K60 Stretch Gate: run same acceptance protocol at 60 fps input; if sustained >= 60 fps with quality gate pass, lock a second profile, otherwise keep 4K48 locked profile as release target and retain 4K60 backlog items. *depends on 18*
20. Optional Phase 6 if needed for 4K60: evaluate encode-path acceleration and advanced Metal binding optimizations only after objective bottleneck confirmation from profiling data. *depends on 19*

**Relevant files**
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift — parity planner, weight mapping, equivalence validator, pass acceptance diagnostics.
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift — pass execution, MPS plan usage points, threadgroup and texture binding overhead.
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/Anime4KOfflineProcessor.swift — frame processing orchestration, command-buffer lifecycle, no-readback inflight behavior, CVMetal integration point.
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/ViewModels/ProcessingEngine.swift — decode/encode orchestration, worker scheduling, fallback routing for new decode path.
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/Tools/phase4_aahq_benchmark.swift — benchmark worker/inflight controls, metrics output, artifact generation.
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh — baseline/trial automation, quality gate orchestration, per-milestone benchmarking.
- /Users/kaveenhimash/Projects/Anime4K-Upscalar-macOS/anime4k_metal_phase4.md — target benchmark and quality roadmap alignment.

**Verification**
1. Build verification: xcodebuild debug build must pass at each phase checkpoint.
2. Quality verification: SSIM >= 0.999 and quality_status=PASS in benchmark output for every accepted optimization.
3. Performance verification for required target: 1080p48 to 4K HQ A+A sustained >= 48 fps over >= 240 frames.
4. Stretch verification for optional target: 1080p60 to 4K HQ A+A sustained >= 60 fps over >= 240 frames.
5. Stability verification: no frame order corruption, no command-buffer failures, no deadlocks under multi-worker/inflight runs.
6. Regression verification: legacy non-Phase4 paths remain functional (upscale/compress/stream optimize core flows).

**Decisions**
- Required outcome: lock 4K48 at 1x speed with strict quality gate.
- Stretch outcome: 4K60 at 1x speed only if achieved without quality relaxation.
- Scope includes major refactor work now (VideoToolbox decode bridge and zero-copy texture binding).
- Quality thresholds are fixed; no default relaxation is allowed for release profile.
- Sequence is correctness first (MPS parity), then throughput tuning, then decode-path refactor, then stretch target.

**Further Considerations**
1. Use feature flags for each major refactor slice so fallback to stable path is immediate during verification failures.
2. Keep M3 Pro specific tuned defaults separated from portable defaults to avoid regressions on other Apple Silicon tiers.
3. Defer encode-path replacement until profiling proves encode dominates after decode and parity work are complete.
