import Foundation
import Metal
import CoreML
import CoreImage
import CoreGraphics
import CoreVideo

enum A4KComputeBackend: String, Sendable, CaseIterable {
    case metal = "metal"
    case mps = "mps"
    case coreML = "coreml"

    var enablesMPSConvolution: Bool {
        self == .mps
    }

    static func parse(_ raw: String?) -> A4KComputeBackend? {
        guard let raw else { return nil }

        switch raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") {
        case "metal":
            return .metal
        case "mps", "mpsconvolution":
            return .mps
        case "coreml", "ane", "neural", "neuralengine":
            return .coreML
        default:
            return nil
        }
    }

    static func resolve(from env: [String: String]) -> A4KComputeBackend {
        if let parsed = parse(env["A4K_COMPUTE_BACKEND"]) {
            return parsed
        }

        if let parsed = parse(env["A4K_BENCH_BACKEND"]) {
            return parsed
        }

        return env["A4K_ENABLE_MPS_CONV"] == "1" ? .mps : .metal
    }
}

final class A4KCoreMLBackend {
    enum ComputeUnits: String, Sendable {
        case all = "all"
        case cpuOnly = "cpu"
        case cpuAndGPU = "cpugpu"
        case cpuAndANE = "cpuane"

        static func parse(_ raw: String?) -> ComputeUnits {
            guard let raw else { return .all }

            switch raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "") {
            case "cpu":
                return .cpuOnly
            case "cpugpu":
                return .cpuAndGPU
            case "cpuane", "ane", "neural", "neuralengine":
                return .cpuAndANE
            default:
                return .all
            }
        }
    }

    enum CoreMLError: LocalizedError {
        case unavailable(String)
        case unsupportedStage(String)
        case runtimeFailure(String)

        var errorDescription: String? {
            switch self {
            case let .unavailable(reason):
                return "Core ML backend unavailable: \(reason)"
            case let .unsupportedStage(stage):
                return "Core ML stage unsupported: \(stage)"
            case let .runtimeFailure(reason):
                return "Core ML execution failed: \(reason)"
            }
        }
    }

    private let coreMLEnabled: Bool
    private let modelPath: String?
    private let computeUnits: ComputeUnits
    private let inputFeatureNameOverride: String?
    private let outputFeatureNameOverride: String?
    private let diagnosticsEnabled: Bool
    private let ciContext: CIContext
    private let colorSpace: CGColorSpace

    private var model: MLModel?
    private var loadedModelPath: String?
    private var modelInputFeatureName: String?
    private var modelOutputFeatureName: String?
    private var modelInputConstraint: MLImageConstraint?
    private var modelInputPixelFormat: OSType?

    init(env: [String: String]) {
        coreMLEnabled = env["A4K_COREML_ENABLE"] == "1"
        modelPath = env["A4K_COREML_MODEL_PATH"]
        computeUnits = ComputeUnits.parse(env["A4K_COREML_COMPUTE_UNITS"])
        inputFeatureNameOverride = env["A4K_COREML_INPUT_NAME"]
        outputFeatureNameOverride = env["A4K_COREML_OUTPUT_NAME"]
        diagnosticsEnabled = env["A4K_COREML_DIAG"] == "1"
        ciContext = CIContext(options: nil)
        colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    func loadIfAvailable() -> Bool {
        guard coreMLEnabled else {
            NSLog("[A4KCoreML] Disabled (set A4K_COREML_ENABLE=1 to enable scaffold)")
            return false
        }

        guard let modelPath,
              !modelPath.isEmpty,
              FileManager.default.fileExists(atPath: modelPath) else {
            NSLog("[A4KCoreML] Model path missing or invalid (A4K_COREML_MODEL_PATH)")
            return false
        }

        guard loadModelIfNeeded(from: modelPath) else {
            return false
        }

        NSLog("[A4KCoreML] Enabled modelPath=%@ computeUnits=%@ input=%@ output=%@",
              modelPath,
              computeUnits.rawValue,
              modelInputFeatureName ?? "<unknown>",
              modelOutputFeatureName ?? "<unknown>")
        return true
    }

    func supportsStage(_ stageName: String) -> Bool {
        // First rollout target: a single heavy stage hook.
        stageName == "Anime4K_Restore_CNN_VL"
    }

    func processStage(commandBuffer: MTLCommandBuffer,
                      inputTexture: MTLTexture,
                      stageName: String,
                      targetOutputWidth: Int,
                      targetOutputHeight: Int) throws -> MTLTexture? {
        _ = commandBuffer

        guard supportsStage(stageName) else {
            throw CoreMLError.unsupportedStage(stageName)
        }

        guard let model,
              let inputFeatureName = modelInputFeatureName,
              let outputFeatureName = modelOutputFeatureName else {
            throw CoreMLError.unavailable("model metadata not loaded")
        }

        let expectedInputWidth = max(1, modelInputConstraint?.pixelsWide ?? inputTexture.width)
        let expectedInputHeight = max(1, modelInputConstraint?.pixelsHigh ?? inputTexture.height)

        guard let inputPixelBuffer = makePixelBuffer(width: expectedInputWidth,
                                                     height: expectedInputHeight) else {
            throw CoreMLError.runtimeFailure("failed to allocate input pixel buffer")
        }

        let convertInStart = Self.nowMs()
        guard fill(pixelBuffer: inputPixelBuffer,
                   from: inputTexture,
                   outputWidth: expectedInputWidth,
                   outputHeight: expectedInputHeight) else {
            throw CoreMLError.runtimeFailure("failed to convert input texture to pixel buffer")
        }
        let convertInMs = Self.nowMs() - convertInStart

        let providerStart = Self.nowMs()
        let inputValue = MLFeatureValue(pixelBuffer: inputPixelBuffer)
        let provider: MLDictionaryFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [inputFeatureName: inputValue])
        } catch {
            throw CoreMLError.runtimeFailure("failed to build feature provider: \(error.localizedDescription)")
        }
        let providerMs = Self.nowMs() - providerStart

        let predictionStart = Self.nowMs()
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            throw CoreMLError.runtimeFailure("prediction failed: \(error.localizedDescription)")
        }
        let predictionMs = Self.nowMs() - predictionStart

        guard let outputFeature = prediction.featureValue(for: outputFeatureName),
              let outputPixelBuffer = outputFeature.imageBufferValue else {
            throw CoreMLError.runtimeFailure("missing image output feature '\(outputFeatureName)'")
        }

        let convertOutStart = Self.nowMs()
        guard let outputTexture = makeTexture(from: outputPixelBuffer,
                                              on: inputTexture.device) else {
            throw CoreMLError.runtimeFailure("failed to convert model output to texture")
        }
        let convertOutMs = Self.nowMs() - convertOutStart

        if diagnosticsEnabled {
            NSLog("[A4KCoreML] stage=%@ input=%dx%d modelInput=%dx%d modelOutput=%dx%d target=%dx%d timings(in/provider/predict/out)=%.2f/%.2f/%.2f/%.2fms",
                  stageName,
                  inputTexture.width,
                  inputTexture.height,
                  expectedInputWidth,
                  expectedInputHeight,
                  outputTexture.width,
                  outputTexture.height,
                  targetOutputWidth,
                  targetOutputHeight,
                  convertInMs,
                  providerMs,
                  predictionMs,
                  convertOutMs)
        }

        return outputTexture
    }

    private func loadModelIfNeeded(from path: String) -> Bool {
        if loadedModelPath == path,
           model != nil,
           modelInputFeatureName != nil,
           modelOutputFeatureName != nil {
            return true
        }

        let sourceURL = URL(fileURLWithPath: path)
        let modelURL: URL
        do {
            if sourceURL.pathExtension.lowercased() == "mlmodel" {
                modelURL = try MLModel.compileModel(at: sourceURL)
            } else {
                modelURL = sourceURL
            }
        } catch {
            NSLog("[A4KCoreML] Failed to compile model %@: %@",
                  path,
                  error.localizedDescription)
            return false
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = mapComputeUnits(computeUnits)

        let loadedModel: MLModel
        do {
            loadedModel = try MLModel(contentsOf: modelURL, configuration: configuration)
        } catch {
            NSLog("[A4KCoreML] Failed to load model %@: %@",
                  modelURL.path,
                  error.localizedDescription)
            return false
        }

        guard let inputName = resolveInputFeatureName(for: loadedModel),
              let outputName = resolveOutputFeatureName(for: loadedModel) else {
            NSLog("[A4KCoreML] Could not resolve image input/output feature names")
            return false
        }

        model = loadedModel
        loadedModelPath = path
        modelInputFeatureName = inputName
        modelOutputFeatureName = outputName
        modelInputConstraint = loadedModel.modelDescription.inputDescriptionsByName[inputName]?.imageConstraint
        modelInputPixelFormat = modelInputConstraint?.pixelFormatType

        if diagnosticsEnabled {
            let inConstraint = loadedModel.modelDescription.inputDescriptionsByName[inputName]?.imageConstraint
            let outConstraint = loadedModel.modelDescription.outputDescriptionsByName[outputName]?.imageConstraint
            NSLog("[A4KCoreML] modelLoaded input=%@ (%dx%d) output=%@ (%dx%d) units=%@",
                  inputName,
                  inConstraint?.pixelsWide ?? -1,
                  inConstraint?.pixelsHigh ?? -1,
                  outputName,
                  outConstraint?.pixelsWide ?? -1,
                  outConstraint?.pixelsHigh ?? -1,
                  computeUnits.rawValue)
        }

        return true
    }

    private func mapComputeUnits(_ units: ComputeUnits) -> MLComputeUnits {
        switch units {
        case .all:
            return .all
        case .cpuOnly:
            return .cpuOnly
        case .cpuAndGPU:
            return .cpuAndGPU
        case .cpuAndANE:
            return .cpuAndNeuralEngine
        }
    }

    private func resolveInputFeatureName(for model: MLModel) -> String? {
        let descriptions = model.modelDescription.inputDescriptionsByName

        if let inputFeatureNameOverride,
           !inputFeatureNameOverride.isEmpty,
           descriptions[inputFeatureNameOverride] != nil {
            return inputFeatureNameOverride
        }

        for key in descriptions.keys.sorted() {
            if descriptions[key]?.type == .image {
                return key
            }
        }

        return descriptions.keys.sorted().first
    }

    private func resolveOutputFeatureName(for model: MLModel) -> String? {
        let descriptions = model.modelDescription.outputDescriptionsByName

        if let outputFeatureNameOverride,
           !outputFeatureNameOverride.isEmpty,
           descriptions[outputFeatureNameOverride] != nil {
            return outputFeatureNameOverride
        }

        for key in descriptions.keys.sorted() {
            if descriptions[key]?.type == .image {
                return key
            }
        }

        return descriptions.keys.sorted().first
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let requestedPixelFormat = modelInputPixelFormat ?? kCVPixelFormatType_32BGRA
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         requestedPixelFormat,
                                         attrs as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }

    private func fill(pixelBuffer: CVPixelBuffer,
                      from texture: MTLTexture,
                      outputWidth: Int,
                      outputHeight: Int) -> Bool {
        if let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) {
            var image = ciImage
            if texture.width != outputWidth || texture.height != outputHeight {
                let scaleX = CGFloat(outputWidth) / CGFloat(texture.width)
                let scaleY = CGFloat(outputHeight) / CGFloat(texture.height)
                image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            }

            ciContext.render(image,
                             to: pixelBuffer,
                             bounds: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
                             colorSpace: colorSpace)
            return true
        }

        let supportsDirectCopy = (texture.pixelFormat == .bgra8Unorm ||
                                  texture.pixelFormat == .bgra8Unorm_srgb)
        guard supportsDirectCopy,
              texture.width == outputWidth,
              texture.height == outputHeight else {
            return false
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return false
        }

        texture.getBytes(base,
                         bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                         from: MTLRegionMake2D(0, 0, outputWidth, outputHeight),
                         mipmapLevel: 0)
        return true
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer,
                             on device: MTLDevice) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                  width: width,
                                                                  height: height,
                                                                  mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if pixelFormat == kCVPixelFormatType_32BGRA {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                return nil
            }

            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: base,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer))
            return texture
        }

        // Fallback conversion path for non-BGRA output formats.
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        ciContext.render(image,
                         to: texture,
                         commandBuffer: nil,
                         bounds: CGRect(x: 0, y: 0, width: width, height: height),
                         colorSpace: colorSpace)
        return texture
    }

    private static func nowMs() -> Double {
        CFAbsoluteTimeGetCurrent() * 1000.0
    }
}

