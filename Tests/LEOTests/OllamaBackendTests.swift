import Foundation
import XCTest
@testable import LEO

final class OllamaBackendTests: XCTestCase {
    override func tearDown() {
        OllamaURLProtocol.handler = nil
        super.tearDown()
    }

    func testRejectsNonLoopbackEndpoints() throws {
        XCTAssertThrowsError(try OllamaBackend(endpoint: URL(string: "http://example.com:11434")!)) { error in
            XCTAssertEqual(error as? OllamaBackendError, .invalidEndpoint)
        }
        XCTAssertThrowsError(try OllamaBackend(endpoint: URL(string: "http://localhost.evil:11434")!)) { error in
            XCTAssertEqual(error as? OllamaBackendError, .invalidEndpoint)
        }
    }

    func testPrepareVerifiesConfiguredModelFromLocalTags() async throws {
        OllamaURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/tags")
            return OllamaURLProtocol.response(body: #"{"models":[{"name":"gemma3:4b"}]}"#)
        }
        let backend = try OllamaBackend(
            endpoint: URL(string: "http://127.0.0.1:11434")!,
            session: OllamaURLProtocol.session()
        )

        try await backend.prepare()
    }

    func testPrepareFailsWhenConfiguredModelIsNotInstalled() async throws {
        OllamaURLProtocol.handler = { _ in
            OllamaURLProtocol.response(body: #"{"models":[{"name":"qwen3:0.8b"}]}"#)
        }
        let backend = try OllamaBackend(
            endpoint: URL(string: "http://localhost:11434")!,
            session: OllamaURLProtocol.session()
        )

        do {
            try await backend.prepare()
            XCTFail("Expected missing model error")
        } catch let error as OllamaBackendError {
            XCTAssertEqual(error, .modelNotFound("gemma3:4b"))
        }
    }

    func testStreamSendsGenerateRequestAndYieldsChunkedNDJSONResponses() async throws {
        OllamaURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/generate")
            let body = try XCTUnwrap(request.bodyDataForTest)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "gemma3:4b")
            XCTAssertEqual(json["prompt"] as? String, "hello")
            XCTAssertEqual(json["stream"] as? Bool, true)
            return OllamaURLProtocol.response(
                body: "{\"response\":\"Hel\"}\n{\"response\":\"lo 🌎\"}\n{\"done\":true}\n",
                chunkSize: 3
            )
        }
        let backend = try OllamaBackend(
            endpoint: URL(string: "http://[::1]:11434")!,
            session: OllamaURLProtocol.session()
        )

        var chunks: [String] = []
        for try await chunk in backend.stream(ModelRequest(prompt: "hello")) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["Hel", "lo 🌎"])
    }

    func testMapsHTTPAndStreamErrors() async throws {
        OllamaURLProtocol.handler = { request in
            if request.url?.path == "/api/generate" {
                return OllamaURLProtocol.response(
                    status: 500,
                    body: #"{"error":"model runner unavailable"}"#
                )
            }
            return OllamaURLProtocol.response(status: 404, body: #"{"error":"not found"}"#)
        }
        let backend = try OllamaBackend(
            endpoint: URL(string: "http://127.0.0.1:11434")!,
            session: OllamaURLProtocol.session()
        )

        do {
            for try await _ in backend.stream(ModelRequest(prompt: "hello")) {}
            XCTFail("Expected server error")
        } catch let error as OllamaBackendError {
            XCTAssertEqual(error, .server(statusCode: 500, message: "model runner unavailable"))
        }
    }

    func testRejectsMalformedNDJSON() async throws {
        OllamaURLProtocol.handler = { _ in
            OllamaURLProtocol.response(body: "not-json\n")
        }
        let backend = try OllamaBackend(
            endpoint: URL(string: "http://127.0.0.1:11434")!,
            session: OllamaURLProtocol.session()
        )

        do {
            for try await _ in backend.stream(ModelRequest(prompt: "hello")) {}
            XCTFail("Expected malformed NDJSON error")
        } catch let error as OllamaBackendError {
            XCTAssertEqual(error, .malformedResponse)
        }
    }
}

private final class OllamaURLProtocol: URLProtocol {
    struct Stub {
        let response: HTTPURLResponse
        let body: Data
        let chunkSize: Int
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Stub)?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func response(status: Int = 200, body: String, chunkSize: Int = .max) -> Stub {
        Stub(
            response: HTTPURLResponse(
                url: URL(string: "http://127.0.0.1:11434")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/x-ndjson"]
            )!,
            body: Data(body.utf8),
            chunkSize: chunkSize
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { return }
            let stub = try handler(request)
            client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
            var offset = 0
            while offset < stub.body.count {
                let end = min(offset + stub.chunkSize, stub.body.count)
                client?.urlProtocol(self, didLoad: stub.body.subdata(in: offset..<end))
                offset = end
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyDataForTest: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
