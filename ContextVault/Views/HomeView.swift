import SwiftUI
import SwiftData

/// The control plane: what Siri knows (context cards coming up), About Me,
/// vault stats, source status, recent activity, global search — with
/// guided empty states that walk a new user through connect → ask.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Memory.modifiedAt, order: .reverse) private var memories: [Memory]
    @Query(sort: \MemoryCollection.name) private var collections: [MemoryCollection]
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @Query private var cards: [ProfileCard]
    @Query(sort: \ContextCard.asOf, order: .reverse) private var contextCards: [ContextCard]

    @State private var searchText = ""
    @State private var showingCapture = false
    @State private var syncing = false

    /// Cards that are in the system index right now.
    private var indexedCardCount: Int { contextCards.filter { $0.indexedAt != nil }.count }

    /// The next few things happening, soonest first — what a person is
    /// most likely to ask Siri about.
    private var upcomingCards: [ContextCard] {
        contextCards
            .filter { !$0.isArchived }
            .sorted { CardSorting.isBefore($0, $1) }
            .prefix(5)
            .map(\.self)
    }

    private var cardSearchResults: [ContextCard] {
        guard !searchText.isEmpty else { return [] }
        return contextCards.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.statement.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var searchResults: [Memory] {
        guard !searchText.isEmpty else { return [] }
        return memories.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    dashboard
                } else {
                    if !cardSearchResults.isEmpty {
                        Section("Cards") {
                            ForEach(cardSearchResults.prefix(20)) { card in
                                NavigationLink {
                                    CardDetailView(card: card)
                                } label: {
                                    CardRow(card: card)
                                }
                            }
                        }
                    }
                    Section("Memories") {
                        if searchResults.isEmpty {
                            Text("No memories match.").foregroundStyle(.secondary)
                        }
                        ForEach(searchResults.prefix(50)) { memory in
                            NavigationLink {
                                MemoryDetailView(memory: memory)
                            } label: {
                                MemoryRow(memory: memory)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search your vault")
            .navigationTitle("Context Vault")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Capture", systemImage: "plus") { showingCapture = true }
                }
            }
            .sheet(isPresented: $showingCapture) {
                CaptureSheet()
            }
            .refreshable {
                await SyncManager.shared.syncAll()
            }
            // "Search Context Vault for …" from Siri or Spotlight lands here.
            .onChange(of: AppNavigator.shared.searchQuery, initial: true) { _, query in
                if let query {
                    searchText = query
                    AppNavigator.shared.searchQuery = nil
                }
            }
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        // What Siri knows: the cards coming up next.
        if !contextCards.isEmpty {
            Section {
                ForEach(upcomingCards) { card in
                    NavigationLink {
                        CardDetailView(card: card)
                    } label: {
                        CardRow(card: card)
                    }
                }
                NavigationLink {
                    CardListView()
                } label: {
                    Label("All cards", systemImage: "rectangle.stack")
                }
            } header: {
                Text("What Siri knows")
            } footer: {
                Text("Cards are short facts distilled from your sources. Ask Siri about any of them without naming this app.")
            }
        }

        AboutMeCardSection()

        // Stats
        Section {
            HStack(spacing: 0) {
                stat(count: contextCards.count, label: "Cards", icon: "rectangle.stack")
                Divider()
                stat(count: indexedCardCount, label: "Siri can see", icon: "sparkles")
                Divider()
                stat(count: memories.count, label: "Memories", icon: "archivebox")
            }
            .frame(maxWidth: .infinity)
        }

        // Guided next step
        if accounts.isEmpty && memories.isEmpty {
            Section {
                NavigationLink {
                    SourcesView()
                } label: {
                    Label("Connect your first source", systemImage: "link.badge.plus")
                        .font(.headline)
                }
            } footer: {
                Text("Connect Gmail, Google Drive, Notion or Obsidian and your vault builds itself on this device.")
            }
        } else if collections.isEmpty && !memories.isEmpty {
            Section {
                NavigationLink {
                    CollectionsView()
                } label: {
                    Label("Create your first collection", systemImage: "square.stack.3d.up.badge.a")
                }
            } footer: {
                Text("Collections group memories by topic and control exactly what Siri can see — they can even subscribe to whole folders.")
            }
        }

        // Sources status
        if !accounts.isEmpty {
            Section("Sources") {
                ForEach(accounts) { account in
                    NavigationLink {
                        SourceDetailView(account: account)
                    } label: {
                        HStack {
                            Text(account.displayName)
                            Spacer()
                            Text(account.lastSyncedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "never synced")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    syncing = true
                    Task {
                        await SyncManager.shared.syncAll()
                        syncing = false
                    }
                } label: {
                    if syncing {
                        HStack { ProgressView(); Text("Syncing…") }
                    } else {
                        Label("Sync all now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncing)
            }
        }

        // Recent
        if !memories.isEmpty {
            Section("Recent") {
                ForEach(memories.prefix(5)) { memory in
                    NavigationLink {
                        MemoryDetailView(memory: memory)
                    } label: {
                        MemoryRow(memory: memory)
                    }
                }
            }
        }
    }

    private func stat(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text("\(count)").font(.title2.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
