import Foundation

struct StatusPresenter: Sendable {
    private(set) var lastStatus: String?

    mutating func present(_ event: AssistantEvent) -> String? {
        let candidate: String?
        switch event {
        case .thinking:
            candidate = "Thinking…"
        case .reasoningSummary(let summary):
            candidate = summary
        case .actionStarted(let action):
            candidate = action.title
        case .actionProgress(let progress):
            candidate = progress.detail
        case .actionFinished(let result):
            candidate = result.title
        case .responseCompleted:
            candidate = "Done"
        case .failed:
            candidate = "Failed"
        default:
            candidate = nil
        }

        guard let candidate, !candidate.isEmpty, candidate != lastStatus else { return nil }
        lastStatus = candidate
        return candidate
    }
}
