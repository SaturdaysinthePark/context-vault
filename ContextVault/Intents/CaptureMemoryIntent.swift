import AppIntents

/// Saves something into the vault — from Siri ("remember that the spare
/// key is with Dana"), Shortcuts, Spotlight or the Action button. The
/// text becomes a note immediately and is indexed for Siri and Spotlight.
///
/// It is a tool, so Siri AI can call it without a fixed phrase. The same
/// intent still backs the "Capture a memory" App Shortcut for Spotlight
/// and the Action button.
@AppIntent(.tool)
struct CaptureMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Memory"
    static let description = IntentDescription(
        """
        Saves a note into the person's Context Vault so it can be recalled later. Use it when \
        the person asks to remember, save or note something for later.
        """,
        categoryName: "Vault"
    )

    @Parameter(
        title: "Text",
        description: "The thing to remember, written as a complete statement, for example: The spare key is with Dana.",
        requestValueDialog: "What should I remember?"
    )
    var text: String

    @Parameter(
        title: "Collection",
        description: "A collection in Context Vault to file the note under. Leave it empty unless the person names one."
    )
    var collection: CollectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text)") {
            \.$collection
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = String(text.prefix(60)).components(separatedBy: .newlines).first ?? "Memory"
        let memory = Memory(title: title, body: text, sourceType: .manual)

        if let id = collection?.id,
           let target = try VaultStore.shared.collections(ids: [id]).first {
            memory.collections = [target]
        }

        try await VaultStore.shared.upsert(memory)
        return .result(dialog: "Saved to your vault.")
    }
}
