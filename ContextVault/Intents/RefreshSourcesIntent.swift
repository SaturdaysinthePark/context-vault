import AppIntents

/// A tool Siri can call when a person wants the newest information
/// ("check if my package shipped yet"). It tops up fast-moving sources —
/// mail — and distils what arrived, so a lookup afterwards is current.
///
/// The lookup tool already does a brief top-up by itself; this one spends
/// longer and reports what it found.
@AppIntent(.tool)
struct RefreshSourcesIntent: AppIntent {
    static let title: LocalizedStringResource = "Check for Updates"

    static let description = IntentDescription(
        """
        Checks the person's connected sources, such as Gmail, for new information and updates \
        what Context Vault knows. Use it when the person asks for the latest status of \
        something, or says the information looks out of date. Look the topic up again afterwards.
        """,
        categoryName: "Vault"
    )

    @Parameter(
        title: "Source",
        description: "The connected source to check. Leave it empty to check every source that can change quickly, such as Gmail."
    )
    var source: SourceKind?

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$source) for updates")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let updated = await SyncManager.shared.refreshIfStale(
            sources: source?.sourceTypes,
            maxAge: 0,
            budget: .seconds(20)
        )
        let text: String
        switch updated {
        case 0: text = "Nothing new since the last check."
        case 1: text = "One item was updated."
        default: text = "\(updated) items were updated."
        }
        return .result(value: updated, dialog: IntentDialog(stringLiteral: text))
    }
}
