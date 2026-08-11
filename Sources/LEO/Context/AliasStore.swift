import Foundation

struct AliasRecord: Codable, Sendable, Equatable, Identifiable {
    let alias: String
    var target: String

    var id: String { alias }
}

enum AliasStoreError: Error, Equatable {
    case invalidAlias
    case invalidTarget
    case duplicateAlias(String)
    case aliasNotFound(String)
    case persistenceFailed
}

/// An in-memory store for explicit, user-defined names.
///
/// Persistence and context integration intentionally belong to a later slice.
struct AliasStore: Sendable {
    private var entries: [String: AliasRecord] = [:]
    private let storageURL: URL?

    init() {
        storageURL = nil
    }

    init(storageURL: URL) throws {
        self.storageURL = storageURL
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let records = try JSONDecoder().decode([AliasRecord].self, from: Data(contentsOf: storageURL))
            for record in records {
                entries[try Self.requireAlias(record.alias).lowercased()] = record
            }
        } catch {
            throw AliasStoreError.persistenceFailed
        }
    }

    var records: [AliasRecord] {
        entries.values.sorted { left, right in
            let leftKey = Self.lookupKey(left.alias) ?? ""
            let rightKey = Self.lookupKey(right.alias) ?? ""
            return leftKey == rightKey ? left.alias < right.alias : leftKey < rightKey
        }
    }

    @discardableResult
    mutating func create(alias: String, target: String) throws -> AliasRecord {
        let canonicalAlias = try Self.requireAlias(alias)
        let normalizedAlias = Self.lookupKey(canonicalAlias)!
        let normalizedTarget = try Self.requireTarget(target)
        guard entries[normalizedAlias] == nil else {
            throw AliasStoreError.duplicateAlias(normalizedAlias)
        }

        let record = AliasRecord(alias: canonicalAlias, target: normalizedTarget)
        entries[normalizedAlias] = record
        try persist()
        return record
    }

    func read(alias: String) -> AliasRecord? {
        guard let normalizedAlias = Self.lookupKey(alias) else { return nil }
        return entries[normalizedAlias]
    }

    @discardableResult
    mutating func update(alias: String, target: String) throws -> AliasRecord {
        let normalizedAlias = try Self.requireAlias(alias).lowercased()
        let normalizedTarget = try Self.requireTarget(target)
        guard entries[normalizedAlias] != nil else {
            throw AliasStoreError.aliasNotFound(normalizedAlias)
        }

        let record = AliasRecord(alias: entries[normalizedAlias]!.alias, target: normalizedTarget)
        entries[normalizedAlias] = record
        try persist()
        return record
    }

    @discardableResult
    mutating func delete(alias: String) throws -> Bool {
        guard let normalizedAlias = Self.lookupKey(alias) else { return false }
        let removed = entries.removeValue(forKey: normalizedAlias) != nil
        if removed { try persist() }
        return removed
    }

    /// Resolves an alias using the same normalization as CRUD operations.
    func resolve(_ alias: String) -> String? {
        read(alias: alias)?.target
    }

    private static func requireTarget(_ value: String) throws -> String {
        guard !containsUnsafeCharacters(value) else {
            throw AliasStoreError.invalidTarget
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AliasStoreError.invalidTarget
        }
        return normalized
    }

    private static func requireAlias(_ value: String) throws -> String {
        guard let canonical = canonicalAlias(value) else {
            throw AliasStoreError.invalidAlias
        }
        return canonical
    }

    private static func canonicalAlias(_ value: String) -> String? {
        guard !value.isEmpty, !containsUnsafeCharacters(value) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsed = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed
    }

    private static func lookupKey(_ value: String) -> String? {
        canonicalAlias(value)?.lowercased()
    }

    private static func containsUnsafeCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func persist() throws {
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: storageURL, options: .atomic)
        } catch {
            throw AliasStoreError.persistenceFailed
        }
    }
}
