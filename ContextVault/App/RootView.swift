import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showingOnboarding = false
    @State private var selectedTab = AppTab.home
    @State private var navigator = AppNavigator.shared
    @Environment(\.scenePhase) private var scenePhase

    enum AppTab: Hashable {
        case home, collections, ask, sources
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Collections", systemImage: "square.stack.3d.up", value: AppTab.collections) {
                CollectionsView()
            }
            Tab("Ask", systemImage: "brain.head.profile", value: AppTab.ask) {
                ChatView()
            }
            Tab("Sources", systemImage: "link", value: AppTab.sources) {
                SourcesView()
            }
        }
        .task {
            if !hasOnboarded { showingOnboarding = true }
            await SyncManager.shared.syncAll()
            SyncManager.shared.scheduleBackgroundSync()
            SyncManager.shared.scheduleBackgroundRefresh()
        }
        // Coming back to the app is the most reliable moment to catch up
        // on mail; the system gives no guarantee about background runs.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SyncManager.shared.refreshIfStale(sources: nil, budget: .seconds(20)) }
            }
        }
        // A search handed over by Siri or Spotlight is shown on Home.
        .onChange(of: navigator.searchQuery) { _, query in
            if query != nil { selectedTab = .home }
        }
        // A card or memory opened from Siri or Spotlight.
        .sheet(item: openCardBinding) { target in
            NavigationStack {
                OpenedCardView(cardID: target.id)
            }
        }
        .sheet(item: openMemoryBinding) { target in
            NavigationStack {
                OpenedMemoryView(memoryID: target.id)
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView()
        }
    }

    private var openCardBinding: Binding<OpenTarget?> {
        Binding(
            get: { navigator.openCardID.map(OpenTarget.init) },
            set: { if $0 == nil { navigator.openCardID = nil } }
        )
    }

    private var openMemoryBinding: Binding<OpenTarget?> {
        Binding(
            get: { navigator.openMemoryID.map(OpenTarget.init) },
            set: { if $0 == nil { navigator.openMemoryID = nil } }
        )
    }
}

/// Identifies what a sheet should show.
private struct OpenTarget: Identifiable, Equatable {
    let id: UUID
}

/// Looks a card up by ID and shows it, or says it is gone.
private struct OpenedCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [ContextCard]

    init(cardID: UUID) {
        _cards = Query(filter: #Predicate<ContextCard> { $0.id == cardID })
    }

    var body: some View {
        Group {
            if let card = cards.first {
                CardDetailView(card: card)
            } else {
                ContentUnavailableView("Card not found", systemImage: "rectangle.stack.badge.minus")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

/// Looks a memory up by ID and shows it, or says it is gone.
private struct OpenedMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var memories: [Memory]

    init(memoryID: UUID) {
        _memories = Query(filter: #Predicate<Memory> { $0.id == memoryID })
    }

    var body: some View {
        Group {
            if let memory = memories.first {
                MemoryDetailView(memory: memory)
            } else {
                ContentUnavailableView("Memory not found", systemImage: "doc.questionmark")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Memory.self, MemoryCollection.self, SourceAccount.self, ContextCard.self], inMemory: true)
}
