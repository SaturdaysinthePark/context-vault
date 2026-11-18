import AppIntents

/// Test-support intents. They are hidden from Shortcuts and Siri
/// (`isDiscoverable = false`) and are not tools; the Siri evaluation suite
/// runs them directly to put the app in a known state before each
/// scenario, as Apple's evaluation guide recommends.

/// Replaces the demo cards with a fresh fictional set and indexes them.
struct SeedDemoCardsIntent: AppIntent {
    static let title: LocalizedStringResource = "Seed Demo Cards"
    static let description = IntentDescription("Adds fictional cards for testing Siri.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let count = try await DemoSeed.seed()
        return .result(value: count)
    }
}

/// Removes every demo card from the vault and the index.
struct RemoveDemoCardsIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Demo Cards"
    static let description = IntentDescription("Removes the fictional test cards.")
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let count = try await DemoSeed.remove()
        return .result(value: count)
    }
}
