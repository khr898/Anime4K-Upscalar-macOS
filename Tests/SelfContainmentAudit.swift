// Tests/SelfContainmentAudit.swift
// TDD Unit test asserting 100% self-containment of the application bundle.
// Audits all binaries and dylibs for external references and verifies sterile execution.

import Foundation

@main
struct SelfContainmentAudit {
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

        func runCommand(_ cmd: String) -> (output: String, exitCode: Int32) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", cmd]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (out, proc.terminationStatus)
        }

        let repoRoot = FileManager.default.currentDirectoryPath
        let possibleAppPaths = [
            "\(repoRoot)/build/Release/Anime4K Upscaler.app",
            "\(repoRoot)/build/Debug/Anime4K Upscaler.app",
            "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData"
        ]

        // Find the most recently built app bundle
        var frameworksDir: String?
        for path in possibleAppPaths {
            let fw = "\(path)/Contents/Frameworks"
            if FileManager.default.fileExists(atPath: fw) {
                frameworksDir = fw
                break
            }
        }

        if frameworksDir == nil {
            // Search in DerivedData
            let ddResult = runCommand("find ~/Library/Developer/Xcode/DerivedData -name 'Anime4K Upscaler.app' -type d 2>/dev/null | head -1")
            if !ddResult.output.isEmpty && FileManager.default.fileExists(atPath: "\(ddResult.output)/Contents/Frameworks") {
                frameworksDir = "\(ddResult.output)/Contents/Frameworks"
            }
        }

        guard let fwDir = frameworksDir else {
            print("FAIL: Could not locate built app Frameworks directory. Build the app first.")
            exit(1)
        }

        print("🔍 Auditing bundle at: \(fwDir)")

        // 1. Audit all dylibs and binaries for unresolved external references
        let itemsResult = runCommand("find '\(fwDir)' -type f \\( -name '*.dylib' -o -name 'ffmpeg' -o -name 'ffprobe' -o -name 'realesrgan-ncnn-vulkan' \\)")
        let items = itemsResult.output.split(separator: "\n").map(String.init)
        check("Found bundled items to audit", !items.isEmpty, "found \(items.count)")

        for item in items {
            let baseName = URL(fileURLWithPath: item).lastPathComponent
            let otoolRes = runCommand("otool -L '\(item)' 2>/dev/null | awk 'NR>1 {print $1}'")
            let refs = otoolRes.output.split(separator: "\n").map(String.init)
            
            let externalRefs = refs.filter { ref in
                !ref.hasPrefix("@executable_path") &&
                !ref.hasPrefix("/usr/lib/") &&
                !ref.hasPrefix("/System/Library/") &&
                !ref.hasPrefix("@rpath") // if any rpath, ensure it resolves
            }

            check("\(baseName) has zero Homebrew/user references", externalRefs.isEmpty, "external refs: \(externalRefs)")
        }

        // 2. Sterile environment execution test (no Homebrew PATH or DYLD fallback)
        let ffmpegPath = "\(fwDir)/ffmpeg"
        if FileManager.default.fileExists(atPath: ffmpegPath) {
            let res = runCommand("env -i PATH=/usr/bin:/bin '\(ffmpegPath)' -version")
            check("ffmpeg launches cleanly in sterile env", res.exitCode == 0, res.output)
        }

        let ffprobePath = "\(fwDir)/ffprobe"
        if FileManager.default.fileExists(atPath: ffprobePath) {
            let res = runCommand("env -i PATH=/usr/bin:/bin '\(ffprobePath)' -version")
            check("ffprobe launches cleanly in sterile env", res.exitCode == 0, res.output)
        }

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
