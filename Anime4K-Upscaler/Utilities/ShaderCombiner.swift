// Anime4K-Upscaler/Utilities/ShaderCombiner.swift
import Foundation

/// Concatenates multiple .glsl shader files into a single combined file with isolated texture namespaces.
/// Returns the path to the combined file in the app's caches directory.
struct ShaderCombiner {
    private static let cacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CombinedShaders", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Built-in texture and hook identifiers that must never be namespaced.
    private static let reservedTextures: Set<String> = [
        "MAIN", "OUTPUT", "PREKERNEL", "POSTKERNEL", "SCALED", "NATIVE",
        "LUMA", "CHROMA", "ALPHA", "PLANE", "RGB", "XYZ"
    ]

    static func combinedShaderPath(shaders: [Anime4KShader], directory: String) -> String {
        if shaders.count == 1 {
            // Single shader — no concatenation needed
            return (directory as NSString).appendingPathComponent(shaders[0].rawValue)
        }

        // Generate a deterministic filename from the shader names
        let key = shaders.map(\.rawValue).joined(separator: "+")
        let filename = "combined_v2_\(key.hashValue & 0x7FFFFFFF).glsl"
        let outputURL = cacheDir.appendingPathComponent(filename)

        // Only regenerate if not cached
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            var combined = ""
            for (index, shader) in shaders.enumerated() {
                let path = (directory as NSString).appendingPathComponent(shader.rawValue)
                if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                    let isolatedContent = isolateShaderTextures(content: content, prefix: "s\(index)_")
                    combined += isolatedContent
                    combined += "\n\n"
                }
            }
            try? combined.write(to: outputURL, atomically: true, encoding: .utf8)
        }

        return outputURL.path
    }

    /// Rewrites user-defined texture declarations and helper tokens (SAVE, BIND, .w, .h, _texOff, _tex, _pt, etc.)
    /// with a unique per-shader prefix to prevent texture memory aliasing across concatenated shaders in libplacebo.
    static func isolateShaderTextures(content: String, prefix: String) -> String {
        guard let savePattern = try? NSRegularExpression(pattern: #"//!SAVE\s+([A-Za-z0-9_]+)"#) else {
            return content
        }
        let nsContent = content as NSString
        let matches = savePattern.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var userTextures = Set<String>()
        for match in matches {
            let name = nsContent.substring(with: match.range(at: 1))
            if !reservedTextures.contains(name) {
                userTextures.insert(name)
            }
        }

        guard !userTextures.isEmpty else { return content }

        // Sort by length descending to replace longer names before substrings (e.g. conv2d_1_tf before conv2d_tf)
        let sortedTextures = userTextures.sorted { $0.count > $1.count }
        var result = content
        for tex in sortedTextures {
            let patternStr = "\\b" + NSRegularExpression.escapedPattern(for: tex) + "(_texOff|_tex|_pt|_size|_rot|_mul|_map|_raw|\\.[wh]|\\b)"
            if let regex = try? NSRegularExpression(pattern: patternStr) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: (result as NSString).length),
                    withTemplate: "\(prefix)$0"
                )
            }
        }
        return result
    }
}