/// Offline Anime4K processor for export workflows.
///
/// It runs the same translated runtime pass chain used in Glass Player, but on
/// raw BGRA frames supplied by FFmpeg decode and returned to FFmpeg encode.
final class Anime4KOfflineProcessor {
    enum ProcessorError: LocalizedError {
        case noDevice
        case noCommandQueue
        case missingMetalSource(String)
        case failedToReadMetalSource(String)
        case failedToCompileLibrary(String)
        case failedToCreateRuntimePipeline(String)
        case failedToCreateConverterPipeline
        case failedToCreateCommandBuffer
        case failedToCreateInputTexture
        case failedToCreateReadbackTexture
        case runtimeCompileFailed(String)
        case runtimeEncodeFailed(String)
        case failedToCreateConverterEncoder
        case failedToCreatePixelBufferTexture
        case commandBufferFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDevice:
                return "Metal device is unavailable"
            case .noCommandQueue:
                return "Failed to create Metal command queue"
            case let .missingMetalSource(path):
                return "Missing translated .metal source: \(path)"
            case let .failedToReadMetalSource(path):
                return "Failed to read translated .metal source: \(path)"
            case let .failedToCompileLibrary(path):
                return "Failed to compile Metal library for: \(path)"
            case let .failedToCreateRuntimePipeline(shader):
                return "Failed to create runtime pass pipeline: \(shader)"
            case .failedToCreateConverterPipeline:
                return "Failed to create conversion pipeline"
            case .failedToCreateCommandBuffer:
                return "Failed to create Metal command buffer"
            case .failedToCreateInputTexture:
                return "Failed to allocate input texture"
            case .failedToCreateReadbackTexture:
                return "Failed to allocate readback texture"
            case let .runtimeCompileFailed(shader):
                return "Failed to compile runtime stage: \(shader)"
            case let .runtimeEncodeFailed(shader):
                return "Failed to encode runtime stage: \(shader)"
            case .failedToCreateConverterEncoder:
                return "Failed to create converter encoder"
            case .failedToCreatePixelBufferTexture:
                return "Failed to create Metal texture from decoded pixel buffer"
            case let .commandBufferFailed(detail):
                return "Metal command buffer failed: \(detail)"
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let converterPipeline: MTLComputePipelineState
    private let converterTargetThreadgroupThreads: Int
    private let targetOutputScale: Float
    private let stageNames: [String]
    private let forceTexelCenterCoordinates: Bool
    private let perfStatsEnabled: Bool
    private let perfLogInterval: Int
    private let noReadbackInflightDepth: Int

