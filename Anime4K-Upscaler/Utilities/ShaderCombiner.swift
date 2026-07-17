// Anime4K-Upscaler/Utilities/ShaderCombiner.swift
import Foundation

/// Concatenates multiple .glsl shader files into a single combined file.
/// Returns the path to the combined file in the app's caches directory.
struct ShaderCombiner {
    private static let cacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CombinedShaders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func combinedShaderPath(shaders: [Anime4KShader], directory: String) -> String {
        if shaders.count == 1 {
            // Single shader — no concatenation needed
            return (directory as NSString).appendingPathComponent(shaders[0].rawValue)
        }

        // Generate a deterministic filename from the shader names
        let key = shaders.map(\.rawValue).joined(separator: "+")
        let filename = "combined_\(key.hashValue & 0x7FFFFFFF).glsl"
        let outputURL = cacheDir.appendingPathComponent(filename)

        // Only regenerate if not cached
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            var combined = ""
            for shader in shaders {
                let path = (directory as NSString).appendingPathComponent(shader.rawValue)
                if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                    combined += content
                    combined += "\n\n"
                }
            }
            try? combined.write(to: outputURL, atomically: true, encoding: .utf8)
        }

        return outputURL.path
    }
}
