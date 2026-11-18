import Foundation
import AppIntentsTesting
import SiriEvaluations

/// The conversations the evaluations run. Each scenario is one request in
/// its own Siri session, so one result never colours the next.
///
/// What each expectation measures:
/// - `Finds`: Siri surfaced our card, by searching the index or by asking
///   the app. This is the primary measure of the unprompted use case.
/// - `SiriResponse`: the reply contains the fact. Siri's wording varies,
///   so the checks name one thing the reply has to say and nothing more.
/// - `Loads(.preferred)`: whether Siri loaded our skill. Reported, never
///   scored — Siri may answer straight from the index without it.
enum Scenarios {

    /// The weekday the demo "Twelve Kingdoms" order is due, e.g. "Friday".
    /// The app seeds that order a fixed number of days ahead
    /// (`DemoSeed.twelveKingdomsDeliveryOffsetDays`, mirrored here because
    /// a UI-test bundle cannot link the app's code).
    static var deliveryWeekday: String {
        let offsetDays = 3
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offsetDays, to: calendar.startOfDay(for: .now)) ?? .now
        var style = Date.FormatStyle().weekday(.wide)
        style.locale = Locale(identifier: "en_US")
        return date.formatted(style)
    }

    // MARK: Primary use case — the app is never named

    static func unprompted() -> SiriScenarioLoader {
        SiriScenarioLoader {
            SiriScenario {
                UserTurn("When should I expect my Amazon package with Twelve Kingdoms to arrive?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("Twelve Kingdoms"))
                    }
                    SiriResponse(.contains(deliveryWeekday, caseSensitive: false))
                    Loads(.preferred) { lookupSkill }
                }
            }
            SiriScenario {
                UserTurn("When is my Twelve Kingdoms book arriving?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("Twelve Kingdoms"))
                    }
                    SiriResponse(.contains(deliveryWeekday, caseSensitive: false))
                }
            }
            SiriScenario {
                UserTurn("What time is my dentist appointment?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("Dental cleaning"))
                    }
                    SiriResponse(.contains("2:30"))
                }
            }
            SiriScenario {
                UserTurn("When is my electricity bill due, and how much is it?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("Electricity bill"))
                    }
                    SiriResponse(.contains("84.20"))
                }
            }
            SiriScenario {
                UserTurn("When does my flight to Denver leave?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("Flight NW 482"))
                    }
                    SiriResponse(.contains("7:45"))
                }
            }
            SiriScenario {
                UserTurn("Does my lease allow pets?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("lease"))
                    }
                    SiriResponse(.contains("deposit", caseSensitive: false))
                }
            }
        }
    }

    // MARK: A source is named instead of the app

    static func sourceNamed() -> SiriScenarioLoader {
        SiriScenarioLoader {
            SiriScenario {
                UserTurn("Check my Gmail: when does my Twelve Kingdoms order arrive?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("Twelve Kingdoms"))
                    }
                    SiriResponse(.contains(deliveryWeekday, caseSensitive: false))
                }
            }
            SiriScenario {
                UserTurn("What does my lease in Google Drive say about ending it early?") {
                    Finds {
                        contextCardEntity.expect(title: .contains("lease"))
                    }
                    SiriResponse(.contains("notice", caseSensitive: false))
                }
            }
        }
    }

    // MARK: Baseline — the app is named (documented as supported)

    static func appNamed() -> SiriScenarioLoader {
        SiriScenarioLoader {
            SiriScenario {
                UserTurn("In Context Vault, when does my Twelve Kingdoms order arrive?") {
                    Calls {
                        lookUpContextIntent
                            .expect(topic: .contains("Twelve Kingdoms"))
                    }
                    SiriResponse(.contains(deliveryWeekday, caseSensitive: false))
                    Loads(.preferred) { lookupSkill }
                }
            }
            SiriScenario {
                UserTurn("In Context Vault, look up my dentist appointment.") {
                    Calls {
                        lookUpContextIntent
                    }
                    SiriResponse(.contains("2:30"))
                }
            }
        }
    }
}
