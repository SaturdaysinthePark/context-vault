import SwiftUI
import SwiftData

/// The privacy dashboard: one screen showing exactly what the system AI
/// can see, with every control in one place.
///
/// What reaches Siri is deliberately narrow: the context cards distilled
/// from your sources, and the text of documents and notes. Email itself
/// is never shared — only the cards made from it. Each control here
/// removes things from that set; nothing here adds to it.
struct PrivacyView: View {
    @AppStorage(SiriExposure.enabledKey) private var siriExposureEnabled = true
    @Query private var memories: [Memory]
    @Query private var contextCards: [ContextCard]
    @Query(sort: \MemoryCollection.name) private var collections: [MemoryCollection]
    @Query private var cards: [ProfileCard]

    @State private var hiddenSources = SiriExposure.hiddenSources
    @State private var hiddenKinds = SiriExposure.hiddenKinds

    private var indexedCards: [ContextCard] { contextCards.filter { $0.indexedAt != nil } }
    private var visibleMemories: [Memory] {
        memories.filter { $0.isSiriVisible && !hiddenSources.contains($0.sourceType) }
    }
    private var mailCount: Int { memories.filter { $0.sourceType == .gmail }.count }
    private var sensitiveHidden: Int {
        memories.filter { $0.sensitivity == .sensitive && !$0.forceSiriVisible }.count
    }

    /// Sources and kinds that actually have content, so the lists stay short.
    private var presentSources: [SourceType] {
        let present = Set(memories.map(\.sourceType)).union(contextCards.map(\.sourceType))
        return SourceType.allCases.filter { present.contains($0) }
    }
    private var presentKinds: [CardKind] {
        let present = Set(contextCards.map(\.kind))
        return CardKind.allCases.filter { present.contains($0) }
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
                    ? "Siri can use the cards and documents below as context. Turn off to remove everything from the system index instantly."
                    : "Nothing from your vault is in the system index. Siri and Spotlight cannot see any of it.")
            }

            if siriExposureEnabled {
                Section {
                    LabeledContent("Context cards", value: "\(indexedCards.count) of \(contextCards.count)")
                    LabeledContent("Documents and notes", value: "\(visibleMemories.count)")
                    if mailCount > 0 {
                        LabeledContent("Email messages", value: "0 of \(mailCount)")
                    }
                    LabeledContent("Auto-hidden as sensitive", value: "\(sensitiveHidden)")
                    if let card = cards.first {
                        LabeledContent("About Me card",
                                       value: card.siriVisible && !card.content.isEmpty ? "Shared" : "Hidden")
                    }
                } header: {
                    Text("What Siri can see")
                } footer: {
                    Text("Email is never shared with Siri. Only the cards distilled from it are, and anything classified as sensitive is held back. Content you share with Siri is handled by Apple Intelligence under Apple's terms.")
                }

                if !presentSources.isEmpty {
                    Section {
                        ForEach(presentSources, id: \.self) { source in
                            Toggle(isOn: sourceBinding(source)) {
                                Label(source.displayName, systemImage: icon(for: source))
                            }
                        }
                    } header: {
                        Text("By source")
                    } footer: {
                        Text("Turn a source off and nothing from it is shared with Siri, while it keeps syncing into your vault.")
                    }
                }

                if !presentKinds.isEmpty {
                    Section {
                        ForEach(presentKinds, id: \.self) { kind in
                            Toggle(isOn: kindBinding(kind)) {
                                Label(kind.pluralName, systemImage: kind.systemImage)
                            }
                        }
                    } header: {
                        Text("By kind of card")
                    }
                }

                Section("By collection") {
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

                Section("Shared cards") {
                    if indexedCards.isEmpty {
                        Text("No cards are shared yet.").foregroundStyle(.secondary)
                    }
                    ForEach(indexedCards.prefix(50)) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            CardRow(card: card)
                        }
                    }
                    if indexedCards.count > 50 {
                        Text("…and \(indexedCards.count - 50) more").foregroundStyle(.secondary)
                    }
                }

                Section("Shared documents and notes") {
                    ForEach(visibleMemories.prefix(50)) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(memory.title).lineLimit(1)
                                Text(memory.sensitivity == .unclassified
                                     ? memory.sourceType.displayName
                                     : "\(memory.sourceType.displayName) · \(memory.sensitivity.rawValue)")
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

            Section {
                NavigationLink {
                    SiriLabView()
                } label: {
                    Label("Siri Lab", systemImage: "testtube.2")
                }
            } footer: {
                Text("Test what Siri can find, with fictional data.")
            }
        }
        .navigationTitle("Privacy")
    }

    // MARK: Controls

    private func sourceBinding(_ source: SourceType) -> Binding<Bool> {
        Binding(
            get: { !hiddenSources.contains(source) },
            set: { shared in
                if shared { hiddenSources.remove(source) } else { hiddenSources.insert(source) }
                SiriExposure.hiddenSources = hiddenSources
                reindexEverything()
            }
        )
    }

    private func kindBinding(_ kind: CardKind) -> Binding<Bool> {
        Binding(
            get: { !hiddenKinds.contains(kind) },
            set: { shared in
                if shared { hiddenKinds.remove(kind) } else { hiddenKinds.insert(kind) }
                SiriExposure.hiddenKinds = hiddenKinds
                reindexEverything()
            }
        )
    }

    /// Rebuilds the index to match the current settings. Reindexing a
    /// hidden item removes it, so this both adds and removes.
    private func reindexEverything() {
        let snapshots = memories.map(MemorySnapshot.init)
        Task { @MainActor in
            try? await SpotlightIndexer.shared.reindex(memories: snapshots)
            try? await VaultStore.shared.reindexAllCards()
            try? await VaultStore.shared.reindexSources()
        }
    }

    private func applyMasterSwitch() {
        let enabled = siriExposureEnabled
        let snapshots = memories.map(MemorySnapshot.init)
        Task { @MainActor in
            if enabled {
                try? await SpotlightIndexer.shared.reindex(memories: snapshots)
                try? await VaultStore.shared.reindexAboutMeCard()
                try? await VaultStore.shared.reindexAllCards()
                try? await VaultStore.shared.reindexSources()
            } else {
                try? await SpotlightIndexer.shared.deleteAll()
                // Record that nothing is indexed any more.
                try? await VaultStore.shared.reindexAllCards()
            }
        }
    }
}
