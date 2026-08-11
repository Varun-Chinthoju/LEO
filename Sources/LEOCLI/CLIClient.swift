import Foundation
import Darwin

enum CLIClientError: Error, CustomStringConvertible {
    case socketPathTooLong
    case connectionFailed(String)
    case frameTooLarge
    case malformedFrame
    case unsupportedVersion(Int)
    case unexpectedPayload
    case serverClosedConnection
    case cancelled

    var description: String {
        switch self {
        case .socketPathTooLong: return "socket path is too long"
        case .connectionFailed(let message): return "could not connect to LEO (\(message))"
        case .frameTooLarge: return "server sent an oversized IPC frame"
        case .malformedFrame: return "server sent a malformed IPC frame"
        case .unsupportedVersion(let version): return "unsupported IPC version \(version)"
        case .unexpectedPayload: return "server sent an unexpected IPC payload"
        case .serverClosedConnection: return "LEO closed the connection before completing the request"
        case .cancelled: return "request cancelled"
        }
    }
}

final class CLICancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var activeFD: Int32 = -1

    func reset() { lock.lock(); cancelled = false; lock.unlock() }
    func setActive(_ fd: Int32) { lock.lock(); activeFD = fd; lock.unlock() }
    func clearActive() { lock.lock(); activeFD = -1; lock.unlock() }
    func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock()
        cancelled = true
        let fd = activeFD
        lock.unlock()
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
    }
}

final class CLIClient: @unchecked Sendable {
    let socketPath: String
    let cancellation: CLICancellationBox

    init(socketPath: String, cancellation: CLICancellationBox = CLICancellationBox()) {
        self.socketPath = socketPath
        self.cancellation = cancellation
    }

    func cancel() { cancellation.cancel() }

    func run(requestText: String, sessionID: UUID = UUID(), renderer: TerminalRenderer = TerminalRenderer()) throws {
        cancellation.reset()
        let fd = try connect()
        cancellation.setActive(fd)
        defer { close(fd); cancellation.clearActive() }

        let request = CLIWireRequest(
            id: UUID(), sessionID: sessionID, input: .text(requestText), source: "cli",
            createdAt: Date(), presentation: .init(showText: true, speakResponse: false, machineReadable: true)
        )
        let message = CLIWireMessage(version: CLIWireMessage.currentVersion, payload: .request(request))
        try send(message, on: fd)

        var outputRenderer = renderer
        var sawTerminalEvent = false
        while !sawTerminalEvent {
            guard let message = try receive(on: fd) else {
                if cancellation.isCancelled() { throw CLIClientError.cancelled }
                throw CLIClientError.serverClosedConnection
            }
            guard message.version == CLIWireMessage.currentVersion else {
                throw CLIClientError.unsupportedVersion(message.version)
            }
            guard case .event(let event) = message.payload else { throw CLIClientError.unexpectedPayload }
            sawTerminalEvent = try outputRenderer.render(event)
        }
    }

    private func connect() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIClientError.connectionFailed(String(cString: strerror(errno))) }
        do {
            var address = try unixAddress()
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw CLIClientError.connectionFailed(String(cString: strerror(errno))) }
            return fd
        } catch { close(fd); throw error }
    }

    private func unixAddress() throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path) - 1
        guard socketPath.utf8.count <= maxLength else { throw CLIClientError.socketPathTooLong }
        socketPath.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { target in
                target.withMemoryRebound(to: CChar.self, capacity: maxLength + 1) {
                    strncpy($0, source, maxLength)
                }
            }
        }
        return address
    }

    private func send(_ message: CLIWireMessage, on fd: Int32) throws {
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= 1_048_576 else { throw CLIClientError.frameTooLarge }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        try frame.withUnsafeBytes { raw in
            var pointer = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.send(fd, pointer, remaining, 0)
                if written > 0 { pointer = pointer.advanced(by: written); remaining -= written; continue }
                if written < 0 && errno == EINTR { continue }
                if cancellation.isCancelled() { throw CLIClientError.cancelled }
                throw CLIClientError.connectionFailed(String(cString: strerror(errno)))
            }
        }
    }

    private func receive(on fd: Int32) throws -> CLIWireMessage? {
        guard let header = try readExactly(4, on: fd) else { return nil }
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length <= 1_048_576 else { throw CLIClientError.frameTooLarge }
        guard let payload = try readExactly(Int(length), on: fd) else { throw CLIClientError.malformedFrame }
        do { return try JSONDecoder().decode(CLIWireMessage.self, from: payload) }
        catch { throw CLIClientError.malformedFrame }
    }

    private func readExactly(_ count: Int, on fd: Int32) throws -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let result = data.withUnsafeMutableBytes { raw in
                Darwin.recv(fd, raw.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            if result == 0 { return nil }
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else {
                if cancellation.isCancelled() { throw CLIClientError.cancelled }
                throw CLIClientError.connectionFailed(String(cString: strerror(errno)))
            }
            offset += result
        }
        return data
    }

}
