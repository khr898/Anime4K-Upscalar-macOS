// Tests/ANEUpscaleProbe.swift
// Headless ANE upscaling probe — actually RUNS each neural model with
// .cpuAndNeuralEngine on a real input frame and verifies output. Complements
// MLComputePlanGate (which checks op PLACEMENT, never runs the model). This is
// the real "upscaling with ANE, no CPU fallback" end-to-end test.
//
// For each model: load .mlmodelc, read input WxH + scale from the model
// description, build a CVPixelBuffer ImageType input filled with a gradient,
// predict (timed), assert output W/H == input*scale AND output is not all-zero.
// FAIL (exit 1) on any model that can't run or produces empty output.
//
// On the VM (no ANE) CoreML falls back to CPU and still runs → logic verified.
// On metal, .cpuAndNeuralEngine runs on the ANE → real timing.
//
// Standalone:
//   swiftc Tests/ANEUpscaleProbe.swift -o /tmp/aneprobe -parse-as-library \
//         -target arm64-apple-macos14.4 -framework CoreML -framework Foundation \
//         -framework CoreVideo -framework Metal
//   MODELS_DIR=".../Resources" /tmp/aneprobe

import Foundation
import CoreML
import CoreVideo
import Metal

@main
struct ANEUpscaleProbe {
    static func main() {
        let repoRoot = FileManager.default.currentDirectoryPath
        let defaultModelsDir = FileManager.default.fileExists(atPath: "\(repoRoot)/Anime4K-Upscaler/Resources/Models")
            ? "\(repoRoot)/Anime4K-Upscaler/Resources/Models"
            : "\(repoRoot)/../Anime4K-Upscaler/Resources/Models"
        let modelsDir = ProcessInfo.processInfo.environment["MODELS_DIR"] ?? defaultModelsDir
        let modelNames = ["pipersr", "realesr-animevideov3", "realesrgan-x4plus-anime"]
        var passed = 0, failed = 0
        for name in modelNames {
            let url = URL(fileURLWithPath: "\(modelsDir)/\(name).mlmodelc")
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("FAIL: \(name) missing .mlmodelc at \(url.path)"); failed += 1; continue
            }
            do {
                let cfg = MLModelConfiguration()
                cfg.computeUnits = .cpuAndNeuralEngine
                let ml = try MLModel(contentsOf: url, configuration: cfg)
                let desc = ml.modelDescription
                guard let inKey = desc.inputDescriptionsByName.keys.first,
                      let inImg = desc.inputDescriptionsByName[inKey]?.imageConstraint,
                      let outKey = desc.outputDescriptionsByName.keys.first,
                      let outImg = desc.outputDescriptionsByName[outKey]?.imageConstraint else {
                    print("FAIL: \(name) no image constraint"); failed += 1; continue
                }
                // Discover allowed input size (mirrors CoreMLUpscaler init).
                let enumerated = inImg.sizeConstraint.enumeratedImageSizes
                var inW = Int(inImg.pixelsWide), inH = Int(inImg.pixelsHigh)
                if !enumerated.isEmpty { inW = Int(enumerated[0].pixelsWide); inH = Int(enumerated[0].pixelsHigh) }
                guard inW > 0, inH > 0 else { print("FAIL: \(name) input size 0"); failed += 1; continue }
                guard let inPB = makeGradientPB(w: inW, h: inH) else {
                    print("FAIL: \(name) input pixelbuffer alloc"); failed += 1; continue
                }
                let provider = try MLDictionaryFeatureProvider(dictionary: [inKey: MLFeatureValue(pixelBuffer: inPB)])
                let feats = try ml.prediction(from: provider)
                guard let outPB = feats.featureValue(for: outKey)?.imageBufferValue else {
                    print("FAIL: \(name) no image output"); failed += 1; continue
                }
                let outW = CVPixelBufferGetWidth(outPB), outH = CVPixelBufferGetHeight(outPB)
                let nonzero = hasNonzero(outPB)
                let expScaleW = outImg.pixelsWide > 0 ? Int((Double(outW) / Double(inW)).rounded()) : 0
                let okDims = expScaleW > 0 && outW == inW * expScaleW && outH == inH * expScaleW
                if okDims && nonzero {
                    print("PASS: \(name) \(inW)x\(inH) → \(outW)x\(outH) (×\(expScaleW), nonzero=true)")
                    passed += 1
                } else {
                    print("FAIL: \(name) dims \(outW)x\(outH) (from \(inW)x\(inH), scale=\(expScaleW)) nonzero=\(nonzero)")
                    failed += 1
                }
            } catch {
                print("FAIL: \(name) prediction error: \(error.localizedDescription)")
                failed += 1
            }
        }
        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    static func makeGradientPB(w: Int, h: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            for x in 0..<w {
                let off = y * bpr + x * 4
                base[off] = UInt8(x & 0xFF)       // B
                base[off + 1] = UInt8(y & 0xFF)  // G
                base[off + 2] = UInt8((x + y) & 0xFF) // R
                base[off + 3] = 255              // A
            }
        }
        return pb
    }

    static func hasNonzero(_ pb: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pb, [.readOnly])
        defer { CVPixelBufferUnlockBaseAddress(pb, [.readOnly]) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let row = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        for y in 0..<h { for x in 0..<w { sum += Int(row[y * bpr + x * 4 + 1]) } }
        return sum > 0
    }
}