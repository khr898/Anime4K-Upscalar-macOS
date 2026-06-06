// Anime4K-Upscaler/Utilities/FFmpegLocator.swift
// Locates bundled ffmpeg/ffprobe binaries and configures Vulkan ICD at runtime.

import Foundation

/// Locates the bundled FFmpeg and FFprobe binaries within the app bundle,
/// generates the Vulkan ICD JSON for MoltenVK at runtime, and provides
/// the required environment variables for Process execution.
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

    /// URL to the bundled shaders directory inside Resources/Shaders/.
    static var shaderDirectoryURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Shaders")
    }

    /// Absolute path string to the shader directory.
    static var shaderDirectoryPath: String {
        shaderDirectoryURL?.path ?? ""
    }

    /// URL to the bundled `libMoltenVK.dylib` inside Frameworks/.
    static var moltenVKURL: URL? {
        frameworksDirectoryURL?.appendingPathComponent("libMoltenVK.dylib")
    }

    // MARK: - Vulkan ICD JSON

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

    /// Validates that all required bundled dependencies are present.
    /// - Returns: A list of missing dependency names (empty if all present).
    static func validateDependencies() -> [String] {
        var missing: [String] = []

        if let url = ffmpegURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("ffmpeg") }

        if let url = ffprobeURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("ffprobe") }

        if let url = moltenVKURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("libMoltenVK.dylib") }

        if let url = shaderDirectoryURL, FileManager.default.fileExists(atPath: url.path) { /* OK */ }
        else { missing.append("Shaders directory") }

        return missing
    }

    /// Whether the bundled FFmpeg binary is executable.
    static var isFFmpegExecutable: Bool {
        guard let url = ffmpegURL else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
}
