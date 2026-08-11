import Foundation

enum VoiceCue: String, Sendable {
    case thinking
    case answering
}

final class VoiceCuePlayer: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcess: Process?

    func play(_ cue: VoiceCue) async {
        guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "aiff", subdirectory: "VoiceCues") else {
            leoVoiceLogger.error("voice_cue_missing cue=\(cue.rawValue, privacy: .public)")
            return
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.playSynchronously(url)
                continuation.resume()
            }
        }
    }

    func stop() {
        lock.lock()
        let process = activeProcess
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    private func playSynchronously(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["-v", "3.0", url.path]

        lock.lock()
        activeProcess = process
        lock.unlock()
        defer {
            lock.lock()
            if activeProcess === process { activeProcess = nil }
            lock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            leoVoiceLogger.error("voice_cue_failed cue=\(url.deletingPathExtension().lastPathComponent, privacy: .public)")
        }
    }
}
