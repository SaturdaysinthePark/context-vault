import Foundation

/// The kind of source a memory came from.
enum SourceType: String, Codable, CaseIterable, Sendable {
    case manual
    case obsidian
    case notion
    case googleDrive
    case gmail
    case files
    case shareExtension

    /// The name a person would say for this source ("in my Gmail"). It is
    /// written into every card's indexed text so sources are mentionable.
    var displayName: String {
        switch self {
        case .manual: "Notes"
        case .obsidian: "Obsidian"
        case .notion: "Notion"
        case .googleDrive: "Google Drive"
        case .gmail: "Gmail"
        case .files: "Files"
        case .shareExtension: "Shared items"
        }
    }

    /// Whether raw evidence from this source may enter the system index.
    /// Documents and notes may; email never does — only the context cards
    /// distilled from it are indexed.
    var indexesEvidence: Bool {
        self != .gmail
    }
}

/// On-device-classified sensitivity of a memory. `sensitive` content is
/// excluded from the system index by default, making privacy proactive.
enum Sensitivity: String, Codable, CaseIterable, Sendable {
    case unclassified
    case personal
    case professional
    case sensitive
}

/// How much of the underlying file's content this memory carries.
enum ContentFidelity: String, Codable, CaseIterable, Sendable {
    case full          // native text (docs, markdown)
    case extracted     // text pulled out of a binary (PDF, EPUB, DOCX)
    case captioned     // OCR/caption enrichment (images)
    case metadataOnly  // name, type, location — content unreadable

    var badge: String? {
        switch self {
        case .full: nil
        case .extracted: "text extracted"
        case .captioned: "captioned"
        case .metadataOnly: "metadata only"
        }
    }
}
