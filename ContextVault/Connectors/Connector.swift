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
    /// Content fidelity (default full). Non-full items arrive pre-rendered:
    /// rawContent is the final body, filename minus extension is the title.
    var fidelity: ContentFidelity = .full
    /// Short type label for display ("PDF", "EPUB", …).
    var fileKind: String? = nil
    /// Explicit title. When nil the title is derived from `filename`, which
    /// is wrong for mail subjects ("Your Amazon.com order" has no extension).
    var title: String? = nil
    /// Who the item is from (mail sender), if the source has that notion.
    var sender: String? = nil
    /// Groups items that belong together, such as a mail thread.
    var threadKey: String? = nil
    /// schema.org JSON-LD blocks found in the item's original HTML.
    var structuredData: [String] = []
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
    /// Folder IDs subscribed by collection rules for this account — files
    /// inside them get enrichment effort even when the sync scope is
    /// "everything" (populated by SyncManager before each pass).
    var ruleFolderIDs: [String] = []
    /// When set, the connector should fetch at most this many of the newest
    /// items and return quickly — used for the short top-up that runs when
    /// Siri asks a question (populated by SyncManager).
    var quickLimit: Int? = nil

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
