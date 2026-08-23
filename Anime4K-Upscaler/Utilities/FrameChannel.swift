// Anime4K-Upscaler/Utilities/FrameChannel.swift
// Phase 4 ring: bounded FIFO that pipelines decode→infer→write across frames
// while preserving strict PTS/frame order. Two layers:
//
//   - `BoundedFIFO<E>`: pure value-type core (non-blocking tryPush/tryPop/close).
//     Deterministically unit-testable standalone (no threads, no I/O).
//   - `FrameChannel<E>`: thread-safe blocking wrapper (NSCondition over BoundedFIFO).
//     `push` blocks when full (backpressure — producer can't outrun the writer
//     by more than `capacity` frames); `pop` blocks when empty; `close` unblocks
//     a blocked `pop` with nil (clean EOF).
//
// Why 2-deep (capacity 2-3) is enough: ANE/MetalFX `upscale` is not thread-safe
// (one infer at a time), so decode and infer stay serial on the producer. The
// overlap that actually wins is *writer-append(N) ‖ producer-infer(N+1)* — the
// AVAssetWriter callback runs on its own queue; the producer runs ahead on a
// dedicated queue and feeds this channel. A 3-stage (decode‖infer‖write on three
// threads) needs two serial resources (infer, writer) to serialize anyway, so
// the extra thread buys little. Ponytail: 2-deep.
//
// No AVFoundation/CoreML dep — unit-testable via swiftc (see FrameChannelTests).

import Foundation

/// Pure value-type bounded FIFO. Non-blocking; the testable core of
/// `FrameChannel`. Not thread-safe on its own — wrap in `FrameChannel` for
/// cross-thread use.
public struct BoundedFIFO<E> {
    private let capacity: Int
    private var buffer: [E]
    public private(set) var closed: Bool = false

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.buffer = []
        self.buffer.reserveCapacity(self.capacity)
    }

    public var count: Int { buffer.count }
    public var isEmpty: Bool { buffer.isEmpty }
    public var isFull: Bool { buffer.count >= capacity }

    /// Append an element. Returns false if closed or at capacity (no mutation).
    @discardableResult
    public mutating func tryPush(_ x: E) -> Bool {
        if closed || buffer.count >= capacity { return false }
        buffer.append(x)
        return true
    }

    /// Pop the oldest element (FIFO). Returns nil if empty (does NOT consult
    /// `closed` — a closed channel with buffered frames still drains them).
    public mutating func tryPop() -> E? {
        buffer.isEmpty ? nil : buffer.removeFirst()
    }

    /// Mark closed. Buffered frames still drain via `tryPop`; further `tryPush`
    /// is a no-op.
    public mutating func close() { closed = true }
}

/// Thread-safe blocking bounded channel. Wraps `BoundedFIFO` with an
/// `NSCondition` so `push` backpressures and `pop` blocks-until-data-or-close.
/// Used as the producer→writer handoff in `runUpscaleEncode`.
final class FrameChannel<E> {
    private let cond = NSCondition()
    private var fifo: BoundedFIFO<E>

    init(capacity: Int) { fifo = BoundedFIFO(capacity: capacity) }

    /// Push, blocking if at capacity until space frees or the channel closes.
    /// No-op (returns immediately) if the channel is already closed.
    func push(_ x: E) {
        cond.lock(); defer { cond.unlock() }
        while !fifo.closed && fifo.isFull { cond.wait() }
        guard !fifo.closed else { return }
        _ = fifo.tryPush(x)
        cond.signal()
    }

    /// Pop the oldest element, blocking if empty until a push or close arrives.
    /// Returns nil once the channel is closed AND drained (EOF).
    func pop() -> E? {
        cond.lock(); defer { cond.unlock() }
        while fifo.isEmpty && !fifo.closed { cond.wait() }
        let v = fifo.tryPop()
        cond.signal()   // a blocked push may now have room
        return v
    }

    /// Close the channel. Blocked `pop` callers wake and drain; once drained
    /// they receive nil. Blocked `push` callers wake and no-op.
    func close() {
        cond.lock()
        fifo.close()
        cond.broadcast()
        cond.unlock()
    }
}