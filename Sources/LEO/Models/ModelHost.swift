import Foundation

protocol ModelBackend: Sendable {
    func prepare() async throws
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<String, Error>
    func unload() async
}

struct MockModelBackend: ModelBackend {
    let response: String
    init(response: String = "Done.") { self.response = response }

    func prepare() async throws {}
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }
    func unload() async {}
}

actor ModelHost {
    private let backend: any ModelBackend
    private var prepared = false
    private var preparationTask: Task<Void, Error>?
    private var activeRequests = 0
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(backend: any ModelBackend = MockModelBackend()) { self.backend = backend }

    func prepare() async throws {
        guard !prepared else { return }
        if let preparationTask {
            return try await preparationTask.value
        }

        let backend = self.backend
        let task = Task {
            try await backend.prepare()
        }
        preparationTask = task

        do {
            try await task.value
            prepared = true
            preparationTask = nil
        } catch {
            preparationTask = nil
            throw error
        }
    }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<String, Error> {
        let id = UUID()
        activeRequests += 1
        let source = backend.stream(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in source {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                self.finished(id)
            }
            // The host is already isolated here, so register synchronously. This
            // prevents unload() from racing the task-registration hop.
            activeTasks[id] = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func responseStream(to input: AssistantInput) async throws -> AsyncThrowingStream<String, Error> {
        try Task.checkCancellation()
        try await prepare()
        try Task.checkCancellation()
        return stream(request(for: input))
    }

    func cancelAll() {
        for task in activeTasks.values { task.cancel() }
        activeTasks.removeAll()
        activeRequests = 0
    }

    func unload() async {
        cancelAll()
        await backend.unload()
        prepared = false
        preparationTask?.cancel()
        preparationTask = nil
    }

    func resourceSnapshot() -> ModelResourceSnapshot {
        ModelResourceSnapshot(isPrepared: prepared, activeRequestCount: activeRequests)
    }

    private func finished(_ id: UUID) { activeTasks.removeValue(forKey: id); activeRequests = max(0, activeRequests - 1) }
}

extension ModelHost: StreamingLanguageModel {
    func response(to input: AssistantInput) async throws -> String {
        var response = ""
        for try await chunk in try await responseStream(to: input) {
            try Task.checkCancellation()
            response.append(contentsOf: chunk)
        }
        // AsyncThrowingStream may finish its iterator normally when the
        // consuming task is cancelled. Preserve LanguageModel cancellation
        // semantics at the bridge boundary.
        try Task.checkCancellation()
        return response
    }
}

private extension ModelHost {
    func request(for input: AssistantInput) -> ModelRequest {
        switch input {
        case .text(let prompt):
            return ModelRequest(prompt: prompt)
        }
    }
}
