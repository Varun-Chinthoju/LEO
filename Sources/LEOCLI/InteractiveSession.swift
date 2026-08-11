import Foundation
import Darwin

final class InteractiveSession {
    private let client: CLIClient
    private let cancellation: CLICancellationBox
    private let sessionID = UUID()

    init(client: CLIClient, cancellation: CLICancellationBox) {
        self.client = client
        self.cancellation = cancellation
    }

    func run() {
        while true {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 100)
            if cancellation.isCancelled() {
                cancellation.reset()
                fputs("leo: request cancelled\n", stderr)
                continue
            }
            guard ready > 0 else { continue }
            guard let line = readLine(strippingNewline: true) else { return }
            let request = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if request.isEmpty { continue }
            do {
                try client.run(requestText: request, sessionID: sessionID)
            } catch CLIClientError.cancelled {
                cancellation.reset()
                fputs("leo: request cancelled\n", stderr)
            } catch {
                fputs("leo: \(error)\n", stderr)
            }
        }
    }
}
