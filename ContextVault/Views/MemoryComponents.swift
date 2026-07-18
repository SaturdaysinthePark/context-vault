import SwiftUI
import SwiftData

// Shared memory components (MemoryRow, MemoryDetailView, CaptureSheet).
// The old Vault stream tab was absorbed into HomeView (dashboard + global
// search) and SourceDetailView (per-source browsing).

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
            // User removal: live rules must never re-add this memory.
            collection.excludedMemoryIDs.insert(memory.id)
        } else {
            memory.collections.append(collection)
            collection.excludedMemoryIDs.remove(memory.id)
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
