import Foundation

/// Reads an Obsidian vault (or any Markdown folder — Logseq, Bear exports,
/// plain notes) chosen by the user through the document picker.
///
/// The folder is retained via a security-scoped bookmark stored in the
/// SourceAccount's configData. Works for iCloud Drive vaults (including
/// `iCloud~md~obsidian`) and On My iPhone folders. Sync is incremental via
/// a modification-time high-water mark stored as the cursor.
struct ObsidianConnector: Connector {
    let sourceType: SourceType = .obsidian

    func sync(account: SourceAccountSnapshot) async throws -> SyncResult {
        guard let bookmarkData = account.configData else {
            throw ConnectorError.missingConfiguration
        }

        var isStale = false
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale { throw ConnectorError.bookmarkStale }

        guard folderURL.startAccessingSecurityScopedResource() else {
            throw ConnectorError.accessDenied
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        let highWaterMark = account.syncCursor.flatMap { Double($0) }.map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        var newest = highWaterMark
        var items: [SourceItem] = []

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw ConnectorError.accessDenied
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            // Skip Obsidian internals.
            if fileURL.pathComponents.contains(".obsidian") { continue }

            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            guard modified > highWaterMark else { continue }

            // iCloud files may not be local yet; request download and skip
            // this pass — the next sync picks them up.
            if FileManager.default.isUbiquitousItem(at: fileURL) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path, with: "")
            let directory = (relativePath as NSString).deletingLastPathComponent
            let folderPath = directory.isEmpty || directory == "/" ? nil : directory
            items.append(SourceItem(
                sourceRef: "obsidian:\(account.id.uuidString):\(relativePath)",
                filename: fileURL.lastPathComponent,
                rawContent: content,
                modifiedAt: modified,
                folderPath: folderPath,
                folderIDPath: folderPath // paths ARE the IDs for file-based sources
            ))
            newest = max(newest, modified)
        }

        return SyncResult(
            items: items,
            newCursor: String(newest.timeIntervalSince1970)
        )
    }
}
