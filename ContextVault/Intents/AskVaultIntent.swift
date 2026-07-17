import AppIntents

/// "Ask Context Vault ..." — usable from Shortcuts, the Action button, and
/// Siri on any iOS 26+ Apple Intelligence device. This is the pre-Siri-AI
/// fallback surface: it works today, everywhere, regardless of the iOS 27
/// personal-context rollout.
struct AskVaultIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Context Vault"
    static let description = IntentDescription(
        "Answers a question using your memories and collections as context.",
        categoryName: "Vault"
    )

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    @Parameter(title: "Collection", description: "Limit the answer to one collection.")
    var collection: CollectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question)") {
            \.$collection
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard #available(iOS 26.0, *) else {
            return .result(dialog: "Context Vault needs iOS 26 or later.")
        }

        let scoped: MemoryCollection? = try await MainActor.run {
            guard let id = collection?.id else { return nil }
            return try VaultStore.shared.collections(ids: [id]).first
        }

        let service = VaultChatService()
        let answer = try await service.ask(question, scopedTo: scoped)
        return .result(dialog: IntentDialog(stringLiteral: answer.text))
    }
}
