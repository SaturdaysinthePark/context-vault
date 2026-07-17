import Foundation
import SwiftData

/// The kind of source a memory came from.
enum SourceType: String, Codable, CaseIterable, Sendable {
    case manual
    case obsidian
    case notion
    case googleDrive
    case files
    case shareExtension
}

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
    var createdAt: Date
    var modifiedAt: Date
    /// Set when the memory has been written to the Spotlight index.
    var indexedAt: Date?
    var collections: [MemoryCollection]

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    /// True when at least one containing collection allows Siri exposure,
    /// or when the memory is uncollected (default-exposed; see SpotlightIndexer).
    var isSiriVisible: Bool {
        collections.isEmpty || collections.contains { $0.siriVisible }
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
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.collections = collections
    }
}
