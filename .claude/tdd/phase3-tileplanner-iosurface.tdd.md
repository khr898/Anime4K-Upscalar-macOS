# TDD Evidence: Phase 3 — TilePlanner extraction + IOSurface backing

**Source plan:** `.claude/plans/special-pipeline-fps-fix.plan.md` → Phase 3 (CoreMLUpscaler full-frame + ring + IOSurface + Metal)
**Date:** 2026-08-05
**Commits:** `bdca1b4` (RED+GREEN TilePlanner), `fb0eacd` (refactor CoreMLUpscaler + IOSurface)

## Scope split (VM vs host)

Phase 3 spans four pieces. This run delivered the two verifiable in a Parallels macOS VM (no ANE passthrough, no Metal visual verify); the other two defer to bare metal per the Phase 2 note ("Phase 3/4/5 Swift pipeline work can proceed in VM; ANE-placement + fps gates defer to host").

| Piece | Status | Where verified |
|---|---|---|
| Tile-plan seam math extracted → `TilePlanner` (unit-tested) | **done** | VM — swiftc standalone test |
| IOSurface-backed output `CVPixelBuffer` | **done** | VM — xcodebuild compile |
| `MetalSRConvert.swift` float16→BGRA compute shader (replaces `CIContext.render`) | **deferred** | host — needs Metal device + visual output verify |
| Full-frame TensorType single dispatch (Phase 2 models promoted) | **deferred** | host — needs Phase 2 `.mlpackage` reconvert promoted into `Resources/Models` + ANE placement audit |

## User journeys (from plan)

- As a developer, I want the tile-plan edge-clamp + overlap-halo math unit-tested, so that refactoring `CoreMLUpscaler.upscale` cannot silently break seam handling.
- As a pipeline engineer, I want output `CVPixelBuffer`s IOSurface-backed, so that the Phase 4 ring and the Metal convert path can hand off zero-copy to the GPU.

## Task report

### Task 1 — `TilePlanner` extraction (RED → GREEN)

- **Summary:** Wrote `Tests/TilePlannerTests.swift` (standalone `@main` + assert + `exit(1)`, pure Foundation, mirrors `FrameAccumulatorTests`) BEFORE the type existed → compile-time RED (`Cannot find 'TilePlanner' in scope`). Implemented `Anime4K-Upscaler/Utilities/TilePlanner.swift` with `plans(frameW:frameH:tileW:tileH:overlap:)` mirroring the exact edge-clamp + halo math from `CoreMLUpscaler.upscale`, deduped by `(topX,topY)` (clamped edge duplicates cropped/inferred/blitted identical regions idempotently → same output, less wasted dispatch). 28/28 pass.
- **Validation command:** `swiftc Anime4K-Upscaler/Utilities/TilePlanner.swift Tests/TilePlannerTests.swift -o /tmp/tileplan && /tmp/tileplan`
- **RED evidence:** `swiftc` → `Tests/TilePlannerTests.swift:42:25: error: cannot find 'TilePlanner' in scope` (and 7 more). SourceKit diagnostics confirmed compile-time RED on the real symbol.
- **GREEN evidence:** `28 passed, 0 failed` (exit 0).

### Task 2 — Refactor `CoreMLUpscaler.upscale` to consume `TilePlanner.plans()`

- **Summary:** Replaced the inline `TilePlan` struct + nested `while` loop with `let plans = TilePlanner.plans(...)`. Crop/blit loops unchanged (field names match). Behavior-preserving; the dedup is observationally identical (idempotent overwrites removed).
- **Validation command:** `xcodebuild build -project Anime4K-Upscaler.xcodeproj -scheme Anime4K-Upscaler -configuration Debug -destination 'platform=macOS'`
- **GREEN evidence:** `SwiftCompile … TilePlanner.swift` then `** BUILD SUCCEEDED **`.

### Task 3 — IOSurface backing on `makePixelBuffer`

- **Summary:** Added `kCVPixelBufferIOSurfacePropertiesKey: [:]` to the `CVPixelBufferCreate` attrs in `CoreMLUpscaler.makePixelBuffer` (alongside the existing Metal-compat key). IOSurface backing is required for `CVPixelBuffer`↔`MTLTexture` zero-copy sharing; without it the future Metal convert path falls back to a host-memory copy. No behavior change to the current `CIImage.render` path.
- **Validation command:** same xcodebuild as Task 2.
- **GREEN evidence:** `** BUILD SUCCEEDED **` (no type/SDK errors on the new key).

