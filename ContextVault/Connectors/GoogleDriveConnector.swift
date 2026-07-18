import Foundation

/// Pulls Google Docs and text/Markdown files from the user's Drive.
///
/// Auth: tokens in the Keychain (see GoogleDriveAuth); the OAuth client ID
/// lives in the account's configData. Incremental sync via a `modifiedTime`
/// high-water mark (RFC3339) stored as the cursor.
struct GoogleDriveConfig: Codable {
    var clientID: String
    /// Folder IDs the user chose to sync (subtrees included). nil or empty
    /// means sync everything.
    var selectedFolderIDs: [String]? = nil
}

struct GoogleDriveConnector: Connector {
    let sourceType: SourceType = .googleDrive

    func sync(account: SourceAccountSnapshot) async throws -> SyncResult {
        guard let configData = account.configData,
              let config = try? JSONDecoder().decode(GoogleDriveConfig.self, from: configData),
              var tokens = KeychainStore.load(GoogleTokens.self, for: keychainKey(account)) else {
            throw ConnectorError.missingConfiguration
        }

        if tokens.isExpired {
            tokens = try await refreshOrFail(tokens, config: config, account: account)
        }

        // Fresh folder inventory every sync (1–3 calls): powers folder paths,
        // scope filtering, and the path-refresh pass — and self-heals renames.
        var tokensBox = tokens
        var folders = try await DriveFolderService.fetch { url in
            try await self.authorizedRequest(url: url, tokens: &tokensBox, config: config, account: account)
        }
        tokens = tokensBox

        // Selected folders + all descendants; nil = everything in scope.
        let allowed: Set<String>? = {
            guard let selected = config.selectedFolderIDs, !selected.isEmpty else { return nil }
            return folders.descendantClosure(of: selected)
        }()

        // Enrichment scope: folders the user explicitly chose — sync scope
        // selections plus collection-subscribed folders. Media/unknown files
        // inside get metadata memories (and OCR later); outside, skipped.
        let enrichmentScope: Set<String> = folders.descendantClosure(
            of: (config.selectedFolderIDs ?? []) + account.ruleFolderIDs
        )

        let cursor = account.syncCursor ?? "1970-01-01T00:00:00Z"
        var items: [SourceItem] = []
        var newest = cursor
        var pageToken: String?

        repeat {
            let page = try await listFiles(
                modifiedAfter: cursor,
                pageToken: pageToken,
                tokens: &tokens,
                config: config,
                account: account
            )
            for file in page.files {
                let parentID = file.parents?.first
                if let allowed, !folders.isInScope(parentID: parentID, allowed: allowed) {
                    continue // out of sync scope; no content fetched
                }

                let inEnrichmentScope = folders.isInScope(parentID: parentID, allowed: enrichmentScope)
                let strategy = FileEnricher.strategy(for: file.mimeType, inEnrichmentScope: inEnrichmentScope)
                guard strategy != .skip else { continue }

                let paths = parentID.flatMap { folders.paths(for: $0) }
                let modified = Self.parseRFC3339(file.modifiedTime) ?? .now
                let kind = FileEnricher.fileKind(for: file.mimeType)

                var content: String?
                var fidelity: ContentFidelity = .full

                switch strategy {
                case .export, .downloadText:
                    content = try? await fetchContent(of: file, tokens: &tokens, config: config, account: account)
                case .pdf:
                    if let data = try? await fetchData(of: file, tokens: &tokens, config: config, account: account),
                       let text = FileEnricher.extractPDFText(data) {
                        content = text
                        fidelity = .extracted
                    } else {
                        // Scanned or unreadable PDF → metadata stub for now.
                        content = FileEnricher.stubBody(name: file.name, kind: "scanned PDF", folderPath: paths?.path, modified: modified)
                        fidelity = .metadataOnly
                    }
                case .zipDocument:
                    if let data = (try? await fetchData(of: file, tokens: &tokens, config: config, account: account)) ?? nil,
                       let extracted = ZipDocumentExtractor.extract(data: data, filename: file.name) {
                        content = extracted.text
                        fidelity = extracted.fidelity
                    } else {
                        content = FileEnricher.stubBody(name: file.name, kind: kind, folderPath: paths?.path, modified: modified)
                        fidelity = .metadataOnly
                    }
                case .metadataOnly, .image:
                    // Images get OCR/caption in a later phase.
                    content = FileEnricher.stubBody(name: file.name, kind: kind, folderPath: paths?.path, modified: modified)
                    fidelity = .metadataOnly
                case .skip:
                    continue
                }

                guard let content, !content.isEmpty else { continue }
                items.append(SourceItem(
                    sourceRef: "gdrive:\(account.id.uuidString):\(file.id)",
                    filename: file.name,
                    rawContent: content,
                    modifiedAt: modified,
                    folderPath: paths?.path,
                    folderIDPath: paths?.idPath,
                    fidelity: fidelity,
                    fileKind: kind
                ))
                if file.modifiedTime > newest { newest = file.modifiedTime }
            }
            pageToken = page.nextPageToken
        } while pageToken != nil

        return SyncResult(items: items, newCursor: newest, folderPaths: folders.allPaths())
    }

