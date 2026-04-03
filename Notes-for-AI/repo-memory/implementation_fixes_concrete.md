# MPS Parity Fixes — Concrete Code-Level Implementation Sequence

## Phase 1: Configuration-Only Fixes (NO CODE REWRITES)

### Fix 1.1: Offset Configuration Default Change
**File:** Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift  
**Lines:** 148–149

**Current:**
```swift
let offsetX = max(0, min(2, Int(env["A4K_MPS_OFFSET_X"] ?? "0") ?? 0))
let offsetY = max(0, min(2, Int(env["A4K_MPS_OFFSET_Y"] ?? "0") ?? 0))
```

**Change To:**
```swift
// Changed default from "0" to "1" to match Metal shader kernel center (-1,-1) offset
let offsetX = max(0, min(2, Int(env["A4K_MPS_OFFSET_X"] ?? "1") ?? 1))
let offsetY = max(0, min(2, Int(env["A4K_MPS_OFFSET_Y"] ?? "1") ?? 1))
```

**Rationale:** Metal kernels sample from (-1, -1) to (1, 1) centered. MPS offset (1, 1) aligns the window center.

**Risk:** NONE — defaults changed to optimal value; env var still allows override

**Test Checkpoint:** After this change, run benchmark and verify SSIM improves or passes

---

### Fix 1.2: Ensure Benchmark Script Propagates MPS Config to Trial Run
**File:** Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh  
**Lines:** 43–45

**Current:** Trial run does not explicitly export MPS config env vars

**Add To Script:**
```bash
# Explicit MPS configuration for trial run
export A4K_MPS_OFFSET_X="${A4K_MPS_OFFSET_X:-1}"
export A4K_MPS_OFFSET_Y="${A4K_MPS_OFFSET_Y:-1}"
export A4K_MPS_VALIDATE_EQUIVALENCE="${A4K_MPS_VALIDATE_EQUIVALENCE:-1}"
```

**Insert into trial run command:**
```bash
A4K_MPS_OFFSET_X="$A4K_MPS_OFFSET_X" A4K_MPS_OFFSET_Y="$A4K_MPS_OFFSET_Y" \
  "$BIN_OUT" "$VIDEO" "$MAX_FRAMES" | tee "$OPT_LOG"
```

**Rationale:** Currently MPS config vars are only inherited if set in parent shell.

**Risk:** NONE — explicit exports make behavior visible and testable

---

## Phase 2: Validation Enhancement (Light Code Changes)

### Fix 2.1: Tighten Validation Thresholds for Production Video
**File:** Anime4K-Upscaler/ViewModels/Anime4KMPSConvolution.swift  
**Lines:** 121–123

**Current:**
```swift
let maxAbs = Float(env["A4K_MPS_EQ_MAX_ABS"] ?? "0.003") ?? 0.003
let meanAbs = Float(env["A4K_MPS_EQ_MEAN_ABS"] ?? "0.0005") ?? 0.0005
```

**Change To:**
```swift
// Stricter defaults for production: 0.003 is too loose for 5+ pass chains
let argMaxAbs = env["A4K_MPS_EQ_MAX_ABS"] ?? "0.001"  // Tightened
let argMeanAbs = env["A4K_MPS_EQ_MEAN_ABS"] ?? "0.0001" // Tightened
let maxAbs = Float(argMaxAbs) ?? 0.001
let meanAbs = Float(argMeanAbs) ?? 0.0001
```

**Rationale:** Tighter bounds catch precision/layout errors that loose thresholds hide.

**Risk:** MEDIUM — may cause valid plans to be rejected if thresholds too tight.

---

### Fix 2.2: Add Diagnostic Logging for Index Verification
**File:** Anime4K-Upscaler/ViewModels/Anime4KRuntimePipeline.swift  
**Lines:** 337–350

**Add Diagnostic Before MPS Plan Lookup:**
```swift
if let mpsPlan = mpsPassPlans[sourcePassIndex],
   shader.inputTextureNames.count == 1 {
    // DIAGNOSTIC: Log plan existence
    if ProcessInfo.processInfo.environment["A4K_VERBOSE_MPS_LOOKUP"] == "1" {
        NSLog("[Anime4KRuntime] MPS plan passIndex=%d matched", sourcePassIndex)
    }
    // ... use mpsPlan
}
```

**Rationale:** Diagnostic logging reveals index mismatches during benchmark runs.

**Risk:** NONE — logging only

---

## Checkpoint Acceptance Criteria

| Checkpoint | Test | Pass Criteria |
|---|---|---|
| **CP1 (Fix 1.1)** | Offset change + benchmark | SSIM >= 0.999 OR improves by >= 0.01 |
| **CP2 (Fix 1.2)** | Env propagation + benchmark | SSIM matches CP1 result consistently |
| **CP3 (Fix 2.1)** | Tightened thresholds | At least one config passes SSIM >= 0.999 |
| **CP4 (Full Config Sweep)** | 32-config matrix test | >= 50% configs pass (8+ PASS entries) |
| **CP5 (Production Gate)** | Real video tests | All produce SSIM >= 0.999 with best config |

---

## Validation Commands

### Quick Test
```bash
A4K_MPS_OFFSET_X=1 A4K_MPS_OFFSET_Y=1 \
  bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 120
tail -1 /tmp/a4k_phase4_metrics.csv | awk -F',' '{print "SSIM="$16}'
```

### Config Sweep
```bash
for offset in "0 0" "1 1" "1 0" "0 1"; do
  X="${offset%% *}"; Y="${offset##* }"
  echo "Testing offset=($X,$Y)"
  A4K_MPS_OFFSET_X=$X A4K_MPS_OFFSET_Y=$Y \
    bash Anime4K-Upscaler/Tools/run_phase4_aahq_benchmark.zsh test.mp4 30 2>&1 | grep "Quality gate"
done
```

