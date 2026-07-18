import Foundation

/// A live membership rule on a collection: "everything from this source" or
/// "this folder (and its subtree) of this source". Rules are additive-only —
/// new matching memories auto-join on every sync; removal is always a user
/// action (recorded as an exclusion so rules never re-add).
struct CollectionRule: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case entireSource
        case folder
    }

    var id: UUID
    var sourceAccountID: UUID
    var sourceTypeRaw: String
    var kind: Kind
    /// Drive folder ID (stable across rename/move); nil for entireSource
    /// and for Obsidian, where the path is the identifier.
    var folderID: String?
    /// Display path; also the match key for Obsidian folders.
    var folderPath: String?
    /// e.g. "Google Drive · /Projects/Acme" or "Entire source: Notion"
    var displayName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceAccountID: UUID,
        sourceTypeRaw: String,
        kind: Kind,
        folderID: String? = nil,
        folderPath: String? = nil,
        displayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceAccountID = sourceAccountID
        self.sourceTypeRaw = sourceTypeRaw
        self.kind = kind
        self.folderID = folderID
        self.folderPath = folderPath
        self.displayName = displayName
        self.createdAt = createdAt
    }

    /// The sourceRef prefix for this rule's account (e.g. "gdrive:<uuid>:").
    var sourceRefPrefix: String {
        let type: String
        switch SourceType(rawValue: sourceTypeRaw) {
        case .googleDrive: type = "gdrive"
        case .notion: type = "notion"
        case .obsidian, .files: type = "obsidian"
        default: type = sourceTypeRaw
        }
        return "\(type):\(sourceAccountID.uuidString):"
    }
}
