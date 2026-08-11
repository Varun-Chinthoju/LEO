import Foundation

struct KokoroSpeechConfiguration: Sendable, Equatable {
    // Qwen3-TTS is more expressive than the previous Kokoro preset while
    // keeping the 0.6B model small enough for a responsive local assistant.
    var model = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    var voice = "Ryan"
    var languageCode = "English"
}

actor KokoroSpeechSynthesizer: SpeechSynthesizer {
    private let configuration: KokoroSpeechConfiguration
    private let runner: KokoroProcessRunner

    init(configuration: KokoroSpeechConfiguration = .init()) {
        self.configuration = configuration
        self.runner = KokoroProcessRunner()
    }

    func speak(_ text: String) -> AsyncStream<AudioFrame> {
        let configuration = self.configuration
        let runner = self.runner
        return AsyncStream { continuation in
            Task.detached {
                do {
                    leoVoiceLogger.info("tts_started")
                    NSLog("LEO Kokoro TTS starting")
                    try runner.generateAndPlay(text: text, configuration: configuration)
                    continuation.yield(AudioFrame(samples: [0], sampleRate: 24_000))
                    leoVoiceLogger.info("tts_finished")
                    NSLog("LEO Kokoro TTS finished")
                } catch KokoroSpeechError.interrupted {
                    leoVoiceLogger.info("tts_interrupted")
                } catch {
                    leoVoiceLogger.error("tts_failed")
                    NSLog("LEO Kokoro TTS failed: %{public}@", error.localizedDescription)
                }
                continuation.finish()
            }
        }
    }

    func stop() {
        runner.stop()
    }
}

private final class KokoroProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var activeProcesses: [Process] = []
    private var stopRequested = false
    private let volumeDucker = SystemAudioDucker()

    func generateAndPlay(text: String, configuration: KokoroSpeechConfiguration) throws {
        lock.lock()
        stopRequested = false
        lock.unlock()

        let root = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let python = root.appendingPathComponent(".venv/bin/python").path
        let script = root.appendingPathComponent("script/kokoro_speak.py").path
        guard FileManager.default.isExecutableFile(atPath: python), FileManager.default.fileExists(atPath: script) else {
            throw KokoroSpeechError.runtimeUnavailable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-kokoro-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: python)
        var environment = ProcessInfo.processInfo.environment
        environment["VIRTUAL_ENV"] = root.appendingPathComponent(".venv").path
        environment["PATH"] = root.appendingPathComponent(".venv/bin").path + ":" + (environment["PATH"] ?? "")
        generator.environment = environment
        let generatorError = Pipe()
        generator.standardError = generatorError
        generator.arguments = [
            script,
            "--model", configuration.model,
            "--voice", configuration.voice,
            "--lang-code", configuration.languageCode,
            "--text", text,
            "--output", outputURL.path
        ]
        try run(generator, errorPipe: generatorError, label: "generation")

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "1.0", outputURL.path]
        let originalVolume = volumeDucker.beginForSpeechPlayback()
        defer {
            if let originalVolume { volumeDucker.restore(originalVolume) }
        }
        try run(player, label: "playback")
    }

    func stop() {
        lock.lock()
        stopRequested = true
        let processes = activeProcesses
        lock.unlock()
        processes.forEach { process in
            if process.isRunning { process.terminate() }
        }
    }

    private func run(_ process: Process, errorPipe: Pipe? = nil, label: String) throws {
        lock.lock()
        activeProcesses.append(process)
        lock.unlock()
        defer {
            lock.lock()
            activeProcesses.removeAll { $0 === process }
            lock.unlock()
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            lock.lock()
            let wasStopped = stopRequested
            lock.unlock()
            if wasStopped {
                throw KokoroSpeechError.interrupted
            }
            let detail = errorPipe.flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) } ?? ""
            let safeDetail = detail
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(1200)
            leoVoiceLogger.error("tts_process_failed stage=\(label, privacy: .public) status=\(process.terminationStatus, privacy: .public) detail=\(String(safeDetail), privacy: .public)")
            NSLog("LEO Kokoro TTS %{public}@ exited with status %d: %{public}@", label, process.terminationStatus, detail.trimmingCharacters(in: .whitespacesAndNewlines))
            throw KokoroSpeechError.processFailed
        }
    }
}

private enum KokoroSpeechError: LocalizedError {
    case runtimeUnavailable
    case processFailed
    case interrupted

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: return "Project-local Kokoro runtime is not installed."
        case .processFailed: return "Kokoro generation or audio playback failed."
        case .interrupted: return "Kokoro speech was interrupted."
        }
    }
}
