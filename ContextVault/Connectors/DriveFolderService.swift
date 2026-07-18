import Foundation

/// Fetches and resolves the Google Drive folder tree.
///
/// One paginated listing per call (folders only — a personal Drive is
/// hundreds to low-thousands of folders, so 1–3 requests). The map is never
/// persisted: refetching every sync self-heals renames and moves, and rule
/// matching uses stable folder IDs, not names.
struct DriveFolderService {

    struct Node: Sendable {
        var id: String
        var name: String
        var parent: String?
    }

    /// folder ID → node
    private(set) var nodes: [String: Node] = [:]
    private var resolvedPaths: [String: FolderPaths] = [:]

    static let folderMimeType = "application/vnd.google-apps.folder"
    private static let maxDepth = 50 // cycle guard for corrupt parent chains

    init(nodes: [String: Node] = [:]) {
        self.nodes = nodes
    }

    // MARK: Fetch

    /// Fetch the complete folder inventory using an access-token provider
    /// (the connector's authorized-request machinery).
    static func fetch(request: (URL) async throws -> Data) async throws -> DriveFolderService {
        var nodes: [String: Node] = [:]
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            components.queryItems = [
                URLQueryItem(name: "q", value: "mimeType='\(folderMimeType)' and trashed=false"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,parents)"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            struct Listing: Decodable {
                struct File: Decodable {
                    let id: String
                    let name: String
                    let parents: [String]?
                }
                let files: [File]
                let nextPageToken: String?
            }

            let data = try await request(components.url!)
            let listing = try JSONDecoder().decode(Listing.self, from: data)
            for file in listing.files {
                nodes[file.id] = Node(id: file.id, name: file.name, parent: file.parents?.first)
            }
            pageToken = listing.nextPageToken
        } while pageToken != nil

        return DriveFolderService(nodes: nodes)
    }

    /// Convenience for UI callers (folder picker): fetch using stored
    /// tokens, refreshing once on 401/expiry and persisting the refresh
    /// under `keychainKey` when provided.
    static func fetch(tokens: GoogleTokens, clientID: String, keychainKey: String?) async throws -> DriveFolderService {
        var current = tokens
        if current.isExpired {
            current = try await GoogleDriveAuth.refresh(tokens: current, clientID: clientID)
            if let keychainKey { KeychainStore.save(current, for: keychainKey) }
        }

        func authorized(_ url: URL) async throws -> Data {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                current = try await GoogleDriveAuth.refresh(tokens: current, clientID: clientID)
                if let keychainKey { KeychainStore.save(current, for: keychainKey) }
                var retry = URLRequest(url: url)
                retry.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
                guard (retryResponse as? HTTPURLResponse)?.statusCode == 200 else {
                    throw ConnectorError.accessDenied
                }
                return retryData
            }
            guard status == 200 else { throw ConnectorError.accessDenied }
            return data
        }

        return try await fetch(request: authorized)
    }

    // MARK: Path resolution

    /// Resolve a folder's display path and ID chain (root → this folder).
    /// Returns nil for unknown IDs (e.g. My Drive root itself).
    mutating func paths(for folderID: String) -> FolderPaths? {
        if let cached = resolvedPaths[folderID] { return cached }
        guard nodes[folderID] != nil else { return nil }

        var names: [String] = []
        var ids: [String] = []
        var current: String? = folderID
        var depth = 0
        while let id = current, let node = nodes[id], depth < Self.maxDepth {
            names.insert(node.name, at: 0)
            ids.insert(node.id, at: 0)
            current = node.parent
            depth += 1
        }

        let result = FolderPaths(
            path: "/" + names.joined(separator: "/"),
            idPath: "/" + ids.joined(separator: "/")
        )
        resolvedPaths[folderID] = result
        return result
    }

    /// All resolved paths keyed by folder ID (for SyncResult.folderPaths).
    mutating func allPaths() -> [String: FolderPaths] {
        for id in nodes.keys {
            _ = paths(for: id)
        }
        return resolvedPaths
    }

    // MARK: Subtree closure

    /// The given folder IDs plus every descendant folder ID.
    func descendantClosure(of selected: some Collection<String>) -> Set<String> {
        let selectedSet = Set(selected)
        var result = selectedSet

        // children index
        var children: [String: [String]] = [:]
        for node in nodes.values {
            if let parent = node.parent {
                children[parent, default: []].append(node.id)
            }
        }

        var queue = Array(selectedSet)
        while let id = queue.popLast() {
            for child in children[id] ?? [] where !result.contains(child) {
                result.insert(child)
                queue.append(child)
            }
        }
        return result
    }

    /// True when the folder (by ID chain walk) sits inside the allowed set.
    func isInScope(parentID: String?, allowed: Set<String>) -> Bool {
        var current = parentID
        var depth = 0
        while let id = current, depth < Self.maxDepth {
            if allowed.contains(id) { return true }
            current = nodes[id]?.parent
            depth += 1
        }
        return false
    }

    /// Top-level tree for the picker UI: root folders (parent unknown/absent)
    /// with recursive children lookup.
    func rootFolders() -> [Node] {
        nodes.values
            .filter { $0.parent == nil || nodes[$0.parent!] == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func childFolders(of id: String) -> [Node] {
        nodes.values
            .filter { $0.parent == id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
