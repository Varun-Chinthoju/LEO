import Foundation

struct TerminalRenderer {
    private var renderedDelta = false

    mutating func render(_ event: CLIWireEvent) throws -> Bool {
        switch event.value {
        case .responseDelta(let text):
            print(text, terminator: "")
            fflush(stdout)
            renderedDelta = true
            return false
        case .responseCompleted(let text):
            if !renderedDelta { print(text) } else { print() }
            return true
        case .failed(let failure):
            fputs("leo: \(failure.message)\n", stderr)
            return true
        case .accepted, .thinking, .reasoningSummary, .actionStarted, .actionProgress, .actionFinished, .confirmationRequired:
            return false
        }
    }
}
