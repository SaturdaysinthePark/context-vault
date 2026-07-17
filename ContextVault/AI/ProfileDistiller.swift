import Foundation
import FoundationModels

/// Distills raw memories into the "About Me" card — the on-device
/// equivalent of a persona file, built by the Foundation Model instead of a
/// cloud pipeline. Runs after sync passes and on demand from the card UI.
///
/// Never overwrites a card the user edited: fresh drafts land in
/// `pendingSuggestion` for the user to accept or dismiss.
@available(iOS 26.0, *)
final class ProfileDistiller {

    @Generable
    struct CardDraft {
        @Guide(description: """
            Markdown with exactly these four short sections, each a heading \
            followed by bullet points: '## Who I am' (role, work, identity), \
            '## Current projects', '## How I write' (tone, style), \
            '## Preferences' (tools, habits, likes). Only include facts the \
            notes actually support — never invent. Omit a section entirely \
            if the notes reveal nothing for it.
            """)
        var markdown: String
    }

    /// Build or refresh the About Me card from recent memories.
    /// Returns true when a new draft was produced.
    @discardableResult
    func distill() async -> Bool {
        guard case .available = SystemLanguageModel.default.availability else { return false }

        let material = await MainActor.run { () -> String in
            let memories = (try? VaultStore.shared.recentMemories(limit: 30)) ?? []
            return memories
                .map { "### \($0.title)\n\($0.summary ?? String($0.body.prefix(600)))" }
                .joined(separator: "\n\n")
        }
        guard !material.isEmpty else { return false }

        // Keep the prompt inside the on-device window (~4K tokens on iOS 26):
        // instructions + material + draft must all fit.
        let clipped = String(material.prefix(2200 * 4))
        let session = LanguageModelSession(instructions: """
            You analyze a user's personal notes and distill a concise \
            profile of who they are. Only state things the notes actually \
            support. If the notes reveal nothing about the user, respond \
            with the single word: NOTHING
            """)

        do {
            let response = try await session.respond(
                to: "Notes:\n\n\(clipped)",
                generating: CardDraft.self
            )
            let draft = response.content.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !draft.isEmpty, draft != "NOTHING" else { return false }

            try await MainActor.run {
                let card = try VaultStore.shared.aboutMeCard()
                if card.userEdited && !card.content.isEmpty {
                    card.pendingSuggestion = draft
                } else {
                    card.content = draft
                    card.pendingSuggestion = nil
                }
                card.lastDistilledAt = .now
                try VaultStore.shared.context.save()
                Task { try? await VaultStore.shared.reindexAboutMeCard() }
            }
            return true
        } catch {
            // Distillation is best-effort; a failed pass just leaves the
            // card stale.
            return false
        }
    }
}
