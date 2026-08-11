import Foundation
import os

private let leoPreferenceLogger = Logger(subsystem: "com.varun.leo", category: "preferences")

struct UserPreference: Codable, Sendable, Equatable {
    let text: String
    let recordedAt: Date
}

/// Stores only preferences the user explicitly asks LEO to remember.
actor UserPreferenceStore {
    private static let maxEntries = 24

    private var entries: [UserPreference]
    private let fileURL: URL?

    init(fileURL: URL? = UserPreferenceStore.defaultURL()) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([UserPreference].self, from: data) {
            self.entries = Array(saved.suffix(Self.maxEntries))
        } else {
            self.entries = []
        }
    }

    @discardableResult
    func remember(_ text: String) -> UserPreference? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 240 else { return nil }
        let preference = UserPreference(text: normalized, recordedAt: .now)
        entries.removeAll { $0.text.caseInsensitiveCompare(normalized) == .orderedSame }
        entries.append(preference)
        entries = Array(entries.suffix(Self.maxEntries))
        persist()
        return preference
    }

    func promptContext() -> String? {
        guard !entries.isEmpty else { return nil }
        return entries.map { "- \($0.text)" }.joined(separator: "\n")
    }

    func all() -> [UserPreference] { entries }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            leoPreferenceLogger.error("user_preferences_persist_failed")
        }
    }

    private static func defaultURL() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LEO", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }
}
