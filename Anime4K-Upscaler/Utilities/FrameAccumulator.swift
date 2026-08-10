// Anime4K-Upscaler/Utilities/FrameAccumulator.swift
// Slices a raw byte stream into fixed-size frames. Pure value type, no I/O.
//
// Used to parse ffmpeg `-f rawvideo` stdout: each frame is exactly
// width * height * bytesPerPixel bytes, but pipe reads may split a frame
// across chunks or merge several frames into one chunk. This accumulator
// buffers partial frames until a full one is available.
//
// Pure Foundation on purpose — unit-testable standalone via swiftc, no
// AVFoundation / CoreVideo dependency.

import Foundation

struct FrameAccumulator {
    private var buffer = Data()
    private var readOffset = 0

    /// Append a chunk of bytes from the stream.
    mutating func push(_ chunk: Data) {
        if readOffset > 0 {
            // ponytail: compact consumed prefix; O(remaining) per push, but
            // remaining stays < one frame in the streaming case (consumer
            // pulls every frame as it arrives), so this is effectively O(1).
            // If frames ever backlog massively, switch to a ring buffer.
            buffer.removeFirst(readOffset)
            readOffset = 0
        }
        buffer.append(chunk)
    }

    /// Extract all complete frames of `frameSize` bytes currently buffered.
    /// Incomplete trailing bytes stay buffered for the next push / inspection.
    ///
    /// Indices are ABSOLUTE into `buffer`: `push` compacts via
    /// `removeFirst`, which advances `buffer.startIndex` past the consumed
    /// prefix (a sliced `Data` keeps a nonzero `startIndex`). Treating
    /// `readOffset` as an absolute index with an assumed `startIndex == 0`
    /// traps inside `subdata(in:)` on the second frame — `0 < startIndex` is
    /// not a valid index even when `count >= frameSize`. Always offset from
    /// `buffer.startIndex`.
    mutating func pullFrames(frameSize: Int) -> [Data] {
        guard frameSize > 0 else { return [] }
        var frames: [Data] = []
        while readOffset + frameSize <= buffer.count {
            let start = buffer.startIndex + readOffset
            frames.append(buffer.subdata(in: start..<start + frameSize))
            readOffset += frameSize
        }
        return frames
    }

    /// Pull a single complete frame, or nil if not enough bytes yet. Leftover
    /// complete frames and the incomplete tail stay buffered. Used by the
    /// streaming reader which wants one frame per call. See `pullFrames` for
    /// why the slice base is `buffer.startIndex + readOffset`, not `readOffset`.
    mutating func pullFrame(frameSize: Int) -> Data? {
        guard frameSize > 0, readOffset + frameSize <= buffer.count else { return nil }
        let start = buffer.startIndex + readOffset
        let frame = buffer.subdata(in: start..<start + frameSize)
        readOffset += frameSize
        return frame
    }

    /// Leftover bytes not yet forming a complete frame (inspect at EOF).
    var remaining: Data {
        buffer.count > readOffset
            ? buffer.subdata(in: buffer.startIndex + readOffset..<buffer.endIndex)
            : Data()
    }
}