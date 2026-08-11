import Foundation

enum OllamaBackendError: Error, Equatable, Sendable {
    case invalidEndpoint
    case invalidModel
    case modelNotFound(String)
    case server(statusCode: Int, message: String)
    case malformedResponse
    case transport(String)
}

extension OllamaBackendError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Ollama endpoint must be localhost or a loopback address."
        case .invalidModel:
            return "Ollama model name is invalid."
        case .modelNotFound(let model):
            return "Ollama model is not installed locally: \(model)"
        case .server(let statusCode, let message):
            return "Ollama returned HTTP \(statusCode): \(message)"
        case .malformedResponse:
            return "Ollama returned malformed NDJSON."
        case .transport(let message):
            return "Ollama transport failed: \(message)"
        }
    }
}

struct OllamaBackend: ModelBackend {
    static let defaultEndpoint = URL(string: "http://127.0.0.1:11434")!
    static let defaultModel = "gemma3:4b"

    let endpoint: URL
    let model: String
    private let session: URLSession

    init(
        endpoint: URL = OllamaBackend.defaultEndpoint,
        model: String = OllamaBackend.defaultModel,
        session: URLSession = .shared
    ) throws {
        guard Self.isLoopback(endpoint) else { throw OllamaBackendError.invalidEndpoint }
        guard Self.isValidModel(model) else { throw OllamaBackendError.invalidModel }
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    func prepare() async throws {
        var request = URLRequest(url: endpoint.appendingPathComponent("api/tags"))
        request.httpMethod = "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OllamaBackendError.transport(error.localizedDescription)
        }
        try Self.validateHTTP(response, body: data)

        do {
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            guard tags.models.contains(where: { $0.name == model }) else {
                throw OllamaBackendError.modelNotFound(model)
            }
        } catch let error as OllamaBackendError {
            throw error
        } catch {
            throw OllamaBackendError.malformedResponse
        }
    }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<String, Error> {
        let endpoint = endpoint
        let model = model
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: endpoint.appendingPathComponent("api/generate"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(
                        GenerateRequest(model: model, prompt: request.prompt, stream: true)
                    )

                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await session.bytes(for: urlRequest)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw OllamaBackendError.transport(error.localizedDescription)
                    }

                    guard let response = response as? HTTPURLResponse else {
                        throw OllamaBackendError.malformedResponse
                    }
                    guard (200..<300).contains(response.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                        }
                        throw Self.serverError(statusCode: response.statusCode, body: body)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.utf8.count <= 1_048_576 else {
                            throw OllamaBackendError.malformedResponse
                        }
                        guard !line.isEmpty else { continue }
                        let event: GenerateResponse
                        do {
                            event = try JSONDecoder().decode(GenerateResponse.self, from: Data(line.utf8))
                        } catch {
                            throw OllamaBackendError.malformedResponse
                        }
                        if let error = event.error {
                            throw OllamaBackendError.server(statusCode: response.statusCode, message: error)
                        }
                        if let text = event.response, !text.isEmpty {
                            continuation.yield(text)
                        }
                        if event.done == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unload() async {}

    private static func isValidModel(_ model: String) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == model && !model.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 0x20 })
    }

    private static func isLoopback(_ endpoint: URL) -> Bool {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let rawHost = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return false }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 127 && octets.allSatisfy { (0...255).contains($0) }
    }

    private static func validateHTTP(_ response: URLResponse, body: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw OllamaBackendError.malformedResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw serverError(statusCode: response.statusCode, body: body)
        }
    }

    private static func serverError(statusCode: Int, body: Data) -> OllamaBackendError {
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: body).error)
            ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return .server(statusCode: statusCode, message: message)
    }
}

private struct TagsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

private struct GenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct GenerateResponse: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

private struct ErrorResponse: Decodable {
    let error: String
}
