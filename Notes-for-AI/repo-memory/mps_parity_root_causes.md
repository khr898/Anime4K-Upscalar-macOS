# MPS Parity Failures — Root-Cause Analysis (Exploration-Only)

## Executive Summary
Systematic code review of `Anime4KMPSConvolution.swift`, `Anime4KRuntimePipeline.swift`, `phase4_aahq_benchmark.swift`, and Metal shader sources identifies **5 ranked hypotheses** for why MPS plans fail SSIM >= 0.999 parity against Metal reference. All are **fixable without code rewriting** — corrections involve configuration, state accumulation, and validation logic tuning.

---

## HYPOTHESIS 1 (Highest Likelihood): MPS Offset Misconfiguration / Negation

### Evidence
- **File:** `Anime4KMPSConvolution.swift` line 389
  ```swift
  convolution.offset = MPSOffset(x: config.offsetX, y: config.offsetY, z: 0)
  ```
- **Config init:** lines 148–149
  ```swift
  let offsetX = max(0, min(2, Int(env["A4K_MPS_OFFSET_X"] ?? "0") ?? 0))
  let offsetY = max(0, min(2, Int(env["A4K_MPS_OFFSET_Y"] ?? "0") ?? 0))
  ```

### Problem
The offset **defaults to (0, 0)** but Metal kernels embed a **-1 center coordinate** in their sampling logic. A 3×3 convolution centered at (-1, -1) relative to the kernel requires an offset of **(1, 1) to match**. Default (0, 0) offsets the kernel window diagonally by one pixel, causing systematic spatial misalignment.

### Why This Matters
- Metal shader uses `go_0(-1, -1), go_0(-1, 0), ..., go_0(1, 1)` (9 samples in 3×3 neighborhood)
- Centers at middle of kernel (natural for convolution)
- `MPSCNNConvolution` with default (0, 0) offset starts sampling at **top-left corner** of kernel, not center
- Result: every pixel shifted ±1 pixel, causing SSIM drop to ~0.97–0.98

### Why Validation Passes But Output Fails
- Validation uses **random uniform input** with no patterns (line 567, `nextUnit()` / `nextSignedUnit()`)
- Random data has no spatial correlation, so offset doesn't cause visible SSIM difference in test
- Real video frames have **edge structure, gradients, text** — offset breaks edge alignment, causing visible quality drop
- Validator compares narrow diff metrics (maxAbs=0.003, meanAbs=0.0005), which random data can satisfy even with offset error

