import Foundation
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// How context cards are written to the Spotlight index. Apple documents
/// two ways and says not to use both for the same content (Spotlight
/// would create two entries). Which one Siri AI finds more reliably is
/// not documented, so the choice is a setting the Siri Lab can flip and
/// measure.
enum CardIndexingPath: String, CaseIterable, Sendable {
    /// `indexAppEntities` — the entity is the index entry. Used by both
    /// of Apple's sample apps.
    case entities
    /// `CSSearchableItem` with `associateAppEntity` — the app builds the
    /// item and links the entity to it. Keeps our own identifiers.
    case associatedItems

    static let defaultsKey = "cardIndexingPath"

    static var current: CardIndexingPath {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(CardIndexingPath.init(rawValue:)) ?? .entities
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var displayName: String {
        switch self {
        case .entities: "Entities (indexAppEntities)"
        case .associatedItems: "Items linked to entities"
        }
    }
}

/// Writes the vault into the Core Spotlight index.
///
/// This index serves two purposes:
/// 1. SYSTEM surface — Siri AI finds app entities in the Spotlight
///    semantic index, and sees the properties indexed for them. Context
///    cards are the main thing indexed for this.
/// 2. IN-APP RAG — the "Ask your Vault" chat queries the same index.
///
/// What goes in:
/// - **Context cards**, as app entities (`ContextCardEntity`).
/// - **Memories from document sources** (Drive, Notion, Obsidian, notes),
///   as searchable items linked to `MemoryEntity`.
/// - **Never raw email.** Mail evidence stays in the app; only the cards
///   distilled from it are indexed.
///
/// Privacy rule: nothing is indexed unless `isSiriVisible` is true for
/// it, and the master switch empties the index and blocks repopulation.
actor SpotlightIndexer {
    static let shared = SpotlightIndexer()
    static let domainIdentifier = "com.saturdaysinthepark.contextvault.memories"
    static let cardDomainIdentifier = "com.saturdaysinthepark.contextvault.cards"
    static let indexName = "context-vault-memories"

    private var index: CSSearchableIndex {
        CSSearchableIndex(name: Self.indexName)
    }

    /// Master kill-switch set from the Privacy dashboard: when off, nothing
    /// is ever (re)indexed, so a sync can't quietly repopulate the index.
    private var exposureEnabled: Bool { SiriExposure.isEnabled }

    // MARK: Context cards

    /// Index (or reindex) a batch of cards, honouring Siri visibility.
    /// Hidden and archived cards are removed.
    func reindex(cards: [CardSnapshot]) async throws {
        guard exposureEnabled else { return }
        let (visible, hidden) = cards.partitioned { $0.isSiriVisible && !$0.isArchived }

        if !hidden.isEmpty {
            await removeCards(ids: hidden.map(\.id))
        }
        guard !visible.isEmpty else { return }

        switch CardIndexingPath.current {
        case .entities:
            // Make sure no item-path copy lingers from an earlier setting.
            try? await index.deleteSearchableItems(withIdentifiers: visible.map(\.itemIdentifier))
            // Priority is per call, so index each priority group together.
            let groups = Dictionary(grouping: visible) { $0.indexPriority() }
            for (priority, group) in groups {
                try await index.indexAppEntities(group.map(ContextCardEntity.init), priority: priority)
            }

        case .associatedItems:
            try? await index.deleteAppEntities(identifiedBy: visible.map(\.id), ofType: ContextCardEntity.self)
            let items = visible.map { card -> CSSearchableItem in
                let entity = ContextCardEntity(card)
                let attributes = entity.attributeSet
                attributes.title = card.title
                attributes.contentDescription = card.statement
                attributes.textContent = [card.statement, card.detail].joined(separator: "\n\n")
                attributes.associateAppEntity(entity, priority: card.indexPriority())
                return CSSearchableItem(
                    uniqueIdentifier: card.itemIdentifier,
                    domainIdentifier: Self.cardDomainIdentifier,
                    attributeSet: attributes
                )
            }
            try await index.indexSearchableItems(items)
        }
    }

    /// Remove cards from the index, whichever path indexed them.
    func removeCards(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        try? await index.deleteAppEntities(identifiedBy: ids, ofType: ContextCardEntity.self)
        try? await index.deleteSearchableItems(withIdentifiers: ids.map { "card-\($0.uuidString)" })
    }

    /// Remove every card from the index (both paths).
    func removeAllCards() async {
        try? await index.deleteAppEntities(ofType: ContextCardEntity.self)
        try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.cardDomainIdentifier])
    }

    // MARK: Memories (document evidence)

    /// Index (or reindex) a batch of memories, honoring Siri visibility.
    func reindex(memories: [MemorySnapshot]) async throws {
        guard exposureEnabled else { return }
        let (visible, hidden) = memories.partitioned { $0.isSiriVisible }

        if !hidden.isEmpty {
            try await index.deleteSearchableItems(withIdentifiers: hidden.map(\.identifier))
        }
        guard !visible.isEmpty else { return }

        let items = visible.map { memory -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = memory.title
            attributes.textContent = [memory.summary, memory.body]
                .compactMap(\.self)
                .joined(separator: "\n\n")
            attributes.contentDescription = memory.summary ?? String(memory.body.prefix(280))
            attributes.keywords = memory.aspectValues + [memory.sourceName]
            attributes.containerTitle = memory.sourceName
            attributes.contentCreationDate = memory.createdAt
            attributes.contentModificationDate = memory.modifiedAt
            // Linking the entity is what makes this item something Siri
            // and Apple Intelligence can act on, not just a search hit.
            attributes.associateAppEntity(MemoryEntity(snapshot: memory))

            let item = CSSearchableItem(
                uniqueIdentifier: memory.identifier,
                domainIdentifier: Self.domainIdentifier,
                attributeSet: attributes
            )
            return item
        }
        try await index.indexSearchableItems(items)
    }

    /// Empty the index completely: memories, cards and the About Me card.
    func deleteAll() async throws {
        await removeAllCards()
        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
    }

    /// Index (or remove) the About Me card so Siri can answer identity
    /// questions ("what projects am I working on?") from it.
    func reindexAboutMe(_ card: ProfileCardSnapshot) async throws {
        guard exposureEnabled else { return }
        guard card.siriVisible, !card.content.isEmpty else {
            try await index.deleteSearchableItems(withIdentifiers: [card.identifier])
            return
        }
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "About Me"
        attributes.textContent = card.content
        attributes.contentDescription = "Your distilled profile"
        let item = CSSearchableItem(
            uniqueIdentifier: card.identifier,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
        try await index.indexSearchableItems([item])
    }

    // MARK: Querying our own index

    /// Query the index directly and return the identifiers of the top
    /// matching searchable items. Memories come back as `memory-<UUID>`;
    /// cards indexed on the item path as `card-<UUID>`. Cards indexed on
    /// the entity path have identifiers the system chooses, so callers
    /// that need cards should use `VaultStore.searchCards` instead.
    func search(_ query: String, limit: Int = 8) async throws -> [String] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]
        context.maxResultCount = limit
        let userQuery = CSUserQuery(userQueryString: query, userQueryContext: context)

        var identifiers: [String] = []
        for try await element in userQuery.responses {
            if case .item(let item) = element {
                identifiers.append(item.item.uniqueIdentifier)
            }
        }
        return identifiers
    }

    /// How many index entries match a query — a quick self-check for the
    /// Siri Lab that content really reached the index.
    func matchCount(_ query: String) async -> Int {
        (try? await search(query, limit: 25).count) ?? 0
    }
}

