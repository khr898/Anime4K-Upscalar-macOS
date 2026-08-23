# Phase 9 — Temporal Redundancy Skip (FrameRedundancyCache) TDD Evidence

**Source plan:** `.claude/plans/special-pipeline-fps-fix.plan.md` (Phase 9 / N1)
**Impl:** `Anime4K-Upscaler/Utilities/FrameRedundancyCache.swift` (pure Foundation, no AVFoundation/CoreML/CoreVideo dep — unit-testable standalone)
**Test:** `Tests/FrameRedundancyTests.swift` (standalone `@main`, 18 cases, AAA pattern)

## User journey
As a user upscaling limited-animation anime (24fps container, ≤12fps unique art), I want duplicate/near-duplicate frames to reuse the previous upscaled output (skip ANE infer + blit), so throughput rises without visible quality loss on the reused frames.

## Validation commands actually run
RED (impl missing):
```
ls Anime4K-Upscaler/Utilities/FrameRedundancyCache.swift   # No such file
swiftc FrameRedundancyCache.swift Tests/FrameRedundancyTests.swift
  # error opening input file 'FrameRedundancyCache.swift' (No such file)  ← compile-time RED
```
GREEN:
```
swiftc Anime4K-Upscaler/Utilities/FrameRedundancyCache.swift Tests/FrameRedundancyTests.swift -o /tmp/reduntest && /tmp/reduntest
```
Result: `18 passed, 0 failed`, exit 0.

## Test specification
| # | Guarantee | Case | Result |
|---|-----------|------|--------|
| 1 | First frame fresh (no prev) | case1 | PASS |
| 2 | Identical frame reuse | case2 | PASS |
| 3 | Near-identical (delta 3) reuse | case3 | PASS |
| 4 | Scene change (delta 100) fresh | case4 | PASS |
| 5 | record() updates prev → dup of new scene reuses | case5 | PASS |
| 6 | reset() forces next fresh | case6 | PASS |
| 7 | empty data / zero dims fresh | case7 (×3) | PASS |
| 8 | dimension mismatch fresh (no cross-size compare) | case8 | PASS |
| 9 | slow-pan guard: 1 cell jumps 100, mean 0.69 → fresh via max-cell cap | case9 | PASS |
| 10 | threshold boundary delta 4 → fresh (strict `<`) | case10 | PASS |
| 11 | unrecorded fresh does NOT update prev | case11 | PASS |
| 12 | 1080p deterministic, identical reuse + heavily-modified fresh | case12 (×2) | PASS |
| 13 | custom threshold (50/200) reuses delta 30 | case13 | PASS |

## What the passing tests guarantee
- Safe defaults: never falsely reuse on empty/zero-dim/dim-mismatch/no-prev (no visible stutter from a wrong reuse).
- Dup detection: 16×9 luma grid (BGRA G channel), mean cell diff `< dupThreshold` AND max cell diff `< sceneChangeMaxCellDiff`.
- Slow-pan guard: per-cell max cap catches a single large moving region the mean would miss.
- `shouldReuse` is non-mutating — caller owns when to `record` (a queried-but-unrecorded fresh frame leaves prev intact).
- Defaults: `dupThreshold = 4.0`, `sceneChangeMaxCellDiff = 20.0`. Custom via `init(dupThreshold:sceneChangeMaxCellDiff:)`.

## Known gaps / follow-ups
- CVPixelBuffer/PTS gluing into `ProcessingEngine.nextUpscaledFrame` is NOT done here (pure-logic cache only). Wiring lands in Phase 4 ring rewrite.
- No coverage measurement (no XCTest/Swift Testing harness; assert-based standalone per repo convention — see `FrameAccumulatorTests`).
- Test helper bug fixed during GREEN: `UInt8(((i*7)&0xFF) &+ 80)` trapped (Int 280 → UInt8 init traps); fixed to `UInt8(((i*7) &+ 80) & 0xFF)` (wrap after add).

## Merge evidence (RED/GREEN summary for squash)
- RED: `swiftc … FrameRedundancyCache.swift Tests/…` → compile error (missing file). Intended.
- GREEN: same command after writing impl → `18 passed, 0 failed`, exit 0.
- No refactor stage (impl was minimal from design; ponytail: one struct, no abstraction).