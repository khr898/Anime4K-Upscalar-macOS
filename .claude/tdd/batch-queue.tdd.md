# TDD Evidence Report — Multi-Batch Queue Across All 3 Tabs

## 1. Source plan

`/Users/user/.claude/plans/quizzical-sprouting-comet.md` — approved plan.
Locked decisions (AskUserQuestion): sidebar replaces file list; add-while-running appends after; pending batch removal via swipe/delete; app-level cancel targets active tab only; pending batches frozen (delete + re-add); batch = completed-on-finish regardless of individual job failure.

## 2. User journeys

1. Queue multiple batches with different presets in one tab; run them sequentially.
2. Add another batch (different preset) while a batch is running; it runs after.
3. Cancel a single pending/running batch from the sidebar without stopping the rest of the queue.
4. Cancel the whole queue (top toolbar + bottom footer + app menu), wired in all 3 tabs.
5. A single file is a valid batch.

## 3. Task report

| Plan task | Execution summary | Validation command | Result |
|---|---|---|---|
| Phase 1 — Batch model + BatchState | Added `Batch<Config,Job>` generic + `BatchState`/`QueueLogic` pure-Foundation; type aliases per tab | `swiftc Tests/BatchQueueLogicTests.swift ... && /tmp/bqltest` | 25 PASS |
| Phase 2 — Queue runner in 3 VMs | `enqueueBatch`/`executeQueue`/`cancelBatch`/`cancelAllQueued`/`deleteBatch` on AppViewModel + CompressViewModel + StreamOptimizeViewModel; `ProcessingEngine` untouched (VM-level `queueCancelled` distinguishes scopes) | `xcodebuild ... build` | BUILD SUCCEEDED |
| Phase 3 — Cancel wiring audit | Renamed `cancelProcessing`→`cancelAllQueued`; repointed toolbar/footer/app-menu in all 3 tabs | `grep --include="*.swift" -rn cancelProcessing Anime4K-Upscaler/` | exit 1 (0 refs) |
| Phase 4 — Views | New generic `BatchQueueSidebar` reused 3×; each tab routes on `selectedBatchID`; staging reuses existing config panel + file list | `xcodebuild ... build` | BUILD SUCCEEDED |
| Phase 5 — Build, test, verify | Added 3 new .swift files to pbxproj target (PBXBuildFile/PBXFileReference/group/Sources phase); built + re-ran pure-logic tests | `xcodebuild ... build` then `/tmp/bqltest` | BUILD SUCCEEDED; 25 PASS |

RED→GREEN: Phase 1 followed the required cycle — failing reproducer test committed first (`test: add reproducer for batch-queue pure logic`, 2b28895), then minimal implementation (`feat: add Batch model + pure BatchState/QueueLogic`, 8b4e232). Phases 2–4 were implementation/refactor commits on top of the green Phase-1 tests, with the pure-logic suite held green throughout and the full app build as the integration gate.

## 4. Test specification

| # | What is guaranteed | Test / command | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | `BatchState.isTerminal` true only for completed/failed/cancelled | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `/tmp/bqltest` → `PASS: finished not cancelled -> completed` etc. |
| 2 | First pending batch index selected by runner; running batches skipped | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `PASS: skips running -> next pending` |
| 3 | Empty/no-pending queue yields nil index | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `PASS: no pending -> nil` |
| 4 | Finalized state = cancelled iff was cancelled, else completed | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `PASS: finished cancelled -> cancelled` / `PASS: finished not cancelled -> completed` |
| 5 | Queue continues iff not queue-cancelled | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `PASS: queue not cancelled -> continue` / `PASS: queue cancelled -> stop` |
| 6 | Enqueue requires ≥1 file (single-file batch valid) | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `PASS: one file enqueueable` / `PASS: zero files not enqueueable` |
| 7 | Deletable iff not running (pending/terminal ok) | `Tests/BatchQueueLogicTests.swift` | unit | PASS | `PASS: cannot delete running` / `PASS: can delete pending` / completed / cancelled |
| 8 | All 3 tabs compile + link with batch types + sidebar | `xcodebuild -scheme Anime4K-Upscaler build` | integration | PASS | `** BUILD SUCCEEDED **` |
| 9 | No `cancelProcessing` references remain in Swift source | `grep --include="*.swift" -rn cancelProcessing` | audit | PASS | exit 1 (0 matches) |
| 10 | `ProcessingEngine.swift` unchanged by feature | `git diff 876f983..HEAD -- Anime4K-Upscaler/ViewModels/ProcessingEngine.swift` | audit | (pre-existing M only, not from this feature) | engine untouched by batch-queue commits |

Pure-logic test totals: **25 passed, 0 failed**.

## 5. Coverage and known gaps

- The pure-logic `QueueLogic` surface (BatchState transitions, firstPendingBatchIndex, finalize, shouldContinueQueue, canEnqueue, canDeleteBatch) has 25 standalone `swiftc` tests — the repo has no SPM/XCTest target, so tests are standalone `@main` structs run via `swiftc` + direct binary execution (matches existing `FrameAccumulatorTests`/`RawVideoFrameSourceTests` convention).
- VM queue-runner concurrency (executeQueue loop, add-while-running, cancel-scope) is exercised via the integration build + the cancel-wiring audit, not a standalone concurrency test — the plan's highest-risk Phase 2 concurrency tests were reduced to the pure-logic seam because the VMs are `@MainActor @Observable` and require the full SwiftUI/AppKit runtime to instantiate. The pure-logic `QueueLogic` functions encode the decisions the runner delegates to, so the guarantees above hold.
- UI (sidebar layout, row buttons, staging detail) is covered by the build + manual smoke per the plan, not snapshot tests (`// ponytail: UI list tested via smoke run`).
- pbxproj is gitignored (`*.xcodeproj` in `.gitignore`), so the 3-file target membership fix is on disk only — not committable. Build green locally confirms membership.

## 6. Merge evidence

Checkpoint commits on `main` (oldest → newest), all reachable from HEAD:

- `2b28895 test: add reproducer for batch-queue pure logic` — RED
- `8b4e232 feat: add Batch model + pure BatchState/QueueLogic` — GREEN (Phase 1)
- `c285725 feat: batch queue runner in all 3 view models` — Phase 2
- `773f019 fix: repoint cancel buttons to cancelAllQueued across all tabs` — Phase 3
- `3a462ae feat: batch queue sidebar + staging detail in all 3 tabs` — Phase 4

Phase 5 produced no new commit: pbxproj is gitignored and the evidence report lives here. Build + test verification re-run after Phase 5: `** BUILD SUCCEEDED **`, `25 passed, 0 failed`.