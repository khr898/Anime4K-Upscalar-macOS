- After Swift edits in this repo, run full xcodebuild validation; get_errors can miss compile-time issues (e.g., missing return in Anime4KOfflineProcessor).
- For benchmark no-readback path, use Anime4KOfflineProcessor.waitForIdle() before timing/reporting completion when inflight depth > 1.

- Structured equivalence patterns (ramps/checkerboard/step) exposed parity issues earlier than random-only inputs; offset (1,1) increased error substantially in current MPS mapping, so keep default offset at (0,0) until layout/pack mapping is corrected.

- VideoToolbox decode bridge is now feature-flagged in ProcessingEngine (`A4K_DECODE_BACKEND=videotoolbox` or `A4K_USE_VT_DECODE=1`) with automatic fallback to FFmpeg decode on reader setup failure.
- Anime4KOfflineProcessor now supports zero-copy CVPixelBuffer ingest via CVMetalTextureCache through `processPixelBuffer(...)`, avoiding CPU upload when decode source is pixel buffers.
- MPS planner auto-mapping (`A4K_MPS_AUTO_MAP=1`) now sweeps layout/pack/channel/flip candidates and reports best rejected candidate; bias must be remapped with channel order for correct candidate evaluation.
- Even after auto-map and bias remap, strict equivalence still rejects all current single-input 3x3 passes; latest 240-frame run stayed ~15.21 fps trial vs ~14.58 fps baseline with SSIM 1.000000.
- Full FFmpeg removal is currently unsafe: FFmpeg still provides ffprobe metadata probing, export encode path (audio/subtitle copy), and complete compress/stream-optimize pipelines including SVT-AV1; current AVFoundation/VideoToolbox alternative only covers decode ingestion.
- Expanded MPS mapping model to decouple input/output channel orders and search output hypotheses per input permutation (configured order, RGBA, input permutation, inverse permutation).
- Compile is green after channel-hypothesis expansion, but strict equivalence still rejects all current single-input 3x3 passes under border=0.
- Targeted probes indicate parser fundamentals are correct for center taps (OHWI packing + column-major matrix interpretation), so persistent failures are not from basic pack/layout/channel orientation.
- Shift probes indicate nonzero texel-offset sampling in reference shader path does not map cleanly to fixed MPS spatial taps on small validation textures, suggesting a sampling-semantic mismatch that can cause systematic strict false negatives.

- Parallelism defaults were raised: ProcessingEngine now auto-scales worker count by active CPU cores/backend and sets a deeper queued frame pipeline (`A4K_PIPELINE_QUEUE_DEPTH`) to keep decode, workers, and GPU concurrently busy.
- Runtime compute defaults now target 512 threads per threadgroup (`A4K_TARGET_THREADGROUP_THREADS`) and converter pass has its own tuning knob (`A4K_CONVERTER_TG_THREADS`) to better occupy GPU cores.
- Benchmark harness now auto-chooses worker count by hardware/backend and exposes queue depth (`A4K_BENCH_QUEUE_DEPTH`) separately from GPU inflight depth.
