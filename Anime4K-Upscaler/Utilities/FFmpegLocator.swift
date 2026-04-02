// Anime4K-Upscaler/Utilities/FFmpegLocator.swift
// Locates bundled ffmpeg/ffprobe binaries and validates runtime prerequisites.

import Foundation

/// Locates bundled FFmpeg/FFprobe binaries and Anime4K Metal source resources,
/// then provides the process environment and runtime validation helpers.
struct FFmpegLocator {

    // MARK: - Binary Paths

    /// URL to the bundled `ffmpeg` binary inside Frameworks/.
    static var ffmpegURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")
            ?? frameworksDirectoryURL?.appendingPathComponent("ffmpeg")
    }

    /// URL to the bundled `ffprobe` binary inside Frameworks/.
    static var ffprobeURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "ffprobe")
            ?? frameworksDirectoryURL?.appendingPathComponent("ffprobe")
    }

    /// URL to the Frameworks directory within the app bundle.
    static var frameworksDirectoryURL: URL? {
        Bundle.main.privateFrameworksURL
    }

    /// URL to the bundled legacy GLSL shader directory inside Resources/Shaders/.
    static var shaderDirectoryURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Shaders")
    }

    /// Absolute path string to the shader directory.
    static var shaderDirectoryPath: String {
        shaderDirectoryURL?.path ?? ""
    }

    /// URL to bundled translated Anime4K .metal source files.
    ///
    /// Preferred location is Resources/metal_sources in app bundle. For local
    /// development (run from project root), fallback roots are searched within
    /// this Upscaler repository only.
    static var metalSourceDirectoryURL: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("metal_sources"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let cwd = FileManager.default.currentDirectoryPath
        let candidates = [
            cwd + "/Anime4K-Upscaler/Resources/metal_sources",
            cwd + "/Resources/metal_sources",
            cwd + "/../Anime4K-Upscaler/Resources/metal_sources",
            cwd + "/../../Anime4K-Upscaler/Resources/metal_sources"
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return nil
    }

    /// Absolute path to translated .metal source directory.
    static var metalSourceDirectoryPath: String {
        metalSourceDirectoryURL?.path ?? ""
    }

    /// URL to the bundled `libMoltenVK.dylib` inside Frameworks/.
    static var moltenVKURL: URL? {
        frameworksDirectoryURL?.appendingPathComponent("libMoltenVK.dylib")
    }

    // MARK: - Vulkan ICD JSON (legacy libplacebo path)

    /// Directory where the runtime-generated Vulkan ICD JSON will be stored.
    /// Uses the app's caches directory (sandbox-writable).
    private static var icdDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("VulkanICD", isDirectory: true)
    }

    /// URL to the generated ICD JSON file.
    private static var icdJSONURL: URL {
        icdDirectory.appendingPathComponent("MoltenVK_icd.json")
    }

    /// Cached ICD path — once generated, never regenerated.
    private static var cachedICDPath: String?
    private static let icdLock = NSLock()

    /// Generates the Vulkan ICD JSON file at runtime pointing to the bundled MoltenVK.
    /// Thread-safe and idempotent — the file is only written once, then cached.
    /// - Returns: The absolute path to the generated ICD JSON, or nil if MoltenVK is not bundled.
    @discardableResult
    static func generateVulkanICDJSON() -> String? {
        icdLock.lock()
        defer { icdLock.unlock() }

        if let cached = cachedICDPath {
            return cached
        }

        guard let moltenVKPath = moltenVKURL?.path,
              FileManager.default.fileExists(atPath: moltenVKPath) else {
            return nil
        }

        let icdContent = """
        {
            "file_format_version": "1.0.0",
            "ICD": {
                "library_path": "\(moltenVKPath)",
                "api_version": "1.2.0"
            }
        }
        """

        do {
            try FileManager.default.createDirectory(
                at: icdDirectory,
                withIntermediateDirectories: true
            )
            try icdContent.write(to: icdJSONURL, atomically: true, encoding: .utf8)
            cachedICDPath = icdJSONURL.path
            return cachedICDPath
        } catch {
            return nil
        }
    }

    // MARK: - Environment Variables

    /// Cached process environment — computed once via dispatch_once semantics,
    /// reused for every FFmpeg/ffprobe invocation. Eliminates per-process
    /// dictionary allocation and redundant ICD lock acquisition.
    private static let cachedProcessEnvironment: [String: String] = {
        var env: [String: String] = [:]

        // Inherit minimal environment
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            env["PATH"] = path
        }
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            env["HOME"] = home
        }

        // Vulkan ICD
        if let icdPath = generateVulkanICDJSON() {
            env["VK_ICD_FILENAMES"] = icdPath
        }

        // Dylib search path (Frameworks directory)
        if let fwPath = frameworksDirectoryURL?.path {
            env["DYLD_LIBRARY_PATH"] = fwPath
            env["DYLD_FRAMEWORK_PATH"] = fwPath
        }

        // Disable FFmpeg interactive mode
        env["FFREPORT"] = ""

        return env
    }()

    /// Returns the cached environment dictionary for FFmpeg Process execution.
    /// Thread-safe and zero-allocation after first call.
    static func processEnvironment() -> [String: String] {
        cachedProcessEnvironment
    }

    // MARK: - Validation

    /// Validates that required bundled dependencies are present.
    /// - Returns: A list of missing dependency names (empty if all present).
    static func validateDependencies() -> [String] {
        var missing: [String] = []

        if let url = ffmpegURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("ffmpeg") }

        if let url = ffprobeURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("ffprobe") }

        if let url = moltenVKURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("libMoltenVK.dylib") }

        if let url = metalSourceDirectoryURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("metal_sources directory") }

        return missing
    }

    /// Whether the bundled FFmpeg binary is executable.
    static var isFFmpegExecutable: Bool {
        guard let url = ffmpegURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    // MARK: - Strict libplacebo Requirement

    @MainActor
    private static var cachedLibplaceboValidation: (required: String, ok: Bool, detail: String)?

    /// Strictly validate that FFmpeg is linked against the required libplacebo
    /// runtime family (for compatibility baselines and parity workflows).
    ///
    /// The requirement is satisfied if detected version starts with the required
    /// prefix (e.g. required `7.351` accepts `7.351.0`).
    @MainActor
    static func validateStrictLibplaceboVersion(requiredVersion: String = "7.351") -> (ok: Bool, detail: String) {
        if let cached = cachedLibplaceboValidation,
           cached.required == requiredVersion {
            return (cached.ok, cached.detail)
        }

        guard let ffmpeg = ffmpegURL else {
            let detail = "ffmpeg binary not found"
            cachedLibplaceboValidation = (requiredVersion, false, detail)
            return (false, detail)
        }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-hide_banner",
            "-v", "verbose",
            "-f", "lavfi",
            "-i", "color=size=16x16:rate=1:color=black",
            "-vf", "libplacebo",
            "-frames:v", "1",
            "-f", "null",
            "-"
        ]
        process.environment = processEnvironment()

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let detail = "failed to execute ffmpeg libplacebo probe: \(error.localizedDescription)"
            cachedLibplaceboValidation = (requiredVersion, false, detail)
            return (false, detail)
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        let pattern = "libplacebo\\s+v?([0-9]+(?:\\.[0-9]+){1,3})"
        let detectedVersion: String? = {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let range = NSRange(location: 0, length: (output as NSString).length)
            guard let match = regex.firstMatch(in: output, options: [], range: range),
                  match.numberOfRanges >= 2 else {
                return nil
            }
            return (output as NSString).substring(with: match.range(at: 1))
        }()

        guard let detectedVersion else {
            let detail = "unable to detect libplacebo version from ffmpeg output"
            cachedLibplaceboValidation = (requiredVersion, false, detail)
            return (false, detail)
        }

        let ok = detectedVersion.hasPrefix(requiredVersion)
        let detail = ok
            ? "libplacebo \(detectedVersion)"
            : "libplacebo \(detectedVersion), required \(requiredVersion).x"

        cachedLibplaceboValidation = (requiredVersion, ok, detail)
        return (ok, detail)
    }
}
