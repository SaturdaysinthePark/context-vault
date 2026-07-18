import Foundation

/// A single item pulled from an external source, before it becomes a Memory.
struct SourceItem: Sendable {
    var sourceRef: String
    var filename: String
    var rawContent: String
    var modifiedAt: Date
    /// Human-readable folder path within the source (nil = root/unknown).
    var folderPath: String? = nil
    /// Machine ancestor chain (see Memory.sourceFolderPath).
    var folderIDPath: String? = nil
}

/// Resolved folder location, keyed by folder ID in `SyncResult.folderPaths`.
struct FolderPaths: Sendable {
    var path: String
    var idPath: String
}

/// The result of one incremental sync pass.
struct SyncResult: Sendable {
    var items: [SourceItem]
    var newCursor: String?
    /// Fresh folder map (immediate-parent folder ID → resolved paths) for
    /// sources with server-side folder structure (Drive). Ingest uses it to
    /// refresh paths on ALL of the account's memories so renames/moves stay
    /// current without extra API calls.
    var folderPaths: [String: FolderPaths]? = nil
}

/// A connector pulls content from one external source into the vault.
/// Implementations must be incremental: given the previous cursor, return
/// only what changed, plus the next cursor.
protocol Connector: Sendable {
    var sourceType: SourceType { get }
    func sync(account: SourceAccountSnapshot) async throws -> SyncResult
}

/// Sendable snapshot of a SourceAccount for use inside connectors.
struct SourceAccountSnapshot: Sendable {
    var id: UUID
    var sourceType: SourceType
    var displayName: String
    var configData: Data?
    var syncCursor: String?

    init(_ account: SourceAccount) {
        self.id = account.id
        self.sourceType = account.sourceType
        self.displayName = account.displayName
        self.configData = account.configData
        self.syncCursor = account.syncCursor
    }
}

enum ConnectorError: LocalizedError {
    case missingConfiguration
    case bookmarkStale
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "This source isn't configured yet."
        case .bookmarkStale: "The folder moved — pick it again in Sources."
        case .accessDenied: "Context Vault can't access this source anymore."
        }
    }
}
