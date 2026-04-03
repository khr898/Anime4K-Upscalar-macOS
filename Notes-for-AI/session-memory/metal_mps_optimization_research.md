# Apple Metal + MPS CNN Video Pipeline Optimization Research
## Research Date: April 3, 2026

### Sources Analyzed
- Apple Metal Resource Synchronization (official docs)
- Metal Performance Shaders documentation
- MPSImage and CNN kernel guidance
- Core ML compute device strategy
- WWDC24: "Accelerate machine learning with Metal" (10218)
- WWDC24: "Explore Swift performance" (10217)
- WWDC23: "Optimize machine learning for Metal apps" (10050)
- Metal Tuning Hints (official best practices)
- Argument Buffers management (Metal 3)

### Key Findings

#### Metal Compute Optimization
- Fences/barriers preferred over wait/dispatch cycle (2.5ms penalty for empty buffers)
- Argument buffers reduce CPU overhead 5-10x vs individual resource binding
- Metal 3 direct GPU resource handles eliminate encoding cost
- Concurrent compute passes require explicit synchronization (MTLDispatchType.concurrent)
- Hazard tracking overhead: untracked heaps for latency-sensitive paths

#### MPS CNN Specifics
- MPSTemporaryImage for intermediate CNN layers (automatic memory pooling)
- Feature channel storage: N channels = ceil(N/4) texture array slices
- Batch processing amortizes overhead (critical for small images)
- Memory residency tracking important for multi-layer pipelines
- Clamp highlights layer standard for preventing overflow artifacts

#### Command Buffer Strategy
- Multiple command buffers inflight >> single wait/encode cycle
- Batch compute/render encoder invocations (avoid mode switching cost)
- ~512KB tile size optimal for multi-pass image chains
- Resource allocation latency can CPU-bound (pre-allocate + recycle)

#### Core ML Compute Devices
- CoreML auto-routes to CPU/GPU/Neural Engine
- MPS Graph supports GPU + Neural Engine execution for hybrid workloads
- Pure Metal deterministic vs Core ML variable latency
- Metal 4: enhanced synchronization primitives (MTL4Queue, MTL4Encoder)

#### Memory Residency
- useResource() calls mandatory once per lifetime for argument buffers
- MTLHeap + argument buffers combine for 2x throughput on multi-pass
- Purgeable state tracking for texture memory efficiency
- Resource synchronization fences better than intra-pass barriers for large graphs
