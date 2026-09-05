import SwiftUI

/// GitHub connection settings. The token is stored in the Keychain.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("coach_show_cost") private var showCost = true
    @AppStorage("bar_weight") private var barWeight: Double = 20
    @AppStorage("plate_inventory") private var inventory = PlateInventory.standard

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
                        .onChange(of: store.token) { _, _ in store.saveToken() }
                    Text("Create a fine-grained token scoped to just this repo with **Contents: Read and write**.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))

                Section("Gym") {
                    Picker("bar weight", selection: $barWeight) {
                        ForEach(PlateMath.bars, id: \.self) { kg in
                            Text("\(PlateMath.label(kg)) kg").tag(kg)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Your default bar. An exercise on a different one — seal rows on the 10 — is set from the plate line in Session, and remembered for that exercise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(PlateMath.sizes, id: \.self) { size in
                        Stepper(value: plateCount(size), in: 0...20) {
                            HStack {
                                Text("\(PlateMath.label(size)) kg")
                                    .monospacedDigit()
                                Spacer()
                                Text("× \(inventory.counts[size] ?? 0)")
                                    .monospacedDigit()
                                    .foregroundStyle((inventory.counts[size] ?? 0) == 0 ? .tertiary : .secondary)
                            }
                        }
                    }
                    Text("The plates you own, both sides together — four 25s is two a side. The calculator never suggests a plate you don't have.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))

                Section("Coach") {
                    SecureField("sk-ant-… (Claude API key)", text: $store.anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: store.anthropicKey) { _, _ in store.saveAnthropicKey() }
                    Text("""
                    Stored in the Keychain — never in source or UserDefaults. \
                    Create one in the [Claude Console](https://platform.claude.com/). \
                    Usage bills to your Anthropic account.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    labeled("coaching file", text: $store.coachingPath, placeholder: "coaching.md")
                    labeled("goals file", text: $store.goalsPath, placeholder: "goals.md")
                    Text(coachingHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        store.requestBrief()
                    } label: {
                        Label("Your brief — goals & how you train", systemImage: "person.text.rectangle")
                    }

                    labeled("workspace id", text: $store.anthropicWorkspace, placeholder: "wrkspc_… (optional)")

                    Toggle("Show cost under each answer", isOn: $showCost)
                    Text("""
                    Only needed if the key isn't scoped to a single workspace. \
                    Find it in the **ID** column of Settings ▸ Workspaces in the Console — \
                    or leave this blank and create a workspace-scoped key instead.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Section {
                    VStack(spacing: 8) {
                        Barbell(height: 26)
                        Text("LiftLog")
                            .font(.caption.weight(.heavy))
                            .tracking(3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle("Settings")
        }
    }

    /// Whether the coaching notes were found, and what to do about it.
    private var coachingHint: LocalizedStringKey {
        let found = [store.brief.coaching.isEmpty ? nil : store.coachingPath,
                     store.brief.goals.isEmpty ? nil : store.goalsPath].compactMap { $0 }
        if found.isEmpty {
            return "Neither file found. Commit them beside your log — **\(store.coachingPath)** for how you like to train and what to work around, **\(store.goalsPath)** for what you're aiming at — and they become the coach's standing brief."
        }
        return "Loaded \(found.joined(separator: " and ")). Edit them in your repo, then reload below."
    }

    /// A binding into one plate size's count. Writing replaces the whole inventory
    /// value, which is what makes AppStorage persist it.
    private func plateCount(_ size: Double) -> Binding<Int> {
        Binding(
            get: { inventory.counts[size] ?? 0 },
            set: { inventory.counts[size] = $0 }
        )
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
