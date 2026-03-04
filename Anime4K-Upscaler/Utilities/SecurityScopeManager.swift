// Anime4K-Upscaler/Utilities/SecurityScopeManager.swift
// Manages security-scoped URL access for sandboxed file operations.

import Foundation
import UniformTypeIdentifiers
import AppKit

/// Handles security-scoped URL lifecycle and bookmark persistence
/// for App Sandbox compliance.
/// Thread-safe via internal NSLock; @unchecked Sendable for cross-isolation use.
final class SecurityScopeManager: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SecurityScopeManager()
    private init() {}

    // MARK: - Active Access Tracking

    /// URLs currently being accessed via security scope.
    private var activeAccessURLs: Set<URL> = []
    private let lock = NSLock()

    // MARK: - Security-Scoped Access

    /// Begin accessing a security-scoped URL.
    /// - Parameter url: The URL obtained from NSOpenPanel or bookmark resolution.
    /// - Returns: `true` if access was granted.
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        let success = url.startAccessingSecurityScopedResource()
        if success {
            lock.lock()
            activeAccessURLs.insert(url)
            lock.unlock()
        }
        return success
    }

    /// Stop accessing a security-scoped URL.
    /// - Parameter url: The URL to release.
    func stopAccessing(_ url: URL) {
        lock.lock()
        let wasActive = activeAccessURLs.remove(url) != nil
        lock.unlock()
        if wasActive {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Stop accessing all currently active security-scoped URLs.
    func stopAccessingAll() {
        lock.lock()
        let urls = activeAccessURLs
        activeAccessURLs.removeAll()
        lock.unlock()
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Bookmark Data

    /// Create a security-scoped bookmark for a URL.
    /// - Parameter url: The file URL to bookmark.
    /// - Returns: Bookmark data, or nil on failure.
    func createBookmark(for url: URL) -> Data? {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            return nil
        }
    }

    /// Resolve a security-scoped bookmark back to a URL.
    /// - Parameter data: The bookmark data to resolve.
    /// - Returns: The resolved URL, or nil on failure. Automatically starts accessing if stale.
    func resolveBookmark(_ data: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Re-create bookmark if stale
                _ = createBookmark(for: url)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - File Picker

    /// Present an NSOpenPanel configured for video file selection.
    /// - Parameter allowMultiple: Whether to allow selecting multiple files.
    /// - Returns: Array of selected video file URLs with security-scoped access started.
    @MainActor
    func presentVideoFilePicker(allowMultiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowMultiple
        panel.title = "Select Video Files"
        panel.message = "Choose video files to process with Anime4K"

        // Configure allowed content types
        var contentTypes: [UTType] = []
        contentTypes.append(.movie)
        contentTypes.append(.mpeg4Movie)
        contentTypes.append(.quickTimeMovie)
        contentTypes.append(.avi)
        if let mkv = UTType("org.matroska.mkv") {
            contentTypes.append(mkv)
        }
        if let webm = UTType("org.webmproject.webm") {
            contentTypes.append(webm)
        }
        if let ts = UTType("public.mpeg-2-transport-stream") {
            contentTypes.append(ts)
        }
        panel.allowedContentTypes = contentTypes

        let response = panel.runModal()
        guard response == .OK else { return [] }

        var results: [URL] = []
        for url in panel.urls {
            startAccessing(url)
            results.append(url)
        }
        return results
    }

    /// Present an NSOpenPanel for selecting an output directory.
    /// - Returns: The selected directory URL with security-scoped access started, or nil.
    @MainActor
    func presentOutputDirectoryPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Output Directory"
        panel.message = "Choose where to save processed files"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }

        startAccessing(url)
        return url
    }
}
