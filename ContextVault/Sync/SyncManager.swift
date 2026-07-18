import Foundation
import BackgroundTasks
import SwiftData

/// Orchestrates connector syncs: foreground-first (on app open and manual
/// pull-to-refresh), with best-effort background top-ups via BGProcessingTask.
final class SyncManager: @unchecked Sendable {
    static let shared = SyncManager()
    static let backgroundTaskIdentifier = "com.saturdaysinthepark.contextvault.sync"

    private let connectors: [SourceType: any Connector] = [
        .obsidian: ObsidianConnector(),
        .files: ObsidianConnector(), // any Markdown folder uses the same reader
        .notion: NotionConnector(),
        .googleDrive: GoogleDriveConnector(),
    ]

    // MARK: Background scheduling

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            self.handleBackgroundSync(task)
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

    /// Sync every configured source. Safe to call repeatedly; each connector
    /// is incremental via its cursor.
    func syncAll() async {
        let accounts: [SourceAccountSnapshot]
        do {
            accounts = try await MainActor.run {
                try VaultStore.shared.context
                    .fetch(FetchDescriptor<SourceAccount>())
                    .map(SourceAccountSnapshot.init)
            }
        } catch {
            return
        }

        var ingestedAnything = false
        for account in accounts {
            guard let connector = connectors[account.sourceType] else { continue }
            do {
                let result = try await connector.sync(account: account)
                try await ingest(result, account: account)
                ingestedAnything = ingestedAnything || !result.items.isEmpty
            } catch {
                // Individual source failures shouldn't stop the others.
                continue
            }
        }

        // Post-sync intelligence: tag sensitivity on new memories, then
        // refresh the About Me card. Best-effort, on-device.
        if #available(iOS 26.0, *) {
            await SensitivityClassifier.classifyPending()
            if ingestedAnything {
                await ProfileDistiller().distill()
            }
        }
    }

    private func ingest(_ result: SyncResult, account: SourceAccountSnapshot) async throws {
        for item in result.items {
            let normalized = MarkdownNormalizer.normalize(
                filename: item.filename,
                rawMarkdown: item.rawContent
            )

            try await MainActor.run {
                let existing = try VaultStore.shared.memory(sourceRef: item.sourceRef)
                let memory = existing ?? Memory(
                    title: normalized.title,
                    body: normalized.body,
                    sourceType: account.sourceType,
                    sourceRef: item.sourceRef
                )
                memory.title = normalized.title
                memory.body = normalized.body
                memory.modifiedAt = item.modifiedAt
                memory.sourcePath = item.folderPath
                memory.sourceFolderPath = item.folderIDPath
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
