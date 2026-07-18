import Foundation

/// Pulls pages the user shared with their Notion internal integration.
///
/// Auth: an internal-integration token pasted by the user (Keychain).
/// Public OAuth needs a client secret that can't ship in an app binary, so
/// the internal token is the correct v1 — the user creates one at
/// notion.so/my-integrations and shares pages/databases with it.
///
/// Incremental sync: search results sorted by last_edited_time descending;
/// we stop at the first page not newer than the cursor. Rate limit is
/// 3 req/sec — calls are paced and 429s honor Retry-After.
struct NotionConnector: Connector {
    let sourceType: SourceType = .notion

    private static let apiBase = "https://api.notion.com/v1"
    private static let notionVersion = "2022-06-28"
    private static let pacing: Duration = .milliseconds(350)

    struct NotionToken: Codable {
        var token: String
    }

    func sync(account: SourceAccountSnapshot) async throws -> SyncResult {
        guard let stored = KeychainStore.load(NotionToken.self, for: keychainKey(account)) else {
            throw ConnectorError.missingConfiguration
        }
        let token = stored.token
        let cursorDate = account.syncCursor ?? "1970-01-01T00:00:00.000Z"

        var items: [SourceItem] = []
        var newest = cursorDate
        var searchCursor: String?
        var done = false

        repeat {
            let page = try await search(after: searchCursor, token: token)
            for pageObject in page.results {
                guard let id = pageObject["id"] as? String,
                      let lastEdited = pageObject["last_edited_time"] as? String else { continue }
                // Results are newest-first; stop at the cursor boundary.
                if lastEdited <= cursorDate { done = true; break }

                let title = NotionBlockRenderer.pageTitle(from: pageObject)
                let content = try await fetchPageContent(pageID: id, token: token)
                guard !content.isEmpty else { continue }

                // One-level parent for future subtree rules (full ancestor
                // chains deferred — search only returns the immediate parent).
                let parentPageID = (pageObject["parent"] as? [String: Any])?["page_id"] as? String

                items.append(SourceItem(
                    sourceRef: "notion:\(account.id.uuidString):\(id)",
                    filename: "\(title).md",
                    rawContent: "# \(title)\n\n\(content)",
                    modifiedAt: Self.parseISO(lastEdited) ?? .now,
                    folderPath: nil,
                    folderIDPath: parentPageID.map { "/\($0)" }
                ))
                if lastEdited > newest { newest = lastEdited }
            }
            searchCursor = page.nextCursor
        } while searchCursor != nil && !done

        return SyncResult(items: items, newCursor: newest)
    }

    /// Validate a token by fetching the bot user; returns the workspace bot name.
    static func validate(token: String) async throws -> String {
        let data = try await request(path: "/users/me", method: "GET", body: nil, token: token)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["name"] as? String ?? "Notion"
    }

    // MARK: Search + blocks

    private struct SearchPage {
        var results: [[String: Any]]
        var nextCursor: String?
    }

    private func search(after cursor: String?, token: String) async throws -> SearchPage {
        var body: [String: Any] = [
            "filter": ["property": "object", "value": "page"],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"],
            "page_size": 50,
        ]
        if let cursor { body["start_cursor"] = cursor }

        let data = try await Self.request(
            path: "/search",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            token: token
        )
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return SearchPage(
            results: json["results"] as? [[String: Any]] ?? [],
            nextCursor: (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        )
    }

    private func fetchPageContent(pageID: String, token: String) async throws -> String {
        var blocks: [[String: Any]] = []
        var childMap: [String: [[String: Any]]] = [:]
        var cursor: String?

        repeat {
            var path = "/blocks/\(pageID)/children?page_size=100"
            if let cursor { path += "&start_cursor=\(cursor)" }
            let data = try await Self.request(path: path, method: "GET", body: nil, token: token)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let results = json["results"] as? [[String: Any]] ?? []
            blocks.append(contentsOf: results)
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil

        // One level of nesting: fetch children for list/toggle items that
        // report having them. Deeper nesting is flattened away for v1.
        for block in blocks {
            guard block["has_children"] as? Bool == true,
                  let id = block["id"] as? String,
                  let type = block["type"] as? String,
                  ["bulleted_list_item", "numbered_list_item", "toggle", "to_do"].contains(type) else { continue }
            let data = try? await Self.request(path: "/blocks/\(id)/children?page_size=50", method: "GET", body: nil, token: token)
            if let data,
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                childMap[id] = json["results"] as? [[String: Any]] ?? []
            }
        }

        return NotionBlockRenderer.render(blocks: blocks, children: childMap)
    }

    // MARK: HTTP

    @discardableResult
    private static func request(path: String, method: String, body: Data?, token: String) async throws -> Data {
        try await Task.sleep(for: pacing) // 3 req/sec budget

        var request = URLRequest(url: URL(string: apiBase + path)!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        if http?.statusCode == 429 {
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 2
            try await Task.sleep(for: .seconds(retryAfter))
            return try await self.request(path: path, method: method, body: body, token: token)
        }
        guard let status = http?.statusCode, (200..<300).contains(status) else {
            throw ConnectorError.accessDenied
        }
        return data
    }

    private func keychainKey(_ account: SourceAccountSnapshot) -> String {
        "source-token-\(account.id.uuidString)"
    }

    private static func parseISO(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
