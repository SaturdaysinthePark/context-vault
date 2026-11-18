import Foundation
import Observation

/// Where the app should go when something outside it asks: Siri or
/// Spotlight opening a card or a memory, or an in-app search request.
/// App Intents set these; `RootView` observes them and presents the
/// matching screen.
@MainActor @Observable
final class AppNavigator {
    static let shared = AppNavigator()

    /// A context card to show.
    var openCardID: UUID?
    /// A memory (document or note) to show.
    var openMemoryID: UUID?
    /// A search to run on the cards screen.
    var searchQuery: String?

    private init() {}

    func open(cardID: UUID) {
        openMemoryID = nil
        openCardID = cardID
    }

    func open(memoryID: UUID) {
        openCardID = nil
        openMemoryID = memoryID
    }

    func search(_ query: String) {
        openCardID = nil
        openMemoryID = nil
        searchQuery = query
    }
}
