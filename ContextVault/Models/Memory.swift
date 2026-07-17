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

/// On-device-classified sensitivity of a memory. `sensitive` content is
/// excluded from the system index by default, making privacy proactive.
enum Sensitivity: String, Codable, CaseIterable, Sendable {
    case unclassified
    case personal
    case professional
    case sensitive
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
    var sensitivityRaw: String
    /// User override: expose to Siri even though classified sensitive.
    var forceSiriVisible: Bool
    var createdAt: Date
    var modifiedAt: Date
    /// Set when the memory has been written to the Spotlight index.
    var indexedAt: Date?
    var collections: [MemoryCollection]

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .manual }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var sensitivity: Sensitivity {
        get { Sensitivity(rawValue: sensitivityRaw) ?? .unclassified }
        set { sensitivityRaw = newValue.rawValue }
    }

    /// True when the memory may enter the system index: its collections
    /// allow Siri exposure (uncollected memories are default-exposed) AND
    /// it isn't classified sensitive (unless the user overrode that).
    var isSiriVisible: Bool {
        let collectionAllows = collections.isEmpty || collections.contains { $0.siriVisible }
        let sensitivityAllows = sensitivity != .sensitive || forceSiriVisible
        return collectionAllows && sensitivityAllows
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
