import Foundation

enum SpeechRecognitionEvent: Sendable, Equatable {
    case partial(String)
    case final(String)
}

protocol SpeechRecognizer: Sendable {
    func recognize(frames: [AudioFrame]) async throws -> AsyncStream<SpeechRecognitionEvent>
}

enum ParakeetSpeechRecognizerError: Error, Equatable {
    case noAudio
    case runtimeUnavailable(String)
    case transcriptionFailed(String)
}

protocol ParakeetTranscriptionCommand: Sendable {
    func transcribe(audioURL: URL, model: String) throws -> String
}

/// Bridges LEO's frame-oriented voice pipeline to the Apple-Silicon Parakeet
/// MLX runtime. The command is injected so model execution stays replaceable
/// and deterministic in tests.
struct ParakeetSpeechRecognizer: SpeechRecognizer {
    // Prefer the larger MLX checkpoint for robust recognition of natural
    // phrasing. The smaller 110M English model remains available through the
    // LEO_PARAKEET_MODEL environment override when latency is the priority.
    static let defaultModel = ProcessInfo.processInfo.environment["LEO_PARAKEET_MODEL"]
        ?? "mlx-community/parakeet-tdt-0.6b-v3"

    let model: String
    let command: any ParakeetTranscriptionCommand

    init(model: String = Self.defaultModel, command: any ParakeetTranscriptionCommand = ProcessParakeetTranscriptionCommand()) {
        self.model = model
        self.command = command
    }

    func recognize(frames: [AudioFrame]) async throws -> AsyncStream<SpeechRecognitionEvent> {
        guard !frames.isEmpty else { throw ParakeetSpeechRecognizerError.noAudio }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leo-parakeet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let audioURL = temporaryDirectory.appendingPathComponent("input.wav")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try WAVFile.write(frames: frames, to: audioURL)

        let text: String
        do {
            text = try command.transcribe(audioURL: audioURL, model: model)
        } catch let error as ParakeetSpeechRecognizerError {
            throw error
        } catch {
            throw ParakeetSpeechRecognizerError.transcriptionFailed(error.localizedDescription)
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsyncStream { continuation in
            guard !normalized.isEmpty else {
                continuation.finish()
                return
            }
            continuation.yield(.final(normalized))
            continuation.finish()
        }
    }
}

struct ProcessParakeetTranscriptionCommand: ParakeetTranscriptionCommand {
    let executable: String

    init(executable: String = "parakeet-mlx") {
        self.executable = executable
    }

    func transcribe(audioURL: URL, model: String) throws -> String {
        let outputDirectory = audioURL.deletingLastPathComponent()
        let outputURL = outputDirectory.appendingPathComponent("result.txt")
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let resolvedExecutable = resolveExecutable()
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = [
            audioURL.path,
            "--model", model,
            "--output-dir", outputDirectory.path,
            "--output-format", "txt",
            "--output-template", "result"
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ParakeetSpeechRecognizerError.runtimeUnavailable(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown Parakeet runtime error"
            throw ParakeetSpeechRecognizerError.transcriptionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let text = try? String(contentsOf: outputURL, encoding: .utf8) else {
            let message = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Parakeet produced no transcript"
            throw ParakeetSpeechRecognizerError.transcriptionFailed(message)
        }
        return text
    }

    private func resolveExecutable() -> String {
        if executable.contains("/") { return executable }

        let fileManager = FileManager.default
        let bundleRoot = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            bundleRoot.appendingPathComponent(".venv/bin/\(executable)").path,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/\(executable)").path,
            "/opt/homebrew/bin/\(executable)",
            "/usr/local/bin/\(executable)"
        ]
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? "/usr/bin/env"
    }
}

private enum WAVFile {
    static func write(frames: [AudioFrame], to url: URL) throws {
        guard let first = frames.first else { throw ParakeetSpeechRecognizerError.noAudio }
        let sampleRate = UInt32(first.sampleRate.rounded())
        let channels = UInt16(max(1, first.channelCount))
        var pcm = Data()
        pcm.reserveCapacity(frames.reduce(0) { $0 + $1.samples.count } * MemoryLayout<Int16>.size)
        for frame in frames {
            for sample in frame.samples {
                let clipped = max(-1.0, min(1.0, sample))
                var value = Int16((clipped * Float(Int16.max)).rounded())
                withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
            }
        }

        var wav = Data("RIFF".utf8)
        appendUInt32(36 + UInt32(pcm.count), to: &wav)
        wav.append(Data("WAVEfmt ".utf8))
        appendUInt32(16, to: &wav)
        appendUInt16(1, to: &wav)
        appendUInt16(channels, to: &wav)
        appendUInt32(sampleRate, to: &wav)
        appendUInt32(sampleRate * UInt32(channels) * 2, to: &wav)
        appendUInt16(channels * 2, to: &wav)
        appendUInt16(16, to: &wav)
        wav.append(Data("data".utf8))
        appendUInt32(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        try wav.write(to: url, options: .atomic)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

struct MockSpeechRecognizer: SpeechRecognizer {
    let transcript: String

    func recognize(frames: [AudioFrame]) async throws -> AsyncStream<SpeechRecognitionEvent> {
        AsyncStream { continuation in
            continuation.yield(.partial(transcript))
            continuation.yield(.final(transcript))
            continuation.finish()
        }
    }
}
