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
                for: Memory.self, MemoryCollection.self, SourceAccount.self, ProfileCard.self
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
    /// collection's Siri visibility toggle flips.
    func reindexCollection(_ collection: MemoryCollection) async throws {
        let snapshots = collection.memories.map(MemorySnapshot.init)
        try await SpotlightIndexer.shared.reindex(memories: snapshots)
    }
}
