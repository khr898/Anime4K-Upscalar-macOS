// Anime4K-Upscaler/ViewModels/MetalFXUpscaler.swift
import Foundation
import Metal
import MetalFX
import CoreVideo
import IOSurface

/// GPU spatial upscaler backed by Apple MetalFX (`MTLFXSpatialScaler`).
/// Provides Metal 4 capabilities on modern Apple Silicon with seamless Metal 3 fallback.
/// Real-time on Apple GPUs; no ANE, no tiling, one `encode(commandBuffer:)`
/// per frame. Conforms to `FrameUpscaler` so it drops into the same encode
/// loop as `CoreMLUpscaler` (ProcessingEngine.runUpscaleEncode).
///
/// The scaler is created lazily on the first frame (input dims are constant
/// for a clip) and reused for every subsequent frame — scaler creation is
/// expensive (Apple guidance: create once). Output CVPixelBuffer + texture
/// are also cached and overwritten each frame (zero per-frame allocation).
final class MetalFXUpscaler {
    enum MetalFeatureTier: String, Sendable {
        case metal4 = "Metal 4 (Apple Silicon Modern GPU)"
        case metal3 = "Metal 3 (Standard GPU Spatial Scaler)"
    }

    let featureTier: MetalFeatureTier
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var scaler: MTLFXSpatialScaler?
    private struct OutputSlot {
        let outPixelBuffer: CVPixelBuffer
        let outTexture: MTLTexture
        let scalerReadView: MTLTexture?
        let sharpPixelBuffer: CVPixelBuffer?
        let sharpTexture: MTLTexture?
    }

    private var outputSlots: [OutputSlot] = []
    private var slotIndex = 0
    private var cachedInW = 0, cachedInH = 0, cachedOutW = 0, cachedOutH = 0

    /// Optional contrast-gated unsharp-mask pass after the spatial upscale
    /// (3DSnickerStream anime pattern: sharpen edges, leave flat areas alone).
    /// When nil, upscale() returns the scaler output directly.
    private let applySharpen: Bool
    private var sharpenPipeline: MTLComputePipelineState?

    enum Error: LocalizedError {
        case noDevice, unsupportedDevice, scalerInit(String), noCommandBuffer
        case notIOSurface, textureInit(String), outputBufferCreate
        case sharpenPipeline(String)

        var errorDescription: String? {
            switch self {
            case .noDevice:             return "No Metal device available."
            case .unsupportedDevice:    return "This GPU does not support MetalFX spatial upscaling (requires Metal 3 or Metal 4 compatible GPU)."
            case .scalerInit(let s):     return "MetalFX spatial scaler unavailable: \(s)"
            case .noCommandBuffer:       return "Metal command buffer could not be created."
            case .notIOSurface:          return "Decoded frame is not IOSurface-backed (cannot zero-copy to Metal)."
            case .textureInit(let s):    return "Metal texture init failed: \(s)"
            case .outputBufferCreate:    return "Could not create MetalFX output pixel buffer."
            case .sharpenPipeline(let s): return "Sharpen compute pipeline init failed: \(s)"
            }
        }
    }

