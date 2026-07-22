// Tests/MLComputePlanAudit.swift
// Phase 1 audit — prove whether existing converted models run on ANE or
// silently fall back to CPU/GPU. Baseline for Phase 2/7 (which must show 0 CPU
// fallback on rebuilt models).
//
// Standalone swiftc-compiled probe (matches existing Tests/ convention).
//
// Build + run:
//   swiftc Tests/MLComputePlanAudit.swift -o /tmp/mlplan -parse-as-library \
//         -target arm64-apple-macos14.4 -framework CoreML -framework Foundation \
//   && /tmp/mlplan
//
// Loads each .mlpackage in Anime4K-Upscaler/Resources/Models, compiles it to
// .mlmodelc, builds MLComputePlan with .cpuAndNeuralEngine, and tallies the
// preferred compute device per ML Program operation.
//
// Swift overlay notes (NS_REFINED_FOR_SWIFT):
//   - MLModelStructure is an enum: .program(Program), .neuralNetwork(...), .pipeline(...)
//   - MLComputeDevice is an enum: .cpu / .gpu / .neuralEngine
//   - plan.deviceUsage(for:) -> MLComputePlan.DeviceUsage?  (not computeDeviceUsage)

import Foundation
import CoreML

@main
struct MLComputePlanAudit {
    static func main() async {
        let repoRoot = FileManager.default.currentDirectoryPath
        // Allow running from repo root or from Tests/ dir.
        let modelsDir = FileManager.default.fileExists(atPath: "\(repoRoot)/Anime4K-Upscaler/Resources/Models")
            ? "\(repoRoot)/Anime4K-Upscaler/Resources/Models"
            : "\(repoRoot)/../Anime4K-Upscaler/Resources/Models"
        let modelNames = ["pipersr", "realesr-animevideov3", "realesrgan-x4plus-anime"]

        print("=== MLComputePlan Audit ===")
        print("modelsDir: \(modelsDir)")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")

        for name in modelNames {
            let packageURL = URL(fileURLWithPath: "\(modelsDir)/\(name).mlpackage")
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                print("--- \(name): MISSING \(packageURL.path) ---")
                continue
            }
            await auditModel(name: name, packageURL: packageURL)
            print("")
        }
    }

    static func auditModel(name: String, packageURL: URL) async {
        print("--- \(name) ---")
        let compiledURL: URL
        do {
            compiledURL = try await MLModel.compileModel(at: packageURL)
        } catch {
            print("compile FAILED: \(error)")
            return
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        let plan: MLComputePlan
        do {
            plan = try await MLComputePlan.load(contentsOf: compiledURL, configuration: config)
        } catch {
            print("MLComputePlan.load FAILED: \(error)")
            return
        }

        // MLModelStructure is a Swift enum (NS_REFINED_FOR_SWIFT overlay):
        // case .program(MLModelStructure.Program), .neuralNetwork(...), .pipeline(...)
        guard case .program(let program) = plan.modelStructure else {
            print("modelStructure is not .program (neuralNetwork/pipeline/other)")
            return
        }
        guard let mainFunc = program.functions["main"] else {
            print("no 'main' function; functions: \(program.functions.keys.sorted())")
            return
        }
        let operations = mainFunc.block.operations

        var counts: [String: Int] = ["ANE": 0, "CPU": 0, "GPU": 0, "nil": 0]
        var cpuOps: [String] = []
        var gpuOps: [String] = []

        for op in operations {
            guard let usage = plan.deviceUsage(for: op) else {
                counts["nil", default: 0] += 1
                continue
            }
            // MLComputeDevice is a Swift enum: .cpu / .gpu / .neuralEngine
            let dev: String
            switch usage.preferred {
            case .neuralEngine: dev = "ANE"
            case .cpu: dev = "CPU"
            case .gpu: dev = "GPU"
            @unknown default: dev = "unknown"
            }
            counts[dev, default: 0] += 1
            if dev == "CPU" { cpuOps.append(op.operatorName) }
            if dev == "GPU" { gpuOps.append(op.operatorName) }
        }

        let total = operations.count
        print("ops total: \(total)")
        print("placement: \(counts)")
        print("unique op types: \(Set(operations.map { $0.operatorName }).sorted())")
        if !cpuOps.isEmpty {
            print("CPU-FALLBACK OPS (\(cpuOps.count)): \(cpuOps)")
        } else {
            print("CPU-FALLBACK OPS: none")
        }
        if !gpuOps.isEmpty {
            print("GPU ops (\(gpuOps.count)): \(Set(gpuOps).sorted())")
        }
    }
}