// Tests/MetalFXProbe.swift
// Headless MetalFX spatial-scaler probe — creates MTLFXSpatialScaler, runs a
// real encode 640x360 → 2× and 4×, verifies output dims + nonzero. This is the
// MetalFX preset's GPU upscaler test (the part the GUI preset exercises, minus
// the Restore VL preprocess which is an ffmpeg shader chain, not MetalFX).
//
// macOS 13+ (MTLFXSpatialScaler). Fails (exit 1) if the device doesn't support
// MetalFX spatial scaling or the encode produces empty output.
//
// Standalone:
//   swiftc Tests/MetalFXProbe.swift -o /tmp/mfxprobe -parse-as-library \
//         -target arm64-apple-macos14.4 -framework Metal -framework MetalFX \
//         -framework Foundation
//   /tmp/mfxprobe

import Foundation
import Metal
import MetalFX
import CoreVideo

@main
struct MetalFXProbe {
    static func main() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            print("FAIL: no Metal device"); exit(1)
        }
        let isMetal4 = dev.supportsFamily(.apple9) || dev.supportsFamily(.apple8)
        let tierName = isMetal4 ? "Metal 4 (Apple Silicon Modern)" : "Metal 3 (Standard GPU Spatial Scaler)"
        print("ℹ️ Detected Metal Feature Tier: \(tierName) on \(dev.name)")

        let inW = 640, inH = 360
        let scales = [2, 4]
        var passed = 0, failed = 0
        for s in scales {
            let outW = inW * s, outH = inH * s
            let desc = MTLFXSpatialScalerDescriptor()
            desc.inputWidth = inW; desc.inputHeight = inH
            desc.outputWidth = outW; desc.outputHeight = outH
            desc.colorTextureFormat = .bgra8Unorm_srgb
            desc.outputTextureFormat = .bgra8Unorm_srgb
            desc.colorProcessingMode = .perceptual
            guard MTLFXSpatialScalerDescriptor.supportsDevice(dev) else {
                print("FAIL: ×\(s) device not supported"); failed += 1; continue
            }
            guard let scaler = desc.makeSpatialScaler(device: dev) else {
                print("FAIL: ×\(s) makeSpatialScaler nil"); failed += 1; continue
            }
            guard let inTex = makeGradientTexture(dev, w: inW, h: inH),
                  let outTex = dev.makeTexture(descriptor: outTexDesc(w: outW, h: outH)) else {
                print("FAIL: ×\(s) texture alloc"); failed += 1; continue
            }
            guard let cmd = dev.makeCommandQueue()?.makeCommandBuffer() else {
                print("FAIL: ×\(s) command buffer"); failed += 1; continue
            }
            scaler.colorTexture = inTex
            scaler.outputTexture = outTex
            let t0 = Date()  // ponytail: Date() ok in main (not workflow script)
            scaler.encode(commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
            let ms = Date().timeIntervalSince(t0) * 1000
            let nonzero = hasNonzero(outTex)
            let okDims = outTex.width == outW && outTex.height == outH
            if okDims && nonzero {
                print(String(format: "PASS: ×%d %dx%d → %dx%d (%.2f ms, nonzero=true)", s, inW, inH, outW, outH, ms))
                passed += 1
            } else {
                print("FAIL: ×\(s) dims \(outTex.width)x\(outTex.height) nonzero=\(nonzero)")
                failed += 1
            }
        }
        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    static func outTexDesc(w: Int, h: Int) -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor()
        d.textureType = .type2D
        d.pixelFormat = .bgra8Unorm_srgb
        d.width = w; d.height = h
        d.usage = [.shaderRead, .shaderWrite]
        return d
    }

    static func makeGradientTexture(_ dev: MTLDevice, w: Int, h: Int) -> MTLTexture? {
        guard let tex = dev.makeTexture(descriptor: outTexDesc(w: w, h: h)) else { return nil }
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h { for x in 0..<w {
            let o = y * bpr + x * 4
            base[o] = UInt8(x & 0xFF); base[o+1] = UInt8(y & 0xFF); base[o+2] = UInt8((x+y) & 0xFF); base[o+3] = 255
        }}
        CVPixelBufferUnlockBaseAddress(pb, [])
        let region = MTLRegionMake2D(0, 0, w, h)
        tex.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: bpr)
        return tex
    }

    static func hasNonzero(_ tex: MTLTexture) -> Bool {
        let w = tex.width, h = tex.height
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pb else { return false }
        CVPixelBufferLockBaseAddress(pb, [])
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!
        tex.getBytes(base, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var sum = 0
        let row = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h { for x in 0..<w { sum += Int(row[y * bpr + x * 4 + 1]) } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return sum > 0
    }
}