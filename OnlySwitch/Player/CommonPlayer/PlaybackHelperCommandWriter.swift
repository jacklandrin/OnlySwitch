import Foundation
import os
import Darwin

/// Pipe IO runs on one queue; a lock bounds pending work before enqueueing, so repeated slider
/// changes cannot block the UI or accumulate unbounded queued writes when a child stops reading.
final class PlaybackHelperCommandWriter: Sendable {
    private struct Frame: Sendable {
        var data: Data
        var action: PlaybackHelperCommand.Action
        var offset = 0
        var inFlight = false
    }
    private struct State: Sendable {
        var frames: [Frame] = []
        var draining = false
        var closed = false
        var stalledSince: UInt64?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "com.onlyswitch.playback-helper.commands")
    private let handle: FileHandle
    private let onFailure: @Sendable () -> Void

    init?(handle: FileHandle, onFailure: @escaping @Sendable () -> Void) {
        self.handle = handle
        self.onFailure = onFailure
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        guard flags >= 0, fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) != -1,
              fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
    }

    func send(_ command: PlaybackHelperCommand) {
        guard let encoded = try? JSONEncoder().encode(command), encoded.count < PlaybackHelperLineFramer.maximumFrameSize else { return }
        let data = encoded + Data([10])
        let result = state.withLock { state -> Int in
            guard !state.closed else { return 0 }
            if command.action == .volume || command.action == .visible,
               let index = state.frames.indices.last, state.frames[index].offset == 0, !state.frames[index].inFlight,
               state.frames[index].action == command.action {
                state.frames[index].data = data
            } else {
                guard state.frames.count < 32,
                      state.frames.reduce(0, { $0 + $1.data.count }) + data.count <= 262_144 else { return -1 }
                state.frames.append(Frame(data: data, action: command.action))
            }
            guard !state.draining else { return 0 }
            state.draining = true
            return 1
        }
        if result < 0 { close(failed: true) }
        else if result > 0 { queue.async { self.drain() } }
    }

    func close(failed: Bool = false) {
        let shouldClose = state.withLock { state -> Bool in
            guard !state.closed else { return false }
            state.closed = true; state.frames = []
            return true
        }
        guard shouldClose else { return }
        queue.async { try? self.handle.close(); if failed { self.onFailure() } }
    }

    private func drain() {
        while let frame = state.withLock({ state -> Frame? in
            guard !state.closed, !state.frames.isEmpty else { state.draining = false; return nil }
            state.frames[0].inFlight = true
            return state.frames[0]
        }) {
            let count = frame.data.withUnsafeBytes { bytes in
                Darwin.write(handle.fileDescriptor, bytes.baseAddress!.advanced(by: frame.offset), frame.data.count - frame.offset)
            }
            if count > 0 {
                state.withLock { state in
                    guard !state.frames.isEmpty else { return }
                    state.stalledSince = nil
                    state.frames[0].inFlight = false
                    state.frames[0].offset += count
                    if state.frames[0].offset == state.frames[0].data.count { state.frames.removeFirst() }
                }
            } else if count < 0, errno == EINTR {
                continue
            } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                let expired = state.withLock { state -> Bool in
                    if !state.frames.isEmpty { state.frames[0].inFlight = false }
                    let now = DispatchTime.now().uptimeNanoseconds
                    if let start = state.stalledSince { return now - start >= 2_000_000_000 }
                    state.stalledSince = now
                    return false
                }
                if expired { close(failed: true) }
                else { queue.asyncAfter(deadline: .now() + .milliseconds(10)) { self.drain() } }
                return
            } else { close(failed: true); return }
        }
    }
}

