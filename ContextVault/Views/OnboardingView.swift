import SwiftUI
import SwiftData

/// First-launch flow — the "90 seconds to value" arc: connect a folder (or
/// skip), watch the vault build and the About Me card distill, land in the
/// app with context already working. Entirely on device.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    private enum Step {
        case welcome
        case building(String)
        case done(cardBuilt: Bool)
    }

    @State private var step: Step = .welcome
    @State private var showingFolderPicker = false

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Your AI, with your context")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Connect a notes folder and Context Vault builds a private, on-device memory Siri and Apple Intelligence can draw from. Nothing ever leaves your iPhone.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Connect Obsidian or a Markdown folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Start with an empty vault") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            case .building(let status):
                Spacer()
                ProgressView().controlSize(.large)
                Text("Building your vault")
                    .font(.title2.bold())
                Text(status)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()

            case .done(let cardBuilt):
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text(cardBuilt ? "Your context is ready" : "Vault connected")
                    .font(.title2.bold())
                Text(cardBuilt
                    ? "Your memories are synced and an About Me card has been distilled. Ask your vault anything — or just ask Siri."
                    : "Your memories are synced. The About Me card will distill after the next sync once Apple Intelligence is available.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
                Button {
                    finish()
                } label: {
                    Text("Open my vault").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .interactiveDismissDisabled()
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result else { return }
            connectAndBuild(url)
        }
    }

    private func connectAndBuild(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let account = SourceAccount(
                sourceType: .obsidian,
                displayName: url.lastPathComponent,
                configData: bookmark
            )
            context.insert(account)
            try context.save()
        } catch {
            return
        }

        step = .building("Reading your notes…")
        Task { @MainActor in
            await SyncManager.shared.syncAll()
            step = .building("Distilling your About Me card…")
            var cardBuilt = false
            if #available(iOS 26.0, *) {
                cardBuilt = await ProfileDistiller().distill()
            }
            step = .done(cardBuilt: cardBuilt)
        }
    }

    private func finish() {
        hasOnboarded = true
        dismiss()
    }
}
