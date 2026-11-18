import Foundation

/// Lexical ranking of cards against a free-text query. Used when Siri (or
/// the in-app chat) asks the app directly rather than finding a card in
/// the Spotlight index. Pure and synchronous so it can be unit-tested.
enum CardSearch {

    /// Words that carry no retrieval signal in a spoken question.
    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "about", "at", "be", "by", "can", "did", "do", "does",
        "expect", "for", "from", "get", "going", "has", "have", "how", "i", "in", "is",
        "it", "me", "my", "of", "on", "or", "please", "should", "tell", "that", "the",
        "this", "to", "was", "what", "when", "where", "which", "who", "will", "with", "you"
    ]

    /// Lowercased alphanumeric tokens, stopwords removed, diacritics folded.
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopwords.contains($0) }
    }

    /// Scores one card. Zero means "no match".
    static func score(_ card: CardSnapshot, queryTokens: [String], now: Date = .now) -> Double {
        guard !queryTokens.isEmpty else { return 0 }

        let fields: [(text: String, weight: Double)] = [
            (card.title, 3),
            (card.aliases.joined(separator: " "), 3),
            (card.counterpart ?? "", 2),
            (card.attributes[CardFact.items] ?? "", 2),
            (card.statement, 1.5),
            (card.kind.displayName + " " + card.sourceType.displayName, 1),
            (card.kind.synonyms.joined(separator: " "), 0.5),
            (card.detail, 1)
        ]
        let fieldTokens = fields.map { (Set(tokens($0.text)), $0.weight) }

        var total = 0.0
        var matched = 0
        for token in queryTokens {
            var best = 0.0
            for (set, weight) in fieldTokens {
                if set.contains(token) {
                    best = max(best, weight)
                } else if token.count >= 4,
                          set.contains(where: { $0.hasPrefix(token) || token.hasPrefix($0) && $0.count >= 4 }) {
                    // "kingdom" ↔ "kingdoms", "deliver" ↔ "delivery".
                    best = max(best, weight * 0.6)
                }
            }
            if best > 0 { matched += 1 }
            total += best
        }
        guard matched > 0 else { return 0 }

        // Reward covering more of the question, so a card matching both
        // "twelve" and "kingdoms" beats one matching only "amazon".
        let coverage = Double(matched) / Double(queryTokens.count)
        var score = total * (0.5 + coverage)

        // Things happening soon are what people ask about.
        if let date = card.primaryDate {
            let days = date.timeIntervalSince(now) / 86_400
            if days >= -1 && days <= 14 { score *= 1.25 }
            else if days < -30 { score *= 0.7 }
        }
        if card.isArchived { score *= 0.5 }
        return score
    }

    /// Ranks cards against a query, best first, dropping non-matches.
    /// An empty query returns the cards by date relevance instead.
    static func rank(
        _ cards: [CardSnapshot],
        query: String,
        kind: CardKind? = nil,
        sources: Set<SourceType>? = nil,
        limit: Int = 5,
        now: Date = .now
    ) -> [CardSnapshot] {
        let candidates = cards.filter { card in
            if let kind, card.kind != kind { return false }
            if let sources, !sources.contains(card.sourceType) { return false }
            return true
        }
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else {
            return Array(candidates.sorted { relevanceDate($0, now) < relevanceDate($1, now) }.prefix(limit))
        }
        var scored: [(card: CardSnapshot, score: Double)] = []
        for card in candidates {
            let value = score(card, queryTokens: queryTokens, now: now)
            if value > 0 {
                scored.append((card, value))
            }
        }
        // Best score first; between equal scores, the fresher card.
        scored.sort { first, second in
            if first.score != second.score {
                return first.score > second.score
            }
            return first.card.asOf > second.card.asOf
        }
        return scored.prefix(limit).map { $0.card }
    }

    /// Distance from now to the card's date; undated cards sort last,
    /// newest first.
    private static func relevanceDate(_ card: CardSnapshot, _ now: Date) -> TimeInterval {
        if let date = card.primaryDate {
            let delta = date.timeIntervalSince(now)
            // Upcoming beats past at the same distance.
            return delta >= 0 ? delta : -delta * 4
        }
        return 1e12 - card.asOf.timeIntervalSince1970
    }
}
