import Foundation

struct ReferentCandidate: Sendable, Equatable {
    /// The first alias retained for compatibility with callers that display a label.
    let label: String
    let entityID: String
    let displayName: String
    var aliases: [String]
    var salience: Double
    let source: RequestSource
    var updatedAt: Date
    var lastReferencedAt: Date
}

struct ReferentStore: Sendable {
    private(set) var candidates: [ReferentCandidate] = []
    private let halfLife: TimeInterval
    private let ambiguityEpsilon = 0.000001

    init(halfLife: TimeInterval = 300) {
        self.halfLife = max(1, halfLife)
    }

    mutating func record(
        entityID: String,
        displayName: String,
        source: RequestSource,
        labels: [String] = ["it", "that file"],
        salience: Double = 1,
        at date: Date = .now
    ) {
        let normalizedLabels = labels.map(Self.normalize).filter { !$0.isEmpty }
        guard !entityID.isEmpty, !normalizedLabels.isEmpty else { return }

        if let index = candidates.firstIndex(where: { $0.entityID == entityID }) {
            var candidate = candidates[index]
            candidate.aliases = stableUnique(candidate.aliases + normalizedLabels)
            candidate.salience = max(0, salience)
            candidate.updatedAt = date
            candidate.lastReferencedAt = date
            candidates[index] = candidate
        } else {
            candidates.append(ReferentCandidate(
                label: normalizedLabels[0],
                entityID: entityID,
                displayName: displayName,
                aliases: stableUnique(normalizedLabels),
                salience: max(0, salience),
                source: source,
                updatedAt: date,
                lastReferencedAt: date
            ))
        }
        reorder(at: date)
    }

    /// Resolving is itself a reference, so a successful lookup updates recency.
    /// Equal-ranked entities are left unresolved instead of guessed.
    mutating func resolve(_ phrase: String, at date: Date = .now) -> ReferentCandidate? {
        let normalizedPhrase = Self.normalize(phrase)
        let matches = candidates
            .filter { $0.aliases.contains(normalizedPhrase) }
            .map { candidate in
                var copy = candidate
                copy.salience = decayed(candidate, at: date)
                return copy
            }
            .filter { $0.salience > 0.01 }
            .sorted(by: rankedBefore)

        guard let best = matches.first else { return nil }
        if let second = matches.dropFirst().first,
           abs(best.salience - second.salience) <= ambiguityEpsilon {
            return nil
        }

        guard let index = candidates.firstIndex(where: { $0.entityID == best.entityID }) else { return nil }
        candidates[index].lastReferencedAt = date
        candidates[index].updatedAt = max(candidates[index].updatedAt, date)
        reorder(at: date)
        return best
    }

    mutating func decay(at date: Date = .now) {
        candidates = candidates
            .map { candidate in
                var copy = candidate
                copy.salience = decayed(candidate, at: date)
                return copy
            }
            .filter { $0.salience > 0.01 }
        reorder(at: date)
    }

    private mutating func reorder(at date: Date) {
        var reordered = candidates
        reordered.sort { left, right in
            let leftSalience = decayed(left, at: date)
            let rightSalience = decayed(right, at: date)
            if abs(leftSalience - rightSalience) > ambiguityEpsilon {
                return leftSalience > rightSalience
            }
            if left.lastReferencedAt != right.lastReferencedAt {
                return left.lastReferencedAt > right.lastReferencedAt
            }
            return left.entityID < right.entityID
        }
        candidates = reordered
    }

    private func decayed(_ candidate: ReferentCandidate, at date: Date) -> Double {
        let age = max(0, date.timeIntervalSince(candidate.lastReferencedAt))
        return candidate.salience * pow(0.5, age / halfLife)
    }

    private func rankedBefore(_ left: ReferentCandidate, _ right: ReferentCandidate) -> Bool {
        if abs(left.salience - right.salience) > ambiguityEpsilon {
            return left.salience > right.salience
        }
        if left.lastReferencedAt != right.lastReferencedAt {
            return left.lastReferencedAt > right.lastReferencedAt
        }
        return left.entityID < right.entityID
    }

    private func stableUnique(_ labels: [String]) -> [String] {
        var result: [String] = []
        for label in labels where !result.contains(label) {
            result.append(label)
        }
        return result
    }

    private static func normalize(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
