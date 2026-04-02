import Foundation
import CoreML
import Vision
import CoreGraphics

struct Phase4BenchConfig {
    let inputURL: URL
    let maxFrames: Int
    let preloadFrames: Int
    let outputScale: Int
    let workerCount: Int
    let backend: A4KComputeBackend
    let useNeuralAssist: Bool
    let ffmpegURL: URL
    let ffprobeURL: URL
    let metalSourceDirectoryPath: String

    var useMPS: Bool {
        backend == .mps
    }

    init(arguments: [String], env: [String: String]) throws {
        guard arguments.count >= 2 else {
            throw BenchError.invalidArguments("usage: phase4_aahq_benchmark <input-video> [max-frames]")
        }

        inputURL = URL(fileURLWithPath: arguments[1])
        maxFrames = max(1, arguments.count >= 3 ? (Int(arguments[2]) ?? 240) : 240)
        preloadFrames = max(1, min(maxFrames, Int(env["A4K_BENCH_PRELOAD_FRAMES"] ?? "12") ?? 12))
        outputScale = max(1, Int(env["A4K_BENCH_OUTPUT_SCALE"] ?? "2") ?? 2)

        let explicitBackend = A4KComputeBackend.parse(env["A4K_BENCH_BACKEND"])
        let legacyUseMPS = (env["A4K_BENCH_USE_MPS"] ?? "1") != "0"
        backend = explicitBackend ?? (legacyUseMPS ? .mps : .metal)
        useNeuralAssist = (env["A4K_BENCH_USE_NEURAL_ASSIST"] ?? "1") != "0"
        let defaultWorkers = useNeuralAssist ? 3 : 1
        workerCount = max(1, min(8, Int(env["A4K_BENCH_WORKERS"] ?? "\(defaultWorkers)") ?? defaultWorkers))

        ffmpegURL = URL(fileURLWithPath: env["A4K_BENCH_FFMPEG"] ?? "/opt/homebrew/bin/ffmpeg")
        ffprobeURL = URL(fileURLWithPath: env["A4K_BENCH_FFPROBE"] ?? "/opt/homebrew/bin/ffprobe")

        let cwd = FileManager.default.currentDirectoryPath
        var candidates: [String] = []

        if let explicitMetalDir = env["A4K_BENCH_METAL_DIR"], !explicitMetalDir.isEmpty {
            candidates.append(explicitMetalDir)
        }

        candidates.append(contentsOf: [
            cwd + "/Anime4K-Upscaler/Resources/metal_sources",
            cwd + "/Anime4K-Upscalar-macOS/Anime4K-Upscaler/Resources/metal_sources",
            cwd + "/Resources/metal_sources",
            cwd + "/../Anime4K-Upscaler/Resources/metal_sources"
        ])

        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw BenchError.invalidArguments("Could not find metal_sources directory from cwd=\(cwd)")
        }
        metalSourceDirectoryPath = found
    }
}

enum BenchError: Error, LocalizedError {
    case invalidArguments(String)
    case toolFailed(String)
    case probeFailed(String)
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message): return message
        case let .toolFailed(message): return message
        case let .probeFailed(message): return message
        case let .processingFailed(message): return message
        }
    }
}

struct VideoProbe {
    let width: Int
    let height: Int
    let fps: Double
}

