import Foundation
import FoundationModels

/// "Ask your Vault" — on-device RAG over the user's memories.
///
/// iOS 27 path: hand the Foundation Models session a `SpotlightSearchTool`
/// and let the model retrieve from the app's own Spotlight index directly
/// (WWDC26 246). iOS 26 path: retrieve manually via CSUserQuery, stuff the
/// top chunks into the prompt, and budget tokens against the 4K window.
///
/// NOTE: The iOS 27 branch is written against the API surface announced at
/// WWDC26 and gated behind `#if compiler` + availability. Verify exact
/// signatures against the Xcode 27 SDK — beta APIs can shift between seeds.
@available(iOS 26.0, *)
final class VaultChatService {

    struct Answer: Sendable {
        var text: String
        /// Identifiers of memories used as context, for the citations UI.
        var sourceMemoryIDs: [UUID]
    }

    enum ChatError: LocalizedError {
        case modelUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                "Apple Intelligence isn't available: \(reason)"
            }
        }
    }

    private let instructions = """
        You are Context Vault, the user's personal memory assistant. Answer \
        questions using ONLY the provided context from the user's own notes \
        and documents. If the context doesn't contain the answer, say so \
        plainly — never invent facts. Keep answers concise.
        """

    /// Answer a question, optionally scoped to one collection.
    func ask(_ question: String, scopedTo collection: MemoryCollection? = nil) async throws -> Answer {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ChatError.modelUnavailable(String(describing: reason))
        }

        if #available(iOS 27.0, *) {
            return try await askWithSpotlightTool(question, collection: collection)
        } else {
            return try await askWithManualRetrieval(question, collection: collection)
        }
    }

    // MARK: iOS 27 — SpotlightSearchTool RAG

    @available(iOS 27.0, *)
    private func askWithSpotlightTool(_ question: String, collection: MemoryCollection?) async throws -> Answer {
        // TODO(iOS 27 SDK): adopt SpotlightSearchTool once building against
        // the Xcode 27 SDK, e.g.:
        //   let tool = SpotlightSearchTool()
        //   let session = LanguageModelSession(tools: [tool], instructions: instructions)
        //   let response = try await session.respond(to: question)
        //   let used = await tool.searchResults  // -> map to memory IDs for citations
        // Until then, fall through to manual retrieval so the app works on
        // iOS 27 devices built with the iOS 26 SDK.
        try await askWithManualRetrieval(question, collection: collection)
    }

    // MARK: iOS 26 — manual retrieve-then-read

    private func askWithManualRetrieval(_ question: String, collection: MemoryCollection?) async throws -> Answer {
        // 0. The About Me card rides along with every question — dense,
        //    always-on personal context that retrieval can't surface.
        let aboutMe: String = await MainActor.run {
            guard let card = try? VaultStore.shared.aboutMeCard(),
                  card.siriVisible, !card.content.isEmpty else { return "" }
            return card.content
        }

        // 1. Retrieve candidate memories from the Spotlight index.
        let identifiers = try await SpotlightIndexer.shared.search(question, limit: 8)
        let ids = identifiers.compactMap { UUID(uuidString: $0.replacingOccurrences(of: "memory-", with: "")) }

        var memories = try await MainActor.run {
            try VaultStore.shared.memories(ids: ids)
        }
        if let collection {
            let collectionID = collection.id
            memories = memories.filter { m in m.collections.contains { $0.id == collectionID } }
        }

        // 2. Build context within the on-device window. Instructions +
        //    question + answer headroom get ~1K tokens; context gets the rest.
        let contextBudget = 2800 * 4 // chars, ~2.8K tokens of a 4K window
        var contextParts: [String] = []
        var used = 0
        var usedIDs: [UUID] = []
        if !aboutMe.isEmpty {
            let profileSection = "## About the user\n\(aboutMe)"
            contextParts.append(profileSection)
            used += profileSection.count
        }
        for memory in memories {
            let snippet = "## \(memory.title)\n\(memory.summary ?? String(memory.body.prefix(Chunker.targetSize)))"
            guard used + snippet.count <= contextBudget else { break }
            contextParts.append(snippet)
            used += snippet.count
            usedIDs.append(memory.id)
        }

        guard !contextParts.isEmpty else {
            return Answer(
                text: "I couldn't find anything in your vault about that yet. Try syncing your sources or adding memories.",
                sourceMemoryIDs: []
            )
        }

        // 3. Ask the on-device model.
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
            Context from the user's vault:

            \(contextParts.joined(separator: "\n\n"))

            Question: \(question)
            """
        let response = try await session.respond(to: prompt)
        return Answer(text: response.content, sourceMemoryIDs: usedIDs)
    }
}
