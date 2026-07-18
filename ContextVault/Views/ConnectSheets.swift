import SwiftUI
import SwiftData

/// Google Drive connect flow: paste the iOS OAuth Client ID (one-time setup
/// documented in docs/CONNECTORS.md), then sign in with Google via
/// ASWebAuthenticationSession. Tokens land in the Keychain.
struct GoogleDriveConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var clientID = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("xxxx.apps.googleusercontent.com", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } header: {
                    Text("iOS OAuth Client ID")
                } footer: {
                    Text("One-time setup: create a Google Cloud project with the Drive API enabled and an iOS OAuth client, then paste its ID here. Full steps are in docs/CONNECTORS.md. Your files sync directly from Google to this device.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        if working {
                            HStack { ProgressView(); Text("Signing in…") }
                        } else {
                            Label("Sign in with Google", systemImage: "person.badge.key")
                        }
                    }
                    .disabled(working || !clientID.hasSuffix(".apps.googleusercontent.com"))
                }
            }
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        working = true
        errorMessage = nil
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            defer { working = false }
            do {
                let tokens = try await GoogleDriveAuth().signIn(clientID: trimmedID)

                let config = GoogleDriveConfig(clientID: trimmedID)
                let account = SourceAccount(
                    sourceType: .googleDrive,
                    displayName: "Google Drive",
                    configData: try? JSONEncoder().encode(config)
                )
                KeychainStore.save(tokens, for: account.keychainKey)
                context.insert(account)
                try context.save()

                dismiss()
                Task { await SyncManager.shared.syncAll() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Notion connect flow: paste an internal-integration token (created free at
/// notion.so/my-integrations), validated against the API, stored in Keychain.
struct NotionConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var token = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ntn_… or secret_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Internal integration token")
                } footer: {
                    Text("Create a free internal integration at notion.so/my-integrations, copy its secret, and share the pages you want synced with the integration (page ••• menu → Connections). Steps in docs/CONNECTORS.md.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        if working {
                            HStack { ProgressView(); Text("Validating…") }
                        } else {
                            Label("Connect Notion", systemImage: "link")
                        }
                    }
                    .disabled(working || token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Notion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        working = true
        errorMessage = nil
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            defer { working = false }
            do {
                let botName = try await NotionConnector.validate(token: trimmedToken)

                let account = SourceAccount(
                    sourceType: .notion,
                    displayName: "Notion (\(botName))"
                )
                KeychainStore.save(NotionConnector.NotionToken(token: trimmedToken), for: account.keychainKey)
                context.insert(account)
                try context.save()

                dismiss()
                Task { await SyncManager.shared.syncAll() }
            } catch {
                errorMessage = "Couldn't validate that token — check it and make sure pages are shared with the integration."
            }
        }
    }
}
