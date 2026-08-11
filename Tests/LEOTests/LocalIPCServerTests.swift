import XCTest
import Foundation
import Darwin
@testable import LEO

final class LocalIPCServerTests: XCTestCase {
    func testServerStreamsOrchestratorEventsOverUnixSocket() async throws {
        let runtimeDirectoryURL = try makeRuntimeDirectory()
        let orchestrator = InteractionOrchestrator(model: MockLanguageModel(responseText: "Hello"))
        let server = LocalIPCServer(runtimeDirectoryURL: runtimeDirectoryURL, orchestrator: orchestrator)

        try await server.start()
        defer { Task { await server.stop() } }

        XCTAssertEqual(try posixPermissions(of: runtimeDirectoryURL), 0o700)
        XCTAssertEqual(try posixPermissions(of: server.socketURL), 0o600)

        let connection = try LocalIPCConnection.connect(to: server.socketURL)
        defer { connection.close() }

        let request = AssistantRequest(input: .text("hello"), source: .commandPalette)
        try connection.send(IPCMessage(payload: .request(request)))

        let events = try collectEvents(from: connection)
        XCTAssertEqual(
            events,
            [
                .accepted(request.id),
                .thinking,
                .reasoningSummary("Working on your request"),
                .responseCompleted("Hello")
            ]
        )
    }

    func testMalformedClientDoesNotPreventSubsequentConnections() async throws {
        let runtimeDirectoryURL = try makeRuntimeDirectory()
        let orchestrator = InteractionOrchestrator(model: MockLanguageModel(responseText: "Recovered"))
        let server = LocalIPCServer(runtimeDirectoryURL: runtimeDirectoryURL, orchestrator: orchestrator)

        try await server.start()
        defer { Task { await server.stop() } }

        try sendMalformedFrame(to: server.socketURL)

        let connection = try LocalIPCConnection.connect(to: server.socketURL)
        defer { connection.close() }

        let request = AssistantRequest(input: .text("hello again"), source: .commandPalette)
        try connection.send(IPCMessage(payload: .request(request)))

        let events = try collectEvents(from: connection)
        XCTAssertEqual(events.last, .responseCompleted("Recovered"))
    }

    func testStopRemovesSocketAndRejectsReconnects() async throws {
        let runtimeDirectoryURL = try makeRuntimeDirectory()
        let server = LocalIPCServer(runtimeDirectoryURL: runtimeDirectoryURL, orchestrator: InteractionOrchestrator())

        try await server.start()
        let socketURL = server.socketURL
        try await server.stop()

        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
        XCTAssertThrowsError(try LocalIPCConnection.connect(to: socketURL))
    }

    private func collectEvents(from connection: LocalIPCConnection) throws -> [AssistantEvent] {
        var events: [AssistantEvent] = []
        while let message = try connection.receive() {
            switch message.payload {
            case .event(let event):
                events.append(event)
                if case .responseCompleted = event {
                    return events
                }
            case .request:
                XCTFail("Server should not send request payloads to the client")
            }
        }

        return events
    }

    private func makeRuntimeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func posixPermissions(of url: URL) throws -> Int {
        var info = stat()
        let result = url.path.withCString { stat($0, &info) }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL) }
        return Int(info.st_mode & 0o777)
    }

    private func sendMalformedFrame(to socketURL: URL) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTCONN) }
        defer { close(fd) }

        var address = try unixSocketAddress(for: socketURL)
        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTCONN) }

        let payload = Data([0x00, 0x01])
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        try frame.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var remaining = bytes.count
            var pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
            while remaining > 0 {
                let written = Darwin.send(fd, pointer, remaining, 0)
                guard written >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE) }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }

    private func unixSocketAddress(for socketURL: URL) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let path = socketURL.path
        let maxLength = MemoryLayout.size(ofValue: address.sun_path) - 1
        guard path.utf8.count <= maxLength else { throw POSIXError(.ENAMETOOLONG) }

        _ = path.withCString { cString in
            withUnsafeMutablePointer(to: &address.sun_path) { sunPath in
                sunPath.withMemoryRebound(to: CChar.self, capacity: maxLength + 1) { destination in
                    strncpy(destination, cString, maxLength)
                }
            }
        }

        return address
    }
}
