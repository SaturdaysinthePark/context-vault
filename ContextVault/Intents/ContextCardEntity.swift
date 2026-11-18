import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// The App Intents face of a context card — the thing Siri AI finds.
///
/// Siri reaches this entity two ways, and the entity is written for both:
/// 1. **Through the Spotlight semantic index.** When Siri finds an entity
///    there, the properties it sees are the ones the app indexes. So the
///    answer-bearing text is mapped to index keys (`title`,
///    `contentDescription`, `textContent`) and the rest is supplied in
///    `attributeSet`.
/// 2. **By querying the app** (through `ContextCardQuery`, or as the
///    result of `LookUpContextIntent`). Then Siri sees every `@Property`,
///    and relies on each property's title and description to understand
///    it. Descriptions are written for someone who has never seen the app.
struct ContextCardEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Context Card",
        numericFormat: "\(placeholder: .int) context cards"
    )
    static let defaultQuery = ContextCardQuery()

    var id: UUID

    @Property(
        title: "Title",
        description: "A short name for the item: the merchant and what was ordered, the flight, the appointment, or the document's title.",
        indexingKey: \.title
    )
    var title: String

    @Property(
        title: "Summary",
        description: "One sentence stating the current facts about the item, including its status, its date written out in full, and the source it came from.",
        indexingKey: \.contentDescription
    )
    var summary: String

    /// Reference and tracking numbers live here, so Siri must confirm the
    /// device is unlocked before reading this property out. The title and
    /// summary, which hold the answer to most questions, need no unlock.
    @Property(
        title: "Details",
        description: "Supporting facts, one per line, such as status, dates, location, amount, reference number, carrier and tracking number.",
        authenticationPolicy: .requiresAuthentication,
        indexingKey: \.textContent
    )
    var details: String

    @Property(
        title: "Kind",
        description: "What the item is: an order or delivery, travel, a reservation, an appointment, a bill, a document or a note."
    )
    var kind: CardKind

    @Property(
        title: "Source",
        description: "The connected source the information came from, such as Gmail or Google Drive."
    )
    var source: SourceKind

    @Property(
        title: "From",
        description: "The company, organisation or person the information is from, such as the merchant, airline, clinic or sender."
    )
    var from: String?

    @Property(
        title: "Date",
        description: "The date that matters most for the item: expected delivery, departure, appointment time or due date."
    )
    var date: Date?

    @Property(
        title: "Status",
        description: "The item's current state, such as shipped, out for delivery, delivered, confirmed or due."
    )
    var status: String?

    @Property(
        title: "Last Updated",
        description: "When the information was last updated from its source. Use it to say how current the answer is."
    )
    var lastUpdated: Date

    /// Extra words for the index: aliases, kind synonyms, source name.
    var keywords: [String]
    var endDate: Date?
    var createdAt: Date
    /// Spotlight ranking hint (see `CardSnapshot.indexPriority`).
    var priority: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(summary)")
    }

    /// Attributes that have no matching `@Property` index key. Spotlight
    /// merges these with the indexed properties above.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.keywords = keywords
        attributes.contentCreationDate = createdAt
        attributes.contentModificationDate = lastUpdated
        if let date {
            attributes.startDate = date
            attributes.dueDate = date
        }
        if let endDate {
            attributes.endDate = endDate
        }
        if let from {
            attributes.authorNames = [from]
        }
        // The source's spoken name, so "in my Gmail" has something to match.
        attributes.containerTitle = source.localizedName
        attributes.domainIdentifier = SpotlightIndexer.cardDomainIdentifier
        return attributes
    }

    init(_ card: CardSnapshot) {
        self.id = card.id
        self.title = card.title
        self.summary = card.statement
        self.details = card.detail
        self.kind = card.kind
        self.source = SourceKind(card.sourceType)
        self.from = card.counterpart
        self.date = card.primaryDate
        self.status = card.status
        self.lastUpdated = card.asOf
        self.keywords = card.keywords
        self.endDate = card.endDate
        self.createdAt = card.createdAt
        self.priority = card.indexPriority()
    }
}

extension SourceKind {
    /// The source's name as plain text, for index attributes.
    var localizedName: String {
        switch self {
        case .gmail: "Gmail"
        case .googleDrive: "Google Drive"
        case .notion: "Notion"
        case .obsidian: "Obsidian"
        case .files: "Files"
        case .notes: "Notes"
        }
    }
}

/// How the system asks the app for cards directly. Every method honours
/// the privacy settings: a card the user has hidden from Siri is never
/// returned, whichever route asks for it.
struct ContextCardQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ContextCardEntity] {
        try VaultStore.shared.siriVisibleCards(ids: identifiers).map(ContextCardEntity.init)
    }

    /// Resolves spoken words ("my Twelve Kingdoms order") to cards.
    @MainActor
    func entities(matching string: String) async throws -> [ContextCardEntity] {
        try VaultStore.shared.searchCards(query: string, limit: 8).map(ContextCardEntity.init)
    }

    /// What is coming up next — a sensible default set.
    @MainActor
    func suggestedEntities() async throws -> [ContextCardEntity] {
        try VaultStore.shared.searchCards(query: "", limit: 8).map(ContextCardEntity.init)
    }

    /// Lets the system enumerate cards when it cannot use the index.
    /// Capped, because this is a fallback path, not a bulk export.
    @MainActor
    func allEntities() async throws -> [ContextCardEntity] {
        try VaultStore.shared.searchCards(query: "", limit: 200).map(ContextCardEntity.init)
    }
}

/// Spotlight can ask the app to rebuild its index (after a restore, or
/// when the index is damaged). Cards indexed as entities are rebuilt here.
extension ContextCardQuery: IndexedEntityQuery {

    func reindexEntities(
        for identifiers: [UUID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let snapshots = try await MainActor.run {
            try VaultStore.shared.siriVisibleCards(ids: identifiers)
        }
        try await SpotlightIndexer.shared.reindex(cards: snapshots)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await VaultStore.shared.reindexAllCards()
    }
}
