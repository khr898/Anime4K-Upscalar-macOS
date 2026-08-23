// Anime4K-Upscaler/Utilities/RawVideoFrameSource.swift
// Streams decoded video frames from an ffmpeg subprocess over stdout as raw
// BGRA bytes, yielding one CVPixelBuffer per frame.
//
// Replaces the decode-to-PNG prepass for Core ML special modes. Zero temp
// disk, no PNG codec cost, container-agnostic (ffmpeg reads MKV/AVI/etc that
// AVAssetReader refuses). Backpressure is natural: FileHandle.availableData
// blocks until bytes arrive, and ffmpeg blocks when the stdout pipe buffer
// fills, so decode runs at the consumer's (Core ML) pace.
//
// Dependency-free on purpose (environment dict passed in, no FFmpegLocator
// import) so the CVPixelBuffer factory is unit-testable standalone via swiftc.

import Foundation
import CoreVideo

final class RawVideoFrameSource {

    /// Decode strategy for the streaming source. The Special pipeline probes
    /// `.videoToolbox` first (hardware AV1/HEVC/H264 decode on Apple Silicon),
    /// then falls back to `.softwareDav1d` (libdav1d software AV1 decode — works
    /// on devices without AV1 VideoToolbox support, e.g. Intel / M1 / M2), then
    /// `.default`. The native `av1` decoder selected by `.default` is
    /// hardware-only and yields zero frames on devices without a functioning
    /// AV1 hwaccel, so AV1 sources must use one of the override modes.
    enum DecodeMode { case videoToolbox, softwareDav1d, `default` }

    /// Builds the exact ffmpeg argument array the streaming source launches with.
    /// Pure (no I/O) so it is unit-testable standalone via swiftc.
    static func streamArgs(mode: DecodeMode, inputPath: String,
                           usesRestoreShader: Bool, shaderPath: String) -> [String] {
        // Restore-shader modes (SDRescue + MetalFX) run the Anime4K Restore VL
        // shader via a Vulkan libplacebo chain to reconstruct degraded anime
        // line art BEFORE the upscaler — MetalFX alone is a generic spatial
        // scaler and looks soft/blurry on anime without this preprocess. Plain
        // modes just decode. Both emit `-pix_fmt bgra -f rawvideo pipe:1`
        // consumed here. -hwaccel videotoolbox is only applied to the plain
        // path — its interaction with the Vulkan hwupload chain is unverified,
        // so restore-shader .videoToolbox collapses to .default and relies on
        // the .softwareDav1d fallback for AV1 sources.
        if usesRestoreShader {
            let vf = "hwupload,libplacebo=custom_shader_path=\(shaderPath):format=p010le,hwdownload,format=p010le"
            var a = ["-init_hw_device", "vulkan=vk:0", "-filter_hw_device", "vk", "-y"]
            if mode == .softwareDav1d { a += ["-c:v", "libdav1d"] }
            a += ["-i", inputPath, "-vf", vf, "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"]
            return a
        }
        var a = ["-y"]
        if mode == .videoToolbox { a += ["-hwaccel", "videotoolbox"] }
        if mode == .softwareDav1d { a += ["-c:v", "libdav1d"] }
        a += ["-i", inputPath, "-pix_fmt", "bgra", "-f", "rawvideo", "pipe:1"]
        return a
    }

    private let process: Process
    private let stdout: Pipe
    private let stderr: Pipe
    private let frameSize: Int      // width * height * 4 (BGRA)
    private let width: Int
    private let height: Int
    private var acc = FrameAccumulator()
    private var eof = false
    private var pendingRawFrame: Data?   // re-injected by pushFrame (probe ladder)

    /// Serializes access to `acc`, `eof`, `pendingRawFrame`, `framesPulled`,
    /// and `terminationStatus`. The probe ladder pulls one frame off-main via a
    /// `Task.detached` and the encode loop pulls on the `a4k.ane.encode` queue;
    /// without serialization a torn read of `acc`'s `readOffset`/`buffer` could
    /// pass `pullFrame`'s bounds guard with a stale value and trap inside
    /// `Data.subdata(in:)`. All mutating accessors route through this queue so
    /// state transfers are atomic across the probe→encode handoff.
    private let stateQueue = DispatchQueue(label: "a4k.rawframesource.state")

    /// ffmpeg's exit status, set when the process terminates (nil until then).
    private(set) var terminationStatus: Int32?

    /// Number of complete frames returned via `nextFrame()`. Used by `hasFailed`
    /// to distinguish a launch/decode failure (0 frames) from a mid-stream error.
    private(set) var framesPulled: Int = 0

    /// True when ffmpeg died with a nonzero status before yielding any frame —
    /// the signal for the pipeline to retry with the libdav1d software fallback
    /// (or surface the real error). A mid-stream error after frames were produced
    /// is NOT a launch failure, so this stays false in that case.
    var hasFailed: Bool {
        stateQueue.sync {
            (terminationStatus.map { $0 != 0 } ?? false) && framesPulled == 0
        }
    }

    /// Per-line stderr callback (for surfacing ffmpeg progress/errors in the log).
    var onLog: ((String) -> Void)?

