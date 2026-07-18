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

    private static let docsMimeType = "application/vnd.google-apps.document"
    private static let textMimeTypes = ["text/markdown", "text/plain", "text/x-markdown"]

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
                    continue // metadata row skipped; no content fetched
                }
                guard let content = try? await fetchContent(of: file, tokens: &tokens, config: config, account: account),
                      !content.isEmpty else { continue }
                let paths = parentID.flatMap { folders.paths(for: $0) }
                items.append(SourceItem(
                    sourceRef: "gdrive:\(account.id.uuidString):\(file.id)",
                    filename: file.name,
                    rawContent: content,
                    modifiedAt: Self.parseRFC3339(file.modifiedTime) ?? .now,
                    folderPath: paths?.path,
                    folderIDPath: paths?.idPath
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
        let mimeClauses = ([Self.docsMimeType] + Self.textMimeTypes)
            .map { "mimeType='\($0)'" }
            .joined(separator: " or ")
        let query = "trashed=false and (\(mimeClauses)) and modifiedTime > '\(cursor)'"

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,modifiedTime,parents)"),
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
        if file.mimeType == Self.docsMimeType {
            url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)/export?mimeType=text/plain")!
        } else {
            url = URL(string: "https://www.googleapis.com/drive/v3/files/\(file.id)?alt=media")!
        }
        let data = try await authorizedRequest(url: url, tokens: &tokens, config: config, account: account)
        return String(data: data, encoding: .utf8) ?? ""
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
