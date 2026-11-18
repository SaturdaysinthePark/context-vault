import Foundation
import SwiftData

/// Main-actor gateway to the SwiftData store for code that lives outside
/// SwiftUI (App Intents, sync, indexing). Owns a shared ModelContainer that
/// matches the one the app creates.
@MainActor
final class VaultStore {
    static let shared = VaultStore()

    let container: ModelContainer

    private init() {
        do {
            container = try ModelContainer(
                for: Memory.self, MemoryCollection.self, SourceAccount.self, ProfileCard.self,
                ContextCard.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var context: ModelContext { container.mainContext }

    // MARK: Memories

    func memories(ids: [UUID]) throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return try context.fetch(descriptor)
    }

    func memory(id: UUID) throws -> Memory? {
        try memories(ids: [id]).first
    }

    func searchMemories(_ text: String) throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate {
                $0.title.localizedStandardContains(text) ||
                $0.body.localizedStandardContains(text)
            },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func recentMemories(limit: Int) throws -> [Memory] {
        var descriptor = FetchDescriptor<Memory>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// All memories belonging to one source account (sourceRef prefix scan) —
    /// used by the Drive path-refresh pass and retroactive rule application.
    func memories(sourceRefPrefix prefix: String) throws -> [Memory] {
        let descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { $0.sourceRef?.starts(with: prefix) == true }
        )
        return try context.fetch(descriptor)
    }

    /// Find a memory by its source reference (used by connectors for upsert).
    func memory(sourceRef: String) throws -> Memory? {
        var descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate { $0.sourceRef == sourceRef }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Collections

    func collections(ids: [UUID]) throws -> [MemoryCollection] {
        let descriptor = FetchDescriptor<MemoryCollection>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return try context.fetch(descriptor)
    }

    func allCollections() throws -> [MemoryCollection] {
        try context.fetch(FetchDescriptor<MemoryCollection>(
            sortBy: [SortDescriptor(\.name)]
        ))
    }

    // MARK: About Me card

    /// The single About Me card, created on first access.
    func aboutMeCard() throws -> ProfileCard {
        if let existing = try context.fetch(FetchDescriptor<ProfileCard>()).first {
            return existing
        }
        let card = ProfileCard()
        context.insert(card)
        try context.save()
        return card
    }

    /// Push the About Me card into (or remove it from) the Spotlight index.
    func reindexAboutMeCard() async throws {
        let card = try aboutMeCard()
        let snapshot = ProfileCardSnapshot(card)
        try await SpotlightIndexer.shared.reindexAboutMe(snapshot)
    }

    // MARK: Mutation + index maintenance

    /// Insert or update a memory and keep the Spotlight index in step.
    func upsert(_ memory: Memory) async throws {
        context.insert(memory)
        memory.modifiedAt = .now
        try context.save()
        try await SpotlightIndexer.shared.reindex(memories: [MemorySnapshot(memory)])
        memory.indexedAt = .now
        try context.save()
    }

    /// Re-run indexing for every memory in a collection — called when the
    /// collection's Siri visibility toggle flips. Cards distilled from
    /// those memories inherit the change, so they are reindexed too.
    func reindexCollection(_ collection: MemoryCollection) async throws {
        let snapshots = collection.memories.map(MemorySnapshot.init)
        try await SpotlightIndexer.shared.reindex(memories: snapshots)

        let memoryIDs = Set(collection.memories.map(\.id))
        let affected = try cards(includeArchived: false).filter { card in
            card.evidenceIDs.contains { memoryIDs.contains($0) }
        }
        try await reindex(cards: affected)
    }

    // MARK: Connected sources

    /// Sendable copies of the connected accounts, for indexing. A source is
    /// visible to Siri unless sharing is off or the source is hidden.
    func sourceSnapshots() throws -> [SourceSnapshot] {
        let accounts = try context.fetch(FetchDescriptor<SourceAccount>())
        let allCards = try cards(includeArchived: false)
        let hidden = SiriExposure.hiddenSources
        return accounts.map { account in
            SourceSnapshot(
                id: account.id,
                sourceType: account.sourceType,
                lastSyncedAt: account.lastSyncedAt,
                cardCount: allCards.filter { $0.sourceAccountID == account.id }.count,
                isSiriVisible: SiriExposure.isEnabled && !hidden.contains(account.sourceType)
            )
        }
    }

    /// Push the connected sources into (or remove them from) the index.
    func reindexSources() async throws {
        try await SpotlightIndexer.shared.reindex(sources: sourceSnapshots())
    }

    // MARK: Context cards

    func cards(ids: [UUID]) throws -> [ContextCard] {
        let descriptor = FetchDescriptor<ContextCard>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        return try context.fetch(descriptor)
    }

    /// The card a new piece of evidence should update, if one exists.
    func card(mergeKey: String) throws -> ContextCard? {
        var descriptor = FetchDescriptor<ContextCard>(
            predicate: #Predicate { $0.mergeKey == mergeKey }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Cards distilled from one memory.
    func cards(evidenceID: UUID) throws -> [ContextCard] {
        try cards(includeArchived: true).filter { $0.evidenceIDs.contains(evidenceID) }
    }

    func cards(includeArchived: Bool) throws -> [ContextCard] {
        let descriptor: FetchDescriptor<ContextCard>
        if includeArchived {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.asOf, order: .reverse)])
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate<ContextCard> { !$0.isArchived },
                sortBy: [SortDescriptor(\.asOf, order: .reverse)]
            )
        }
        return try context.fetch(descriptor)
    }

    /// Sendable copies of cards, each carrying the answer to "may Siri see
    /// this?". A card is visible only if every rule allows it: the master
    /// switch, its source and kind, its own sensitivity, and the privacy
    /// settings of the memories it was distilled from.
    func snapshots(for cards: [ContextCard]) throws -> [CardSnapshot] {
        let evidenceIDs = Set(cards.flatMap(\.evidenceIDs))
        var blockedEvidence = Set<UUID>()
        if !evidenceIDs.isEmpty {
            for memory in try memories(ids: Array(evidenceIDs)) where !memory.allowsSiriExposure {
                blockedEvidence.insert(memory.id)
            }
        }
        return cards.map { card in
            let visible = SiriExposure.allows(kind: card.kind, source: card.sourceType)
                && !card.isArchived
                && (card.sensitivity != .sensitive || card.forceSiriVisible)
                && !card.evidenceIDs.contains { blockedEvidence.contains($0) }
            return CardSnapshot(card, isSiriVisible: visible)
        }
    }

    /// The Siri-visible cards among the given IDs.
    func siriVisibleCards(ids: [UUID]) throws -> [CardSnapshot] {
        try snapshots(for: cards(ids: ids)).filter(\.isSiriVisible)
    }

    /// Finds cards for a free-text query, best first. An empty query
    /// returns what is coming up soonest.
    ///
    /// - Parameter siriVisibleOnly: true (the default) for anything that
    ///   leaves the app — App Intents and entity queries. The in-app chat
    ///   passes false, because the user is looking at their own vault.
    func searchCards(
        query: String,
        kind: CardKind? = nil,
        sources: Set<SourceType>? = nil,
        limit: Int = 5,
        siriVisibleOnly: Bool = true
    ) throws -> [CardSnapshot] {
        var candidates = try snapshots(for: cards(includeArchived: false))
        if siriVisibleOnly {
            candidates = candidates.filter(\.isSiriVisible)
        }
        return CardSearch.rank(candidates, query: query, kind: kind, sources: sources, limit: limit)
    }

    /// Insert or update a card and keep the Spotlight index in step.
    func upsert(card: ContextCard) async throws {
        context.insert(card)
        try context.save()
        try await reindex(cards: [card])
    }

    /// Delete cards from the store and the index.
    func delete(cards: [ContextCard]) async throws {
        let ids = cards.map(\.id)
        for card in cards {
            context.delete(card)
        }
        try context.save()
        await SpotlightIndexer.shared.removeCards(ids: ids)
    }

    /// Push cards into (or remove them from) the Spotlight index according
    /// to their current visibility.
    func reindex(cards: [ContextCard]) async throws {
        guard !cards.isEmpty else { return }
        let snapshots = try snapshots(for: cards)
        try await SpotlightIndexer.shared.reindex(cards: snapshots)
        let now = Date.now
        for card in cards {
            let visible = snapshots.first { $0.id == card.id }?.isSiriVisible ?? false
            card.indexedAt = visible ? now : nil
        }
        try context.save()
    }

    /// Rebuild the card part of the index from scratch — used when a
    /// privacy setting or the indexing path changes.
    func reindexAllCards() async throws {
        await SpotlightIndexer.shared.removeAllCards()
        try await reindex(cards: cards(includeArchived: true))
    }
}
