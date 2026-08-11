import Foundation

struct ContextMatch: Sendable, Equatable {
    let event: JournalEvent
    let score: Double
}

enum ContextRanking {
    static func rank(_ event: JournalEvent, for query: String, now: Date = .now) -> Double {
        let normalizedQuery = query.lowercased()
        let tokens = normalizedQuery.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let haystack = [event.type, event.entityID ?? "", event.summary ?? ""].joined(separator: " ").lowercased()
        let keywordScore = tokens.reduce(0.0) { partial, token in
            partial + (haystack.contains(token) ? 1.0 : 0.0)
        }
        let age = max(0, now.timeIntervalSince(event.timestamp))
        let recencyScore = exp(-age / 900)
        let referentScore = normalizedQuery.contains("earlier") || normalizedQuery.contains("that") ? 0.25 : 0
        return keywordScore + recencyScore + referentScore
    }
}
