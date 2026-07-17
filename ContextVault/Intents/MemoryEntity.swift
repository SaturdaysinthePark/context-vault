import AppIntents
import CoreSpotlight
import SwiftData

/// The App Intents face of a Memory. Conforming to `IndexedEntity` puts the
/// marked properties into the Spotlight semantic index, which is the channel
/// through which Siri AI's personal-context understanding sees third-party
/// content on iOS 27 (WWDC26 240).
struct MemoryEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Memory")
    static let defaultQuery = MemoryEntityQuery()

    var id: UUID

    @Property(title: "Title", indexingKey: \.title)
    var title: String

    @Property(title: "Content", indexingKey: \.textContent)
    var content: String

    @Property(title: "Collection")
    var collectionName: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: collectionName.map { "\($0)" }
        )
    }

    init(memory: Memory) {
        self.id = memory.id
        self.title = memory.title
        self.content = memory.summary ?? String(memory.body.prefix(2000))
        self.collectionName = memory.collections.first?.name
    }
}

struct MemoryEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MemoryEntity] {
        try VaultStore.shared.memories(ids: identifiers).map(MemoryEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [MemoryEntity] {
        try VaultStore.shared.searchMemories(string).map(MemoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [MemoryEntity] {
        try VaultStore.shared.recentMemories(limit: 5).map(MemoryEntity.init)
    }
}
