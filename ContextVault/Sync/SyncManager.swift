import Foundation
import BackgroundTasks
import SwiftData

/// Orchestrates connector syncs and the knowledge pipeline that follows
/// them.
///
/// How fresh the vault is, in order of how much each mechanism can be
/// relied on (iOS decides when background work runs, so none of the
/// background ones is a guarantee):
/// 1. **App open** and manual sync — full sync of every source.
/// 2. **Refresh-on-ask** — when Siri calls the lookup tool, a few seconds'
///    top-up of fast-moving sources (mail) before answering.
/// 3. **Background app refresh** (`BGAppRefreshTask`) — a short mail
///    top-up, as often as the system allows.
/// 4. **Background processing** (`BGProcessingTask`) — a full sync when
///    the device is idle.
final class SyncManager: @unchecked Sendable {
    static let shared = SyncManager()
    static let backgroundTaskIdentifier = "com.saturdaysinthepark.contextvault.sync"
    static let refreshTaskIdentifier = "com.saturdaysinthepark.contextvault.refresh"

    /// Sources whose content changes by the minute and is worth topping up
    /// right before answering a question.
    static let fastMovingSources: Set<SourceType> = [.gmail]

    private let connectors: [SourceType: any Connector] = [
        .obsidian: ObsidianConnector(),
        .files: ObsidianConnector(), // any Markdown folder uses the same reader
        .notion: NotionConnector(),
        .googleDrive: GoogleDriveConnector(),
        .gmail: GmailConnector(),
    ]

    /// Ensures one sync runs at a time, so a top-up never interleaves with
    /// a full sync over the same accounts.
    private let gate = SyncGate()

