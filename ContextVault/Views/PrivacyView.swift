import SwiftUI
import SwiftData

/// The privacy dashboard: one screen showing exactly what the system AI can
/// see, with every control in one place. The on-device answer to Unabyss's
/// per-app permission model — "Your data. Your rules."
struct PrivacyView: View {
    @AppStorage("siriExposureEnabled") private var siriExposureEnabled = true
    @Query private var memories: [Memory]
    @Query(sort: \MemoryCollection.name) private var collections: [MemoryCollection]
    @Query private var cards: [ProfileCard]

    private var visibleMemories: [Memory] { memories.filter(\.isSiriVisible) }
    private var sensitiveHidden: Int {
        memories.filter { $0.sensitivity == .sensitive && !$0.forceSiriVisible }.count
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $siriExposureEnabled) {
                    Label("Share vault with Siri & Apple Intelligence", systemImage: "sparkles")
                }
                .onChange(of: siriExposureEnabled) {
                    applyMasterSwitch()
                }
            } footer: {
                Text(siriExposureEnabled
                    ? "Siri can use the memories below as context. Turn off to remove everything from the system index instantly."
                    : "Nothing from your vault is in the system index. Siri and Spotlight cannot see any of it.")
            }

            if siriExposureEnabled {
                Section("What Siri can see") {
                    LabeledContent("Memories in system index", value: "\(visibleMemories.count)")
                    LabeledContent("Hidden by collection settings",
                                   value: "\(memories.count - visibleMemories.count - sensitiveHidden)")
                    LabeledContent("Auto-hidden as sensitive", value: "\(sensitiveHidden)")
                    if let card = cards.first {
                        LabeledContent("About Me card",
                                       value: card.siriVisible && !card.content.isEmpty ? "Indexed" : "Hidden")
                    }
                }

                Section("Per-collection controls") {
                    if collections.isEmpty {
                        Text("No collections yet.").foregroundStyle(.secondary)
                    }
                    ForEach(collections) { collection in
                        Toggle(isOn: Bindable(collection).siriVisible) {
                            VStack(alignment: .leading) {
                                Text(collection.name)
                                Text("\(collection.memories.count) memories")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: collection.siriVisible) {
                            Task { @MainActor in
                                try? await VaultStore.shared.reindexCollection(collection)
                            }
                        }
                    }
                }

                Section("Indexed memories") {
                    ForEach(visibleMemories.prefix(50)) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(memory.title).lineLimit(1)
                                Text(memory.sensitivity == .unclassified
                                     ? memory.sourceType.rawValue
                                     : "\(memory.sourceType.rawValue) · \(memory.sensitivity.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if visibleMemories.count > 50 {
                        Text("…and \(visibleMemories.count - 50) more")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Privacy")
    }

    private func applyMasterSwitch() {
        let enabled = siriExposureEnabled
        Task { @MainActor in
            if enabled {
                let snapshots = memories.map(MemorySnapshot.init)
                try? await SpotlightIndexer.shared.reindex(memories: snapshots)
                try? await VaultStore.shared.reindexAboutMeCard()
            } else {
                try? await SpotlightIndexer.shared.deleteAll()
            }
        }
    }
}
