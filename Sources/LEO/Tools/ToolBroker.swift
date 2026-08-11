import Foundation

enum ToolBrokerError: Error, Equatable, Sendable {
    case invalidToolName(String)
    case unknownTool(String)
    case missingArguments([String])
    case executionFailed(String)
    case confirmationRequired
    case denied(String)
    case timedOut
    case cancelled
}

private final class ToolExecutionRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ToolResult, Error>?
    private var completed = false

    func install(_ continuation: CheckedContinuation<ToolResult, Error>) {
        lock.lock()
        if completed {
            lock.unlock()
            continuation.resume(throwing: ToolBrokerError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func start(
        operation: @escaping @Sendable () -> Result<ToolResult, Error>,
        timeoutNanoseconds: UInt64
    ) {
        lock.lock()
        let shouldStart = !completed
        lock.unlock()
        guard shouldStart else { return }

        Task.detached { [weak self] in
            guard let self else { return }
            self.finish(operation())
        }

        Task.detached { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.finish(.failure(ToolBrokerError.timedOut))
            } catch {
                // The timeout task is best-effort; operation completion or caller
                // cancellation has already decided the result.
            }
        }
    }

    func cancel() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: ToolBrokerError.cancelled)
    }

    private func finish(_ result: Result<ToolResult, Error>) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

actor ToolBroker {
    private var definitions: [String: ToolDefinition] = [:]
    private let policy: PolicyEngine

    init(definitions: [ToolDefinition] = [], policy: PolicyEngine = PolicyEngine()) {
        self.policy = policy
        for definition in definitions { self.definitions[definition.name] = definition }
    }

    func register(_ definition: ToolDefinition) {
        definitions[definition.name] = definition
    }

    func execute(
        _ proposal: ToolProposal,
        source: RequestSource = .commandPalette,
        confirmationGranted: Bool = false,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws -> ToolResult {
        guard proposal.name.range(of: "^[a-z][a-z0-9]*(\\.[a-z][a-z0-9]*)+$", options: .regularExpression) != nil else {
            throw ToolBrokerError.invalidToolName(proposal.name)
        }
        guard let definition = definitions[proposal.name] else { throw ToolBrokerError.unknownTool(proposal.name) }
        let missing = definition.requiredArguments.subtracting(proposal.arguments.keys)
        guard missing.isEmpty else { throw ToolBrokerError.missingArguments(missing.sorted()) }
        switch policy.decide(effect: definition.effect, source: source, confirmationGranted: confirmationGranted) {
        case .allow: break
        case .confirm: throw ToolBrokerError.confirmationRequired
        case .deny(let message): throw ToolBrokerError.denied(message)
        }

        guard !Task.isCancelled else { throw ToolBrokerError.cancelled }

        let traceID = UUID().uuidString
        do {
            let race = ToolExecutionRace()
            let result = try await withTaskCancellationHandler {
                return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ToolResult, Error>) in
                    race.install(continuation)
                    race.start(
                        operation: { Result { try definition.execute(proposal.arguments) } },
                        timeoutNanoseconds: timeoutNanoseconds
                    )
                }
            } onCancel: {
                // The cancellation handler is intentionally independent of the
                // actor, so cancellation can unblock a caller immediately.
                race.cancel()
            }
            return ToolResult(value: result.value, succeeded: result.succeeded, traceID: traceID)
        } catch is CancellationError {
            throw ToolBrokerError.cancelled
        } catch let error as ToolBrokerError {
            throw error
        } catch {
            throw ToolBrokerError.executionFailed(error.localizedDescription)
        }
    }
}
