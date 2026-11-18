import Foundation
import SwiftData

/// Turns newly synced evidence into context cards and summaries, and
/// keeps the index in step.
///
///     evidence (Memory)
///       → extract   structured markup if present, else the on-device model
///       → merge     into the card for the same real-world thing
///       → render    the statement Siri reads, with absolute dates
///       → index     as an app entity in the Spotlight semantic index
///
/// Runs after every sync, and in a small, time-boxed form when Siri asks
/// a question (see `SyncManager.refreshIfStale`). Work is queued by
/// `Memory.cardsExtractedAt == nil`, so an interrupted pass simply resumes.
enum CardPipeline {

    /// Processes queued memories, newest first.
    /// - Parameters:
    ///   - limit: how many memories to handle this pass. Model extraction
    ///     takes seconds per item, so passes are kept short.
    ///   - sources: restrict to these source types (nil = all).
    /// - Returns: the number of cards created or updated.
    @discardableResult
    static func processPending(limit: Int = 40, sources: Set<SourceType>? = nil) async -> Int {
        let pending = await MainActor.run { pendingEvidence(limit: limit, sources: sources) }
        guard !pending.isEmpty else {
            await archiveExpiredCards()
            return 0
        }

        var touchedCardIDs = Set<UUID>()
        var summarizedMemoryIDs = Set<UUID>()

        for evidence in pending {
            if Task.isCancelled { break }

            // Privacy first: decide whether this evidence is sensitive
            // before anything distilled from it can reach the index.
            if evidence.needsSensitivityCheck {
                let sensitivity = await SensitivityClassifier.classify(title: evidence.title, body: evidence.body)
                if sensitivity != .unclassified {
                    await MainActor.run {
                        guard let memory = try? VaultStore.shared.memory(id: evidence.id) else { return }
                        memory.sensitivity = sensitivity
                        try? VaultStore.shared.context.save()
                    }
                }
            }

            let outcome = await extract(evidence)

            // Apply the outcome on the main actor and report back what
            // changed, rather than mutating state across actors.
            let applied: (cardIDs: [UUID], summarizedMemoryID: UUID?) = await MainActor.run {
                guard let memory = try? VaultStore.shared.memory(id: evidence.id) else { return ([], nil) }
                var cardIDs: [UUID] = []
                var summarizedMemoryID: UUID?

                switch outcome {
                case .deferred:
                    // Model not ready: leave the memory queued for a later pass.
                    return ([], nil)
                case .cards(let drafts):
                    for draft in drafts {
                        if let card = try? CardMerger.upsert(
                            draft,
                            source: evidence.sourceType,
                            sourceAccountID: evidence.sourceAccountID,
                            evidenceID: evidence.id,
                            asOf: evidence.date
                        ) {
                            cardIDs.append(card.id)
                        }
                    }
                case .summary(let summary):
                    if let summary, memory.summary != summary {
                        memory.summary = summary
                        summarizedMemoryID = memory.id
                    }
                }
                memory.cardsExtractedAt = .now
                try? VaultStore.shared.context.save()
                return (cardIDs, summarizedMemoryID)
            }
            touchedCardIDs.formUnion(applied.cardIDs)
            if let id = applied.summarizedMemoryID {
                summarizedMemoryIDs.insert(id)
            }
        }

        // Index what changed, once, at the end of the pass.
        let cardIDs = Array(touchedCardIDs)
        let memoryIDs = Array(summarizedMemoryIDs)
        await reindex(cardIDs: cardIDs, memoryIDs: memoryIDs)
        await archiveExpiredCards()
        return touchedCardIDs.count
    }

    /// Reindexes the cards and memories a pass changed, and waits for it,
    /// so a caller that goes on to search sees the new state.
    @MainActor
    private static func reindex(cardIDs: [UUID], memoryIDs: [UUID]) async {
        let store = VaultStore.shared
        if let cards = try? store.cards(ids: cardIDs), !cards.isEmpty {
            try? await store.reindex(cards: cards)
        }
        if let memories = try? store.memories(ids: memoryIDs), !memories.isEmpty {
            try? await SpotlightIndexer.shared.reindex(memories: memories.map(MemorySnapshot.init))
        }
    }

