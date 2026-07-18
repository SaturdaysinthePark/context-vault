import Foundation

/// Evaluates live collection rules against memories. Additive-only: adds
/// matching memories to collections; never removes. Runs after every sync
/// pass (for touched memories) and retroactively when a rule is created.
@MainActor
enum CollectionRuleEngine {

    /// Apply all collections' rules to the given memories.
    /// Returns memories whose membership changed (callers reindex those —
    /// collection membership affects Siri visibility).
    @discardableResult
    static func apply(to memories: [Memory], collections: [MemoryCollection]) -> [Memory] {
        var changed: [Memory] = []

        for collection in collections {
            let rules = collection.rules
            guard !rules.isEmpty else { continue }
            let exclusions = collection.excludedMemoryIDs

            for memory in memories {
                guard !exclusions.contains(memory.id),
                      !memory.collections.contains(where: { $0.id == collection.id }),
                      rules.contains(where: { matches($0, memory) }) else { continue }
                memory.collections.append(collection)
                changed.append(memory)
            }
        }
        return changed
    }

    /// Retroactively apply one new rule across the vault (local only —
    /// paths are already persisted on memories).
    @discardableResult
    static func applyRetroactively(_ rule: CollectionRule, to collection: MemoryCollection) throws -> [Memory] {
        let candidates = try VaultStore.shared.memories(sourceRefPrefix: rule.sourceRefPrefix)
        let exclusions = collection.excludedMemoryIDs
        var changed: [Memory] = []

        for memory in candidates {
            guard !exclusions.contains(memory.id),
                  !memory.collections.contains(where: { $0.id == collection.id }),
                  matches(rule, memory) else { continue }
            memory.collections.append(collection)
            changed.append(memory)
        }
        try VaultStore.shared.context.save()
        return changed
    }

    // MARK: Matching

    nonisolated static func matches(_ rule: CollectionRule, _ memory: Memory) -> Bool {
        guard memory.sourceRef?.hasPrefix(rule.sourceRefPrefix) == true else { return false }

        switch rule.kind {
        case .entireSource:
            return true

        case .folder:
            if let folderID = rule.folderID {
                // Drive/Notion: the ID chain lists every ancestor, so a
                // component match includes the whole subtree.
                guard let chain = memory.sourceFolderPath else { return false }
                return chain.components(separatedBy: "/").contains(folderID)
            }
            if let rulePath = rule.folderPath {
                // Obsidian: prefix match with a boundary guard so "/Proj"
                // doesn't match "/Projects".
                guard let path = memory.sourcePath else { return false }
                return path == rulePath || path.hasPrefix(rulePath + "/")
            }
            return false
        }
    }
}
