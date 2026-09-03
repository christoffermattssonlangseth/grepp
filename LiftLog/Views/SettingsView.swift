import SwiftUI

/// GitHub connection settings. The token is stored in the Keychain.
struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    labeled("owner", text: $store.owner, placeholder: "your-username")
                    labeled("repo", text: $store.repo, placeholder: "training")
                    labeled("file path", text: $store.path, placeholder: "training.md")
                    labeled("branch", text: $store.branch, placeholder: "main")
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))

                Section("GitHub token") {
                    SecureField("ghp_… (fine-grained PAT)", text: $store.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: store.token) { _ in store.saveToken() }
                    Text("Create a fine-grained token scoped to just this repo with **Contents: Read and write**.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))

                Section("Coach") {
                    SecureField("sk-ant-… (Claude API key)", text: $store.anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: store.anthropicKey) { _ in store.saveAnthropicKey() }
                    Text("""
                    Stored in the Keychain — never in source or UserDefaults. \
                    Create one in the [Claude Console](https://platform.claude.com/). \
                    Usage bills to your Anthropic account.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if CoachAvailability.current == .needsPackage {
                        Label("This build doesn't link ClaudeForFoundationModels — see README ▸ Coach.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))

                if !store.pending.isEmpty {
                    Section("Waiting to sync") {
                        ForEach(store.pending) { write in
                            HStack {
                                Text(Theme.readableName(write.exerciseName))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(Session.dateFormatter.string(from: write.date))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("^[\(store.pending.count) change](inflect: true) saved offline. Reloading below pushes them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Rectangle().fill(.regularMaterial))
                }

                Section {
                    Button {
                        Task { await store.load() }
                    } label: {
                        if store.isBusy { ProgressView() } else { Text("test connection / reload") }
                    }
                    .disabled(store.isBusy)
                    if !store.status.isEmpty {
                        Text(store.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle("Settings")
        }
    }

    private func labeled(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
        }
    }
}
