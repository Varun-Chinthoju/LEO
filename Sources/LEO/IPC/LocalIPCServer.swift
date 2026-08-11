import Foundation
import Darwin

final class LocalIPCConnection {
    private let fd: Int32

    fileprivate init(fd: Int32) { self.fd = fd }

    static func connect(to url: URL) throws -> LocalIPCConnection {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTCONN) }
        do {
            var address = try makeUnixAddress(url)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTCONN) }
            return LocalIPCConnection(fd: fd)
        } catch { Darwin.close(fd); throw error }
    }

    func send(_ message: IPCMessage) throws {
        let frame = try IPCFraming.encode(message)
        try writeAll(frame)
    }

    func receive() throws -> IPCMessage? {
        guard let header = try readExactly(4) else { return nil }
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length <= IPCFraming.maxFrameSize, let payload = try readExactly(Int(length)) else { throw IPCFramingError.malformedFrame }
        return try JSONDecoder().decode(IPCMessage.self, from: payload)
    }

    func close() { Darwin.close(fd) }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var pointer = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var remaining = raw.count
            while remaining > 0 {
                let result = Darwin.send(fd, pointer, remaining, 0)
                guard result > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE) }
                pointer = pointer.advanced(by: result); remaining -= result
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data? {
        var data = Data(count: count)
        var received = 0
        while received < count {
            let result = data.withUnsafeMutableBytes { raw in
                Darwin.recv(fd, raw.baseAddress!.advanced(by: received), count - received, 0)
            }
            if result == 0 { return received == 0 ? nil : nil }
            guard result > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE) }
            received += result
        }
        return data
    }
}

final class LocalIPCServer: @unchecked Sendable {
    let socketURL: URL
    private let orchestrator: InteractionOrchestrator
    private var listener: Int32 = -1
    private var acceptWorkItem: DispatchWorkItem?

    init(runtimeDirectoryURL: URL, orchestrator: InteractionOrchestrator) {
        self.socketURL = runtimeDirectoryURL.appendingPathComponent("leo.sock")
        self.orchestrator = orchestrator
    }

    func start() async throws {
        try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        chmod(socketURL.deletingLastPathComponent().path, 0o700)
        unlink(socketURL.path)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = try makeUnixAddress(socketURL)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindResult == 0, Darwin.listen(listener, 8) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE) }
        chmod(socketURL.path, 0o600)
        // `accept()` blocks. Keep the listener off the SwiftUI/AppKit executor so
        // a menu-bar launch can continue servicing IPC clients and UI work.
        let workItem = DispatchWorkItem { [weak self] in self?.acceptLoop() }
        acceptWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    func stop() async {
        acceptWorkItem?.cancel(); acceptWorkItem = nil
        if listener >= 0 { Darwin.close(listener); listener = -1 }
        unlink(socketURL.path)
    }

    private func acceptLoop() {
        while !(acceptWorkItem?.isCancelled ?? true) {
            let client = Darwin.accept(listener, nil, nil)
            guard client >= 0 else { continue }
            Task.detached { [weak self] in await self?.handle(client) }
        }
    }

    private func handle(_ fd: Int32) async {
        let connection = LocalIPCConnection(fd: fd)
        defer { connection.close() }
        do {
            guard let message = try connection.receive(), case .request(let request) = message.payload else { return }
            let events = await orchestrator.submit(request)
            for await event in events { try connection.send(IPCMessage(payload: .event(event))) }
        } catch { return }
    }
}

private func makeUnixAddress(_ url: URL) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = url.path
    let maxLength = MemoryLayout.size(ofValue: address.sun_path) - 1
    guard path.utf8.count <= maxLength else { throw POSIXError(.ENAMETOOLONG) }
    _ = path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { target in
            target.withMemoryRebound(to: CChar.self, capacity: maxLength + 1) { strncpy($0, source, maxLength) }
        }
    }
    return address
}
