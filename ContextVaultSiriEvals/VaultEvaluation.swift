import XCTest
import Evaluations
import AppIntentsTesting
import SiriEvaluations

// Siri evaluations for Context Vault.
//
// These run real requests through Siri on a physical device and record
// what Siri did: which app entities it found, which intents it called,
// which skills it loaded, and what it replied. They need:
//   - a device that supports the Siri AI Developer Preview (iOS 27.3 beta),
//     with Siri set up and Developer Mode + UI Automation enabled;
//   - Context Vault installed and signed by the same team as this target.
// They do not run in Simulator. See docs/SIRI_TESTING.md.
//
// NOTE: this target was written against Apple's documentation without
// access to Xcode, so it has not been compiled. Expect to adjust small
// details of the beta API on first build.

let vaultBundleIdentifier = "com.saturdaysinthepark.contextvault"

/// The intents, entities and skills of the app under test.
let vault = IntentDefinitions(bundleIdentifier: vaultBundleIdentifier)

let lookUpContextIntent = vault.intents["LookUpContextIntent"]
let seedDemoCardsIntent = vault.intents["SeedDemoCardsIntent"]
let contextCardEntity = vault.entities["ContextCardEntity"]
let lookupSkill = vault.skills["personal-context-lookup"]

/// Where Context Vault is when Siri receives the request. Apple's preview
/// notes say a request must name the app while it is in the background,
/// so the background state is the one that tests the primary use case.
enum AppState: Sendable {
    case foreground
    case background
}

/// Runs scenarios through Siri after putting the app in a known state:
/// demo cards seeded and indexed, and the app in the chosen app state.
struct VaultEvaluation: Evaluation {
    /// The title of the evaluation's report in Xcode.
    let name: String
    let dataset: SiriScenarioLoader
    var appState: AppState = .background

    var evaluators: Evaluators {
        SiriExpectationEvaluator()
    }

    func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
        try await VaultTestState.shared.prepare(appState: appState)
        return try await SiriService.run(scenario: sample)
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        Self.computeSiriMetrics(into: &aggregator)
    }
}

/// Seeds the demo cards once per test run, waits for them to reach the
/// Spotlight index, and moves the app to the foreground or background.
actor VaultTestState {
    static let shared = VaultTestState()
    private var seeded = false

    func prepare(appState: AppState) async throws {
        await launchApp()

        if !seeded {
            _ = try await seedDemoCardsIntent.makeIntent().run()
            try await waitForIndex()
            seeded = true
        }

        if appState == .background {
            await MainActor.run { XCUIDevice.shared.press(.home) }
            // Give the system a moment to finish the transition.
            try await Task.sleep(for: .seconds(2))
        }
    }

    @MainActor
    private func launchApp() {
        let app = XCUIApplication(bundleIdentifier: vaultBundleIdentifier)
        if app.state == .notRunning {
            app.launch()
        } else {
            app.activate()
        }
    }

    /// Indexing is asynchronous. Poll until the demo order is findable, so
    /// a scenario never runs against an index that is still filling.
    private func waitForIndex(timeout: Duration = .seconds(90)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let hits = (try? await contextCardEntity.spotlightQuery("Twelve Kingdoms")) ?? []
            if !hits.isEmpty { return }
            try await Task.sleep(for: .seconds(3))
        }
        throw VaultTestError.cardsNeverIndexed
    }
}

enum VaultTestError: Error, CustomStringConvertible {
    case cardsNeverIndexed

    var description: String {
        switch self {
        case .cardsNeverIndexed:
            "The demo cards did not appear in the Spotlight index within the timeout. Check that sharing with Siri is on in the app's Privacy screen."
        }
    }
}