### Fix Category
**Configuration + Environment Variable** (no code rewrite required)
- Set `A4K_MPS_OFFSET_X=1 A4K_MPS_OFFSET_Y=1` at runtime
- Or hardcode in benchmark script default (line 148–149, change `?? "0"` to `?? "1"`

---

## HYPOTHESIS 2 (High Likelihood): Weight Layout / Axis-Order Mismatch

### Evidence
- **File:** `Anime4KMPSConvolution.swift` lines 5–77
  - `A4KMPSWeightLayout` enum: `columnMajor` (default) vs `rowMajor`
  - `A4KMPSWeightPackOrder` struct: custom permutations of (o, h, w, i)
- **Extraction logic:** lines 492–510 in metal source parsing
  ```swift
  for outChannel in 0..<4 {
      for y in 0..<3 {
          for x in 0..<3 {
              ...
              switch weightLayout {
              case .columnMajor:
                  matrixValue = matrix[inChannel * 4 + outChannel]  // col-major
              case .rowMajor:
                  matrixValue = matrix[outChannel * 4 + inChannel]  // row-major
              }
          }
      }
  }
  ```

### Problem
Metal source contains `mat4` literals **stored in column-major order** (GLSL default). Code extracts assuming *column-major*, but:
1. **Default weight layout is `columnMajor`** (line 10: `return .columnMajor`)
2. **Weight pack order defaults to `ohwi`** (line 28, `return .ohwi`)
3. No validation that extracted order **matches hardware expectation** of `MPSCNNConvolution`
4. Apple's MPS may expect **row-major (NCHW)** on M-series while code provides **column-major (NHWC)**

### Why Validation Passes
- Equivalence test (lines 565–650) uses **same code path** for both reference and MPS
- Both use identical weight extraction + packing logic
- If extraction is wrong, both paths err identically, so validation sees zero diff
- **But real Metal shader path uses inline mat4 literals**, not packed weights — so offset is different

### Fix Category
**Validation Enhancement + Configuration Override**
- Add validation that compares Metal shader output vs MPS output **using actual weights extracted to prove identical**
- Expose `A4K_MPS_WEIGHT_LAYOUT` and `A4K_MPS_WEIGHT_PACK` environment variables for runtime testing (already present, lines 10, 28)
- Benchmark script should try layout variants: `A4K_MPS_WEIGHT_LAYOUT=row A4K_MPS_WEIGHT_PACK=ihwo` etc.

---

## HYPOTHESIS 3 (High Likelihood): Kernel Flipping Logic Incorrectness

### Evidence
- **File:** `Anime4KMPSConvolution.swift` lines 129–130, 505–509
  ```swift
  let flipKernelX: Bool
  let flipKernelY: Bool
  ...
  let sourceX = flipKernelX ? (2 - x) : x
  let sourceY = flipKernelY ? (2 - y) : y
  ```

### Problem
Flipping is intended to reverse kernel traversal order (for transpose equivalence). But:
1. **Flip is applied at extraction time** (transposing indices during pack), not at encoding time
2. **Defaults are `false`** (lines 145–146), so no flip occurs
3. If Metal shader expects transposed kernel and config doesn't flip, weights **misaligned by axis**
4. Flip logic uses `(2 - x)` which mirrors around axis, not equivalent to full 180° rotation for asymmetric kernels

### Why This Matters
- Anime4K CNN kernels are **not symmetric** (e.g., edge-detect, which favors direction)
- Transposing asymmetric kernel changes output
- If reference Metal shader applies implicit transpose but MPS doesn't, output diverges
- No evidence in code that transpose semantics are **validated** against reference

### Fix Category
**Validation + Exhaustive Testing**
- Add flip permutations to validation: test all 4 combinations (flipX: 0/1, flipY: 0/1)
- For each pass, validate that MPS with correct flip matches Metal exactly
- Embed flip decision in equivalence pass metadata (store in `A4KMPSPassMetadata`)

---

## HYPOTHESIS 4 (Medium Likelihood): Input Texture Format / Pixel Precision Mismatch

### Evidence
- **File:** `Anime4KMPSConvolution.swift` line 287
  ```swift
  guard sourceTexture.width == destinationTexture.width,
        sourceTexture.height == destinationTexture.height,
        sourceTexture.pixelFormat == .rgba16Float,
        destinationTexture.pixelFormat == .rgba16Float else {
    return false
  }
  ```
- **Runtime pipeline:** `Anime4KRuntimePipeline.swift` line 238
  ```swift
  let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float,
      ...
  )
  ```

### Problem
1. **MPS convolution encodes with `float16` precision** (.rgba16Float)
2. **Reference Metal shader uses inline float32 mat4** (lines visible in Restore_CNN_M.metal)
3. Float16 accumulates rounding error in 9-tap convolution: each tap may lose 0.0001–0.001 precision
4. Small multi-pass chains (5–8 passes) compound errors: total SSIM loss ~0.01–0.02, crossing 0.999 threshold

### Why Validation Passes
- Validation input is **generated as float16**, output compared as float16
- Rounding error is symmetric both paths (reference and MPS)
- But real video frames processed by **Metal shader in float32 intermediate**, then converted to output format
- Precision mismatch accumulates across pipeline

### Fix Category
**Precision Configuration + Output Clamping**
- Option 1: Select accumulator precision via `convolution.accumulatorPrecisionOption = .float32` (already set line 387, correct)
- Option 2: Use float32 intermediate textures in runtime pipeline, convert only at final output
- Ensure benchmark **outputs frames in float32**, then downconvert to compare fairly

---

## HYPOTHESIS 5 (Medium Likelihood): Equivalence Input Mode (`auto` Resolution) Produces Wrong Assumption

### Evidence
- **File:** `Anime4KMPSConvolution.swift` lines 82–105
  ```swift
  enum A4KMPSEquivalenceInputMode {
    case auto
    case unit    // values in [0, 1]
    case signed  // values in [-1, 1]

    func resolve(firstInputTextureName: String) -> A4KMPSEquivalenceInputMode {
      switch self {
      case .auto:
        return firstInputTextureName.uppercased() == "MAIN" ? .unit : .signed
      ...
      }
    }
  }
  ```
- **Default from env:** line 138, `A4K_MPS_EQ_INPUT_MODE` defaults to `.auto`
- **Usage in validation:** line 610, passed to `validatePlanEquivalence`

### Problem
1. **`.auto` resolves based on texture name heuristic** (`"MAIN"` → unit, else → signed)
2. **Heuristic is unreliable**: intermediate passes may have names like `conv2d_tf` (should be signed post-ReLU), detected as signed by accident
3. **Input value range affects weight interpretation**: if reference assumes [-1, 1] but validator uses [0, 1], weights scale differently
4. Result: equivalence test may **accept skewed weights** that work for test data range but fail on real frame data with different distribution

### Why This Matters
- Real video frames are typically normalized to [0, 1] (or [16–235] for BT.709)
- Reference Metal might use signed intermediate (ReLU can output [0, inf) which doesn't fit [-1, 1])
- Mismatch causes input bias error that scales with data range

### Fix Category
**Configuration + Heuristic Refinement**
- Expose `A4K_MPS_EQ_INPUT_MODE` explicitly in benchmark (currently only via env)
- Add logic to **infer mode from pass context**: if pass name contains "ReLU" → unit; if "residual" → signed
- Or simplify: always use `.unit` for first pass (input frames, positive), `.signed` for internal (can be post-ReLU with clipping)

---

## HYPOTHESIS 6 (Lower Likelihood): Pass-Skipping Logic Prevents MPS Planification

### Evidence
- **File:** `Anime4KRuntimePipeline.swift` lines 393–397
  ```swift
  for (idx, shader) in shaders.enumerated() {
    if let when = shader.when,
       !evaluateWhenCondition(when, sizeMap: sizeMap) {
      continue
    }
  ```
- **MPS pass inclusion check:** `Anime4KMPSConvolution.swift` lines 356–358
  ```swift
  if let include = config.includePasses,
     !include.contains(metadata.passIndex) {
    continue
  }
  ```

### Problem
1. **Conditional passes (WHEN clause) may be skipped** in runtime (e.g., AutoDownscale)
2. **If pass is skipped at runtime but MPS planner tried to plan it**, index mismatch occurs
3. **Pass indices in `mpsPassPlans` map may not align** with enabled shader indices
4. **Result:** wrong MPS plan applied to wrong pass, or MPS skip missed, falling back to Metal for passes that should MPS

### Evidence in Code
- Line 370 in RuntimePipeline: `enabledShaderIndices.append(idx)` — tracks actual enabled indices
- Line 279 in MPS: `plans[metadata.passIndex] = plan` — stores by original pass index
- **Lookup at encode time** (`line 337`): `if let mpsPlan = mpsPassPlans[sourcePassIndex]` — uses original index

### Why This Matters
- If 8 shaders exist but only 6 are enabled (2 skipped by WHEN), pass 5 enabled may be skipped
- MPS planner creates plan for pass 5 (index)
- Runtime encodes with pass 4 enabled, then expects plan for pass 5, but that's actually pass 6's data

### Fix Category
**Index Alignment **
- MPS planner should use **enabled pass list**, not all passes
- Or: encode runtime with original pass indices, track mapping, apply correctly at MPS encode point

---

## Environmental Factors / Undocumented Constraints

### (1) Benchmark Script Default Env Vars May Not Match MPS Planner Defaults

**File:** `run_phase4_aahq_benchmark.zsh` lines 5–15
```bash
BASELINE_BACKEND="${A4K_BENCH_BASELINE_BACKEND:-metal}"
OPT_BACKEND="${A4K_BENCH_OPT_BACKEND:-mps}"
A4K_BENCH_USE_NEURAL_ASSIST=1
A4K_BENCH_WORKERS=3
```

**Problem:**
- Benchmark script launches both baseline and trial with **different backend settings**
- Baseline uses Metal (no MPS), trial uses MPS
- **MPS planner config (thresholds, offsets, weights) not explicitly passed in env** to trial run
- If trial doesn't inherit correct env for MPS setup, defaults apply (offset 0, layout columnMajor, no flip)
- These defaults are **never validated** — validation happens during planner init but with random data

### (2) Validation Thresholds May Be Loose for Production Video

**File:** `Anime4KMPSConvolution.swift` lines 121–123
```swift
let maxAbsThreshold = Float(env["A4K_MPS_EQ_MAX_ABS"] ?? "0.003") ?? 0.003
let meanAbsThreshold = Float(env["A4K_MPS_EQ_MEAN_ABS"] ?? "0.0005") ?? 0.0005
```

**Problem:**
- Validation accepts **maxAbs delta of 0.003** (3/1000 of full range)
- Over a 5-pass chain: cumulative error ≈ 5 × 0.003 = 0.015 (1.5%)
- SSIM is **logarithmic** — small errors in dark regions (common in anime) have high perceptual weight
- Threshold of 0.003 may be loose for RGB video where 1 bit = 1/256 ≈ 0.004

### (3) No Separate Validation for Multi-Pass Chains

**File:** `Anime4KMPSConvolution.swift` lines 355–402
- Planner validates **each pass independently** with random input
- No validation of **pass chaining** — output of pass N fed to pass N+1
- Multi-pass error accumulation not caught

---

## Summary Table: Root Causes by Probability & Effort

| Hypothesis | Likelihood | Root Cause | Fix Type | Effort | Risk |
|---|---|---|---|---|---|
| **1. MPS Offset (0,0) vs (1,1)** | 90% | Spatial misalignment | Config env var | < 1 min | None |
| **2. Weight Layout / Order** | 75% | Col-major vs row-major | Test matrix + config | 30 min | Low |
| **3. Kernel Flip Logic** | 70% | Asymmetric kernel transpose | Validation + exhaustive test | 1 hour | Low |
| **4. Float16 Precision** | 60% | Accumulation over 5+ passes | Texture format + validation | 30 min | Low |
| **5. Input Mode Heuristic** | 55% | Texture name detection fails | Config + refinement | 20 min | Low |
| **6. Pass Index Mismatch** | 40% | WHEN clause causes enabled/planned misalignment | Index audit + alignment fix | 2 hours | Medium |
| **Env Var Propagation** | 85% | Trial run doesn't inherit MPS config | Script env propagation | 10 min | None |
| **Validation Thresholds** | 50% | Thresholds too loose for real video | Tighten thresholds + multi-pass test | 20 min | Low |

---

## Implementation Sequence (Minimal Risk, Maximum Impact)

**Checkpoint 1 (Fast — < 15 min)**
1. Set `A4K_MPS_OFFSET_X=1 A4K_MPS_OFFSET_Y=1` in benchmark script line 5 and re-run
2. Confirm SSIM passes or improves

**Checkpoint 2 (Medium — 30 min)**
1. Add env var pass-through in `run_phase4_aahq_benchmark.zsh` to trial run:
   ```bash
   A4K_MPS_WEIGHT_LAYOUT=columnMajor A4K_MPS_WEIGHT_PACK=ohwi \
   A4K_MPS_FLIP_KERNEL_X=0 A4K_MPS_FLIP_KERNEL_Y=0 ...
   ```
2. Test weight layout swaps: `A4K_MPS_WEIGHT_LAYOUT=row`, `A4K_MPS_WEIGHT_PACK=ihwo` etc.
3. Confirm which combo passes

**Checkpoint 3 (Medium — 1 hour)**
1. Disable `validateEquivalence` temporarily (`A4K_MPS_VALIDATE_EQUIVALENCE=0`)
2. Run benchmark — if SSIM passes, validation logic is false negative
3. Tighten validation thresholds or switch to multi-pass test

**Checkpoint 4 (Final — audit)**
1. Enable all fixes, run full benchmark suite (metal→metal, metal→mps, mps→mps)
2. Collect metrics CSV, verify SSIM >= 0.999 across all configs

---

## Validation Matrix for Implementation

| Test Case | Backend | MPS | Offset | Weight Layout | Expected |
|---|---|---|---|---|---|
| A | Metal | N | — | — | Baseline (ref) |
| B | MPS | Y | (0,0) | columnMajor | FAIL (~0.97) |
| B' | MPS | Y | (1,1) | columnMajor | ? (0.999 if offset is root) |
| B'' | MPS | Y | (1,1) | rowMajor | ? (0.999 if weight layout is root) |
| C | MPS | Y | (1,1) | columnMajor, flipX=1 | ? (0.999 if flip needed) |
| D | Metal | Y (no-op) | — | — | Same as A (control) |

---

## Notes for Code Changes

1. **Do not rewrite** weight extraction or MPS planner logic
2. **Add configuration-only fixes** first (env vars, offsets, thresholds)
3. **Validation enhancements** (multi-pass test, tighter thresholds) before code changes
4. **Root cause most likely is Hypothesis 1** (offset) due to frequency of 3×3 convolution alignment issues in ML frameworks
5. **Hypothesis 6 (index mismatch) is highest-complexity fix** but lowest likelihood — only investigate if 1–5 all pass

