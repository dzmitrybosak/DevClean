import Foundation

/// Reads a pipe in the background and delivers complete lines.
/// `readabilityHandler` fires on a private queue, so all state is lock-protected.
/// Buffering happens at the byte level, which keeps split UTF-8 sequences and
/// split `@@MODULE|...` lines intact.
nonisolated final class LineStreamReader: @unchecked Sendable {
    private let handle: FileHandle
    private let onLines: @Sendable ([String]) -> Void
    private let lock = NSLock()
    private var pending = Data()
    private var finished = false

    init(handle: FileHandle, onLines: @escaping @Sendable ([String]) -> Void) {
        self.handle = handle
        self.onLines = onLines
    }

    func start() {
        handle.readabilityHandler = { [weak self] handle in
            self?.readAvailable(from: handle)
        }
    }

    /// Stops streaming, emits any buffered text without a trailing newline,
    /// and closes the reading end of the pipe.
    func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            handle.closeFile()
            return
        }
        finished = true
        handle.readabilityHandler = nil

        // Never wait for EOF here: after a cancellation a grandchild process
        // may still hold the write end of the pipe open. Drain only the bytes
        // that are already available, non-blocking.
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        if flags != -1 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let bytesRead = read(descriptor, &buffer, buffer.count)
            guard bytesRead > 0 else { break }
            pending.append(contentsOf: buffer[0..<bytesRead])
        }

        let tailLines = takeCompleteLines(emitRemainder: true)
        lock.unlock()

        handle.closeFile()
        if !tailLines.isEmpty {
            onLines(tailLines)
        }
    }

    private func readAvailable(from handle: FileHandle) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        let data = handle.availableData
        if data.isEmpty {
            // EOF: the write end was closed.
            finished = true
            handle.readabilityHandler = nil
            let remaining = takeCompleteLines(emitRemainder: true)
            lock.unlock()
            if !remaining.isEmpty {
                onLines(remaining)
            }
            return
        }

        pending.append(data)
        let lines = takeCompleteLines(emitRemainder: false)
        lock.unlock()

        if !lines.isEmpty {
            onLines(lines)
        }
    }

    /// Must be called with `lock` held. Splits off newline-terminated lines and,
    /// when requested, the trailing partial line as well.
    private func takeCompleteLines(emitRemainder: Bool) -> [String] {
        var lines: [String] = []
        var lineStart = pending.startIndex

        while let newlineIndex = pending[lineStart...].firstIndex(of: 0x0A) {
            var lineData = pending[lineStart..<newlineIndex]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            lines.append(String(decoding: lineData, as: UTF8.self))
            lineStart = pending.index(after: newlineIndex)
        }

        pending.removeSubrange(pending.startIndex..<lineStart)

        if emitRemainder, !pending.isEmpty {
            var lineData = pending
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            lines.append(String(decoding: lineData, as: UTF8.self))
            pending.removeAll()
        }

        return lines
    }
}
