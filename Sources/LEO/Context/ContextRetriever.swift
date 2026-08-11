import Foundation

struct ContextRetriever: Sendable {
    let maximumResults: Int
    let maximumContextCharacters: Int

    init(maximumResults: Int = 5, maximumContextCharacters: Int = 2_000) {
        self.maximumResults = max(1, maximumResults)
        self.maximumContextCharacters = max(1, maximumContextCharacters)
    }

    func retrieve(query: String, from events: [JournalEvent], now: Date = .now) -> [ContextMatch] {
        var usedCharacters = 0
        return events
            .map { ContextMatch(event: $0, score: ContextRanking.rank($0, for: query, now: now)) }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.event.timestamp > $1.event.timestamp
            }
            .prefix(maximumResults)
            .filter { match in
                let summarySize = (match.event.summary ?? match.event.type).count
                guard usedCharacters + summarySize <= maximumContextCharacters else { return false }
                usedCharacters += summarySize
                return true
            }
            .map { $0 }
    }
}