    // MARK: Background scheduling

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            self.handleBackgroundSync(task)
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handleBackgroundRefresh(task)
        }
    }

    /// Ask for a short background top-up. The system chooses the moment,
    /// based on how the app is used; fifteen minutes is the earliest.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh() // re-arm for next time

        let work = Task {
            // App refresh gets roughly 30 seconds; stay well inside it.
            await self.refreshIfStale(sources: nil, maxAge: 10 * 60, budget: .seconds(20))
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundSync(_ task: BGProcessingTask) {
        scheduleBackgroundSync() // re-arm for next time

        let work = Task {
            await self.syncAll()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: Sync

    /// Sync every configured source, then distil what arrived. Safe to
    /// call repeatedly; each connector is incremental via its cursor. If a
    /// sync is already running, this call waits for it and then runs, so
    /// when it returns the vault reflects everything connected so far.
    func syncAll() async {
        await gate.wait()
        await runSync(types: nil, quickLimit: nil)
        await runIntelligence(cardLimit: 40, sources: nil)
        // Keep the indexed source entities (name, counts, last sync) current.
        try? await VaultStore.shared.reindexSources()
        await gate.end()
    }

    /// A short top-up of fast-moving sources, for the moment just before a
    /// question is answered. It does only as much as fits in `budget`, and
    /// whatever it does not finish stays queued for the next full sync.
    ///
    /// - Parameters:
    ///   - sources: the sources the question is about (nil = any). Only
    ///     fast-moving ones are refreshed; a question limited to Google
    ///     Drive triggers nothing.
    ///   - maxAge: skip accounts synced more recently than this.
    ///   - budget: the most time to spend before returning.
    /// - Returns: how many cards were created or updated.
    @discardableResult
    func refreshIfStale(
        sources: Set<SourceType>?,
        maxAge: TimeInterval = 5 * 60,
        budget: Duration = .seconds(5)
    ) async -> Int {
        let wanted = (sources ?? Self.fastMovingSources).intersection(Self.fastMovingSources)
        guard !wanted.isEmpty else { return 0 }

        let stale = await MainActor.run { () -> Bool in
            let accounts = (try? VaultStore.shared.context.fetch(FetchDescriptor<SourceAccount>())) ?? []
            return accounts.contains { account in
                wanted.contains(account.sourceType)
                    && (account.lastSyncedAt.map { Date.now.timeIntervalSince($0) > maxAge } ?? true)
            }
        }
        guard stale, await gate.begin() else { return 0 }

        let changed = await withTaskGroup(of: Int?.self) { group -> Int in
            group.addTask {
                // Newest few messages only, then distil just those.
                await self.runSync(types: wanted, quickLimit: 8)
                return await CardPipeline.processPending(limit: 4, sources: wanted)
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            // Whichever finishes first ends the wait; the other is cancelled.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? 0
        }
        await gate.end()
        return changed
    }

    /// Runs connectors for the chosen source types and ingests what they
    /// return.
    /// - Parameter quickLimit: when set, connectors fetch only that many
    ///   of the newest items (see `SourceAccountSnapshot.quickLimit`).
    private func runSync(types: Set<SourceType>?, quickLimit: Int?) async {
        let accounts: [SourceAccountSnapshot]
        do {
            accounts = try await MainActor.run {
                let collections = try VaultStore.shared.allCollections()
                return try VaultStore.shared.context
                    .fetch(FetchDescriptor<SourceAccount>())
                    .map { account in
                        var snapshot = SourceAccountSnapshot(account)
                        // Collection-subscribed folders earn enrichment
                        // effort even when sync scope is "everything".
                        snapshot.ruleFolderIDs = collections
                            .flatMap(\.rules)
                            .filter { $0.sourceAccountID == account.id && $0.kind == .folder }
                            .compactMap(\.folderID)
                        snapshot.quickLimit = quickLimit
                        return snapshot
                    }
                    .filter { types == nil || types!.contains($0.sourceType) }
            }
        } catch {
            return
        }

        for account in accounts {
            if Task.isCancelled { return }
            guard let connector = connectors[account.sourceType] else { continue }
            do {
                let result = try await connector.sync(account: account)
                try await ingest(result, account: account)
            } catch {
                // Individual source failures shouldn't stop the others.
                continue
            }
        }
    }

    /// Post-sync intelligence, all on device and best-effort:
    /// 1. tag sensitivity on new memories, so private content is withheld
    ///    before anything derived from it is indexed;
    /// 2. distil context cards and document summaries;
    /// 3. refresh the About Me card.
    private func runIntelligence(cardLimit: Int, sources: Set<SourceType>?) async {
        await SensitivityClassifier.classifyPending()
        let changed = await CardPipeline.processPending(limit: cardLimit, sources: sources)
        if changed > 0 {
            await ProfileDistiller().distill()
        }
    }

    private func ingest(_ result: SyncResult, account: SourceAccountSnapshot) async throws {
        for item in result.items {
            // Full-fidelity text goes through Markdown normalization;
            // extracted/stub content arrives pre-rendered from the enricher.
            let title: String
            let body: String
            if item.fidelity == .full {
                let normalized = MarkdownNormalizer.normalize(
                    filename: item.filename,
                    rawMarkdown: item.rawContent
                )
                title = item.title ?? normalized.title
                body = normalized.body
            } else {
                title = item.title ?? (item.filename as NSString).deletingPathExtension
                body = item.rawContent
            }

            let structuredJSON: String? = item.structuredData.isEmpty
                ? nil
                : (try? JSONEncoder().encode(item.structuredData)).flatMap { String(data: $0, encoding: .utf8) }

            try await MainActor.run {
                let existing = try VaultStore.shared.memory(sourceRef: item.sourceRef)
                let memory = existing ?? Memory(
                    title: title,
                    body: body,
                    sourceType: account.sourceType,
                    sourceRef: item.sourceRef
                )
                // Only changed content is queued for distilling again; a
                // connector may legitimately return an unchanged item.
                let changed = existing == nil
                    || memory.title != title
                    || memory.body != body
                    || memory.structuredData != structuredJSON
                if changed {
                    memory.cardsExtractedAt = nil
                    memory.summary = nil
                }
                memory.title = title
                memory.body = body
                memory.sender = item.sender
                memory.threadKey = item.threadKey
                memory.structuredData = structuredJSON
                memory.modifiedAt = item.modifiedAt
                memory.sourcePath = item.folderPath
                memory.sourceFolderPath = item.folderIDPath
                memory.fidelity = item.fidelity
                memory.fileKind = item.fileKind
                VaultStore.shared.context.insert(memory)
                try VaultStore.shared.context.save()
            }
        }

        // Path-refresh pass: with a fresh folder map, rebuild paths for ALL
        // of this account's memories from their immediate-parent folder ID —
        // pure local work that keeps names current after renames/moves.
        if let folderPaths = result.folderPaths {
            try await MainActor.run {
                let prefix = "gdrive:\(account.id.uuidString):"
                let memories = try VaultStore.shared.memories(sourceRefPrefix: prefix)
                for memory in memories {
                    guard let idPath = memory.sourceFolderPath,
                          let parentID = idPath.components(separatedBy: "/").last,
                          !parentID.isEmpty,
                          let fresh = folderPaths[parentID] else { continue }
                    memory.sourcePath = fresh.path
                    memory.sourceFolderPath = fresh.idPath
                }
                try VaultStore.shared.context.save()
            }
        }

        // Apply live collection rules to touched memories, reindex everything
        // touched this pass (rule membership affects Siri visibility), then
        // persist the cursor.
        try await MainActor.run {
            let refs = result.items.map(\.sourceRef)
            let touched = try refs.compactMap { try VaultStore.shared.memory(sourceRef: $0) }

            let collections = try VaultStore.shared.allCollections()
            CollectionRuleEngine.apply(to: touched, collections: collections)
            try VaultStore.shared.context.save()

            Task {
                try? await SpotlightIndexer.shared.reindex(memories: touched.map(MemorySnapshot.init))
            }

            let accountID = account.id
            if let stored = try VaultStore.shared.context.fetch(
                FetchDescriptor<SourceAccount>(predicate: #Predicate { $0.id == accountID })
            ).first {
                stored.syncCursor = result.newCursor
                stored.lastSyncedAt = .now
                try VaultStore.shared.context.save()
            }
        }
    }
}

/// A one-at-a-time gate for sync work.
private actor SyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Takes the gate if it is free. Returns false, without waiting, if a
    /// sync is running — for work that is not worth queueing.
    func begin() -> Bool {
        guard !busy else { return false }
        busy = true
        return true
    }

    /// Takes the gate, waiting for the current holder to finish first.
    func wait() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        // Ownership was handed over by `end()`; `busy` is still true.
    }

    /// Releases the gate, handing it to the next waiter if there is one.
    func end() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