    /// Designated initializer. Does NOT launch — call `start()`.
    /// `environment` should be `FFmpegLocator.processEnvironment()` from the caller.
    init(executableURL: URL, arguments: [String],
         width: Int, height: Int, environment: [String: String]) {
        precondition(width > 0 && height > 0, "RawVideoFrameSource: bad dims")
        self.width = width
        self.height = height
        self.frameSize = width * height * 4

        process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.qualityOfService = .userInitiated

        stdout = Pipe()
        stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Drain stderr concurrently so it can never fill its pipe buffer and
        // deadlock ffmpeg while we block reading stdout. Each line -> onLog.
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let cb = self?.onLog
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                cb?(String(line))
            }
        }

        // Reap + clean up on exit: stop the stderr pump and close the stderr FD
        // so neither leaks across jobs in a batch. stdout is left to EOF naturally
        // (the read loop sees empty availableData and returns nil); closing it
        // here would race a blocked nextFrame() read. stdout closes when the
        // source deallocates. Capture the exit status so `hasFailed` can gate the
        // software-fallback retry after a 0-frame decode.
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.stateQueue.sync { self.terminationStatus = proc.terminationStatus }
            self.stderr.fileHandleForReading.readabilityHandler = nil
            try? self.stderr.fileHandleForReading.close()
        }
    }

    /// Launch ffmpeg. Throws if the process can't be started.
    func start() throws {
        try process.run()
    }

    /// Block until ffmpeg has exited and `terminationStatus` is set. Safe to
    /// call after `nextFrame()` returned nil (EOF); the process is already
    /// exiting. The pipeline calls this before consulting `hasFailed` to avoid
    /// a race between pipe EOF and the async termination handler —
    /// `waitUntilExit()` can return a hair before the handler fires, so read
    /// `process.terminationStatus` directly as a backstop.
    func waitUntilExited() {
        process.waitUntilExit()
        stateQueue.sync {
            if terminationStatus == nil { terminationStatus = process.terminationStatus }
        }
    }

    /// Pull the next decoded frame, or nil at EOF / after cancel.
    /// Blocks the calling thread on the pipe until a full frame arrives — call
    /// from an off-main task (the Core ML encode loop runs detached).
    func nextFrame() -> CVPixelBuffer? {
        // Re-injected probe frame (see pushFrame) is returned first so the
        // encode loop never loses the frame the probe already paid for. State
        // reads/writes go through `stateQueue` so the probe's `Task.detached`
        // and the `a4k.ane.encode` queue can't tear `acc`/`eof`/`pendingRawFrame`.
        if let pending = stateQueue.sync(execute: { () -> Data? in
            if let p = pendingRawFrame { pendingRawFrame = nil; return p }
            return nil
        }) {
            stateQueue.sync { framesPulled &+= 1 }
            return Self.makeBGRA(from: pending, width: width, height: height)
        }
        if stateQueue.sync(execute: { eof }) { return nil }
        while true {
            if let frame = stateQueue.sync(execute: { acc.pullFrame(frameSize: frameSize) }) {
                stateQueue.sync { framesPulled &+= 1 }
                return Self.makeBGRA(from: frame, width: width, height: height)
            }
            // Blocking pipe read stays off the state queue — only the encode
            // loop reads stdout, so no other thread can race the read itself.
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty {
                // EOF (ffmpeg exited or pipe closed). Discard any partial tail.
                stateQueue.sync { eof = true }
                return nil
            }
            stateQueue.sync { acc.push(chunk) }
        }
    }

    /// Pull the next frame as raw BGRA bytes (no CVPixelBuffer wrap). Used by
    /// the probe ladder to test whether a decode mode yields any frames before
    /// committing the encode loop to it. Does NOT advance `framesPulled` — the
    /// frame is either pushed back via `pushFrame` (counted on the next
    /// `nextFrame`) or discarded (failed probe).
    func nextRawFrame() -> Data? {
        if stateQueue.sync(execute: { eof }) { return nil }
        while true {
            if let frame = stateQueue.sync(execute: { acc.pullFrame(frameSize: frameSize) }) { return frame }
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { stateQueue.sync { eof = true }; return nil }
            stateQueue.sync { acc.push(chunk) }
        }
    }

    /// Re-inject a raw frame (from `nextRawFrame`) so the next `nextFrame()`
    /// returns it first. Data is Sendable, so this crosses actor boundaries
    /// cleanly — the probe runs on a detached task and hands the bytes back to
    /// the encode loop without a non-Sendable CVPixelBuffer crossing.
    func pushFrame(_ frame: Data) {
        stateQueue.sync { pendingRawFrame = frame }
    }

    /// Terminate ffmpeg. The next `nextFrame()` call returns nil (EOF).
    func cancel() {
        if process.isRunning { process.terminate() }
    }

    /// Whether ffmpeg has exited.
    var hasExited: Bool { !process.isRunning }

    // MARK: - CVPixelBuffer factory (unit-tested)

    /// Wrap tightly-packed BGRA bytes (width*4 per row, no source padding) into
    /// a 32BGRA CVPixelBuffer. CVPixelBufferCreate may pad `bytesPerRow` for
    /// alignment; if so, copy row-by-row so pixels land in the right place.
    /// Copies the bytes — `data` may be freed after this returns.
    static func makeBGRA(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        guard width > 0, height > 0, data.count >= width * height * 4 else { return nil }
        var pb: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess,
              let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return pb }
        let dstBPR = CVPixelBufferGetBytesPerRow(pb)
        let srcBPR = width * 4
        data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) in
            guard let src = srcRaw.baseAddress else { return }
            if dstBPR == srcBPR {
                memcpy(base, src, srcBPR * height)
            } else {
                for row in 0..<height {
                    memcpy(base.advanced(by: row * dstBPR),
                           src.advanced(by: row * srcBPR),
                           srcBPR)
                }
            }
        }
        return pb
    }
}