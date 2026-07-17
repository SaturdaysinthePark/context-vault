import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Writes memories into the Core Spotlight index.
///
/// This index serves two purposes:
/// 1. SYSTEM surface — on iOS 27, entity content in the Spotlight semantic
///    index feeds Siri AI's personal-context understanding (WWDC26 240).
/// 2. IN-APP RAG — `SpotlightSearchTool` (iOS 27) retrieves from this same
///    index for the "Ask your Vault" chat; on iOS 26 we query it manually
///    via CSUserQuery (see VaultChatService).
///
/// Privacy rule: only memories whose collections allow Siri visibility are
/// indexed. Flipping a collection's `siriVisible` re-runs indexing for its
/// memories, adding or deleting entries accordingly.
actor SpotlightIndexer {
    static let shared = SpotlightIndexer()
    static let domainIdentifier = "com.saturdaysinthepark.contextvault.memories"

    private var index: CSSearchableIndex {
        CSSearchableIndex(name: "context-vault-memories")
    }

    /// Master kill-switch set from the Privacy dashboard: when off, nothing
    /// is ever (re)indexed, so a sync can't quietly repopulate the index.
    private var exposureEnabled: Bool {
        UserDefaults.standard.object(forKey: "siriExposureEnabled") as? Bool ?? true
    }

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
            attributes.keywords = memory.aspectValues
            attributes.contentCreationDate = memory.createdAt
            attributes.contentModificationDate = memory.modifiedAt

            let item = CSSearchableItem(
                uniqueIdentifier: memory.identifier,
                domainIdentifier: Self.domainIdentifier,
                attributeSet: attributes
            )
            return item
        }
        try await index.indexSearchableItems(items)
    }

    func deleteAll() async throws {
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

    /// iOS 26 fallback retrieval: query the index directly and return the
    /// top matching memory identifiers. On iOS 27, SpotlightSearchTool
    /// replaces this path inside the Foundation Models session.
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
    var createdAt: Date
    var modifiedAt: Date

    var identifier: String { "memory-\(id.uuidString)" }

    init(_ memory: Memory) {
        self.id = memory.id
        self.title = memory.title
        self.body = memory.body
        self.summary = memory.summary
        self.isSiriVisible = memory.isSiriVisible
        self.aspectValues = memory.collections.flatMap { $0.aspects.map(\.value) }
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