    let requestedBackend: A4KComputeBackend
    private(set) var activeBackend: A4KComputeBackend

    private var filePipelines: [A4KFilePipeline] = []
    private var inputTexture: MTLTexture?
    private var readbackTexture: MTLTexture?
    private var cvTextureCache: CVMetalTextureCache?
    private var coreMLBackend: A4KCoreMLBackend?
    private var pendingNoReadbackBuffers: [MTLCommandBuffer] = []
    private let pendingNoReadbackLock = NSLock()

    private struct StagePerfStats {
        var compileCheckTotalMs: Double = 0
        var encodeTotalMs: Double = 0
        var maxCompileCheckMs: Double = 0
        var maxEncodeMs: Double = 0
        var samples: Int = 0

        mutating func add(compileCheckMs: Double, encodeMs: Double) {
            compileCheckTotalMs += compileCheckMs
            encodeTotalMs += encodeMs
            maxCompileCheckMs = max(maxCompileCheckMs, compileCheckMs)
            maxEncodeMs = max(maxEncodeMs, encodeMs)
            samples += 1
        }

        var avgCompileCheckMs: Double {
            guard samples > 0 else { return 0 }
            return compileCheckTotalMs / Double(samples)
        }

        var avgEncodeMs: Double {
            guard samples > 0 else { return 0 }
            return encodeTotalMs / Double(samples)
        }
    }

