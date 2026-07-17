import AppIntents

/// App Intents face of a MemoryCollection, so users can scope questions and
/// shortcuts to a collection ("Ask my Work collection...").
struct CollectionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Collection")
    static let defaultQuery = CollectionEntityQuery()

    var id: UUID
    var name: String
    var memoryCount: Int
    var siriVisible: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(memoryCount) memories"
        )
    }

    init(collection: MemoryCollection) {
        self.id = collection.id
        self.name = collection.name
        self.memoryCount = collection.memories.count
        self.siriVisible = collection.siriVisible
    }
}

struct CollectionEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CollectionEntity] {
        try VaultStore.shared.collections(ids: identifiers).map(CollectionEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CollectionEntity] {
        try VaultStore.shared.allCollections()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(CollectionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CollectionEntity] {
        try VaultStore.shared.allCollections().map(CollectionEntity.init)
    }
}
