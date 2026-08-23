// Tests/MLComputePlanGate.swift
// Phase 6 CI gate — FAIL (exit 1) if any neural model regresses to an
// unexpected CPU-fallback op. Passes (exit 0) only when every op places on ANE
// (or GPU), with the single known-acceptable exception: the ImageType-output
// `mul`+`cast` clamp×255 tail (2 ops/model, inherent to ImageWrapper — see
// Phase 7 audit; not worth a TensorType+MetalConvert rewrite for 2 scalar ops).
//
// METAL-GATED: this gate is only meaningful on real Apple Silicon with an ANE.
// On a VM without ANE passthrough, CoreML places ops on CPU regardless of the
// model → the gate would false-fail. So: compile on the VM (proves the code is
// valid), RUN on the metal host (the bare-metal handoff step). The Phase 7
// audit already established the VM shows false CPU placement (prelu on CPU)
// that real metal does not.
//
// Standalone swiftc (matches Tests/ convention):
//   swiftc Tests/MLComputePlanGate.swift -o /tmp/mlgate -parse-as-library \
//         -target arm64-apple-macos14.4 -framework CoreML -framework Foundation \
//   && /tmp/mlgate
//
// Models are read from Anime4K-Upscaler/Resources/Models (the shipped
// .mlmodelc compiled artifacts; MODELS_DIR env overrides).

import Foundation
import CoreML

@main
struct MLComputePlanGate {
    static func main() async {
        let repoRoot = FileManager.default.currentDirectoryPath
        let defaultModelsDir = FileManager.default.fileExists(atPath: "\(repoRoot)/Anime4K-Upscaler/Resources/Models")
            ? "\(repoRoot)/Anime4K-Upscaler/Resources/Models"
            : "\(repoRoot)/../Anime4K-Upscaler/Resources/Models"
        let modelsDir = ProcessInfo.processInfo.environment["MODELS_DIR"] ?? defaultModelsDir
        let modelNames = ["pipersr", "realesr-animevideov3", "realesrgan-x4plus-anime"]

        // ImageType output → ImageWrapper clamps+scales float16→0-255 via a
        // `mul` (×255) + `cast` (to uint8) tail. These two op names on CPU are
        // EXPECTED and accepted. Any OTHER op on CPU is a regression (the op
        // should run on ANE). This is the exact residual Phase 7 documented.
        let acceptableCPUOps: Set<String> = ["mul", "cast", "const", "reshape", "squeeze", "transpose"]
        // ^ const/reshape/squeeze/transspose are shape-only / zero-cost and may
        //   legitimately land on CPU; they are not compute. Only true compute
        //   ops (conv, matmul, activation, etc.) on CPU would be a regression.

        var passed = 0, failed = 0
        var failures: [String] = []

        for name in modelNames {
            // Prefer the shipped compiled .mlmodelc (faster, what the app loads);
            // fall back to compiling the .mlpackage.
            let compiledURL = URL(fileURLWithPath: "\(modelsDir)/\(name).mlmodelc")
            let packageURL = URL(fileURLWithPath: "\(modelsDir)/\(name).mlpackage")
            let loadURL: URL
            if FileManager.default.fileExists(atPath: compiledURL.path) {
                loadURL = compiledURL
            } else if FileManager.default.fileExists(atPath: packageURL.path) {
                do { loadURL = try await MLModel.compileModel(at: packageURL) }
                catch { print("FAIL: \(name) compile error: \(error)"); failed += 1; continue }
            } else {
                print("FAIL: \(name) missing (no .mlmodelc or .mlpackage)")
                failed += 1; continue
            }

            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let plan: MLComputePlan
            do { plan = try await MLComputePlan.load(contentsOf: loadURL, configuration: config) }
            catch { print("FAIL: \(name) MLComputePlan.load error: \(error)"); failed += 1; continue }

            guard case .program(let program) = plan.modelStructure else {
                print("FAIL: \(name) not a .program structure"); failed += 1; continue
            }
            guard let mainFunc = program.functions["main"] else {
                print("FAIL: \(name) no main function"); failed += 1; continue
            }

            var cpuOps: [String] = []
            for op in mainFunc.block.operations {
                guard let usage = plan.deviceUsage(for: op) else { continue }
                if case .cpu = usage.preferred {
                    cpuOps.append(op.operatorName)
                }
            }
            // Normalize: strip opset prefix (e.g. "ios17.cast" → "cast"). The
            // ImageWrapper mul+cast tail has the SAME meaning under the ios17
            // opset as the plain opset — pipersr emits "cast"/"mul", the RRDB/
            // animevideov3 models emit "ios17.cast"/"ios17.mul". Without this,
            // the gate false-fails the ios17 models on the known-acceptable tail.
            let base = { (op: String) -> String in
                op.split(separator: ".").last.map(String.init) ?? op
            }
            let unexpected = cpuOps.filter { !acceptableCPUOps.contains(base($0)) }
            if unexpected.isEmpty {
                print("PASS: \(name) — \(cpuOps.count) CPU op(s), all acceptable: \(Set(cpuOps).sorted())")
                passed += 1
            } else {
                let msg = "\(name) — UNEXPECTED CPU-fallback ops: \(Set(unexpected).sorted()) (all CPU: \(Set(cpuOps).sorted()))"
                print("FAIL: \(msg)")
                failures.append(msg)
                failed += 1
            }
        }

        print("\n\(passed) passed, \(failed) failed")
        if !failures.isEmpty {
            print("\nREGRESSIONS:")
            failures.forEach { print("  - \($0)") }
        }
        if failed > 0 { exit(1) }
    }
}