import Foundation
import Dispatch
import Darwin

enum CLIEntrypoint {
    static func run(arguments: [String]) -> Never {
        let socketLocation = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LEO/runtime/leo.sock").path
        let cancellation = CLICancellationBox()
        let client = CLIClient(socketPath: socketLocation, cancellation: cancellation)

        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.global(qos: .userInitiated))
        interrupt.setEventHandler { cancellation.cancel() }
        interrupt.resume()

        if arguments.isEmpty {
            InteractiveSession(client: client, cancellation: cancellation).run()
        } else {
            do {
                try client.run(requestText: arguments.joined(separator: " "))
            } catch {
                fputs("leo: \(error)\n", stderr)
                interrupt.cancel()
                if case CLIClientError.cancelled = error { exit(130) }
                exit(1)
            }
        }
        interrupt.cancel()
        exit(0)
    }
}

CLIEntrypoint.run(arguments: Array(CommandLine.arguments.dropFirst()))
