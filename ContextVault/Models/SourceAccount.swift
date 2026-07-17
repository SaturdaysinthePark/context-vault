import Foundation
import SwiftData

/// A connected external source: an Obsidian vault folder, a Notion workspace,
/// a Google Drive selection. Auth material lives in the Keychain; this model
/// stores non-secret configuration and the incremental-sync cursor.
@Model
final class SourceAccount {
    @Attribute(.unique) var id: UUID
    var sourceTypeRaw: String
    var displayName: String
    /// Source-specific configuration:
    /// - obsidian/files: security-scoped bookmark data for the chosen folder
    /// - notion: workspace ID (token in Keychain under `keychainKey`)
    /// - googleDrive: selected folder/file IDs
    var configData: Data?
    /// Incremental sync cursor (e.g. Notion last_edited_time checkpoint,
    /// Drive changes page token, file mtime high-water mark).
    var syncCursor: String?
    var lastSyncedAt: Date?
    var createdAt: Date

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .files }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var keychainKey: String { "source-token-\(id.uuidString)" }

    init(
        id: UUID = UUID(),
        sourceType: SourceType,
        displayName: String,
        configData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceTypeRaw = sourceType.rawValue
        self.displayName = displayName
        self.configData = configData
        self.createdAt = createdAt
    }
}
