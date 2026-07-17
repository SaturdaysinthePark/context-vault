import Foundation
import FoundationModels

/// On-device sensitivity classification: tags memories personal /
/// professional / sensitive so private content is auto-hidden from the
/// system index before Siri ever sees it. Falls back to `.unclassified`
/// (which indexes normally) when the model is unavailable.
@available(iOS 26.0, *)
enum SensitivityClassifier {

    @Generable
    enum Label: String {
        case personal
        case professional
        case sensitive
    }

    /// Classify a single memory's content.
    static func classify(title: String, body: String) async -> Sensitivity {
        guard case .available = SystemLanguageModel.default.availability else {
            return .unclassified
        }

        let session = LanguageModelSession(instructions: """
            Classify the user's note. Choose exactly one label:
            - personal: everyday personal content (hobbies, plans, journal)
            - professional: work, projects, career content
            - sensitive: health, finances, credentials, legal matters, \
            relationships conflicts, or anything the user would not want an \
            assistant to repeat aloud
            """)

        do {
            let excerpt = "\(title)\n\(String(body.prefix(1200)))"
            let response = try await session.respond(to: excerpt, generating: Label.self)
            switch response.content {
            case .personal: return .personal
            case .professional: return .professional
            case .sensitive: return .sensitive
            }
        } catch {
            return .unclassified
        }
    }

    /// Classify any unclassified memories, updating the index as tags land.
    /// Best-effort background work — capped per pass to keep sync snappy.
    static func classifyPending(limit: Int = 20) async {
        let pending: [(UUID, String, String)] = await MainActor.run {
            let unclassifiedRaw = Sensitivity.unclassified.rawValue
            var descriptor = FetchDescriptor<Memory>(
                predicate: #Predicate { $0.sensitivityRaw == unclassifiedRaw },
                sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            let memories = (try? VaultStore.shared.context.fetch(descriptor)) ?? []
            return memories.map { ($0.id, $0.title, $0.body) }
        }

        for (id, title, body) in pending {
            let result = await classify(title: title, body: body)
            guard result != .unclassified else { continue }
            await MainActor.run {
                guard let memory = try? VaultStore.shared.memory(id: id) else { return }
                memory.sensitivity = result
                try? VaultStore.shared.context.save()
                let snapshot = MemorySnapshot(memory)
                Task { try? await SpotlightIndexer.shared.reindex(memories: [snapshot]) }
            }
        }
    }
}
