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

    init(modelName: String) throws {
        let compiledURL = try Self.compiledModelURL(modelName: modelName)
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
        if let enumerated = inImg.sizeConstraint.enumeratedImageSizes, !enumerated.isEmpty {
            sizes = enumerated.map { (Int($0.pixelsWide), Int($0.pixelsHigh)) }
        } else {
            sizes = [(inImg.pixelsWide, inImg.pixelsHigh)]
        }
        sizes.sort { $0.0 * $0.1 > $1.0 * $1.1 }
        self.tiles = sizes.map { (w: $0.0, h: $0.1) }

        // Native scale from output/input edge ratio; fall back by model name.
        if let outImg = outDesc[outKey]?.imageConstraint,
           let first = sizes.first, first.0 > 0, outImg.pixelsWide > 0 {
            self.nativeScale = max(1, Int((Double(outImg.pixelsWide) / Double(first.0)).rounded()))
        } else {
            self.nativeScale = modelName.lowercased().contains("piper") ? 2 : 4
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
    func upscale(_ inputBuffer: CVPixelBuffer, targetScale: Int) throws -> CVPixelBuffer {
        let w = CVPixelBufferGetWidth(inputBuffer)
        let h = CVPixelBufferGetHeight(inputBuffer)
        return try upscale(CIImage(cvPixelBuffer: inputBuffer), width: w, height: h, targetScale: targetScale)
    }

    /// Upscale a full frame from a CIImage (used by the SD-Rescue PNG path) to `targetScale`×.
    func upscale(_ inputImage: CIImage, width: Int, height: Int, targetScale: Int) throws -> CVPixelBuffer {
        // Normalize the input to a top-left-origin CGImage so all tiling math is in image space.
        guard let inputCG = ciContext.createCGImage(
                inputImage,
                from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            throw NSError(domain: "CoreMLUpscaler", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to rasterize input frame."])
        }

        let nativeW = width * nativeScale
        let nativeH = height * nativeScale
        guard let nativeBuffer = Self.makePixelBuffer(nativeW, nativeH) else {
            throw NSError(domain: "CoreMLUpscaler", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer."])
        }

        let (tw, th) = chooseTile(width: width, height: height)
        let stepX = max(1, tw - 2 * overlap)
        let stepY = max(1, th - 2 * overlap)

        var y = 0
        while y < height {
            let topY = min(y, max(0, height - th))
            var x = 0
            while x < width {
                let topX = min(x, max(0, width - tw))

                // Crop a tile (with halo, clamped to the frame) from the CGImage (top-left origin).
                let cropW = min(tw, width - topX)
                let cropH = min(th, height - topY)
                guard let tileCG = inputCG.cropping(to: CGRect(x: topX, y: topY, width: cropW, height: cropH)),
                      let tileInput = Self.makePixelBuffer(tw, th) else { x += stepX; continue }
                Self.draw(tileCG, into: tileInput, ciContext: ciContext)   // top-left, exact tile size

                // Run the model.
                let outTile = try infer(tileInput)                          // tw*native × th*native

                // Composite only the clean center region into the native output buffer.
                let validLeft  = (topX == 0) ? 0 : overlap
                let validTop   = (topY == 0) ? 0 : overlap
                let validRight = (topX + tw >= width)  ? cropW : cropW - overlap
                let validBot   = (topY + th >= height) ? cropH : cropH - overlap

                Self.blit(outTile,
                          srcRect: CGRect(x: validLeft * nativeScale,
                                          y: validTop  * nativeScale,
                                          width:  max(0, (validRight - validLeft)) * nativeScale,
                                          height: max(0, (validBot   - validTop )) * nativeScale),
                          into: nativeBuffer,
                          dstOrigin: CGPoint(x: (topX + validLeft) * nativeScale,
                                             y: (topY + validTop)  * nativeScale),
                          ciContext: ciContext)
                x += stepX
            }
            y += stepY
        }

        // Resize native → target.
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

    private func infer(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let input = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)])
        let out = try model.prediction(from: input)
        guard let buf = out.featureValue(for: outputName)?.imageBufferValue else {
            throw NSError(domain: "CoreMLUpscaler", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Model produced no output frame."])
        }
        return buf
    }

    private static func makePixelBuffer(_ w: Int, _ h: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess else { return nil }
        return pb
    }

    private static func draw(_ cg: CGImage, into buffer: CVPixelBuffer, ciContext: CIContext) {
        // Render a CGImage into an exact-size buffer at top-left origin.
        let img = CIImage(cgImage: cg)
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        // CIImage(cgImage:) is already top-left oriented for CIContext.render bounds below.
        ciContext.render(img, to: buffer, bounds: CGRect(x: 0, y: 0, width: w, height: h), colorSpace: nil)
    }

    private static func blit(_ src: CVPixelBuffer, srcRect: CGRect,
                             into dst: CVPixelBuffer, dstOrigin: CGPoint, ciContext: CIContext) {
        guard srcRect.width > 0, srcRect.height > 0 else { return }
        let srcImg = CIImage(cvPixelBuffer: src)
        let dstH = CGFloat(CVPixelBufferGetHeight(dst))
        // Convert top-left coords to CIImage (bottom-left) space for the destination render bounds.
        let cropped = srcImg.cropped(to: CGRect(
            x: srcRect.origin.x,
            y: CGFloat(CVPixelBufferGetHeight(src)) - srcRect.origin.y - srcRect.height,
            width: srcRect.width, height: srcRect.height))
        let dy = dstH - dstOrigin.y - srcRect.height
        let placed = cropped.transformed(by: CGAffineTransform(
            translationX: dstOrigin.x - srcRect.origin.x,
            y: dy - (CGFloat(CVPixelBufferGetHeight(src)) - srcRect.origin.y - srcRect.height)))
        ciContext.render(placed, to: dst,
                         bounds: CGRect(x: dstOrigin.x, y: dy, width: srcRect.width, height: srcRect.height),
                         colorSpace: nil)
    }
}
