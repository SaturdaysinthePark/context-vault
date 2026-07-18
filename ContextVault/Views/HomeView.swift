import SwiftUI
import SwiftData

/// The control plane: About Me, vault stats, source status, recent activity,
/// global search — with guided empty states that walk a new user through
/// connect → collect → ask.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Memory.modifiedAt, order: .reverse) private var memories: [Memory]
    @Query(sort: \MemoryCollection.name) private var collections: [MemoryCollection]
    @Query(sort: \SourceAccount.createdAt) private var accounts: [SourceAccount]
    @Query private var cards: [ProfileCard]

    @State private var searchText = ""
    @State private var showingCapture = false
    @State private var syncing = false

    private var siriVisibleCount: Int { memories.filter(\.isSiriVisible).count }

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
                    Section("Results") {
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
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        AboutMeCardSection()

        // Stats
        Section {
            HStack(spacing: 0) {
                stat(count: memories.count, label: "Memories", icon: "archivebox")
                Divider()
                stat(count: siriVisibleCount, label: "Siri can see", icon: "sparkles")
                Divider()
                stat(count: collections.count, label: "Collections", icon: "square.stack.3d.up")
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
                Text("Connect Obsidian, Google Drive, or Notion and your vault builds itself — entirely on this device.")
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
