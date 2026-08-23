// Tests/FileDiscoveryTests.swift
// Pure Foundation unit test for universal file & directory ingestion and recursive resolution.

import Foundation

enum TestFileDiscovery {
    static let supportedExtensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "webm", "ts", "m4v", "flv", "wmv", "mpg", "mpeg", "m2ts"
    ]

    static func resolveRawVideoURLs(from urls: [URL]) -> [URL] {
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

@main
struct FileDiscoveryTests {
    static func main() {
        var passed = 0
        var failed = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("PASS: \(name)")
                passed += 1
            } else {
                print("FAIL: \(name) \(detail)")
                failed += 1
            }
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("Anime4K_FileDiscoveryTest_\(UUID().uuidString)")
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Setup mock file hierarchy:
        // tempDir/
        //   ├── ep01.mkv
        //   ├── ep02.mp4
        //   ├── subtitle.srt (ignored)
        //   ├── notes.txt (ignored)
        //   └── Season 2/
        //       ├── ep03.mov
        //       ├── ep04.webm
        //       ├── cover.jpg (ignored)
        //       └── Specials/
        //           ├── ova01.ts
        //           └── readme.md (ignored)

        let ep01 = tempDir.appendingPathComponent("ep01.mkv")
        let ep02 = tempDir.appendingPathComponent("ep02.mp4")
        let sub01 = tempDir.appendingPathComponent("subtitle.srt")
        let note01 = tempDir.appendingPathComponent("notes.txt")

        let season2Dir = tempDir.appendingPathComponent("Season 2")
        let specialsDir = season2Dir.appendingPathComponent("Specials")
        try? fm.createDirectory(at: specialsDir, withIntermediateDirectories: true)

        let ep03 = season2Dir.appendingPathComponent("ep03.mov")
        let ep04 = season2Dir.appendingPathComponent("ep04.webm")
        let cover = season2Dir.appendingPathComponent("cover.jpg")
        let ova01 = specialsDir.appendingPathComponent("ova01.ts")
        let readme = specialsDir.appendingPathComponent("readme.md")

        for fileURL in [ep01, ep02, sub01, note01, ep03, ep04, cover, ova01, readme] {
            try? "dummy content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Test 1: Single file discovery
        let singleResult = TestFileDiscovery.resolveRawVideoURLs(from: [ep01])
        check("Single file resolves to 1 video", singleResult.count == 1)
        check("Single file path matches ep01.mkv", singleResult.first?.lastPathComponent == "ep01.mkv")

        // Test 2: Multi-file discovery with non-video filtering
        let multiResult = TestFileDiscovery.resolveRawVideoURLs(from: [ep01, ep02, sub01, note01])
        check("Multi-file filters non-videos (2 out of 4)", multiResult.count == 2)
        check("Multi-file contains ep01.mkv and ep02.mp4",
              multiResult.contains(where: { $0.lastPathComponent == "ep01.mkv" }) &&
              multiResult.contains(where: { $0.lastPathComponent == "ep02.mp4" }))

        // Test 3: Single folder recursive discovery (Season 2 directory)
        let season2Result = TestFileDiscovery.resolveRawVideoURLs(from: [season2Dir])
        check("Season 2 folder resolves 3 recursive videos (ep03, ep04, ova01)", season2Result.count == 3)
        check("Season 2 includes nested ova01.ts", season2Result.contains(where: { $0.lastPathComponent == "ova01.ts" }))
        check("Season 2 ignores cover.jpg and readme.md", !season2Result.contains(where: { $0.pathExtension == "jpg" || $0.pathExtension == "md" }))

        // Test 4: Root directory recursive discovery
        let rootResult = TestFileDiscovery.resolveRawVideoURLs(from: [tempDir])
        check("Root folder resolves all 5 videos recursively", rootResult.count == 5)

        // Test 5: Mixed selection (single file ep01.mkv + Season 2 folder)
        let mixedResult = TestFileDiscovery.resolveRawVideoURLs(from: [ep01, season2Dir])
        check("Mixed selection resolves 4 videos (ep01 + 3 from Season 2)", mixedResult.count == 4)

        // Test 6: Deduplication when file and its parent folder are both selected
        let dedupResult = TestFileDiscovery.resolveRawVideoURLs(from: [ep01, tempDir])
        check("Deduplication handles overlapping file and parent folder (5 unique videos)", dedupResult.count == 5)

        // Test 7: Deterministic sorting (alphabetical)
        let names = rootResult.map { $0.lastPathComponent }
        let sortedNames = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        check("Discovered videos are sorted deterministically", names == sortedNames)

        print("\n\(passed) passed, \(failed) failed\n")
        if failed > 0 { exit(1) }
    }
}
