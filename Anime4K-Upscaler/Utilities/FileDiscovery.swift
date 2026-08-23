// Anime4K-Upscaler/Utilities/FileDiscovery.swift
// Universal recursive file & folder ingestion engine for Anime4K Upscaler.

import Foundation
import UniformTypeIdentifiers

enum FileDiscovery {
    /// Resolves an array of file or directory URLs into a flattened, deduplicated,
    /// sorted list of valid `VideoFile` instances.
    /// - Parameters:
    ///   - urls: URLs selected via NSOpenPanel or received via Drag & Drop (may contain files, folders, or mixed).
    ///   - supportedExtensions: The set of allowed video file extensions (lowercase).
    /// - Returns: Sorted array of discovered `VideoFile` items.
    static func resolveVideoFiles(
        from urls: [URL],
        supportedExtensions: Set<String> = SupportedVideoExtension.allExtensions
    ) -> [VideoFile] {
        var results: [VideoFile] = []
        var seenPaths: Set<String> = []
        let fm = FileManager.default

        for rawURL in urls {
            let standardized = rawURL.standardizedFileURL
            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
                continue
            }

            if isDir.boolValue {
                // Directory: start accessing security scope and recursively enumerate child files
                SecurityScopeManager.shared.startAccessing(standardized)

                if let enumerator = fm.enumerator(
                    at: standardized,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        let standardizedFile = fileURL.standardizedFileURL
                        let ext = standardizedFile.pathExtension.lowercased()

                        if supportedExtensions.contains(ext) && !seenPaths.contains(standardizedFile.path) {
                            seenPaths.insert(standardizedFile.path)
                            SecurityScopeManager.shared.startAccessing(standardizedFile)
                            var vf = VideoFile(url: standardizedFile)
                            vf.bookmarkData = SecurityScopeManager.shared.createBookmark(for: standardizedFile)
                            results.append(vf)
                        }
                    }
                }
            } else {
                // Regular file
                let ext = standardized.pathExtension.lowercased()
                if supportedExtensions.contains(ext) && !seenPaths.contains(standardized.path) {
                    seenPaths.insert(standardized.path)
                    SecurityScopeManager.shared.startAccessing(standardized)
                    var vf = VideoFile(url: standardized)
                    vf.bookmarkData = SecurityScopeManager.shared.createBookmark(for: standardized)
                    results.append(vf)
                }
            }
        }

        // Return deterministically sorted by filename
        return results.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    /// Resolves an array of file or directory URLs into a flattened array of raw video file URLs.
    static func resolveRawVideoURLs(
        from urls: [URL],
        supportedExtensions: Set<String> = SupportedVideoExtension.allExtensions
    ) -> [URL] {
        var results: [URL] = []
        var seenPaths: Set<String> = []
        let fm = FileManager.default

        for rawURL in urls {
            let standardized = rawURL.standardizedFileURL
            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
                continue
            }

            if isDir.boolValue {
                if let enumerator = fm.enumerator(
                    at: standardized,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        let standardizedFile = fileURL.standardizedFileURL
                        let ext = standardizedFile.pathExtension.lowercased()
                        if supportedExtensions.contains(ext) && !seenPaths.contains(standardizedFile.path) {
                            seenPaths.insert(standardizedFile.path)
                            results.append(standardizedFile)
                        }
                    }
                }
            } else {
                let ext = standardized.pathExtension.lowercased()
                if supportedExtensions.contains(ext) && !seenPaths.contains(standardized.path) {
                    seenPaths.insert(standardized.path)
                    results.append(standardized)
                }
            }
        }

        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
