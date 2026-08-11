import Foundation

protocol LanguageModel: Sendable {
    func response(to input: AssistantInput) async throws -> String
}

protocol StreamingLanguageModel: LanguageModel {
    func responseStream(to input: AssistantInput) async throws -> AsyncThrowingStream<String, Error>
}

enum LanguageModelConfigurationError: LocalizedError, Sendable {
    case unavailable

    var errorDescription: String? {
        "The local model is unavailable. Start LM Studio and load the configured model, then try again."
    }
}

struct UnavailableLanguageModel: LanguageModel {
    func response(to input: AssistantInput) async throws -> String {
        throw LanguageModelConfigurationError.unavailable
    }
}

struct MockLanguageModel: LanguageModel {
    let responseText: String
    let delayNanoseconds: UInt64

    init(responseText: String = "Done.", delayNanoseconds: UInt64 = 0) {
        self.responseText = responseText
        self.delayNanoseconds = delayNanoseconds
    }

    func response(to input: AssistantInput) async throws -> String {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        try Task.checkCancellation()
        return responseText
    }
}