@main
struct Phase4AAHQBenchmarkMain {
    static func main() {
        do {
            let env = ProcessInfo.processInfo.environment
            let verbose = (env["A4K_BENCH_VERBOSE"] ?? "0") == "1"
            func stage(_ message: String) {
                guard verbose else { return }
                print("[bench] \(message)")
                fflush(stdout)
            }

            let config = try Phase4BenchConfig(arguments: CommandLine.arguments, env: env)
            stage("config parsed")

            if config.useNeuralAssist {
                let assist = NeuralAssistProbe()
                let result = assist.runProbe()
                print("NEURAL_ASSIST: \(result)")
            } else {
                print("NEURAL_ASSIST: disabled")
            }
            stage("neural assist probe complete")

            let probe = try probeVideo(inputURL: config.inputURL, ffprobeURL: config.ffprobeURL, env: env)
            print("INPUT: \(probe.width)x\(probe.height) @ \(String(format: "%.3f", probe.fps)) fps")
            print("MODE: A+A HQ, scale=\(config.outputScale)x")
            print("BACKEND: \(config.backend.rawValue)")
            print("MPS: \(config.useMPS ? "enabled" : "disabled")")
            print("WORKERS: \(config.workerCount)")
            print("PRELOAD_FRAMES: \(config.preloadFrames)")
            print("METRICS_CSV: \(env["A4K_BENCH_METRICS_CSV"] ?? "/tmp/a4k_phase4_metrics.csv")")
            stage("ffprobe complete")

            let shaders = [
                "Anime4K_Clamp_Highlights",
                "Anime4K_Restore_CNN_VL",
                "Anime4K_Upscale_CNN_x2_VL",
                "Anime4K_Restore_CNN_M",
                "Anime4K_Upscale_CNN_x2_M"
            ]

            stage("creating processors")
            let processors = try (0..<config.workerCount).map { _ in
                try Anime4KOfflineProcessor(
                    shaderFileNames: shaders,
                    targetOutputScale: Float(config.outputScale),
                    metalSourceDirectoryPath: config.metalSourceDirectoryPath,
                    computeBackend: config.backend
                )
            }
            let workerQueues = (0..<config.workerCount).map {
                DispatchQueue(label: "a4k.bench.worker.\($0)", qos: .userInitiated)
            }
            stage("processors created")

            let inputBytesPerFrame = probe.width * probe.height * 4
            let outputWidth = max(1, probe.width * config.outputScale)
            let outputHeight = max(1, probe.height * config.outputScale)
            let outputByteCount = max(1, outputWidth * outputHeight * 4)

            let decode = Process()
            decode.executableURL = config.ffmpegURL
            decode.arguments = [
                "-hide_banner", "-loglevel", "error", "-nostdin",
                "-i", config.inputURL.path,
                "-map", "0:v:0", "-an", "-sn",
                "-vf", "format=bgra",
                "-frames:v", "\(config.preloadFrames)",
                "-f", "rawvideo", "-pix_fmt", "bgra", "pipe:1"
            ]
            decode.environment = env

            let decodeOutPipe = Pipe()
            decode.standardOutput = decodeOutPipe
            decode.standardError = Pipe()
            try decode.run()
            stage("decoder started")

            let decodeReadHandle = decodeOutPipe.fileHandleForReading
            var inputFrames: [Data] = []
            inputFrames.reserveCapacity(config.preloadFrames)

            while inputFrames.count < config.preloadFrames {
                guard let frameData = try readExactly(handle: decodeReadHandle, byteCount: inputBytesPerFrame) else {
                    break
                }
                if frameData.count != inputBytesPerFrame {
                    throw BenchError.processingFailed("Truncated preload frame from decoder (got \(frameData.count), expected \(inputBytesPerFrame)).")
                }
                inputFrames.append(frameData)
            }

            try? decodeReadHandle.close()
            if decode.isRunning {
                decode.terminate()
            }
            decode.waitUntilExit()

            guard !inputFrames.isEmpty else {
                throw BenchError.processingFailed("No decoded preload frames were produced.")
            }

            stage("uploading preload textures")
            let workerInputTextures = try (0..<config.workerCount).map { workerIndex in
                try inputFrames.map { frameData in
                    try processors[workerIndex].makeBGRAInputTexture(
                        frameData: frameData,
                        width: probe.width,
                        height: probe.height
                    )
                }
            }

            let inflightSemaphore = DispatchSemaphore(value: config.workerCount)
            let processingGroup = DispatchGroup()
            let resultLock = NSLock()

            var processedFrames = 0
            var firstError: Error?

            let t0 = Date()
            for frameIndex in 0..<config.maxFrames {
                resultLock.lock()
                let hasError = (firstError != nil)
                resultLock.unlock()
                if hasError {
                    break
                }

                inflightSemaphore.wait()

                let workerIndex = frameIndex % config.workerCount
                let inputTexture = workerInputTextures[workerIndex][frameIndex % inputFrames.count]
                processingGroup.enter()

                workerQueues[workerIndex].async {
                    defer {
                        inflightSemaphore.signal()
                        processingGroup.leave()
                    }

                    do {
                        _ = try processors[workerIndex].processTextureNoReadback(
                            inputTexture: inputTexture,
                            nativeWidth: probe.width,
                            nativeHeight: probe.height,
                            targetOutputWidth: outputWidth,
                            targetOutputHeight: outputHeight
                        )

                        resultLock.lock()
                        processedFrames += 1
                        resultLock.unlock()
                    } catch {
                        resultLock.lock()
                        if firstError == nil {
                            firstError = error
                        }
                        resultLock.unlock()
                    }
                }
            }

            processingGroup.wait()
            let elapsed = max(Date().timeIntervalSince(t0), 0.0001)

            if let firstError {
                throw BenchError.processingFailed(firstError.localizedDescription)
            }

            let fps = Double(processedFrames) / elapsed
            print("RESULT: frames=\(processedFrames) elapsed=\(String(format: "%.3f", elapsed))s fps=\(String(format: "%.3f", fps))")
            print("METRICS_ROW: backend=\(config.backend.rawValue),frames=\(processedFrames),elapsed_s=\(String(format: "%.6f", elapsed)),fps=\(String(format: "%.6f", fps)),workers=\(config.workerCount),preload_frames=\(config.preloadFrames),scale=\(config.outputScale),input=\(probe.width)x\(probe.height),output=\(outputWidth)x\(outputHeight)")
            stage("benchmark finished")

            if processedFrames > 0 {
                let artifactIndex = (processedFrames - 1) % inputFrames.count
                let artifactInput = inputFrames[artifactIndex]
                var artifactFrame = Data(count: outputByteCount)

                _ = try processors[0].processFrame(
                    inputFrame: artifactInput,
                    inputWidth: probe.width,
                    inputHeight: probe.height,
                    nativeWidth: probe.width,
                    nativeHeight: probe.height,
                    targetOutputWidth: outputWidth,
                    targetOutputHeight: outputHeight,
                    outputFrame: &artifactFrame
                )

                let outPath = "/tmp/a4k_phase4_bench_last_frame.raw"
                try artifactFrame.write(to: URL(fileURLWithPath: outPath), options: .atomic)
                print("ARTIFACT: \(outPath) \(outputWidth)x\(outputHeight) bgra")
            }
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func probeVideo(inputURL: URL,
                                   ffprobeURL: URL,
                                   env: [String: String]) throws -> VideoProbe {
        let probe = Process()
        probe.executableURL = ffprobeURL
        probe.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate",
            "-of", "json",
            inputURL.path
        ]
        probe.environment = env

        let out = Pipe()
        let err = Pipe()
        probe.standardOutput = out
        probe.standardError = err

        try probe.run()
        probe.waitUntilExit()

        if probe.terminationStatus != 0 {
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ffprobe failed"
            throw BenchError.probeFailed(detail)
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stream = (root["streams"] as? [[String: Any]])?.first,
              let width = stream["width"] as? Int,
              let height = stream["height"] as? Int else {
            throw BenchError.probeFailed("Could not parse ffprobe JSON")
        }

        let avgFPS = parseFPS(stream["avg_frame_rate"] as? String)
        let rFPS = parseFPS(stream["r_frame_rate"] as? String)
        let fps = max(0.0001, avgFPS ?? rFPS ?? 24.0)

        return VideoProbe(width: width, height: height, fps: fps)
    }

    private static func parseFPS(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty, raw != "0/0" else { return nil }
        if raw.contains("/") {
            let parts = raw.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0 else {
                return nil
            }
            return numerator / denominator
        }

        if let value = Double(raw), value.isFinite, value > 0 {
            return value
        }
        return nil
    }

    private static func readExactly(handle: FileHandle, byteCount: Int) throws -> Data? {
        guard byteCount > 0 else { return Data() }
        var data = Data(capacity: byteCount)

        while data.count < byteCount {
            let needed = byteCount - data.count
            let chunk = try handle.read(upToCount: needed) ?? Data()
            if chunk.isEmpty {
                return data.isEmpty ? nil : data
            }
            data.append(chunk)
        }

        return data
    }
}

private struct NeuralAssistProbe {
    func runProbe() -> String {
        guard #available(macOS 13.0, *) else {
            return "unavailable (requires macOS 13+)"
        }

        guard let neuralEngine = MLComputeDevice.allComputeDevices.first(where: {
            String(describing: $0).contains("MLNeuralEngineComputeDevice")
        }) else {
            return "not_detected"
        }

        if #available(macOS 14.0, *) {
            let image = syntheticImage(width: 96, height: 96)
            let request = VNGenerateImageFeaturePrintRequest()
            request.setComputeDevice(neuralEngine, for: .main)
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
                return "detected+featureprint_warmup_ok"
            } catch {
                return "detected+featureprint_warmup_failed(\(error.localizedDescription))"
            }
        }

        return "detected"
    }

    private func syntheticImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * bytesPerPixel
                let v = UInt8((x ^ y) & 0xFF)
                data[i] = v
                data[i + 1] = UInt8(255 &- v)
                data[i + 2] = UInt8((x + y) & 0xFF)
                data[i + 3] = 255
            }
        }

        let provider = CGDataProvider(data: NSData(bytes: &data, length: data.count))!
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}