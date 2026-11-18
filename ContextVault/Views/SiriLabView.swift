import SwiftUI
import SwiftData

/// A test bench for the one thing this app exists to do: Siri answering a
/// general question from the vault without the app being named.
///
/// It seeds fictional cards, shows whether they reached the system index,
/// lets you switch between the two ways of indexing them, and lists the
/// questions to try. See docs/SIRI_TESTING.md for the full procedure.
struct SiriLabView: View {
    @Query private var cards: [ContextCard]
    @AppStorage(SiriExposure.enabledKey) private var siriExposureEnabled = true
    @AppStorage(CardIndexingPath.defaultsKey) private var indexingPathRaw = CardIndexingPath.entities.rawValue

    @State private var working = false
    @State private var message: String?
    @State private var indexHits: Int?

    private var demoCards: [ContextCard] { cards.filter(\.isDemo) }
    private var indexedCards: [ContextCard] { cards.filter { $0.indexedAt != nil } }

    var body: some View {
        List {
            Section {
                LabeledContent("Sharing with Siri", value: siriExposureEnabled ? "On" : "Off")
                LabeledContent("Cards in the vault", value: "\(cards.count)")
                LabeledContent("Cards in the system index", value: "\(indexedCards.count)")
                LabeledContent("Demo cards", value: "\(demoCards.count)")
            } header: {
                Text("Status")
            } footer: {
                if !siriExposureEnabled {
                    Text("Sharing with Siri is off in Privacy, so nothing is indexed and Siri cannot find any card.")
                }
            }

            Section {
                Button {
                    run("Seeded demo cards.") { _ = try await DemoSeed.seed() }
                } label: {
                    Label("Seed demo cards", systemImage: "wand.and.stars")
                }
                Button(role: .destructive) {
                    run("Removed demo cards.") { _ = try await DemoSeed.remove() }
                } label: {
                    Label("Remove demo cards", systemImage: "trash")
                }
                .disabled(demoCards.isEmpty)
            } header: {
                Text("Demo data")
            } footer: {
                Text("Demo cards are fictional. If Siri answers a test question correctly, the answer can only have come from this vault.")
            }

            Section {
                Picker("Indexing method", selection: $indexingPathRaw) {
                    ForEach(CardIndexingPath.allCases, id: \.rawValue) { path in
                        Text(path.displayName).tag(path.rawValue)
                    }
                }
                .onChange(of: indexingPathRaw) {
                    run("Rebuilt the index with the new method.") {
                        try await VaultStore.shared.reindexAllCards()
                    }
                }
                Button {
                    run("Rebuilt the index.") { try await VaultStore.shared.reindexAllCards() }
                } label: {
                    Label("Rebuild card index", systemImage: "arrow.clockwise")
                }
                Button {
                    working = true
                    Task {
                        indexHits = await SpotlightIndexer.shared.matchCount("Twelve Kingdoms")
                        working = false
                    }
                } label: {
                    Label("Check the index for “Twelve Kingdoms”", systemImage: "magnifyingglass")
                }
                if let indexHits {
                    LabeledContent("Matching index entries", value: "\(indexHits)")
                }
            } header: {
                Text("Index")
            } footer: {
                Text("Apple documents two ways to index an entity and does not say which Siri finds more reliably. Run the test questions under each method and compare.")
            }

            ForEach(SiriLabPhrases.groups) { group in
                Section {
                    ForEach(group.phrases, id: \.self) { phrase in
                        Text("“\(phrase)”")
                            .textSelection(.enabled)
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    Text(group.note)
                }
            }
        }
        .navigationTitle("Siri Lab")
        .overlay(alignment: .bottom) {
            if working {
                ProgressView().padding().background(.regularMaterial, in: Capsule()).padding()
            } else if let message {
                Text(message)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private func run(_ success: String, _ work: @escaping @MainActor () async throws -> Void) {
        working = true
        message = nil
        Task { @MainActor in
            do {
                try await work()
                message = success
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
            indexHits = nil
            working = false
        }
    }
}

/// The questions to ask Siri, grouped by what each group proves.
enum SiriLabPhrases {
    struct Group: Identifiable {
        var id: String { title }
        var title: String
        var note: String
        var phrases: [String]
    }

    static let groups: [Group] = [
        Group(
            title: "Without naming the app",
            note: "The primary test. Ask with Context Vault closed. A correct answer means Siri found the card on its own.",
            phrases: [
                "When should I expect my Amazon package with Twelve Kingdoms to arrive?",
                "When is my Twelve Kingdoms book arriving?",
                "What time is my dentist appointment?",
                "When is my electricity bill due, and how much is it?",
                "When does my flight to Denver leave?",
                "Does my lease allow pets?"
            ]
        ),
        Group(
            title: "Naming a source",
            note: "Tests whether a source is mentionable in place of the app.",
            phrases: [
                "Check my Gmail: when does my Twelve Kingdoms order arrive?",
                "What does my lease in Google Drive say about ending it early?"
            ]
        ),
        Group(
            title: "Naming the app",
            note: "The baseline Apple documents as supported while the app is in the background.",
            phrases: [
                "In Context Vault, when does my Twelve Kingdoms order arrive?",
                "Ask Context Vault what's coming up this week."
            ]
        ),
        Group(
            title: "Privacy check",
            note: "This card is marked sensitive and must not be indexed. Siri should not know the answer.",
            phrases: [
                "What's the Wi-Fi password for the cabin?"
            ]
        )
    ]
}

#Preview {
    NavigationStack { SiriLabView() }
        .modelContainer(for: [ContextCard.self], inMemory: true)
}
