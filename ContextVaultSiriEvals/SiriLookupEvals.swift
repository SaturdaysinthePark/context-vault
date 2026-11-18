import Testing
import Evaluations
import SiriEvaluations

/// The measurements that decide how Context Vault is built and described.
///
/// Read the numbers, not just pass or fail: Siri's behaviour varies between
/// runs, so run this suite several times and compare the Evaluations
/// report in Xcode (Report navigator > the test run > Evaluations).
///
/// A device runs one scenario at a time, so the suite is serialized.
@Suite(.serialized)
struct SiriLookupEvals {

    /// The primary use case: a general question, the app closed and never
    /// named. Apple's preview notes say background requests need the app's
    /// name, while its `ToolIntent` reference says a tool may be called
    /// when "a relevant entity from that app appears in a search result".
    /// This test is how we find out which holds for indexed cards.
    ///
    /// It passes if Siri found the right card in at least one scenario.
    /// The share of scenarios in which it did is the number to track.
    @Test(.evaluates(VaultEvaluation(
        name: "Unprompted, app in background",
        dataset: Scenarios.unprompted(),
        appState: .background
    )))
    func unpromptedInBackground() async throws {
        let result = EvaluationContext.current.result
        let found = result.aggregateValue(.mean(of: .foundEntitiesAllPass))
        let answered = result.aggregateValue(.mean(of: .siriResponseAllPass))
        #expect(found > 0, "Siri never surfaced a vault card for an unprompted request with the app in the background (share found: \(found), share answered: \(answered)).")
    }

    /// The same questions with the app open. Apple documents that no app
    /// name is needed in the foreground, so this separates "Siri cannot
    /// find our cards" from "Siri will not look in a background app".
    @Test(.evaluates(VaultEvaluation(
        name: "Unprompted, app in foreground",
        dataset: Scenarios.unprompted(),
        appState: .foreground
    )))
    func unpromptedInForeground() async throws {
        let result = EvaluationContext.current.result
        let found = result.aggregateValue(.mean(of: .foundEntitiesAllPass))
        #expect(found > 0, "Siri never surfaced a vault card even with the app in the foreground (share found: \(found)).")
    }

    /// Naming a source ("check my Gmail") in place of the app.
    @Test(.evaluates(VaultEvaluation(
        name: "Source named, app in background",
        dataset: Scenarios.sourceNamed(),
        appState: .background
    )))
    func sourceNamedInBackground() async throws {
        let result = EvaluationContext.current.result
        let found = result.aggregateValue(.mean(of: .foundEntitiesAllPass))
        #expect(found > 0, "Naming a source did not lead Siri to a vault card (share found: \(found)).")
    }

    /// The documented baseline: the app is named, so Siri should call the
    /// lookup tool every time. A failure here is a defect in our intent's
    /// title, description or parameters, not an open question.
    @Test(.evaluates(VaultEvaluation(
        name: "App named, app in background",
        dataset: Scenarios.appNamed(),
        appState: .background
    )))
    func appNamedInBackground() async throws {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
    }
}