    init(applySharpen: Bool = false) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw Error.noDevice
        }
        guard MTLFXSpatialScalerDescriptor.supportsDevice(device) else {
            throw Error.unsupportedDevice
        }
        self.device = device
        self.queue = queue
        self.applySharpen = applySharpen

        // Metal 4 detection ladder with Metal 3 fallback
        if device.supportsFamily(.apple9) || device.supportsFamily(.apple8) {
            self.featureTier = .metal4
        } else {
            self.featureTier = .metal3
        }

        if applySharpen { try buildSharpenPipeline() }
    }

    func upscale(_ input: CVPixelBuffer, targetScale: Int) throws -> CVPixelBuffer {
        let inW = CVPixelBufferGetWidth(input), inH = CVPixelBufferGetHeight(input)
        let outW = inW * targetScale, outH = inH * targetScale
        try ensureScaler(inW: inW, inH: inH, outW: outW, outH: outH)

        guard let scaler, !outputSlots.isEmpty else {
            throw Error.scalerInit("scaler not initialized for \(inW)x\(inH) → \(outW)x\(outH)")
        }

        // Cycle through triple-buffer ring to ensure non-aliased backing memory
        // while downstream AVAssetWriter asynchronously encodes previous frame.
        let slot = outputSlots[slotIndex]
        slotIndex = (slotIndex + 1) % outputSlots.count

        let inTexture = try makeTexture(from: input, width: inW, height: inH, usage: .shaderRead)
        scaler.colorTexture = inTexture
        scaler.outputTexture = slot.outTexture

        // Pass 1: MetalFX spatial upscale. Committed + waited before the sharpen
        // compute reads the output — a second command buffer avoids any
        // cross-encoder read-after-write hazard on outTexture's IOSurface.
        guard let cmd = queue.makeCommandBuffer() else { throw Error.noCommandBuffer }
        scaler.encode(commandBuffer: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()

        guard applySharpen, let pipeline = sharpenPipeline,
              let readView = slot.scalerReadView, let sharpTex = slot.sharpTexture,
              let sharpPB = slot.sharpPixelBuffer else {
            return slot.outPixelBuffer
        }

        // Pass 2: contrast-gated unsharp mask. Reads the scaler output (non-srgb
        // view → operates on raw sRGB bytes, perceptual sharpen as 3DSnickerStream
        // does), writes the sharp pixelbuffer. 16×16 threadgroups, bounds-checked
        // in-kernel so edge tiles are safe without a nonuniform dispatch.
        guard let sCmd = queue.makeCommandBuffer() else { throw Error.noCommandBuffer }
        guard let enc = sCmd.makeComputeCommandEncoder() else {
            throw Error.sharpenPipeline("compute encoder")
        }
        enc.setComputePipelineState(pipeline)
        enc.setTexture(readView, index: 0)
        enc.setTexture(sharpTex, index: 1)
        let groupW = 16, groupH = 16
        let tg = MTLSize(width: groupW, height: groupH, depth: 1)
        let ng = MTLSize(width: (outW + groupW - 1) / groupW,
                         height: (outH + groupH - 1) / groupH, depth: 1)
        enc.dispatchThreadgroups(ng, threadsPerThreadgroup: tg)
        enc.endEncoding()
        sCmd.commit()
        sCmd.waitUntilCompleted()
        return sharpPB
    }

    private func ensureScaler(inW: Int, inH: Int, outW: Int, outH: Int) throws {
        if scaler != nil, inW == cachedInW, inH == cachedInH, outW == cachedOutW, outH == cachedOutH { return }
        let desc = MTLFXSpatialScalerDescriptor()
        desc.inputWidth = inW; desc.inputHeight = inH
        desc.outputWidth = outW; desc.outputHeight = outH
        desc.colorTextureFormat = .bgra8Unorm_srgb
        desc.outputTextureFormat = .bgra8Unorm_srgb
        desc.colorProcessingMode = .perceptual
        guard let scaler = desc.makeSpatialScaler(device: device) else {
            throw Error.scalerInit("\(inW)x\(inH) → \(outW)x\(outH)")
        }
        self.scaler = scaler

        // Allocate a 3-buffer ring (triple buffer) of IOSurface-backed + Metal-compatible
        // CVPixelBuffers. This prevents downstream AVAssetWriter from reading from memory
        // being concurrently overwritten by the next frame.
        let pbAttrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        var newSlots: [OutputSlot] = []
        for _ in 0..<3 {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, outW, outH,
                                kCVPixelFormatType_32BGRA, pbAttrs as CFDictionary, &pb)
            guard let outPB = pb else { throw Error.outputBufferCreate }
            let outTex = try makeTexture(from: outPB, width: outW, height: outH, usage: .shaderWrite)

            var readView: MTLTexture?
            var sharpPB: CVPixelBuffer?
            var sharpTex: MTLTexture?

            if applySharpen {
                readView = try makeTexture(from: outPB, width: outW, height: outH,
                                           usage: .shaderRead, pixelFormat: .bgra8Unorm)
                var spb: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, outW, outH,
                                    kCVPixelFormatType_32BGRA, pbAttrs as CFDictionary, &spb)
                guard let createdSharpPB = spb else { throw Error.outputBufferCreate }
                sharpPB = createdSharpPB
                sharpTex = try makeTexture(from: createdSharpPB, width: outW, height: outH,
                                           usage: .shaderWrite, pixelFormat: .bgra8Unorm)
            }

            newSlots.append(OutputSlot(
                outPixelBuffer: outPB,
                outTexture: outTex,
                scalerReadView: readView,
                sharpPixelBuffer: sharpPB,
                sharpTexture: sharpTex
            ))
        }

        self.outputSlots = newSlots
        self.slotIndex = 0
        cachedInW = inW; cachedInH = inH; cachedOutW = outW; cachedOutH = outH
    }

    // MARK: - Sharpen compute pipeline

    /// Contrast-gated unsharp mask, 3×3 neighborhood. One compute pass per frame:
    ///   blurred = gaussian-weighted 3×3 average
    ///   contrast = |center - blurred|            (edge strength)
    ///   gate = smoothstep(lo, hi, contrast)       (flat areas → 0, edges → 1)
    ///   out = center + amount * (center - blurred) * gate
    /// Flat regions skip sharpening (no grain amplification); edges get a strong
    /// unsharp boost. amount/lo/hi tuned for anime line art (3DSnickerStream).
    private static let sharpenSource = """
#include <metal_stdlib>
using namespace metal;

kernel void contrast_gated_unsharp(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint2 dims = uint2(inTex.get_width(), inTex.get_height());
    if (gid.x >= dims.x || gid.y >= dims.y) return;

    float3 center = inTex.read(gid).rgb;
    // 3×3 gaussian-ish weights: center 4, orthogonal 2, diagonal 1 (sum 16).
    float3 blur = float3(0.0);
    float wsum = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int2 p = int2(gid) + int2(dx, dy);
            if (p.x < 0 || p.y < 0 || p.x >= int(dims.x) || p.y >= int(dims.y)) continue;
            float3 s = inTex.read(uint2(p)).rgb;
            float w = (dx == 0 && dy == 0) ? 4.0 : ((dx == 0 || dy == 0) ? 2.0 : 1.0);
            blur += s * w;
            wsum += w;
        }
    }
    blur /= wsum;

    float contrast = length(center - blur);
    // gate: below 0.02 → no sharpen (flat), above 0.06 → full (edge). Tunable.
    float gate = smoothstep(0.02, 0.06, contrast);
    float amount = 1.5;  // unsharp strength
    float3 sharp = center + amount * (center - blur) * gate;
    outTex.write(float4(clamp(sharp, 0.0, 1.0), 1.0), gid);
}
"""

    private func buildSharpenPipeline() throws {
        do {
            let compileOptions = MTLCompileOptions()
            compileOptions.fastMathEnabled = true
            let lib = try device.makeLibrary(source: Self.sharpenSource, options: compileOptions)
            guard let fn = lib.makeFunction(name: "contrast_gated_unsharp") else {
                throw Error.sharpenPipeline("function not found")
            }
            self.sharpenPipeline = try device.makeComputePipelineState(function: fn)
        } catch {
            throw Error.sharpenPipeline(error.localizedDescription)
        }
    }

    private func makeTexture(from pb: CVPixelBuffer, width: Int, height: Int,
                             usage: MTLTextureUsage,
                             pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb) throws -> MTLTexture {
        guard let io = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { throw Error.notIOSurface }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = usage
        desc.storageMode = .shared  // IOSurface-backed → shared CPU/GPU
        guard let tex = device.makeTexture(descriptor: desc, iosurface: io, plane: 0) else {
            throw Error.textureInit("IOSurface → MTLTexture")
        }
        return tex
    }
}