    private var perfFrameCount: Int = 0
    private var stagePerfStats: [String: StagePerfStats] = [:]

    init(
        shaderFileNames: [String],
        targetOutputScale: Float,
        metalSourceDirectoryPath: String,
        computeBackend: A4KComputeBackend? = nil
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ProcessorError.noDevice
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw ProcessorError.noCommandQueue
        }
        self.commandQueue = queue
        self.targetOutputScale = max(1.0, targetOutputScale)
        self.stageNames = shaderFileNames
        self.forceTexelCenterCoordinates = ProcessInfo.processInfo.environment["A4K_FORCE_TEXEL_CENTER"] == "1"

        let env = ProcessInfo.processInfo.environment
        self.perfStatsEnabled = env["A4K_PERF_STATS"] == "1"
        let rawPerfInterval = Int(env["A4K_PERF_LOG_INTERVAL"] ?? "120") ?? 120
        self.perfLogInterval = max(30, rawPerfInterval)
        let rawConverterThreads = Int(env["A4K_CONVERTER_TG_THREADS"] ?? "512") ?? 512
        self.converterTargetThreadgroupThreads = max(64, min(1024, rawConverterThreads))
        let rawNoReadbackInflight = Int(env["A4K_NO_READBACK_INFLIGHT"] ?? env["A4K_BENCH_GPU_INFLIGHT"] ?? "1") ?? 1
        self.noReadbackInflightDepth = max(1, min(8, rawNoReadbackInflight))
        self.requestedBackend = computeBackend ?? A4KComputeBackend.resolve(from: env)

        if requestedBackend == .coreML {
            let scaffold = A4KCoreMLBackend(env: env)
            if scaffold.loadIfAvailable() {
                self.activeBackend = .coreML
                self.coreMLBackend = scaffold
            } else {
                self.activeBackend = .metal
                self.coreMLBackend = nil
                NSLog("[Anime4KOffline] Core ML backend unavailable. Falling back to %@.",
                      activeBackend.rawValue)
            }
        } else {
            self.activeBackend = requestedBackend
            self.coreMLBackend = nil
        }

