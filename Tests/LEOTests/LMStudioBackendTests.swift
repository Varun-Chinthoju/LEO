import Foundation
import XCTest
@testable import LEO

final class LMStudioBackendTests: XCTestCase {
    override func tearDown() {
        LMStudioURLProtocol.handler = nil
        super.tearDown()
    }

    func testDefaultsToQwen3FourBAndRequiresAnInjectedToken() throws {
        let backend = try LMStudioBackend(token: "test-token", session: LMStudioURLProtocol.session())

        XCTAssertEqual(backend.endpoint.absoluteString, "http://127.0.0.1:1234")
        XCTAssertEqual(backend.model, "qwen/qwen3-4b:2")

        XCTAssertThrowsError(try LMStudioBackend(token: "", session: LMStudioURLProtocol.session())) { error in
            XCTAssertEqual(error as? LMStudioBackendError, .missingToken)
        }
    }

    func testRejectsNonLoopbackEndpoints() throws {
        XCTAssertThrowsError(try LMStudioBackend(
            endpoint: URL(string: "http://example.com:1234")!,
            token: "test-token",
            session: LMStudioURLProtocol.session()
        )) { error in
            XCTAssertEqual(error as? LMStudioBackendError, .invalidEndpoint)
        }
        XCTAssertThrowsError(try LMStudioBackend(
            endpoint: URL(string: "http://localhost.evil:1234")!,
            token: "test-token",
            session: LMStudioURLProtocol.session()
        )) { error in
            XCTAssertEqual(error as? LMStudioBackendError, .invalidEndpoint)
        }
    }

    func testPrepareVerifiesConfiguredModelAndDoesNotExposeToken() async throws {
        LMStudioURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            XCTAssertFalse(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("secret-token") == true)
            return LMStudioURLProtocol.response(body: #"{"models":[{"key":"qwen/qwen3-4b"}]}"#)
        }

        let backend = try LMStudioBackend(token: "secret-token", session: LMStudioURLProtocol.session())
        try await backend.prepare()
    }

    func testPrepareMapsMissingModel() async throws {
        LMStudioURLProtocol.handler = { _ in
            LMStudioURLProtocol.response(body: #"{"models":[{"key":"other-model"}]}"#)
        }
        let backend = try LMStudioBackend(token: "test-token", session: LMStudioURLProtocol.session())

        do {
            try await backend.prepare()
            XCTFail("Expected missing model error")
        } catch let error as LMStudioBackendError {
            XCTAssertEqual(error, .modelNotFound("qwen/qwen3-4b:2"))
        }
    }

    func testStreamSendsChatRequestAndYieldsChunkedSSEContent() async throws {
        LMStudioURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try XCTUnwrap(request.bodyDataForTest)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "qwen/qwen3-4b:2")
            XCTAssertEqual(json["stream"] as? Bool, true)
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.first?["role"] as? String, "system")
            XCTAssertTrue((messages.first?["content"] as? String)?.contains("You are LEO") == true)
            XCTAssertEqual(messages.dropFirst().first?["role"] as? String, "user")
            XCTAssertEqual(messages.dropFirst().first?["content"] as? String, "hello")
            return LMStudioURLProtocol.response(
                body: "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"lo 🌎\"}}]}\n\ndata: [DONE]\n\n",
                chunkSize: 2
            )
        }
        let backend = try LMStudioBackend(token: "test-token", session: LMStudioURLProtocol.session())

        var chunks: [String] = []
        for try await chunk in backend.stream(ModelRequest(prompt: "hello")) {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["Hel", "lo 🌎"])
    }

    func testMapsHTTPAndLocalAPIErrors() async throws {
        LMStudioURLProtocol.handler = { request in
            if request.url?.path == "/v1/chat/completions" {
                return LMStudioURLProtocol.response(status: 503, body: #"{"error":{"message":"server busy"}}"#)
            }
            return LMStudioURLProtocol.response(status: 401, body: #"{"error":{"message":"bad token"}}"#)
        }
        let backend = try LMStudioBackend(token: "test-token", session: LMStudioURLProtocol.session())

        do {
            for try await _ in backend.stream(ModelRequest(prompt: "hello")) {}
            XCTFail("Expected server error")
        } catch let error as LMStudioBackendError {
            XCTAssertEqual(error, .server(statusCode: 503, message: "server busy"))
        }
    }

    func testRejectsMalformedSSE() async throws {
        LMStudioURLProtocol.handler = { _ in
            LMStudioURLProtocol.response(body: "data: not-json\n\n")
        }
        let backend = try LMStudioBackend(token: "test-token", session: LMStudioURLProtocol.session())

        do {
            for try await _ in backend.stream(ModelRequest(prompt: "hello")) {}
            XCTFail("Expected malformed response error")
        } catch let error as LMStudioBackendError {
            XCTAssertEqual(error, .malformedResponse)
        }
    }
}

private final class LMStudioURLProtocol: URLProtocol {
    struct Stub {
        let response: HTTPURLResponse
        let body: Data
        let chunkSize: Int
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Stub)?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LMStudioURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func response(status: Int = 200, body: String, chunkSize: Int = .max) -> Stub {
        Stub(
            response: HTTPURLResponse(
                url: URL(string: "http://127.0.0.1:1234")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
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
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