/// Sendable snapshot of the About Me card for the indexing actor.
struct ProfileCardSnapshot: Sendable {
    var content: String
    var siriVisible: Bool

    var identifier: String { "profile-about-me" }

    init(_ card: ProfileCard) {
        self.content = card.content
        self.siriVisible = card.siriVisible
    }
}

/// A Sendable snapshot of a Memory for crossing into the indexing actor —
/// SwiftData models must stay on their own context.
struct MemorySnapshot: Sendable {
    var id: UUID
    var title: String
    var body: String
    var summary: String?
    var isSiriVisible: Bool
    var aspectValues: [String]
    var collectionName: String?
    var sourceName: String
    var createdAt: Date
    var modifiedAt: Date

    var identifier: String { "memory-\(id.uuidString)" }

    init(_ memory: Memory) {
        self.id = memory.id
        self.title = memory.title
        self.body = memory.body
        self.summary = memory.summary
        self.isSiriVisible = memory.isSiriVisible
            && !SiriExposure.hiddenSources.contains(memory.sourceType)
        // Collection names, aspects, and descriptions all sharpen semantic
        // matching for this memory in the system index.
        self.aspectValues = memory.collections.flatMap { collection in
            [collection.name] + collection.aspects.map(\.value) + (collection.details.isEmpty ? [] : [collection.details])
        }
        self.collectionName = memory.collections.first?.name
        self.sourceName = memory.sourceType.displayName
        self.createdAt = memory.createdAt
        self.modifiedAt = memory.modifiedAt
    }
}

private extension Array {
    func partitioned(by belongsInFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for element in self {
            if belongsInFirst(element) { first.append(element) } else { second.append(element) }
        }
        return (first, second)
    }
}