        setenv("A4K_ENABLE_MPS_CONV", activeBackend.enablesMPSConvolution ? "1" : "0", 1)
        NSLog("[Anime4KOffline] backend requested=%@ active=%@", requestedBackend.rawValue, activeBackend.rawValue)
        if perfStatsEnabled {
            NSLog("[A4KPerf] Enabled stage timing (logInterval=%d)", perfLogInterval)
        }
        if noReadbackInflightDepth > 1 {
            NSLog("[Anime4KOffline] No-readback inflight depth=%d", noReadbackInflightDepth)
        }

        let converterLibrary = try device.makeLibrary(source: Self.converterSource, options: nil)
        guard let converterFn = converterLibrary.makeFunction(name: "a4kConvertToBGRA8") else {
            throw ProcessorError.failedToCreateConverterPipeline
        }
        self.converterPipeline = try device.makeComputePipelineState(function: converterFn)

        for shaderFile in shaderFileNames {
            let shaderPath = (metalSourceDirectoryPath as NSString).appendingPathComponent("\(shaderFile).metal")
            guard FileManager.default.fileExists(atPath: shaderPath) else {
                throw ProcessorError.missingMetalSource(shaderPath)
            }

            guard var source = try? String(contentsOfFile: shaderPath, encoding: .utf8) else {
                throw ProcessorError.failedToReadMetalSource(shaderPath)
            }

            if forceTexelCenterCoordinates {
                source = Self.normalizeTexelCenterCoordinates(in: source)
            }

            let library: MTLLibrary
            do {
                library = try device.makeLibrary(source: source, options: nil)
            } catch {
                throw ProcessorError.failedToCompileLibrary(shaderPath)
            }

            guard let runtime = A4KFilePipeline(
                shaderFileName: shaderFile,
                metalSource: source,
                targetOutputScale: self.targetOutputScale,
                device: device,
                library: library
            ) else {
                throw ProcessorError.failedToCreateRuntimePipeline(shaderFile)
            }

            filePipelines.append(runtime)
        }
    }

    func processFrame(
        inputFrame: Data,
        inputWidth: Int,
        inputHeight: Int,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int,
        outputFrame: inout Data
    ) throws -> (width: Int, height: Int) {
        try waitForIdle()

        return try processFrameInternal(
            inputFrame: inputFrame,
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            targetOutputWidth: targetOutputWidth,
            targetOutputHeight: targetOutputHeight,
            outputFrame: &outputFrame,
            includeReadback: true
        )
    }

    /// Processes one frame but keeps the final result on GPU.
    ///
    /// Use this for throughput benchmarks where only frame timing matters and
    /// no per-frame CPU copy is required.
    func processFrameNoReadback(
        inputFrame: Data,
        inputWidth: Int,
        inputHeight: Int,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int
    ) throws -> (width: Int, height: Int) {
        var unused = Data()
        return try processFrameInternal(
            inputFrame: inputFrame,
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            targetOutputWidth: targetOutputWidth,
            targetOutputHeight: targetOutputHeight,
            outputFrame: &unused,
            includeReadback: false
        )
    }

    /// Processes a decoded CVPixelBuffer frame.
    ///
    /// This keeps decode output on GPU by binding a Metal texture directly
    /// via CVMetalTextureCache and avoids a CPU memcpy upload step.
    func processPixelBuffer(
        pixelBuffer: CVPixelBuffer,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int,
        outputFrame: inout Data
    ) throws -> (width: Int, height: Int) {
        try waitForIdle()

        return try processPixelBufferInternal(
            pixelBuffer: pixelBuffer,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            targetOutputWidth: targetOutputWidth,
            targetOutputHeight: targetOutputHeight,
            outputFrame: &outputFrame,
            includeReadback: true
        )
    }

    /// Uploads a BGRA frame once and returns a reusable input texture.
    ///
    /// This is useful for benchmark loops that replay a small frame set and
    /// want to avoid repeated CPU->GPU upload work.
    func makeBGRAInputTexture(frameData: Data,
                              width: Int,
                              height: Int) throws -> MTLTexture {
        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        stagingDescriptor.storageMode = .shared
        stagingDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            throw ProcessorError.failedToCreateInputTexture
        }

