import Foundation
import Testing
@testable import ContextVault

/// Ranking of cards against spoken questions, using the same fictional
/// cards the Siri Lab seeds. These tests pin the app-side half of the
/// primary use case: given the question, the right card comes back first.
struct CardSearchTests {
    /// A fixed "now" so date boosts are deterministic: 2026-11-16 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_830_400)

    private var demoCards: [CardSnapshot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return DemoSeed.items(now: now, calendar: calendar)
            .filter { !$0.sensitive }
            .map { item in
                CardSnapshot(
                    draft: item.draft,
                    source: item.source,
                    asOf: now.addingTimeInterval(-Double(item.updatedDaysAgo) * 86_400),
                    locale: Locale(identifier: "en_US"),
                    timeZone: TimeZone(identifier: "UTC")!
                )
            }
    }

    private func top(_ question: String, sources: Set<SourceType>? = nil, kind: CardKind? = nil) -> CardSnapshot? {
        CardSearch.rank(demoCards, query: question, kind: kind, sources: sources, limit: 5, now: now).first
    }

    @Test func theTargetQuestionFindsTheTwelveKingdomsOrder() {
        let best = top("When should I expect my Amazon package with Twelve Kingdoms to arrive?")
        #expect(best?.title == "Amazon order: The Twelve Kingdoms (paperback)")
    }

    @Test func aSimilarTitleDoesNotWin() {
        // "Twelve Monkeys" shares a word and is also an order.
        let best = top("When is my Twelve Kingdoms book arriving?")
        #expect(best?.title.contains("Twelve Kingdoms") == true)

        let other = top("Did my Twelve Monkeys Blu-ray arrive?")
        #expect(other?.title.contains("Twelve Monkeys") == true)
    }

    @Test func everydayWordsReachTheRightKind() {
        #expect(top("What time is my dentist appointment?")?.title == "Dental cleaning with Dr. Okafor")
        #expect(top("When is my electricity bill due, and how much is it?")?.title == "Electricity bill")
        #expect(top("When does my flight to Denver leave?")?.title == "Flight NW 482 from Seattle to Denver")
        #expect(top("Does my lease allow pets?")?.title == "Apartment lease for Maple Court, unit 3B")
    }

    @Test func aSourceFilterLimitsResults() {
        let drive = CardSearch.rank(demoCards, query: "lease", sources: [.googleDrive], now: now)
        #expect(drive.count == 1)
        #expect(drive.first?.sourceType == .googleDrive)

        let mailOnly = CardSearch.rank(demoCards, query: "lease", sources: [.gmail], now: now)
        #expect(mailOnly.isEmpty)
    }

    @Test func aKindFilterLimitsResults() {
        let bills = CardSearch.rank(demoCards, query: "", kind: .bill, limit: 10, now: now)
        #expect(bills.count == 2)
        #expect(bills.allSatisfy { $0.kind == .bill })
    }

    @Test func anEmptyQueryReturnsWhatIsComingUpSoonest() {
        let upcoming = CardSearch.rank(demoCards, query: "", limit: 3, now: now)
        // Dinner (+2 days), then the Twelve Kingdoms delivery (+3 days).
        // Yesterday's delivery comes next: the recent past still matters
        // ("did it arrive?"), but counts as further away than it is.
        #expect(upcoming.map(\.title) == [
            "Dinner for four at Juniper & Rye",
            "Amazon order: The Twelve Kingdoms (paperback)",
            "Amazon order: USB-C charging cable (2-pack)"
        ])
    }

    @Test func nothingMatchesNothing() {
        #expect(CardSearch.rank(demoCards, query: "quantum chromodynamics lecture", now: now).isEmpty)
    }

    @Test func stopwordsAndPunctuationAreIgnored() {
        #expect(CardSearch.tokens("When should I expect my Amazon package?") == ["amazon", "package"])
        #expect(CardSearch.tokens("What's the Wi-Fi password?") == ["wi", "fi", "password"])
        #expect(CardSearch.tokens("Café  RÉSUMÉ") == ["cafe", "resume"])
    }

    @Test func aSensitiveCardIsNeverAmongTheCandidates() {
        // The seed marks the Wi-Fi note sensitive; the store excludes it
        // before ranking, mirrored here by the filter in `demoCards`.
        #expect(top("What's the Wi-Fi password for the cabin?")?.title != "Cabin Wi-Fi password")
    }

    @Test func keywordsCarrySynonymsAndSource() {
        let order = demoCards.first { $0.title.contains("Twelve Kingdoms") }
        let keywords = order?.keywords ?? []
        #expect(keywords.contains("package"))
        #expect(keywords.contains("Gmail"))
        #expect(keywords.contains("Amazon"))
        #expect(keywords.contains("Twelve Kingdoms"))
        // No duplicates, case-insensitively.
        #expect(Set(keywords.map { $0.lowercased() }).count == keywords.count)
    }

    @Test func soonerCardsGetAHigherIndexPriority() {
        let soon = CardSnapshot(kind: .order, title: "Soon", primaryDate: now.addingTimeInterval(2 * 86_400), sourceType: .gmail)
        let later = CardSnapshot(kind: .order, title: "Later", primaryDate: now.addingTimeInterval(60 * 86_400), sourceType: .gmail)
        let past = CardSnapshot(kind: .order, title: "Past", primaryDate: now.addingTimeInterval(-20 * 86_400), sourceType: .gmail)
        #expect(soon.indexPriority(now: now) > later.indexPriority(now: now))
        #expect(later.indexPriority(now: now) > past.indexPriority(now: now))
    }
}
