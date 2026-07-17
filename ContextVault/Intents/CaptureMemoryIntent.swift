import AppIntents

/// Quick capture into the vault — from Shortcuts, Spotlight, the Action
/// button, or the share sheet (via a Shortcut). The captured text becomes a
/// memory immediately and is indexed for Siri/Spotlight.
struct CaptureMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Memory"
    static let description = IntentDescription(
        "Saves text into your Context Vault.",
        categoryName: "Vault"
    )

    @Parameter(title: "Text", requestValueDialog: "What should I remember?")
    var text: String

    @Parameter(title: "Collection")
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
