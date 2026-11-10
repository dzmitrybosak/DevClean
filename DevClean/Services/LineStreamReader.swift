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

    /// Stops streaming, drains the bytes that are already available (never
    /// waiting for EOF: after a cancellation a grandchild may still hold the
    /// write end open), closes the reading end and returns the buffered text,
    /// including a trailing line without a newline.
    ///
    /// The tail is *returned*, not delivered: at termination the caller must
    /// hand it over in the same MainActor turn as the completion callback.
    func finish() -> [String] {
        lock.lock()
        guard !finished else {
            lock.unlock()
            closeHandle()
            return []
        }
        finished = true
        handle.readabilityHandler = nil

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

        closeHandle()
        return tailLines
    }

    /// `close()` throws instead of crashing, so a double close — the EOF path
    /// already marked the reader finished — is harmless.
    private func closeHandle() {
        try? handle.close()
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
