import SwiftUI
import SwiftData

/// All memories, newest first, with quick capture.
struct VaultView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Memory.modifiedAt, order: .reverse) private var memories: [Memory]
    @State private var showingCapture = false
    @State private var searchText = ""

    private var filtered: [Memory] {
        guard !searchText.isEmpty else { return memories }
        return memories.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if memories.isEmpty {
                    ContentUnavailableView(
                        "Your vault is empty",
                        systemImage: "archivebox",
                        description: Text("Connect a source or capture your first memory.")
                    )
                } else {
                    List {
                        AboutMeCardSection()
                        Section("Memories") {
                            ForEach(filtered) { memory in
                                NavigationLink(value: memory.id) {
                                    MemoryRow(memory: memory)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search memories")
                }
            }
            .navigationTitle("Vault")
            .navigationDestination(for: UUID.self) { id in
                if let memory = memories.first(where: { $0.id == id }) {
                    MemoryDetailView(memory: memory)
                }
            }
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
}

struct MemoryRow: View {
    let memory: Memory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.title).font(.headline).lineLimit(1)
            Text(memory.summary ?? memory.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Label(memory.sourcePath.map { "\(memory.sourceType.rawValue) · \($0)" } ?? memory.sourceType.rawValue,
                      systemImage: sourceIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if !memory.isSiriVisible {
                    Label("Hidden from Siri", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var sourceIcon: String {
        switch memory.sourceType {
        case .manual, .shareExtension: "square.and.pencil"
        case .obsidian, .files: "folder"
        case .notion: "n.square"
        case .googleDrive: "externaldrive"
        }
    }
}

struct MemoryDetailView: View {
    @Bindable var memory: Memory
    @Query(sort: \MemoryCollection.name) private var allCollections: [MemoryCollection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if memory.sensitivity != .unclassified {
                    HStack {
                        Label(memory.sensitivity.rawValue.capitalized, systemImage: "tag")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        Spacer()
                    }
                }

                if memory.sensitivity == .sensitive {
                    Toggle(isOn: $memory.forceSiriVisible) {
                        Label("Show to Siri anyway", systemImage: "sparkles")
                            .font(.callout)
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: memory.forceSiriVisible) {
                        let snapshot = MemorySnapshot(memory)
                        Task {
                            try? await SpotlightIndexer.shared.reindex(memories: [snapshot])
                        }
                        try? memory.modelContext?.save()
                    }
                }

                if let summary = memory.summary {
                    Text(summary)
                        .font(.callout)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                Text(memory.body)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle(memory.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if allCollections.isEmpty {
                        Text("No collections yet")
                    }
                    ForEach(allCollections) { collection in
                        Button {
                            toggleMembership(collection)
                        } label: {
                            if memory.collections.contains(where: { $0.id == collection.id }) {
                                Label(collection.name, systemImage: "checkmark")
                            } else {
                                Text(collection.name)
                            }
                        }
                    }
                } label: {
                    Label("Collections", systemImage: "square.stack.3d.up")
                }
            }
        }
    }

    private func toggleMembership(_ collection: MemoryCollection) {
        if let index = memory.collections.firstIndex(where: { $0.id == collection.id }) {
            memory.collections.remove(at: index)
        } else {
            memory.collections.append(collection)
        }
        try? memory.modelContext?.save()
        let snapshot = MemorySnapshot(memory)
        Task { try? await SpotlightIndexer.shared.reindex(memories: [snapshot]) }
    }
}

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(8)
                .navigationTitle("Capture Memory")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let content = text
                            Task { @MainActor in
                                let title = String(content.prefix(60))
                                    .components(separatedBy: .newlines).first ?? "Memory"
                                let memory = Memory(title: title, body: content)
                                try? await VaultStore.shared.upsert(memory)
                            }
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
