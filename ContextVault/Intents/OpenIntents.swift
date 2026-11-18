import AppIntents

/// Opens one context card in the app. Spotlight runs this when a person
/// taps a card in search results, and Siri runs it when they tap a card
/// snippet or ask to open a card.
@AppIntent(schema: .system.open)
struct OpenCardIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Card"
    static let description = IntentDescription("Opens a context card in Context Vault.")

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @Parameter(title: "Card", requestValueDialog: "Which card?")
    var target: ContextCardEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.open(cardID: target.id)
        return .result()
    }
}

/// Opens one memory (a document or note) in the app.
@AppIntent(schema: .system.open)
struct OpenMemoryIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Memory"
    static let description = IntentDescription("Opens a document or note in Context Vault.")

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @Parameter(title: "Memory", requestValueDialog: "Which document or note?")
    var target: MemoryEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.open(memoryID: target.id)
        return .result()
    }
}

/// Shows search results inside the app ("Search Context Vault for my
/// lease"). Spotlight also uses it to hand a search over to the app when
/// there are more results than it shows itself.
@AppIntent(schema: .system.searchInApp)
struct SearchVaultIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Vault"
    static let description = IntentDescription("Searches your context cards in Context Vault.")

    /// The content categories this action covers.
    static var searchScopes: [StringSearchScope] = [.general]

    /// What to search for.
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.search(criteria.term)
        return .result()
    }
}