        frameData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            stagingTexture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }

        let gpuDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        gpuDescriptor.storageMode = .private
        gpuDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let gpuTexture = device.makeTexture(descriptor: gpuDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw ProcessorError.failedToCreateInputTexture
        }

        blit.copy(from: stagingTexture,
                  sourceSlice: 0,
                  sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: gpuTexture,
                  destinationSlice: 0,
                  destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            let detail = commandBuffer.error?.localizedDescription ?? "unknown"
            throw ProcessorError.commandBufferFailed(detail)
        }

        return gpuTexture
    }

    /// Processes a previously uploaded BGRA texture and keeps output on GPU.
    func processTextureNoReadback(
        inputTexture: MTLTexture,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int
    ) throws -> (width: Int, height: Int) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProcessorError.failedToCreateCommandBuffer
        }

        let currentTexture = try encodeRuntimeStages(
            commandBuffer: commandBuffer,
            inputTexture: inputTexture,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            targetOutputWidth: targetOutputWidth,
            targetOutputHeight: targetOutputHeight
        )

        commandBuffer.commit()
        try enqueueNoReadbackCommandBuffer(commandBuffer)

        return (currentTexture.width, currentTexture.height)
    }

    /// Waits for any pending no-readback GPU work submitted by this processor.
    func waitForIdle() throws {
        let pending: [MTLCommandBuffer]
        pendingNoReadbackLock.lock()
        pending = pendingNoReadbackBuffers
        pendingNoReadbackBuffers.removeAll(keepingCapacity: true)
        pendingNoReadbackLock.unlock()

        for commandBuffer in pending {
            commandBuffer.waitUntilCompleted()
            try validateCompletedCommandBuffer(commandBuffer)
        }
    }

    private func processFrameInternal(
        inputFrame: Data,
        inputWidth: Int,
        inputHeight: Int,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int,
        outputFrame: inout Data,
        includeReadback: Bool
    ) throws -> (width: Int, height: Int) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProcessorError.failedToCreateCommandBuffer
        }

        guard let inputTexture = ensureInputTexture(width: inputWidth, height: inputHeight) else {
            throw ProcessorError.failedToCreateInputTexture
        }

        inputFrame.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            inputTexture.replace(
                region: MTLRegionMake2D(0, 0, inputWidth, inputHeight),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: inputWidth * 4
            )
        }

        let currentTexture = try encodeRuntimeStages(
            commandBuffer: commandBuffer,
            inputTexture: inputTexture,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            targetOutputWidth: targetOutputWidth,
            targetOutputHeight: targetOutputHeight
        )

        if !includeReadback {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            if commandBuffer.status == .error {
                let detail = commandBuffer.error?.localizedDescription ?? "unknown"
                throw ProcessorError.commandBufferFailed(detail)
            }

            return (currentTexture.width, currentTexture.height)
        }

        guard let readbackTexture = ensureReadbackTexture(width: currentTexture.width, height: currentTexture.height) else {
            throw ProcessorError.failedToCreateReadbackTexture
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessorError.failedToCreateConverterEncoder
        }

        encoder.setComputePipelineState(converterPipeline)
        encoder.setTexture(currentTexture, index: 0)
        encoder.setTexture(readbackTexture, index: 1)

        let grid = MTLSize(width: currentTexture.width, height: currentTexture.height, depth: 1)
        let tgWidth = max(1, converterPipeline.threadExecutionWidth)
        let maxHeight = max(1, converterPipeline.maxTotalThreadsPerThreadgroup / tgWidth)
        let preferredHeight = max(1, converterTargetThreadgroupThreads / tgWidth)
        let tgHeight = min(maxHeight, preferredHeight)
        let tpg = MTLSize(width: tgWidth, height: tgHeight, depth: 1)

        encoder.dispatchThreads(grid, threadsPerThreadgroup: tpg)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            let detail = commandBuffer.error?.localizedDescription ?? "unknown"
            throw ProcessorError.commandBufferFailed(detail)
        }

        let outBytesPerRow = currentTexture.width * 4
        let outBytes = outBytesPerRow * currentTexture.height
        if outputFrame.count != outBytes {
            outputFrame = Data(count: outBytes)
        }

        outputFrame.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            readbackTexture.getBytes(
                base,
                bytesPerRow: outBytesPerRow,
                from: MTLRegionMake2D(0, 0, currentTexture.width, currentTexture.height),
                mipmapLevel: 0
            )
        }

        return (currentTexture.width, currentTexture.height)
    }

    private func processPixelBufferInternal(
        pixelBuffer: CVPixelBuffer,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int,
        outputFrame: inout Data,
        includeReadback: Bool
    ) throws -> (width: Int, height: Int) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ProcessorError.failedToCreateCommandBuffer
        }

        guard let inputTexture = makeTexture(from: pixelBuffer) else {
            throw ProcessorError.failedToCreatePixelBufferTexture
        }

        let currentTexture = try encodeRuntimeStages(
            commandBuffer: commandBuffer,
            inputTexture: inputTexture,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight,
            targetOutputWidth: targetOutputWidth,
            targetOutputHeight: targetOutputHeight
        )

        if !includeReadback {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            if commandBuffer.status == .error {
                let detail = commandBuffer.error?.localizedDescription ?? "unknown"
                throw ProcessorError.commandBufferFailed(detail)
            }

            return (currentTexture.width, currentTexture.height)
        }

        guard let readbackTexture = ensureReadbackTexture(width: currentTexture.width, height: currentTexture.height) else {
            throw ProcessorError.failedToCreateReadbackTexture
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ProcessorError.failedToCreateConverterEncoder
        }

        encoder.setComputePipelineState(converterPipeline)
        encoder.setTexture(currentTexture, index: 0)
        encoder.setTexture(readbackTexture, index: 1)

        let grid = MTLSize(width: currentTexture.width, height: currentTexture.height, depth: 1)
        let tgWidth = max(1, converterPipeline.threadExecutionWidth)
        let maxHeight = max(1, converterPipeline.maxTotalThreadsPerThreadgroup / tgWidth)
        let preferredHeight = max(1, converterTargetThreadgroupThreads / tgWidth)
        let tgHeight = min(maxHeight, preferredHeight)
        let tpg = MTLSize(width: tgWidth, height: tgHeight, depth: 1)

        encoder.dispatchThreads(grid, threadsPerThreadgroup: tpg)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            let detail = commandBuffer.error?.localizedDescription ?? "unknown"
            throw ProcessorError.commandBufferFailed(detail)
        }

        let outBytesPerRow = currentTexture.width * 4
        let outBytes = outBytesPerRow * currentTexture.height
        if outputFrame.count != outBytes {
            outputFrame = Data(count: outBytes)
        }

        outputFrame.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            readbackTexture.getBytes(
                base,
                bytesPerRow: outBytesPerRow,
                from: MTLRegionMake2D(0, 0, currentTexture.width, currentTexture.height),
                mipmapLevel: 0
            )
        }

        return (currentTexture.width, currentTexture.height)
    }

    private func encodeRuntimeStages(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        nativeWidth: Int,
        nativeHeight: Int,
        targetOutputWidth: Int,
        targetOutputHeight: Int
    ) throws -> MTLTexture {
        var currentTexture: MTLTexture = inputTexture

        for (idx, filePipeline) in filePipelines.enumerated() {
            let stageName = stageNames[idx]

            if activeBackend == .coreML,
               let coreMLBackend,
               coreMLBackend.supportsStage(stageName) {
                do {
                    if let coreMLOutput = try coreMLBackend.processStage(
                        commandBuffer: commandBuffer,
                        inputTexture: currentTexture,
                        stageName: stageName,
                        targetOutputWidth: targetOutputWidth,
                        targetOutputHeight: targetOutputHeight
                    ) {
                        currentTexture = coreMLOutput
                        continue
                    }
                } catch {
                    // Safe fallback path: disable scaffold and continue on Metal.
                    activeBackend = .metal
                    self.coreMLBackend = nil
                    setenv("A4K_ENABLE_MPS_CONV", "0", 1)
                    NSLog("[Anime4KOffline] Core ML stage failed for %@ (%@). Falling back to Metal.",
                          stageName,
                          error.localizedDescription)
                }
            }

            filePipeline.updateFrameContext(
                nativeWidth: nativeWidth,
                nativeHeight: nativeHeight,
                targetOutputWidth: targetOutputWidth,
                targetOutputHeight: targetOutputHeight
            )

            let compileCheckStartMs = perfStatsEnabled ? Self.nowMs() : 0

            guard filePipeline.recompileIfNeeded(
                inputWidth: currentTexture.width,
                inputHeight: currentTexture.height
            ) else {
                throw ProcessorError.runtimeCompileFailed(stageName)
            }

            let compileCheckMs = perfStatsEnabled ? (Self.nowMs() - compileCheckStartMs) : 0
            let encodeStartMs = perfStatsEnabled ? Self.nowMs() : 0

            guard let processed = filePipeline.encode(commandBuffer: commandBuffer, input: currentTexture) else {
                throw ProcessorError.runtimeEncodeFailed(stageName)
            }

            currentTexture = processed

            if perfStatsEnabled {
                let encodeMs = Self.nowMs() - encodeStartMs
                recordStagePerf(stageName: stageName,
                                compileCheckMs: compileCheckMs,
                                encodeMs: encodeMs)
            }
        }

        if perfStatsEnabled {
            perfFrameCount += 1
            maybeLogPerfSummary(inputWidth: inputTexture.width,
                                inputHeight: inputTexture.height,
                                outputWidth: currentTexture.width,
                                outputHeight: currentTexture.height)
        }

        return currentTexture
    }

    private func recordStagePerf(stageName: String,
                                 compileCheckMs: Double,
                                 encodeMs: Double) {
        var stats = stagePerfStats[stageName] ?? StagePerfStats()
        stats.add(compileCheckMs: compileCheckMs, encodeMs: encodeMs)
        stagePerfStats[stageName] = stats
    }

    private func maybeLogPerfSummary(inputWidth: Int,
                                     inputHeight: Int,
                                     outputWidth: Int,
                                     outputHeight: Int) {
        guard perfFrameCount > 0,
              perfFrameCount % perfLogInterval == 0 else {
            return
        }

        for stageName in stageNames {
            guard let stats = stagePerfStats[stageName], stats.samples > 0 else {
                continue
            }

            NSLog("[A4KPerf] frame=%d backend=%@ stage=%@ compileCheck(avg/max)=%.3f/%.3fms encode(avg/max)=%.3f/%.3fms samples=%d input=%dx%d output=%dx%d",
                  perfFrameCount,
                  activeBackend.rawValue,
                  stageName,
                  stats.avgCompileCheckMs,
                  stats.maxCompileCheckMs,
                  stats.avgEncodeMs,
                  stats.maxEncodeMs,
                  stats.samples,
                  inputWidth,
                  inputHeight,
                  outputWidth,
                  outputHeight)
        }
    }

    private static func nowMs() -> Double {
        CFAbsoluteTimeGetCurrent() * 1000.0
    }

    private func enqueueNoReadbackCommandBuffer(_ commandBuffer: MTLCommandBuffer) throws {
        guard noReadbackInflightDepth > 1 else {
            commandBuffer.waitUntilCompleted()
            try validateCompletedCommandBuffer(commandBuffer)
            return
        }

        var oldestBuffer: MTLCommandBuffer?
        pendingNoReadbackLock.lock()
        pendingNoReadbackBuffers.append(commandBuffer)
        if pendingNoReadbackBuffers.count >= noReadbackInflightDepth {
            oldestBuffer = pendingNoReadbackBuffers.removeFirst()
        }
        pendingNoReadbackLock.unlock()

        if let oldestBuffer {
            oldestBuffer.waitUntilCompleted()
            try validateCompletedCommandBuffer(oldestBuffer)
        }
    }

    private func validateCompletedCommandBuffer(_ commandBuffer: MTLCommandBuffer) throws {
        if commandBuffer.status == .error {
            let detail = commandBuffer.error?.localizedDescription ?? "unknown"
            throw ProcessorError.commandBufferFailed(detail)
        }
    }

    private func ensureInputTexture(width: Int, height: Int) -> MTLTexture? {
        if let existing = inputTexture,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == .bgra8Unorm {
            return existing
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead, .shaderWrite]

        inputTexture = device.makeTexture(descriptor: desc)
        return inputTexture
    }

    private func ensureReadbackTexture(width: Int, height: Int) -> MTLTexture? {
        if let existing = readbackTexture,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == .bgra8Unorm {
            return existing
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead, .shaderWrite]

        readbackTexture = device.makeTexture(descriptor: desc)
        return readbackTexture
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_32BGRA else {
            return nil
        }

        guard let textureCache = ensureCVTextureCache() else {
            return nil
        }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }

        return texture
    }

    private func ensureCVTextureCache() -> CVMetalTextureCache? {
        if let existing = cvTextureCache {
            return existing
        }

        var created: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &created)
        guard status == kCVReturnSuccess, let created else {
            return nil
        }

        cvTextureCache = created
        return created
    }

    private static let converterSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void a4kConvertToBGRA8(texture2d<float, access::read> inputTex [[texture(0)]],
                                  texture2d<float, access::write> outputTex [[texture(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outputTex.get_width() || gid.y >= outputTex.get_height()) {
            return;
        }

        float4 color = clamp(inputTex.read(gid), 0.0, 1.0);
        outputTex.write(color, gid);
    }
    """

    private static func normalizeTexelCenterCoordinates(in source: String) -> String {
        var normalized = source
        normalized = normalized.replacingOccurrences(
            of: "float2 outScale = 1.0 / (outSize - float2(1.0, 1.0));",
            with: "float2 outScale = 1.0 / outSize;"
        )
        normalized = normalized.replacingOccurrences(
            of: "float2 mtlPos = float2(gid) * outScale;",
            with: "float2 mtlPos = (float2(gid) + float2(0.5, 0.5)) * outScale;"
        )
        return normalized
    }
}