    /// Queues every memory for extraction again — used after the pipeline
    /// itself improves, or from the Siri Lab.
    @MainActor
    static func requeueAll() throws {
        let memories = try VaultStore.shared.context.fetch(FetchDescriptor<Memory>())
        for memory in memories {
            memory.cardsExtractedAt = nil
        }
        try VaultStore.shared.context.save()
    }

    // MARK: Extraction

    enum Outcome: Sendable {
        /// Cards to create or update. Empty means the evidence carries
        /// nothing worth a card (most mail).
        case cards([CardDraft])
        /// A document summary, or nil when none was needed.
        case summary(String?)
        /// Could not be processed now; try again on a later pass.
        case deferred
    }

    static func extract(_ evidence: EvidenceInput) async -> Outcome {
        // 1. Structured markup: exact and free, so it always goes first.
        let structured = SchemaOrgExtractor.drafts(
            fromJSONLD: evidence.structuredData,
            fallbackCounterpart: evidence.senderName
        )
        if !structured.isEmpty {
            return .cards(structured)
        }

        // 2. The on-device model.
        switch evidence.sourceType {
        case .gmail:
            guard ModelCardExtractor.isAvailable else { return .deferred }
            let draft = await ModelCardExtractor.draft(fromMail: evidence)
            return .cards(draft.map { [$0] } ?? [])

        case .googleDrive, .notion, .obsidian, .files, .manual, .shareExtension:
            // Documents and notes are indexed as themselves; what they gain
            // here is a summary for the index's description field.
            guard evidence.body.count >= ModelCardExtractor.minimumLengthToSummarize else {
                return .summary(nil)
            }
            guard ModelCardExtractor.isAvailable else { return .deferred }
            return .summary(await ModelCardExtractor.summary(ofDocument: evidence))
        }
    }

    // MARK: Store access

    @MainActor
    private static func pendingEvidence(limit: Int, sources: Set<SourceType>?) -> [EvidenceInput] {
        var descriptor = FetchDescriptor<Memory>(
            predicate: #Predicate<Memory> { $0.cardsExtractedAt == nil },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        // Over-fetch when filtering by source, since the filter runs here.
        descriptor.fetchLimit = sources == nil ? limit : limit * 6
        let memories = (try? VaultStore.shared.context.fetch(descriptor)) ?? []

        return memories
            .filter { memory in
                // Metadata-only stubs have no content to distil.
                memory.fidelity != .metadataOnly && (sources == nil || sources!.contains(memory.sourceType))
            }
            .prefix(limit)
            .map(EvidenceInput.init(memory:))
    }

    /// Archives cards whose date has passed and removes them from the index.
    private static func archiveExpiredCards() async {
        await archiveExpiredOnMain()
    }

    @MainActor
    private static func archiveExpiredOnMain() async {
        guard let expired = try? CardMerger.archiveExpired(), !expired.isEmpty else { return }
        try? VaultStore.shared.context.save()
        try? await VaultStore.shared.reindex(cards: expired)
    }
}

extension EvidenceInput {
    @MainActor
    init(memory: Memory) {
        var blocks: [String] = []
        if let json = memory.structuredData,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            blocks = decoded
        }
        self.init(
            id: memory.id,
            title: memory.title,
            body: memory.body,
            sourceType: memory.sourceType,
            sourceAccountID: memory.sourceRef.flatMap(Self.accountID(fromSourceRef:)),
            sender: memory.sender,
            threadKey: memory.threadKey,
            structuredData: blocks,
            date: memory.modifiedAt,
            needsSensitivityCheck: memory.sensitivity == .unclassified
        )
    }

    /// Source refs look like "gmail:<account uuid>:<id>".
    static func accountID(fromSourceRef ref: String) -> UUID? {
        let parts = ref.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        return UUID(uuidString: parts[1])
    }
}
