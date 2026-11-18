import Foundation

/// Putting the demo cards into the vault and taking them out again.
extension DemoSeed {

    /// Replaces any existing demo cards with a fresh set and indexes them.
    /// Returns the number of cards created.
    @MainActor
    @discardableResult
    static func seed(now: Date = .now) async throws -> Int {
        try await remove()

        let store = VaultStore.shared
        var created: [ContextCard] = []
        for item in items(now: now) {
            let asOf = Calendar.current.date(byAdding: .day, value: -item.updatedDaysAgo, to: now) ?? now
            let card = CardMerger.makeCard(from: item.draft, source: item.source, asOf: asOf)
            card.isDemo = true
            if item.sensitive { card.sensitivity = .sensitive }
            store.context.insert(card)
            created.append(card)
        }
        try store.context.save()
        try await store.reindex(cards: created)
        return created.count
    }

    /// Deletes all demo cards from the store and the index.
    @MainActor
    @discardableResult
    static func remove() async throws -> Int {
        let store = VaultStore.shared
        let demo = try store.cards(includeArchived: true).filter(\.isDemo)
        try await store.delete(cards: demo)
        return demo.count
    }
}
