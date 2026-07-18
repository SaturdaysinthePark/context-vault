import SwiftUI

/// Browsable Google Drive folder tree with subtree selection.
///
/// Checking a folder means "this whole subtree": descendants render as
/// implicitly checked and the stored selection keeps only the top-most
/// checked IDs. Used for sync scoping (Sources) and folder rules
/// (Collections) — same view, different confirm handler.
struct DriveFolderPickerView: View {
    let title: String
    /// Loads the folder inventory (caller supplies tokens/config context).
    let loader: () async throws -> DriveFolderService
    /// Called with the top-most selected folder IDs and their display paths.
    let onConfirm: ([(id: String, path: String)]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var service: DriveFolderService?
    @State private var selected: Set<String> = []
    @State private var loadError: String?

    init(
        title: String,
        initialSelection: [String] = [],
        loader: @escaping () async throws -> DriveFolderService,
        onConfirm: @escaping ([(id: String, path: String)]) -> Void
    ) {
        self.title = title
        self.loader = loader
        self.onConfirm = onConfirm
        _selected = State(initialValue: Set(initialSelection))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let service {
                    List {
                        OutlineGroup(
                            FolderTreeNode.roots(of: service),
                            children: \.children
                        ) { node in
                            row(for: node)
                        }
                    }
                } else if let loadError {
                    ContentUnavailableView("Couldn't load folders", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView("Loading your Drive folders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        confirm()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task {
                do {
                    service = try await loader()
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    private func row(for node: FolderTreeNode) -> some View {
        let isChecked = selected.contains(node.id)
        let isImplied = !isChecked && isDescendantOfSelection(node)
        return Button {
            toggle(node)
        } label: {
            HStack {
                Label(node.name, systemImage: "folder")
                    .foregroundStyle(.primary)
                Spacer()
                if isChecked {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                } else if isImplied {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Included via parent folder")
                } else {
                    Image(systemName: "circle").foregroundStyle(.quaternary)
                }
            }
        }
        .disabled(isImplied)
    }

    private func isDescendantOfSelection(_ node: FolderTreeNode) -> Bool {
        guard var current = node.parentID, let service else { return false }
        var depth = 0
        while depth < 50 {
            if selected.contains(current) { return true }
            guard let next = service.nodes[current]?.parent else { return false }
            current = next
            depth += 1
        }
        return false
    }

    private func toggle(_ node: FolderTreeNode) {
        if selected.contains(node.id) {
            selected.remove(node.id)
        } else {
            selected.insert(node.id)
            // Keep the stored selection minimal: drop any already-selected
            // descendants of the newly selected folder.
            if let service {
                let descendants = service.descendantClosure(of: [node.id]).subtracting([node.id])
                selected.subtract(descendants)
            }
        }
    }

    private func confirm() {
        guard var service else { return }
        let result = selected.compactMap { id -> (id: String, path: String)? in
            guard let paths = service.paths(for: id) else { return nil }
            return (id: id, path: paths.path)
        }
        onConfirm(result)
        dismiss()
    }
}

/// Value-type tree wrapper so OutlineGroup can walk the folder map.
struct FolderTreeNode: Identifiable {
    var id: String
    var name: String
    var parentID: String?
    var childNodes: [FolderTreeNode]

    /// OutlineGroup wants nil (not []) for leaves.
    var children: [FolderTreeNode]? { childNodes.isEmpty ? nil : childNodes }

    static func roots(of service: DriveFolderService) -> [FolderTreeNode] {
        service.rootFolders().map { build(from: $0, service: service, depth: 0) }
    }

    private static func build(from node: DriveFolderService.Node, service: DriveFolderService, depth: Int) -> FolderTreeNode {
        let children = depth < 20
            ? service.childFolders(of: node.id).map { build(from: $0, service: service, depth: depth + 1) }
            : []
        return FolderTreeNode(id: node.id, name: node.name, parentID: node.parent, childNodes: children)
    }
}
