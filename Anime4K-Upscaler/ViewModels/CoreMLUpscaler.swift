// Anime4K-Upscaler/ViewModels/CoreMLUpscaler.swift
import CoreML
import AVFoundation
import VideoToolbox
import CoreImage

/// Offline tiled super-resolution via Core ML on the Apple Neural Engine.
/// Tensor names, allowed input tile sizes, and the native upscale factor are read
/// from the model at load time — nothing is hardcoded, so esrgan (4x, input/output)
/// and PiperSR (2x, input_image/output_image) both work.
final class CoreMLUpscaler {
    private let model: MLModel
    private let ciContext: CIContext
    private let inputName: String
    private let outputName: String
    let nativeScale: Int                       // 2 or 4, derived from the model
    private let tiles: [(w: Int, h: Int)]      // allowed input sizes, largest first
    private let overlap = 16                    // input-px halo to hide tile seams

    convenience init(modelName: String) throws {
        try self.init(compiledModelURL: Self.compiledModelURL(modelName: modelName))
    }

    /// Designated initializer from an already-compiled .mlmodelc URL.
    /// Kept separate from the bundle lookup so tests/CLI harnesses can load
    /// models without a Bundle.main resource context.
    init(compiledModelURL compiledURL: URL) throws {
        let modelName = compiledURL.deletingPathExtension().lastPathComponent
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine          // explicit ANE routing
        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        self.model = model

        let inDesc = model.modelDescription.inputDescriptionsByName
        let outDesc = model.modelDescription.outputDescriptionsByName
        guard let inKey = inDesc.keys.sorted().first,
              let outKey = outDesc.keys.sorted().first,
              let inImg = inDesc[inKey]?.imageConstraint else {
            throw NSError(domain: "CoreMLUpscaler", code: 422,
                          userInfo: [NSLocalizedDescriptionKey: "Model \(modelName) has no image I/O."])
        }
        self.inputName = inKey
        self.outputName = outKey

        // Allowed input tile sizes (enumerated) or the single fixed size.
        var sizes: [(Int, Int)] = []
        let enumerated = inImg.sizeConstraint.enumeratedImageSizes
        if !enumerated.isEmpty {
            sizes = enumerated.map { (Int($0.pixelsWide), Int($0.pixelsHigh)) }
        } else {
            sizes = [(inImg.pixelsWide, inImg.pixelsHigh)]
        }
        sizes.sort { $0.0 * $0.1 > $1.0 * $1.1 }
        self.tiles = sizes.map { (w: $0.0, h: $0.1) }

        // Native scale from output/input edge ratio; fall back by model name.
        // A model whose output image constraint is undefined reports a 1x1 (or
        // otherwise <2x) size — never trust a ratio below 2 for a super-res
        // model; use the name-based default instead.
        let nameScale = modelName.lowercased().contains("piper") ? 2 : 4
        if let outImg = outDesc[outKey]?.imageConstraint,
           let first = sizes.first, first.0 > 0, outImg.pixelsWide > 0 {
            let ratio = Int((Double(outImg.pixelsWide) / Double(first.0)).rounded())
            self.nativeScale = ratio >= 2 ? ratio : nameScale
        } else {
            self.nativeScale = nameScale
        }

        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    // MARK: - Model resolution (compile .mlpackage once, cache the .mlmodelc)

    static func compiledModelURL(modelName: String) throws -> URL {
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            return url
        }
        let fm = FileManager.default
        let cacheDir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                  appropriateFor: nil, create: true)
            .appendingPathComponent("CompiledModels", isDirectory: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachedURL = cacheDir.appendingPathComponent("\(modelName).mlmodelc")
        if fm.fileExists(atPath: cachedURL.path) { return cachedURL }

        guard let pkg = Bundle.main.url(forResource: modelName, withExtension: "mlpackage")
                ?? Bundle.main.url(forResource: modelName, withExtension: "mlpackage", subdirectory: "Models") else {
            throw NSError(domain: "CoreMLUpscaler", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Model \(modelName).mlpackage not found in bundle."])
        }
        let tmp = try MLModel.compileModel(at: pkg)              // temp .mlmodelc
        if fm.fileExists(atPath: cachedURL.path) { try? fm.removeItem(at: cachedURL) }
        try fm.copyItem(at: tmp, to: cachedURL)                  // compile once per install
        return cachedURL
    }

    // MARK: - Public entry points

    /// Upscale a full frame from a pixel buffer to `targetScale`× the original size.
    ///
    /// Hot path for every Special mode (PiperSR / esrgan Fast+Quality / SD-Rescue
    /// upscale) — all route through here. The previous implementation did, per
    /// tile: `CIContext.createCGImage` (full-frame rasterize once), then a
    /// `CIContext.render` to crop the tile into the input buffer, then
    /// `model.prediction`, then another `CIContext.render` to blit the valid
    /// region into the output buffer — and every tile ran SERIALLY. For a 1080p
    /// frame on the 128×128 PiperSR model that is ⌈1920/96⌉×⌈1080/96⌉ = 240
    /// tiles × ~10ms ANE per-call overhead ≈ 2.4s/frame = 0.4fps, plus 480
    /// `CIContext.render` round-trips/frame. Two fixes:
    ///   1. Crop tiles + blit results via direct `CVPixelBuffer` row `memcpy`
    ///      (no CGImage, no per-tile CIContext.render). One full-frame rasterize
    ///      gone; 480 GPU renders gone.
    ///   2. Run the 240 `model.prediction` calls CONCURRENTLY (bounded). ANE
    ///      pipelines queued predictions; `MLModel.prediction` is thread-safe.
    /// The tile PLAN (positions + valid regions) is identical to the old code,
    /// so seam handling is unchanged — only the transport changed.
    func upscale(_ inputBuffer: CVPixelBuffer, targetScale: Int) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(inputBuffer)
        let height = CVPixelBufferGetHeight(inputBuffer)
        let nativeW = width * nativeScale
        let nativeH = height * nativeScale
        guard let nativeBuffer = Self.makePixelBuffer(nativeW, nativeH) else {
            throw NSError(domain: "CoreMLUpscaler", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer."])
        }

        let (tw, th) = chooseTile(width: width, height: height)

        // Tile plan (positions + clamped crop sizes + valid regions) factored
        // into TilePlanner so the edge-clamp + overlap-halo math is unit-tested
        // (Tests/TilePlannerTests.swift). Deduped by (topX,topY): the step
        // iteration used to emit clamped duplicates at the far edge that crop,
        // infer, and blit identical regions — same output, less wasted dispatch.
        let plans = TilePlanner.plans(frameW: width, frameH: height,
                                      tileW: tw, tileH: th, overlap: overlap)

        // --- Crop all tiles via memcpy from the source CVPixelBuffer (locked once). ---
        CVPixelBufferLockBaseAddress(inputBuffer, [.readOnly])
        var tileInputs: [CVPixelBuffer] = []
        tileInputs.reserveCapacity(plans.count)
        if let srcBase = CVPixelBufferGetBaseAddress(inputBuffer) {
            let srcBPR = CVPixelBufferGetBytesPerRow(inputBuffer)
            for p in plans {
                guard let tb = Self.makePixelBuffer(tw, th) else { continue }
                Self.cropMemcpy(srcBase: srcBase, srcBPR: srcBPR,
                                dst: tb, topX: p.topX, topY: p.topY,
                                cropW: p.cropW, cropH: p.cropH, tileW: tw, tileH: th)
                tileInputs.append(tb)
            }
        }
        CVPixelBufferUnlockBaseAddress(inputBuffer, [.readOnly])

        // --- Concurrent inference. ANE pipelines queued predictions; prediction
        // is thread-safe. Bounded so we don't flood the engine past its sweet spot. ---
        let outTiles = try Self.concurrentInfer(model: model,
                                                 inputName: inputName, outputName: outputName,
                                                 inputs: tileInputs,
                                                 maxConcurrent: Self.inferConcurrency)

        // --- Blit valid regions via memcpy into the native output buffer (locked once). ---
        CVPixelBufferLockBaseAddress(nativeBuffer, [])
        if let dstBase = CVPixelBufferGetBaseAddress(nativeBuffer) {
            let dstBPR = CVPixelBufferGetBytesPerRow(nativeBuffer)
            for (i, p) in plans.enumerated() where i < outTiles.count {
                guard let outTile = outTiles[i], p.validW > 0, p.validH > 0 else { continue }
                Self.blitMemcpy(src: outTile,
                                srcRectX: p.validLeft * nativeScale,
                                srcRectY: p.validTop * nativeScale,
                                rectW: p.validW * nativeScale, rectH: p.validH * nativeScale,
                                dst: nativeBuffer, dstBase: dstBase, dstBPR: dstBPR,
                                dstOriginX: (p.topX + p.validLeft) * nativeScale,
                                dstOriginY: (p.topY + p.validTop) * nativeScale)
            }
        }
        CVPixelBufferUnlockBaseAddress(nativeBuffer, [])

        // Resize native → target (one CIContext.render for the whole frame — kept).
        if targetScale == nativeScale { return nativeBuffer }
        let factor = Double(targetScale) / Double(nativeScale)
        let resized = CIImage(cvPixelBuffer: nativeBuffer)
            .applyingFilter("CILanczosScaleTransform",
                            parameters: [kCIInputScaleKey: factor, kCIInputAspectRatioKey: 1.0])
        let outW = width * targetScale, outH = height * targetScale
        guard let outBuffer = Self.makePixelBuffer(outW, outH) else { return nativeBuffer }
        ciContext.render(resized, to: outBuffer,
                         bounds: CGRect(x: 0, y: 0, width: outW, height: outH), colorSpace: nil)
        return outBuffer
    }

    // MARK: - Internals

    private func chooseTile(width: Int, height: Int) -> (Int, Int) {
        // Largest enumerated tile that does not exceed the frame; fall back to the smallest.
        for t in tiles where t.w <= width && t.h <= height { return (t.w, t.h) }
        return tiles.last ?? (160, 90)
    }

    /// Max concurrent `model.prediction` calls. ANE pipelines queued work but
    /// floods past ~8 in flight just add context-switch + memory pressure for
    /// tiny 128×128 tiles. Bounded by a semaphore in `concurrentInfer`.
    /// ponytail: fixed 8 — if a future model shows better throughput at higher
    /// fan-out, make this adaptive on model+tile size.
    private static let inferConcurrency = 8

    /// Run `model.prediction` over `inputs` concurrently, bounded by
    /// `maxConcurrent`. `MLModel.prediction` is documented thread-safe; the ANE
    /// driver pipelines queued predictions so the per-call fixed latency
    /// (~5–10ms for a tiny tile, dominated by submission overhead, not compute)
    /// overlaps across tiles instead of serializing 240 calls back-to-back.
    /// Returns one (possibly nil) output per input, in order. First error wins.
    private static func concurrentInfer(model: MLModel,
                                        inputName: String, outputName: String,
                                        inputs: [CVPixelBuffer],
                                        maxConcurrent: Int) throws -> [CVPixelBuffer?] {
        var outputs = [CVPixelBuffer?](repeating: nil, count: inputs.count)
        let sem = DispatchSemaphore(value: maxConcurrent)
        let errorBox = ErrorBox()
        DispatchQueue.concurrentPerform(iterations: inputs.count) { i in
            guard errorBox.message == nil else { return }
            sem.wait()
            defer { sem.signal() }
            guard errorBox.message == nil else { return }
            do {
                let input = try MLDictionaryFeatureProvider(
                    dictionary: [inputName: MLFeatureValue(pixelBuffer: inputs[i])])
                let out = try model.prediction(from: input)
                outputs[i] = out.featureValue(for: outputName)?.imageBufferValue
            } catch {
                errorBox.set(error.localizedDescription)
            }
        }
        if let msg = errorBox.message {
            throw NSError(domain: "CoreMLUpscaler", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return outputs
    }

    /// Lock-protected single-writer box for the first inference error, readable
    /// as a cheap stop flag from concurrentPerform iterations. Plain mutex — not
    /// on the hot path (only fires on failure).
    private final class ErrorBox {
        private let lock = NSLock()
        private var _msg: String?
        var message: String? { lock.lock(); defer { lock.unlock() }; return _msg }
        func set(_ msg: String) { lock.lock(); if _msg == nil { _msg = msg }; lock.unlock() }
    }

    /// Crop a `cropW × cropH` region from the source buffer (top-left origin,
    /// BGRA) into the top-left of a `tileW × tileH` destination tile buffer.
    /// Direct row memcpy — no CGImage, no CIContext.render. Margin outside the
    /// crop (right/bottom on edge tiles) is left as-is; the valid-region blit
    /// excludes it, matching the old `draw` semantics. `srcBase`/`srcBPR` come
    /// from a `CVPixelBufferLockBaseAddress` the caller owns.
    private static func cropMemcpy(srcBase: UnsafeMutableRawPointer, srcBPR: Int,
                                   dst: CVPixelBuffer,
                                   topX: Int, topY: Int, cropW: Int, cropH: Int,
                                   tileW: Int, tileH: Int) {
        CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(dst, []) }
        guard let dstBase = CVPixelBufferGetBaseAddress(dst) else { return }
        let dstBPR = CVPixelBufferGetBytesPerRow(dst)
        let rowBytes = cropW * 4
        for row in 0..<cropH {
            let src = srcBase.advanced(by: (topY + row) * srcBPR + topX * 4)
            let dstRow = dstBase.advanced(by: row * dstBPR)
            memcpy(dstRow, src, rowBytes)
        }
    }

    /// Blit a `rectW × rectH` region (BGRA) from `src` at `(srcRectX, srcRectY)`
    /// (top-left origin) into `dst` at `(dstOriginX, dstOriginY)`. Direct row
    /// memcpy. `dstBase`/`dstBPR` come from a `CVPixelBufferLockBaseAddress` the
    /// caller owns on `dst`; `src` is locked internally.
    private static func blitMemcpy(src: CVPixelBuffer,
                                   srcRectX: Int, srcRectY: Int, rectW: Int, rectH: Int,
                                   dst: CVPixelBuffer, dstBase: UnsafeMutableRawPointer, dstBPR: Int,
                                   dstOriginX: Int, dstOriginY: Int) {
        CVPixelBufferLockBaseAddress(src, [.readOnly])
        defer { CVPixelBufferUnlockBaseAddress(src, [.readOnly]) }
        guard let srcBase = CVPixelBufferGetBaseAddress(src) else { return }
        let srcBPR = CVPixelBufferGetBytesPerRow(src)
        let rowBytes = rectW * 4
        for row in 0..<rectH {
            let s = srcBase.advanced(by: (srcRectY + row) * srcBPR + srcRectX * 4)
            let d = dstBase.advanced(by: (dstOriginY + row) * dstBPR + dstOriginX * 4)
            memcpy(d, s, rowBytes)
        }
    }

    private static func makePixelBuffer(_ w: Int, _ h: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        // IOSurface-backed + Metal-compatible so the output buffer can hand off
        // to a Metal blit/encode pass zero-copy (Phase 4 ring + Phase 3 Metal
        // convert path). IOSurface backing is required for CVPixelBuffer→MTLTexture
        // sharing; without it the Metal path falls back to a host-memory copy.
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess else { return nil }
        return pb
    }
}
