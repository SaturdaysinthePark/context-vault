import AppIntents
import CoreSpotlight
import SwiftData

/// The App Intents face of a Memory — a whole document or note, as
/// opposed to the short fact a `ContextCardEntity` carries.
///
/// Memories from document sources are indexed as searchable items linked
/// to this entity (see `SpotlightIndexer.reindex(memories:)`), so a
/// question about what a document says can still reach its text. Email
/// evidence is never indexed and never returned here.
struct MemoryEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Memory",
        numericFormat: "\(placeholder: .int) memories"
    )
    static let defaultQuery = MemoryEntityQuery()

    var id: UUID

    @Property(
        title: "Title",
        description: "The title of the document or note.",
        indexingKey: \.title
    )
    var title: String

    @Property(
        title: "Content",
        description: "The opening text of the document or note, or its summary when one exists.",
        indexingKey: \.textContent
    )
    var content: String

    @Property(
        title: "Source",
        description: "The connected source the document came from, such as Google Drive, Notion or Obsidian."
    )
    var source: String

    var collectionName: String?

    var displayRepresentation: DisplayRepresentation {
        if let collectionName {
            DisplayRepresentation(title: "\(title)", subtitle: "\(collectionName)")
        } else {
            DisplayRepresentation(title: "\(title)", subtitle: "\(source)")
        }
    }

    init(memory: Memory) {
        self.id = memory.id
        self.title = memory.title
        self.content = memory.summary ?? String(memory.body.prefix(2000))
        self.source = memory.sourceType.displayName
        self.collectionName = memory.collections.first?.name
    }

    init(snapshot: MemorySnapshot) {
        self.id = snapshot.id
        self.title = snapshot.title
        self.content = snapshot.summary ?? String(snapshot.body.prefix(2000))
        self.source = snapshot.sourceName
        self.collectionName = snapshot.collectionName
    }
}

/// Every method honours the privacy settings: a memory hidden from Siri
/// (by its collection, its sensitivity, its source, or the master switch)
/// is never returned to the system.
struct MemoryEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MemoryEntity] {
        try VaultStore.shared.memories(ids: identifiers)
            .filter(Self.mayBeShown)
            .map(MemoryEntity.init(memory:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [MemoryEntity] {
        try VaultStore.shared.searchMemories(string)
            .filter(Self.mayBeShown)
            .prefix(20)
            .map(MemoryEntity.init(memory:))
    }

    @MainActor
    func suggestedEntities() async throws -> [MemoryEntity] {
        try VaultStore.shared.recentMemories(limit: 20)
            .filter(Self.mayBeShown)
            .prefix(5)
            .map(MemoryEntity.init(memory:))
    }

    @MainActor
    private static func mayBeShown(_ memory: Memory) -> Bool {
        SiriExposure.isEnabled
            && memory.isSiriVisible
            && !SiriExposure.hiddenSources.contains(memory.sourceType)
    }
}
