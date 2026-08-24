// Anime4K-Upscaler/Utilities/LogThrottle.swift
// Coalesces a firehose of stderr lines into periodic batched flushes so the UI
// actor isn't hammered per-line. ffmpeg dumps dozens of lines at startup (every
// stream / metadata / sub track); forwarding each as its own `Task { @MainActor
// in job.appendLog(line) }` lagged the UI. Buffer off-main, flush one joined
// string every `interval` — per-line cost is a lock + array append (no Task),
// MainActor hops drop from dozens/sec to ~10/sec.

import Foundation

final class LogThrottle {

    private let interval: TimeInterval
    private let sink: (String) -> Void
    private let lock = NSLock()
    private var lines: [String] = []
    private var timer: DispatchSourceTimer?

    /// `sink` receives the joined batch. It is called off-main on a utility
    /// queue — hop to the UI actor inside `sink` (e.g. `Task { @MainActor in … }`).
    init(interval: TimeInterval = 0.1, sink: @escaping (String) -> Void) {
        self.interval = interval
        self.sink = sink
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.flushSync() }
        t.resume()
        timer = t
    }

    /// Append a line. Cheap: lock + array append. No Task, no actor hop.
    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    private func flushSync() {
        lock.lock()
        let snapshot = lines
        lines.removeAll(keepingCapacity: true)
        lock.unlock()
        guard !snapshot.isEmpty else { return }
        sink(snapshot.joined(separator: "\n"))
    }

    /// Cancel the timer and flush any remaining lines. Call at job end.
    func stop() {
        timer?.cancel()
        timer = nil
        flushSync()
    }
}