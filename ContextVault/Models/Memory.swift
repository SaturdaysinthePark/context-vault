import Foundation
import SwiftData

/// A normalized piece of knowledge: a note, document, page, or highlight.
@Model
final class Memory {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Full normalized plain-text/Markdown body.
    var body: String
    /// Short on-device-generated summary, indexed alongside the body for recall.
    var summary: String?
    var sourceTypeRaw: String
    /// Stable reference into the source system (file path, Notion page ID, Drive file ID).
    var sourceRef: String?
    /// Human-readable folder path within the source (e.g. "/Projects/Acme").
    /// Display only — can go stale after renames until the next sync refresh.
    var sourcePath: String?
    /// Machine ancestor chain for rule matching. Drive: "/<folderID>/<folderID>"
    /// (root→immediate parent, IDs stable across rename/move). Obsidian: same
    /// as sourcePath. Notion: "/<parentPageID>" (one level, v1).
    var sourceFolderPath: String?
    /// How much of the file's content this memory carries (nil = full).
    var fidelityRaw: String?
    /// Short file-type label for display ("PDF", "EPUB", "Photo", "Archive").
    var fileKind: String?
    var sensitivityRaw: String
    /// User override: expose to Siri even though classified sensitive.
    var forceSiriVisible: Bool
    var createdAt: Date
    var modifiedAt: Date
    /// Set when the memory has been written to the Spotlight index.
    var indexedAt: Date?
    /// Who the evidence is from, for mail: "Amazon.com <ship@amazon.com>".
    var sender: String?
    /// Groups evidence that belongs together (a mail thread), so related
    /// messages can update one context card.
    var threadKey: String?
    /// JSON array of schema.org JSON-LD blocks found in the evidence's
    /// original HTML (orders, deliveries, reservations). Kept because the
    /// HTML itself is discarded after the text is extracted.
    var structuredData: String?
    /// When context cards were last distilled from this memory. Cleared
    /// whenever the content changes, which queues it for extraction again.
    var cardsExtractedAt: Date?
    var collections: [MemoryCollection]

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: sensitivityRaw) ?? .unclassified }
        set { sensitivityRaw = newValue.rawValue }
    }

    var fidelity: ContentFidelity {
        get { fidelityRaw.flatMap(ContentFidelity.init(rawValue:)) ?? .full }
        set { fidelityRaw = newValue.rawValue }
    }

    /// True when the user's own privacy settings allow this memory to
    /// inform Siri: its collections allow Siri exposure (uncollected
    /// memories are default-exposed) AND it isn't classified sensitive
    /// (unless the user overrode that). Cards distilled from this memory
    /// inherit this answer.
    var allowsSiriExposure: Bool {
        let collectionAllows = collections.isEmpty || collections.contains { $0.siriVisible }
        let sensitivityAllows = sensitivity != .sensitive || forceSiriVisible
        return collectionAllows && sensitivityAllows
    }

    /// True when the memory's own text may enter the system index. Email
    /// evidence never does, whatever the privacy settings say.
    var isSiriVisible: Bool {
        allowsSiriExposure && sourceType.indexesEvidence
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        summary: String? = nil,
        sourceType: SourceType = .manual,
        sourceRef: String? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        collections: [MemoryCollection] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.summary = summary
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceRef = sourceRef
        self.sensitivityRaw = Sensitivity.unclassified.rawValue
        self.forceSiriVisible = false
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.collections = collections
    }
}
