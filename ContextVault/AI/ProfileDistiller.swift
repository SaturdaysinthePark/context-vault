import Foundation
import FoundationModels

/// Distills raw memories into Profile Cards — the on-device equivalent of a
/// persona file (voice.md / professional.md), built by the Foundation Model
/// instead of a cloud pipeline.
///
/// Rules:
/// - Runs after sync passes and on demand from the Profile tab.
/// - Never overwrites a card the user edited: fresh drafts land in
///   `pendingSuggestion` for the user to accept or dismiss.
@available(iOS 26.0, *)
final class ProfileDistiller {

    @Generable
    struct CardDraft {
        @Guide(description: "Concise Markdown bullet points (max 8) capturing what the source material reveals. No preamble, no headings.")
        var markdown: String
    }

    /// Distill (or refresh) every card kind from recent memories.
    func distillAll() async {
        guard case .available = SystemLanguageModel.default.availability else { return }

        let material = await MainActor.run { () -> String in
            let memories = (try? VaultStore.shared.recentMemories(limit: 30)) ?? []
            return memories
                .map { "### \($0.title)\n\($0.summary ?? String($0.body.prefix(600)))" }
                .joined(separator: "\n\n")
        }
        guard !material.isEmpty else { return }

        for kind in ProfileCardKind.allCases {
            await distill(kind: kind, from: material)
        }
    }

    private func distill(kind: ProfileCardKind, from material: String) async {
        // Keep the prompt inside the on-device window: instructions +
        // material + draft must fit ~4K tokens on iOS 26.
        let clipped = String(material.prefix(2200 * 4))
        let session = LanguageModelSession(instructions: """
            You analyze a user's personal notes and distill a profile card \
            about \(kind.distillationFocus). Only state things the notes \
            actually support — never invent. If the notes reveal nothing \
            relevant, respond with the single word: NOTHING
            """)

        do {
            let response = try await session.respond(
                to: "Notes:\n\n\(clipped)",
                generating: CardDraft.self
            )
            let draft = response.content.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !draft.isEmpty, draft != "NOTHING" else { return }

            try await MainActor.run {
                let card = try VaultStore.shared.profileCard(kind: kind)
                if card.userEdited && !card.content.isEmpty {
                    card.pendingSuggestion = draft
                } else {
                    card.content = draft
                    card.pendingSuggestion = nil
                }
                card.lastDistilledAt = .now
                try VaultStore.shared.context.save()
                Task { try? await VaultStore.shared.reindexProfileCards() }
            }
        } catch {
            // Distillation is best-effort; a failed card just stays stale.
        }
    }
}
