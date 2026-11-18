import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// A connected source (Gmail, Google Drive, …) as something Siri can find.
///
/// Why index sources at all: Siri may consult an app's tools when "a
/// relevant entity from that app appears in a search result". A person who
/// says "check my Gmail" names no card and no app, but does name a source.
/// Indexing one entity per connected source gives that phrase something of
/// ours to match, which is how a source becomes mentionable in place of
/// the app.
///
/// Only the source's general name is indexed ("Gmail"). The account's
/// address is not.
struct SourceEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Connected Source",
        numericFormat: "\(placeholder: .int) connected sources"
    )
    static let defaultQuery = SourceEntityQuery()

    var id: UUID

    @Property(
        title: "Name",
        description: "The source's name, such as Gmail or Google Drive.",
        indexingKey: \.title
    )
    var name: String

    @Property(
        title: "Summary",
        description: "What Context Vault holds from this source and when it was last updated.",
        indexingKey: \.contentDescription
    )
    var summary: String

    @Property(
        title: "Source",
        description: "Which kind of source this is. Pass it to the look up personal context tool to search only this source."
    )
    var kind: SourceKind

    @Property(
        title: "Last Synced",
        description: "When Context Vault last fetched new information from this source."
    )
    var lastSynced: Date?

    var keywords: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Connected to Context Vault")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.keywords = keywords
        attributes.contentModificationDate = lastSynced
        attributes.domainIdentifier = SpotlightIndexer.sourceDomainIdentifier
        return attributes
    }

    init(_ source: SourceSnapshot) {
        self.id = source.id
        self.name = source.sourceType.displayName
        self.kind = SourceKind(source.sourceType)
        self.lastSynced = source.lastSyncedAt
        self.keywords = source.sourceType.spokenNames

        var parts = ["\(source.sourceType.displayName), connected to Context Vault."]
        if source.cardCount > 0 {
            parts.append("\(source.cardCount) \(source.cardCount == 1 ? "item" : "items") gathered from it, such as orders, bookings, bills and documents.")
        }
        if let lastSynced = source.lastSyncedAt {
            parts.append("Last updated \(CardRenderer.format(lastSynced, hasTime: false)).")
        }
        self.summary = parts.joined(separator: " ")
    }
}

/// A Sendable copy of a connected account for indexing.
struct SourceSnapshot: Sendable, Identifiable {
    var id: UUID
    var sourceType: SourceType
    var lastSyncedAt: Date?
    /// How many cards came from this source.
    var cardCount: Int
    var isSiriVisible: Bool
}

struct SourceEntityQuery: EntityQuery, EntityStringQuery {

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SourceEntity] {
        try VaultStore.shared.sourceSnapshots()
            .filter { $0.isSiriVisible && identifiers.contains($0.id) }
            .map(SourceEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SourceEntity] {
        let query = string.lowercased()
        return try VaultStore.shared.sourceSnapshots()
            .filter { source in
                source.isSiriVisible && source.sourceType.spokenNames.contains { name in
                    let name = name.lowercased()
                    return name.contains(query) || query.contains(name)
                }
            }
            .map(SourceEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SourceEntity] {
        try VaultStore.shared.sourceSnapshots().filter(\.isSiriVisible).map(SourceEntity.init)
    }
}
