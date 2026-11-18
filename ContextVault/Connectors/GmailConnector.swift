import Foundation

/// Which mail the vault reads. Narrow by default: the vault wants the mail
/// that carries facts (orders, bookings, bills), not the whole inbox, and
/// a narrow query keeps every sync small and fast.
enum GmailScope: String, Codable, CaseIterable, Sendable {
    /// Purchases, reservations and updates — Gmail's own categories for
    /// receipts, shipping notices, bookings, bills and statements.
    case transactional
    /// The inbox without promotions, social and forum mail.
    case inbox
    /// All mail except chats.
    case everything

    var title: String {
        switch self {
        case .transactional: "Orders, bookings and bills"
        case .inbox: "Inbox, without promotions"
        case .everything: "All mail"
        }
    }

    var explanation: String {
        switch self {
        case .transactional:
            "Receipts, shipping notices, reservations, bills and account updates. Recommended."
        case .inbox:
            "Everything in your inbox except promotions, social and forum mail."
        case .everything:
            "Every message. Slower to sync, and most mail carries nothing the vault can use."
        }
    }

    /// The Gmail search query for this scope (same syntax as the Gmail
    /// search box).
    var query: String {
        switch self {
        case .transactional: "{category:purchases category:reservations category:updates}"
        case .inbox: "in:inbox -category:promotions -category:social -category:forums"
        case .everything: "-in:chats"
        }
    }
}

struct GmailConfig: Codable {
    var clientID: String
    var scope: GmailScope = .transactional
    /// How far back the first sync reaches.
    var lookbackDays: Int = 60
    /// The connected address, for display.
    var emailAddress: String?
}

/// Pulls mail from Gmail into the vault as evidence.
///
/// Auth: read-only OAuth tokens in the Keychain (see `GoogleAuth`); the
/// client ID lives in the account's configData. Everything goes directly
/// from Google to this device.
///
/// Incremental sync: the cursor is the send time (seconds since 1970) of
/// the newest message seen. Each pass runs the scope's search query with
/// `after:<cursor>`, so only new mail is listed, and the same filter that
/// defines the scope applies to every pass. Messages are upserted by ID,
/// so a small overlap between passes is harmless.
struct GmailConnector: Connector {
    let sourceType: SourceType = .gmail

    /// Most messages fetched on the first sync and on later passes.
    static let initialCap = 200
    static let incrementalCap = 100
    /// Overlap between passes, to cover clock skew and late delivery.
    static let cursorOverlapSeconds = 600

    private static let api = "https://gmail.googleapis.com/gmail/v1/users/me"

    func sync(account: SourceAccountSnapshot) async throws -> SyncResult {
        guard let configData = account.configData,
              let config = try? JSONDecoder().decode(GmailConfig.self, from: configData),
              var tokens = KeychainStore.load(GoogleTokens.self, for: Self.keychainKey(account)) else {
            throw ConnectorError.missingConfiguration
        }
        if tokens.isExpired {
            tokens = try await Self.refresh(tokens, clientID: config.clientID, account: account)
        }
        let accessToken = tokens.accessToken

        let previous = account.syncCursor.flatMap(Double.init)
        var query = config.scope.query
        if let previous {
            query += " after:\(Int(previous) - Self.cursorOverlapSeconds)"
        } else {
            query += " newer_than:\(config.lookbackDays)d"
        }

        let isQuick = account.quickLimit != nil
        let cap = account.quickLimit ?? (previous == nil ? Self.initialCap : Self.incrementalCap)
        let ids = try await Self.listMessageIDs(query: query, cap: cap, accessToken: accessToken)

        var items: [SourceItem] = []
        var newest = previous ?? 0
        // Fetch a few at a time: fast enough for a first sync, gentle on
        // the API's per-user rate limit.
        for batch in ids.chunked(into: 6) {
            try Task.checkCancellation()
            let mails = try await withThrowingTaskGroup(of: ParsedMail?.self) { group in
                for id in batch {
                    group.addTask { try await Self.fetchMessage(id: id, accessToken: accessToken) }
                }
                var collected: [ParsedMail] = []
                for try await mail in group {
                    if let mail { collected.append(mail) }
                }
                return collected
            }
            for mail in mails {
                newest = max(newest, mail.date.timeIntervalSince1970)
                guard !mail.text.isEmpty else { continue }
                items.append(SourceItem(
                    sourceRef: "gmail:\(account.id.uuidString):\(mail.id)",
                    filename: mail.subject,
                    rawContent: mail.text,
                    modifiedAt: mail.date,
                    // Pre-rendered text: skip Markdown normalization.
                    fidelity: .extracted,
                    fileKind: "Email",
                    title: mail.subject.isEmpty ? "(no subject)" : mail.subject,
                    sender: mail.sender,
                    threadKey: "gmail:\(account.id.uuidString):\(mail.threadID)",
                    structuredData: mail.structuredData
                ))
            }
        }

        // A quick pass fetches only the newest few messages, so it must not
        // move the cursor: older unfetched mail would be skipped for good.
        let newCursor: String? = isQuick
            ? account.syncCursor
            : (newest > 0 ? String(Int(newest)) : account.syncCursor)
        return SyncResult(items: items, newCursor: newCursor)
    }

    /// Checks the tokens work and returns the connected address.
    static func validate(tokens: GoogleTokens) async throws -> String {
        struct Profile: Decodable { let emailAddress: String }
        let data = try await get(URL(string: "\(api)/profile")!, accessToken: tokens.accessToken)
        return try JSONDecoder().decode(Profile.self, from: data).emailAddress
    }

    // MARK: Gmail REST

    private struct MessageList: Decodable {
        struct Entry: Decodable { let id: String }
        let messages: [Entry]?
        let nextPageToken: String?
    }

    /// Message IDs matching the query, newest first, up to `cap`.
    private static func listMessageIDs(query: String, cap: Int, accessToken: String) async throws -> [String] {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "\(api)/messages")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: String(min(100, cap - ids.count))),
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let data = try await get(components.url!, accessToken: accessToken)
            let page = try JSONDecoder().decode(MessageList.self, from: data)
            ids.append(contentsOf: (page.messages ?? []).map(\.id))
            pageToken = page.nextPageToken
        } while pageToken != nil && ids.count < cap
        return Array(ids.prefix(cap))
    }

    private static func fetchMessage(id: String, accessToken: String) async throws -> ParsedMail? {
        let url = URL(string: "\(api)/messages/\(id)?format=full")!
        let data = try await get(url, accessToken: accessToken)
        return try? GmailMessageParser.parse(data)
    }

    private static func get(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ConnectorError.accessDenied
        }
        return data
    }

    private static func refresh(
        _ tokens: GoogleTokens,
        clientID: String,
        account: SourceAccountSnapshot
    ) async throws -> GoogleTokens {
        do {
            let refreshed = try await GoogleAuth.refresh(tokens: tokens, clientID: clientID)
            KeychainStore.save(refreshed, for: keychainKey(account))
            return refreshed
        } catch {
            throw ConnectorError.accessDenied
        }
    }

    private static func keychainKey(_ account: SourceAccountSnapshot) -> String {
        "source-token-\(account.id.uuidString)"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
