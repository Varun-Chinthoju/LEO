import Foundation

final class SystemAudioDucker: @unchecked Sendable {
    func begin() -> Int? {
        begin(settingOutputTo: nil)
    }

    func beginForSpeechPlayback() -> Int? {
        begin(settingOutputTo: 18)
    }

    private func begin(settingOutputTo requestedVolume: Int?) -> Int? {
        guard let current = run("output volume of (get volume settings)") else { return nil }
        let ducked = requestedVolume.map { max($0, min(current, 35)) } ?? max(1, Int(Double(current) * 0.35))
        _ = run("set volume output volume \(ducked)")
        leoVoiceLogger.info("system_audio_ducked from=\(current, privacy: .public) to=\(ducked, privacy: .public)")
        return current
    }

    func restore(_ volume: Int) {
        _ = run("set volume output volume \(volume)")
        leoVoiceLogger.info("system_audio_restored volume=\(volume, privacy: .public)")
    }

    private func run(_ script: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return Int(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        } catch {
            leoVoiceLogger.error("system_audio_volume_command_failed")
            return nil
        }
    }
}
