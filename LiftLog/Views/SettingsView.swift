import SwiftUI

/// GitHub connection settings. The token is stored in the Keychain.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("coach_show_cost") private var showCost = true
    @AppStorage("bar_weight") private var barWeight: Double = 20
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()
    @StateObject private var strava = StravaService.shared
    @State private var stravaError: String?
    @State private var stravaID = ""
    @State private var stravaSecret = ""
    @State private var backfillStatus: String?
    @State private var backfilling = false
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

                Section("Muscles") {
                    let unmapped = muscleMap.unmapped(in: store.sessions)
                    let assigned = store.knownExercises.filter { muscleMap.isOverridden($0) }
                    if unmapped.isEmpty && assigned.isEmpty {
                        Text("Every lift in your log is counted. A new one the app doesn't know will show up here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(unmapped + assigned, id: \.self) { name in
                        muscleRow(name)
                    }
                    Text("Sets per muscle in Trends and for the coach. A lift counts fully for the first muscle and half for the second. Lifts the app already knows — squat, bench, chin-ups and the rest — need nothing here.")
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
                    labeled("evidence file", text: $store.researchPath, placeholder: "research.md")
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

                Section("Strava") {
                    if let athlete = strava.athlete {
                        HStack {
                            Text("Connected as \(athlete)")
                            Spacer()
                            Button("Disconnect", role: .destructive) { strava.disconnect() }
                                .font(.subheadline)
                        }
                        Text("A **Post to Strava** button sits under today's session. It posts the day as a Weight Training activity with your lines in the description; press it again after another lift and it updates the same activity. History shows which days are on Strava, with a post button for the ones that aren't.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let unposted = store.sessions.filter { store.stravaActivity(on: $0.date) == nil }
                        if !unposted.isEmpty {
                            Button {
                                backfillStatus = "Starting…"
                                Task { await backfill(unposted.sorted { $0.date < $1.date }) }
                            } label: {
                                HStack(spacing: 8) {
                                    if backfilling { ProgressView().controlSize(.small) }
                                    Text(unposted.count == 1 ? "Post the 1 session not on Strava"
                                                             : "Post the \(unposted.count) sessions not on Strava")
                                        .font(.subheadline.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.strava)
                            .disabled(backfilling)
                            Text("Older days have no clock, so they go up as an hour from noon. Days posted before the app kept track will be posted again — delete the doubles on Strava.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Every logged day is on Strava.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let backfillStatus {
                            Text(backfillStatus).font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        // Keys first, then the one button: fill the two fields
                        // and Connect saves them and signs in, in one tap.
                        let keysTyped = !stravaID.trimmingCharacters(in: .whitespaces).isEmpty
                                     && !stravaSecret.trimmingCharacters(in: .whitespaces).isEmpty
                        if !strava.isConfigured {
                            Text("From your own Strava API app: create one at strava.com/settings/api (any name; set **localhost** as the Authorization Callback Domain) and copy its Client ID and Client Secret from that page. Both go in the Keychain, never in the repo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            labeled("client ID", text: $stravaID, placeholder: "123456")
                            HStack {
                                Text("client secret").frame(width: 90, alignment: .leading)
                                SecureField("paste it here", text: $stravaSecret)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        Button {
                            Task {
                                stravaError = nil
                                if !strava.isConfigured { strava.storeCredentials(id: stravaID, secret: stravaSecret) }
                                do {
                                    try await strava.connect()
                                    stravaSecret = ""
                                } catch {
                                    stravaError = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if strava.isBusy { ProgressView().controlSize(.small) }
                                Text("Connect with Strava")
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.strava)
                        .disabled(strava.isBusy || !(strava.isConfigured || keysTyped))
                        if strava.isConfigured {
                            Button("Forget Strava keys", role: .destructive) {
                                strava.storeCredentials(id: "", secret: "")
                            }
                            .font(.subheadline)
                        }
                    }
                    if let stravaError {
                        Text(stravaError).font(.caption2).foregroundStyle(.orange)
                    }
                    Text("Powered by Strava")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
            // Not the tap-anywhere dismisser the other screens use: on a Form,
            // a tap gesture on the container eats the taps meant for the buttons
            // in its rows. Drag to dismiss, or the Done above the keyboard.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle("Settings")
        }
    }

    /// Whether the coaching notes were found, and what to do about it.
    private var coachingHint: LocalizedStringKey {
        let found = [store.brief.coaching.isEmpty ? nil : store.coachingPath,
                     store.brief.goals.isEmpty ? nil : store.goalsPath,
                     store.brief.research.isEmpty ? nil : store.researchPath].compactMap { $0 }
        if found.isEmpty {
            return "Neither file found. Commit them beside your log — **\(store.coachingPath)** for how you like to train and what to work around, **\(store.goalsPath)** for what you're aiming at — and they become the coach's standing brief."
        }
        return "Loaded \(found.joined(separator: " and ")). Edit them in your repo, then reload below."
    }

    /// Post every day not yet on Strava, oldest first, one at a time — Strava
    /// rate-limits, and a pause between posts keeps well under it.
    private func backfill(_ sessions: [Session]) async {
        backfilling = true
        defer { backfilling = false }
        for (i, session) in sessions.enumerated() {
            backfillStatus = "Posting \(i + 1) of \(sessions.count) — \(session.dateString)…"
            do {
                try await StravaPoster.post(session, store: store, strava: strava)
            } catch {
                backfillStatus = "Stopped at \(session.dateString): \(error.localizedDescription)"
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        backfillStatus = "Posted \(sessions.count) \(sessions.count == 1 ? "session" : "sessions") ✓"
    }

    /// One unknown lift: pick what it's for, and optionally what it also trains.
    private func muscleRow(_ name: String) -> some View {
        let groups = muscleMap.groups(for: name) ?? []
        return HStack {
            Text(Theme.readableName(name))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            musclePicker(current: groups.first, title: "muscle") { picked in
                var next = groups
                if let picked {
                    next = [picked] + groups.dropFirst().filter { $0 != picked }
                } else {
                    next = []
                }
                muscleMap.set(next, for: name)
            }
            if let primary = groups.first {
                musclePicker(current: groups.dropFirst().first, title: "+ half") { picked in
                    muscleMap.set(picked.map { [primary, $0] } ?? [primary], for: name)
                }
            }
        }
    }

    private func musclePicker(current: MuscleGroup?, title: String,
                              onPick: @escaping (MuscleGroup?) -> Void) -> some View {
        Menu {
            ForEach(MuscleGroup.ordered) { group in
                Button {
                    onPick(group)
                } label: {
                    if group == current { Label(group.rawValue, systemImage: "checkmark") }
                    else { Text(group.rawValue) }
                }
            }
            if current != nil {
                Divider()
                Button("none", role: .destructive) { onPick(nil) }
            }
        } label: {
            Text(current?.rawValue ?? title)
                .font(.subheadline.weight(current == nil ? .regular : .semibold))
                .foregroundStyle(current == nil ? Color.secondary : Theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
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
