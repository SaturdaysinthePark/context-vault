import SwiftUI
import SwiftData
import AppIntents

/// One context card in a list: what it is, the fact, and how fresh it is.
struct CardRow: View {
    let card: ContextCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.kind.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.headline)
                    .lineLimit(2)

                if let date = card.primaryDate {
                    Text(CardRenderer.format(date, hasTime: card.primaryDateHasTime))
                        .font(.subheadline)
                }

                HStack(spacing: 6) {
                    if let status = card.status {
                        Text(status)
                    }
                    Text(card.sourceType.displayName)
                    Text("updated \(card.asOf.formatted(.relative(presentation: .named)))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if card.indexedAt == nil {
                // Not in the system index: hidden, archived or sensitive.
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hidden from Siri")
            }
        }
        // Tells Apple Intelligence which card this row shows, so "this
        // one" in a request resolves to it while the list is onscreen.
        .appEntityIdentifier(EntityIdentifier(for: ContextCardEntity.self, identifier: card.id))
    }
}

/// Everything about one card: the statement Siri reads, the supporting
/// facts, where it came from, and whether Siri may see it.
struct CardDetailView: View {
    @Bindable var card: ContextCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var memories: [Memory]

    private var evidence: [Memory] {
        memories.filter { card.evidenceIDs.contains($0.id) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var hiddenReason: String? {
        if !SiriExposure.isEnabled { return "Sharing with Siri is turned off in Privacy." }
        if card.isArchived { return "This card is archived because its date has passed." }
        if SiriExposure.hiddenKinds.contains(card.kind) { return "\(card.kind.pluralName) are hidden from Siri in Privacy." }
        if SiriExposure.hiddenSources.contains(card.sourceType) { return "\(card.sourceType.displayName) is hidden from Siri in Privacy." }
        if card.sensitivity == .sensitive && !card.forceSiriVisible { return "This card is marked sensitive." }
        if evidence.contains(where: { !$0.allowsSiriExposure }) { return "Its source is in a collection hidden from Siri, or is marked sensitive." }
        return nil
    }

    var body: some View {
        List {
            Section {
                Text(card.statement)
            } header: {
                Text("What Siri is told")
            } footer: {
                if let hiddenReason {
                    Label(hiddenReason, systemImage: "eye.slash")
                } else {
                    Label("In the system index. Siri can use it to answer questions.", systemImage: "sparkles")
                }
            }

            if !card.detail.isEmpty {
                Section("Details") {
                    ForEach(card.detail.components(separatedBy: "\n"), id: \.self) { line in
                        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count == 2 {
                            LabeledContent(parts[0], value: parts[1])
                        } else {
                            Text(line)
                        }
                    }
                }
            }

            Section {
                if card.sensitivity == .sensitive {
                    Toggle("Share with Siri anyway", isOn: $card.forceSiriVisible)
                } else {
                    Toggle("Mark as sensitive", isOn: Binding(
                        get: { card.sensitivity == .sensitive },
                        set: { card.sensitivity = $0 ? .sensitive : .personal }
                    ))
                }
                Toggle("Archived", isOn: $card.isArchived)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Sensitive and archived cards stay in your vault but are removed from the system index.")
            }

            if !evidence.isEmpty {
                Section {
                    ForEach(evidence) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryRow(memory: memory)
                        }
                    }
                } header: {
                    Text("Based on")
                } footer: {
                    Text("The original messages and documents stay on this device. Siri is given the card, not these.")
                }
            }

            if card.isDemo {
                Section {
                    Label("Fictional demo card from the Siri Lab.", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Delete Card", role: .destructive) {
                    Task { @MainActor in
                        try? await VaultStore.shared.delete(cards: [card])
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(card.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .appEntityIdentifier(EntityIdentifier(for: ContextCardEntity.self, identifier: card.id))
        .onChange(of: card.forceSiriVisible) { reindex() }
        .onChange(of: card.sensitivityRaw) { reindex() }
        .onChange(of: card.isArchived) { reindex() }
        .task {
            // Tell the system this card was opened, so it can learn which
            // cards matter and suggest them.
            if let snapshot = try? VaultStore.shared.siriVisibleCards(ids: [card.id]).first {
                let intent = OpenCardIntent()
                intent.target = ContextCardEntity(snapshot)
                try? await IntentDonationManager.shared.donate(intent: intent)
            }
        }
    }

    private func reindex() {
        Task { @MainActor in
            try? context.save()
            try? await VaultStore.shared.reindex(cards: [card])
        }
    }
}

/// All cards, grouped by kind, soonest first.
struct CardListView: View {
    @Query(sort: \ContextCard.asOf, order: .reverse) private var cards: [ContextCard]
    @State private var searchText = ""
    @State private var showArchived = false

    private var visibleCards: [ContextCard] {
        cards.filter { card in
            (showArchived || !card.isArchived)
                && (searchText.isEmpty
                    || card.title.localizedCaseInsensitiveContains(searchText)
                    || card.statement.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var groups: [(kind: CardKind, cards: [ContextCard])] {
        CardKind.allCases.compactMap { kind in
            let matching = visibleCards
                .filter { $0.kind == kind }
                .sorted { CardSorting.isBefore($0, $1) }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No cards yet",
                    systemImage: "rectangle.stack",
                    description: Text("Connect Gmail and the vault turns your orders, bookings and bills into cards Siri can answer from.")
                )
            }
            ForEach(groups, id: \.kind) { group in
                Section(group.kind.pluralName) {
                    ForEach(group.cards) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            CardRow(card: card)
                        }
                    }
                }
            }
            if cards.contains(where: \.isArchived) {
                Section {
                    Toggle("Show archived", isOn: $showArchived)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search cards")
        .navigationTitle("Cards")
    }
}

/// Orders cards the way people think about them: what is coming up next
/// first, then undated cards by freshness, then what has already passed.
enum CardSorting {
    static func isBefore(_ a: ContextCard, _ b: ContextCard, now: Date = .now) -> Bool {
        rank(a, now) < rank(b, now)
    }

    private static func rank(_ card: ContextCard, _ now: Date) -> Double {
        guard let date = card.primaryDate else {
            // Undated: after upcoming, newest first.
            return 1e10 - card.asOf.timeIntervalSince1970 / 1e3
        }
        let delta = date.timeIntervalSince(now)
        // Upcoming sorts by how soon; past sorts after everything else.
        return delta >= -86_400 ? delta : 2e10 - delta
    }
}
