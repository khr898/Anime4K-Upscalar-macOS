// Tests/DependencyRulesCheck.swift
// TDD Unit test asserting strict dependency version rules:
// libplacebo must be >= 7.360.1 (or 360.1) and molten-vk must be >= 1.4.2.

import Foundation

@main
struct DependencyRulesCheck {
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

        func runCommand(_ cmd: String) -> String {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", cmd]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        // --- Helper: Version comparison (e.g. "7.360.1" >= "7.360.1", "1.4.2" >= "1.4.2") ---
        func isVersion(_ v: String, atLeast minV: String) -> Bool {
            let vParts = v.split(separator: ".").compactMap { Int($0.prefix(while: { $0.isNumber })) }
            let minParts = minV.split(separator: ".").compactMap { Int($0.prefix(while: { $0.isNumber })) }
            for i in 0..<max(vParts.count, minParts.count) {
                let vVal = i < vParts.count ? vParts[i] : 0
                let mVal = i < minParts.count ? minParts[i] : 0
                if vVal > mVal { return true }
                if vVal < mVal { return false }
            }
            return true
        }

        // 1. Check libplacebo
        let lpVer = runCommand("pkg-config --modversion libplacebo 2>/dev/null || brew list --versions libplacebo 2>/dev/null | awk '{print $2}'")
        let lpValid = !lpVer.isEmpty && isVersion(lpVer, atLeast: "7.360.1")
        check("libplacebo version (\(lpVer)) >= 7.360.1", lpValid, "got \(lpVer)")

        // 2. Check molten-vk
        let mvkVer = runCommand("brew list --versions molten-vk 2>/dev/null | awk '{print $2}'")
        let mvkValid = !mvkVer.isEmpty && isVersion(mvkVer, atLeast: "1.4.2")
        check("molten-vk version (\(mvkVer)) >= 1.4.2", mvkValid, "got \(mvkVer)")

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