### Task 4 — Regression: existing standalone tests

- **Summary:** `Tests/FrameAccumulatorTests.swift` re-run to confirm the `CoreMLUpscaler` refactor + new utility didn't perturb sibling code.
- **Validation command:** `swiftc Anime4K-Upscaler/Utilities/FrameAccumulator.swift Tests/FrameAccumulatorTests.swift -o /tmp/fatest && /tmp/fatest`
- **GREEN evidence:** `37 passed, 0 failed`.

## Test specification

| # | What is guaranteed | Test file or command | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | frame == tile → exactly 1 plan covering the whole frame (valid region == frame) | `Tests/TilePlannerTests.swift` case 1 | unit | PASS | `swiftc … -o /tmp/tileplan && /tmp/tileplan` → 28 passed |
| 2 | frame < tile → 1 plan clamped to frame size, no negative crop/valid dims | `Tests/TilePlannerTests.swift` case 2 | unit | PASS | as above |
| 3 | 16×16 frame, 10×10 tile, overlap 2 → 4 unique plans (deduped), every valid region 8×8, unique origins {(0,0),(6,0),(0,6),(6,6)} | `Tests/TilePlannerTests.swift` case 3 | unit | PASS | as above |
| 4 | Union of valid destinations covers the frame exactly (no gap): {(0,0),(8,0),(0,8),(8,8)} 8×8 blocks tile 16×16 | `Tests/TilePlannerTests.swift` case 4 | unit | PASS | as above |
| 5 | overlap 0 → exact non-overlapping grid, valid == tile, origins at tile strides | `Tests/TilePlannerTests.swift` case 5 | unit | PASS | as above |
| 6 | non-square frame/tile → no negative valid regions, every valid dest stays in-frame | `Tests/TilePlannerTests.swift` case 6 | unit | PASS | as above |
| 7 | degenerate dims (zero/negative frame or tile, overlap ≥ tile) → empty list or all-non-negative, no crash/infinite loop | `Tests/TilePlannerTests.swift` case 7 | unit | PASS | as above |
| 8 | `CoreMLUpscaler.upscale` compiles against `TilePlanner` + IOSurface key; whole target builds | `xcodebuild … build` | compile/integration | PASS | `** BUILD SUCCEEDED **` |
| 9 | `FrameAccumulator` behavior unchanged (sibling utility regression) | `Tests/FrameAccumulatorTests.swift` | unit | PASS | `37 passed, 0 failed` |

## Coverage and known gaps

- **Covered (VM):** `TilePlanner.plans` pure logic (7 case groups, 28 assertions); `CoreMLUpscaler` compile + `makePixelBuffer` IOSurface key; sibling regression.
- **Not covered (deferred to host, not skipped):**
  - `MetalSRConvert.swift` compute-shader output correctness — needs a Metal device + visual diff against the current `CIContext.render` output. Writing the shader blind in VM ships a subtle-color-bug risk; deferred until it can be visually verified on bare metal.
  - Full-frame TensorType single dispatch — blocked on Phase 2's reconverted `.mlpackage` models being promoted into `Resources/Models` and an `MLComputePlanAudit` showing 0-CPU-fallback on a real ANE. Both unverifiable in VM.
  - Per-frame output-buffer pre-allocation (plan step 5) — folds into the Phase 4 ring (pre-allocated `FrameSession` buffers); not implemented in this slice to avoid a speculative pool with no consumer yet (YAGNI).
- **Coverage command note:** this repo has no SPM `Package.swift` / `swift test` — the plan's `swift build` / `swift test --filter CoreML` validation commands are not applicable. The repo's actual validation harness is standalone `swiftc`-compiled `@main` tests + `xcodebuild`. That mapping is used here.

## Merge evidence

Three commits on `main`, in order, all reachable from `HEAD`:
1. `bdca1b4` — `test: add TilePlanner reproducer (Phase 3 seam-math extraction)` — RED (compile-time, `TilePlanner` missing) then GREEN (28/28) in one commit.
2. `fb0eacd` — `refactor: CoreMLUpscaler uses TilePlanner + IOSurface-backed output (Phase 3)` — refactor + IOSurface, xcodebuild BUILD SUCCEEDED.
3. (`cffaf4a` — earlier color-patch fix, unrelated to this TDD cycle, listed for timeline clarity.)

If these are squashed, copy the RED/GREEN summary above into the squash body.