    // MARK: Drive REST

    private struct DriveFile: Decodable {
        let id: String
        let name: String
        let mimeType: String
        let modifiedTime: String
        let parents: [String]?
        let size: String?

        var byteSize: Int { size.flatMap(Int.init) ?? 0 }
    }

    private struct FileList: Decodable {
        let files: [DriveFile]
        let nextPageToken: String?
    }

    private func listFiles(
        modifiedAfter cursor: String,
        pageToken: String?,
        tokens: inout GoogleTokens,
        config: GoogleDriveConfig,
        account: SourceAccountSnapshot
    ) async throws -> FileList {
        // List every non-folder file in the window; FileEnricher routes each
        // client-side (read / extract / metadata stub / skip) so unreadable
        // files still become findable memories.
        let query = "trashed=false and mimeType!='\(DriveFolderService.folderMimeType)' and modifiedTime > '\(cursor)'"

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,modifiedTime,parents,size)"),
            URLQueryItem(name: "orderBy", value: "modifiedTime"),
            URLQueryItem(name: "pageSize", value: "100"),
        ]
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        let data = try await authorizedRequest(url: components.url!, tokens: &tokens, config: config, account: account)
        return try JSONDecoder().decode(FileList.self, from: data)
    }

    private func fetchContent(
        of file: DriveFile,
        tokens: inout GoogleTokens,
        config: GoogleDriveConfig,
        account: SourceAccountSnapshot
    ) async throws -> String {
        let url: URL
        if case .export(let mime) = FileEnricher.strategy(for: file.mimeType, inEnrichmentScope: false) {
            let encoded = mime.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mime
            url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)/export?mimeType=\(encoded)")!
        } else {
            url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
        }
        let data = try await authorizedRequest(url: url, tokens: &tokens, config: config, account: account)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Raw download for binary extraction (PDF etc.), size-capped.
    private func fetchData(
        of file: DriveFile,
        tokens: inout GoogleTokens,
        config: GoogleDriveConfig,
        account: SourceAccountSnapshot
    ) async throws -> Data? {
        guard file.byteSize <= FileEnricher.downloadCap else { return nil }
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
        return try await authorizedRequest(url: url, tokens: &tokens, config: config, account: account)
    }

    /// Performs a GET with the access token, refreshing once on 401.
    private func authorizedRequest(
        url: URL,
        tokens: inout GoogleTokens,
        config: GoogleDriveConfig,
        account: SourceAccountSnapshot
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 {
            tokens = try await refreshOrFail(tokens, config: config, account: account)
            var retry = URLRequest(url: url)
            retry.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
            guard (retryResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw ConnectorError.accessDenied
            }
            return retryData
        }
        guard status == 200 else { throw ConnectorError.accessDenied }
        return data
    }

    private func refreshOrFail(
        _ tokens: GoogleTokens,
        config: GoogleDriveConfig,
        account: SourceAccountSnapshot
    ) async throws -> GoogleTokens {
        do {
            let refreshed = try await GoogleDriveAuth.refresh(tokens: tokens, clientID: config.clientID)
            KeychainStore.save(refreshed, for: keychainKey(account))
            return refreshed
        } catch {
            throw ConnectorError.accessDenied
        }
    }

    private func keychainKey(_ account: SourceAccountSnapshot) -> String {
        "source-token-\(account.id.uuidString)"
    }

    private static func parseRFC3339(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
