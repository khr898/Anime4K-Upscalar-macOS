# Phase 2 Findings — BLOCKER: Parallels VM has no ANE passthrough

**Date:** 2026-07-27
**Environment:** Parallels macOS VM (Tahoe 26.5.2) on Apple Silicon.
  - `system_profiler`: Model Name "Apple Virtual Machine 1", Model Identifier
    "VirtualMac2,1", Chip "Apple M3 Pro (Virtual)", 4 cores, 6 GB.
  - `sysctl kern.hv_vmm_present = 1`.
  - This is a guest VM, NOT bare metal.

## TL;DR

**The plan's entire ANE-placement thesis is unverifiable in this VM.** Apple's
Virtualization framework does NOT pass the Neural Engine through to macOS
guests. Every CoreML model — any config, any size, even a 3-conv pure net —
places 100% on CPU per `MLComputePlan`. Phase 1's "100% CPU, 0 ANE" audit is a
**VM artifact, not a conversion-config bug**. The plan's root-cause diagnosis
is wrong for this environment.

## Web evidence (Parallels VM ANE passthrough)

- Parallels forum (Dec 2024): CoreML app in macOS Arm VM "ran very slowly, as
  if using software (CPU) rather than the Neural Engine." No official fix.
  https://forum.parallels.com/threads/hardware-acceleration-for-coreml.366037/
- Parallels KB 128867: macOS Arm VMs use Apple's Virtualization framework,
  which does not expose all host hardware to the guest.
  https://kb.parallels.com/en/128867
- GoKawiil benchmark (Mac mini M4 Pro, Tahoe 26.4.1): VM CoreML half/quantised
  scores ~15–21% of host (5,291/8,577/6,877 vs 5,973/41,251/56,616) → "Neural
  Engine is not being passed through to the guest."
  https://gokawiil.com/article/286557

## Local evidence (this VM, this session)

All converted at fixed 256x256, audited with `Tests/MLComputePlanAudit.swift`
(`MLComputePlan`, `.cpuAndNeuralEngine`):

| Model / variant | Params | ANE | CPU | nil |
|---|---|---|---|---|
| animevideov3 macOS14 prelu (baseline) | 621K | 0 | 42 | 151 |
| animevideov3 macOS15 prelu | 621K | 0 | 42 | 151 |
| animevideov3 iOS26 prelu | 621K | 0 | 42 | 151 |
| animevideov3 macOS14 SiLU | 621K | 0 | 42 | 134 |
| animevideov3 macOS15 SiLU | 621K | 0 | 42 | 134 |
| animevideov3 iOS26 SiLU | 621K | 0 | 42 | 134 |
| animevideov3 TensorType IO | 621K | 0 | 41 | 150 |
| RRDB 6B macOS14 | ~16M | 0 | 280 | 761 |
| RRDB 6B TensorType IO | ~16M | 0 | 279 | 760 |
| **pure 3-conv net** (no tail/shuffle/upsample) | tiny | 0 | 5 | 21 |

The last row is decisive: a minimal pure-conv net with no SR-specific ops also
places 0 ANE / 5 CPU. The blocker is the environment, not the graph.

## Levers tested and ruled out (in this VM)

- Deployment target macOS14 → macOS15 → iOS26: changes op version labels only.
- PReLU → SiLU (plan Phase 7 hypothesis): disproven here — SiLU still CPU.
  (May still matter on bare metal; cannot tell from VM.)
- ImageType input → TensorType input: no effect on placement.
- Model size 621K vs 16M: both CPU. (<1M-threshold hypothesis disproven here.)
- Pure-conv graph: still CPU.

## What this means for the plan

| Plan item | Status in this VM |
|---|---|
| Phase 2 gate "0 CPU fallback" | **Unverifiable** — MLComputePlan always CPU in VM |
| Phase 1 audit conclusion ("config broken") | **Artifact** — re-audit on bare metal needed |
| Phase 6 fps gates (M3 Pro targets) | **Invalid** — VM runs CoreML at ~15-21% of host |
| Phase 7 PReLU→SiLU swap gate | **Unverifiable** here |
| Conversion config fix (TensorType+FP16+fixed shape+macOS14) | **Still correct** for real hardware — apply it, but can't prove ANE here |
| Phase 3/4/5 Swift pipeline (full-frame, ring, MetalFX) | **Buildable** in VM; runtime fps must be measured on host |

## Recommendation

1. Keep the conversion config fix (TensorType output, FP16, fixed shape,
   CPU_AND_NE, macOS14). It is the right config for bare-metal ANE. Promote
   models to `Resources/Models`.
2. Mark Phase 2 `blocked` on **bare-metal ANE validation**. The config is done;
   the 0-CPU gate cannot be run in this VM.
3. To truly validate this plan, the `MLComputePlanAudit` / `MLComputePlanGate`
   and the Phase 6 benchmark must run on the **host macOS** (bare-metal
   M3 Pro), not inside Parallels.
4. Swift pipeline work (Phase 3/4/5) can proceed in the VM (build + unit
   tests), but fps gates defer to host.

## Files
- Probes: `.claude/plans/probe_animevideov3_256.py`, `probe_variants.py`,
  `probe_rrdb.py`, `probe_tensorio.py`, `probe_pureconv.py`
- Audit logs: `phase2-probe-256.txt`, `phase2-variants-audit.txt`,
  `phase2-rrdb-audit.txt`, `phase2-tensorio.txt`
- This file: `.claude/plans/phase2-findings.md`