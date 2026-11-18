import AppIntents

/// The tool Siri AI calls to consult the vault.
///
/// It returns cards, not a composed answer: Siri does the reasoning and
/// the wording, and can combine what it gets here with anything else it
/// knows. (`AskVaultIntent` remains for Shortcuts and the Action button,
/// where there is no Siri AI to do that and the app answers by itself.)
///
/// Siri decides whether to call a tool from its title, its description
/// and its parameters' descriptions, so those are written as instructions
/// to a reader who has never seen this app.
@AppIntent(.tool)
struct LookUpContextIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up Personal Context"

    static let description = IntentDescription(
        """
        Finds what the person has saved or received about a topic in their connected sources: \
        email such as Gmail, Google Drive, Notion and their notes. It covers orders and \
        deliveries, travel and reservations, appointments, bills and subscriptions, and \
        documents. Use it whenever answering depends on the person's own information, such as \
        when a package will arrive, when a booking is, or what a document says.
        """,
        categoryName: "Vault",
        searchKeywords: ["order", "package", "delivery", "reservation", "appointment", "bill", "document", "email"]
    )

    @Parameter(
        title: "Topic",
        description: "Key words for what to look up: a product name, merchant, person, place or document title. For example: Twelve Kingdoms Amazon order."
    )
    var topic: String

    @Parameter(
        title: "Source",
        description: "Limits the lookup to one connected source. Set it only when the person names a source, such as Gmail or Google Drive."
    )
    var source: SourceKind?

    @Parameter(
        title: "Kind",
        description: "Limits the lookup to one kind of item, such as orders, travel, appointments or bills. Leave it empty unless the request is clearly about one kind."
    )
    var kind: CardKind?

    static var parameterSummary: some ParameterSummary {
        Summary("Look up \(\.$topic)") {
            \.$source
            \.$kind
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[ContextCardEntity]> & ProvidesDialog {
        // Top up from the named source first, within a small time budget,
        // so the answer reflects mail that arrived since the last sync.
        await SyncManager.shared.refreshIfStale(sources: source?.sourceTypes)

        let cards = try await MainActor.run {
            try VaultStore.shared.searchCards(
                query: topic,
                kind: kind,
                sources: source?.sourceTypes,
                limit: 5
            )
        }

        guard let best = cards.first else {
            return .result(
                value: [ContextCardEntity](),
                dialog: IntentDialog(stringLiteral: "I didn't find anything about \(topic) in your vault.")
            )
        }

        // The dialog is what a person hears when the intent runs outside
        // Siri AI (Shortcuts). Lead with the single best fact.
        let more = cards.count - 1
        let text = more > 0
            ? "\(best.statement) I found \(more) more related \(more == 1 ? "item" : "items")."
            : best.statement
        return .result(
            value: cards.map(ContextCardEntity.init),
            dialog: IntentDialog(stringLiteral: text)
        )
    }
}
