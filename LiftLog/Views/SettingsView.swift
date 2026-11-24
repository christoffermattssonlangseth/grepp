import SwiftUI
import WidgetKit

/// Storage, gym equipment, appearance, Coach, and integration settings.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage(Prefs.coachShowCost) private var showCost = true
    @AppStorage(CoachSpend.capKey) private var monthlyCap: Double = CoachSpend.defaultCap
    @ObservedObject private var spend = CoachSpend.shared
    @ObservedObject private var qwen = QwenModel.shared
    @AppStorage(Prefs.barWeight) private var barWeight: Double = 20
    /// In the App Group, not the app's own defaults: the widget reads it.
    @AppStorage(WidgetStyle.key, store: UserDefaults(suiteName: WidgetSnapshot.appGroup))
    private var widgetStyle: WidgetStyle = .auto
    @AppStorage(Prefs.muscleMap) private var muscleMap = MuscleMap()
    @AppStorage(Prefs.trueBlack) private var trueBlack = false
    @StateObject private var strava = StravaService.shared
    /// Strava off means none of it: no post button, no marks in History, no
    /// backfill — the connection and keys are kept for when it comes back.
    @AppStorage(Prefs.stravaEnabled) private var stravaEnabled = true
    @AppStorage(Prefs.healthEnabled) private var healthEnabled = false
    /// Bumped after Health answers, and when the app comes back to the front
    /// — access may have been changed in the Health app meanwhile — so the
    /// caption below the switch follows.
    @State private var healthAsked = 0
    @State private var showingIntake = false
    @State private var showPlates = false
    @State private var showCoachFiles = false
    @State private var isReloading = false
    @State private var stravaError: String?
    @State private var stravaID = ""
    @State private var stravaSecret = ""
    @State private var backfillStatus: String?
    @State private var backfilling = false
    @AppStorage(Prefs.plateInventory) private var inventory = PlateInventory.standard
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    /// The label column in the field rows, scaled with the text.
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 94

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    settingsHeader
                    if !store.pending.isEmpty { pendingCard }
                    storageCard
                    gymCard
                    appearanceCard
                    musclesCard
                    coachCard
                    if QwenModel.isSupported { qwenCard }
                    integrationsCard
                    footerMark
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.backgroundView)
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $showingIntake) {
                IntakeView().environmentObject(store)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { healthAsked += 1 }
            }
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        let source = store.storage == .icloud
            ? "iCloud Drive · \(store.path)"
            : (store.repo.isEmpty ? "GitHub · not configured" : "\(store.owner)/\(store.repo)")
        return ScreenHeader(
            "Settings",
            subtitle: source,
            statusColor: store.pending.isEmpty ? Theme.progressing : Theme.warning
        ) {
            HeaderCircleButton(systemName: "arrow.clockwise",
                               accessibilityLabel: "Reload log",
                               isSpinning: isReloading) {
                withAnimation(.easeInOut(duration: 0.55)) { isReloading = true }
                Task {
                    await store.load()
                    isReloading = false
                }
            }
            .disabled(store.isBusy)
        }
    }

    // MARK: - Pending sync

    private var pendingCard: some View {
        Panel(glow: Theme.warning) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("waiting to sync")
                    Spacer()
                    Text("\(store.pending.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.warning.opacity(0.14), in: Capsule())
                }
                VStack(spacing: 6) {
                    ForEach(store.pending) { write in
                        HStack {
                            Text(Theme.readableName(write.exerciseName))
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(Session.dateFormatter.string(from: write.date))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .insetTile()
                    }
                }
                Text("^[\(store.pending.count) change](inflect: true) saved offline. Reloading pushes them.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                Button {
                    Task { await store.load() }
                } label: {
                    HStack(spacing: 6) {
                        if store.isBusy { ProgressView().controlSize(.small) }
                        Text("Sync now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.panelProminent)
                .tint(Theme.warning)
                .disabled(store.isBusy)
            }
        }
    }

    // MARK: - Storage

    private var storageCard: some View {
        Panel(glow: Theme.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    IconBadge(systemName: store.storage == .icloud ? "icloud" : "chevron.left.forwardslash.chevron.right",
                              color: Theme.accent, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Eyebrow("where the log lives")
                        Text(store.storage == .icloud ? "iCloud Drive" : "GitHub Repository")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Spacer()
                }

                Picker("storage", selection: Binding(
                    get: { store.storage },
                    set: { store.storage = $0; Task { await store.load() } }
                )) {
                    ForEach(Store.Storage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if store.storage == .icloud {
                    labeled("file", text: $store.path, placeholder: "training.md")
                    Text("In iCloud Drive, in a Grepp folder you can open from the Files app. Synced by Apple; nothing leaves your account.")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                } else {
                    VStack(spacing: 8) {
                        labeled("owner", text: $store.owner, placeholder: "your-username")
                        labeled("repo", text: $store.repo, placeholder: "training")
                        labeled("file path", text: $store.path, placeholder: "training.md")
                        labeled("branch", text: $store.branch, placeholder: "main")
                        labeledRow("token") {
                            SecureField("ghp_… (fine-grained PAT)", text: $store.token)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: store.token) { _, _ in store.saveToken() }
                        }
                    }
                    Text("Create a fine-grained token scoped to just this repo with **Contents: Read and write**.")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }

                if !store.status.isEmpty {
                    Text(store.status)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    // MARK: - Gym & plates

    private var gymCard: some View {
        let totalPlates = PlateMath.sizes.reduce(0) { $0 + (inventory.counts[$1] ?? 0) }
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("gym & plates")

                Picker("bar weight", selection: $barWeight) {
                    ForEach(PlateMath.bars, id: \.self) { kg in
                        Text("\(PlateMath.label(kg)) kg").tag(kg)
                    }
                }
                .pickerStyle(.segmented)

                Text("Your default bar. An exercise on a different one is set from the plate line in Log and remembered.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)

                Button {
                    withAnimation(.snappy(duration: 0.25)) { showPlates.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(systemName: "circlebadge.2.fill", color: Theme.accent, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plate inventory")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("\(totalPlates) plates configured")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(showPlates ? 90 : 0))
                    }
                    .padding(12)
                    .insetTile()
                }
                .buttonStyle(.cardPress)

                if showPlates {
                    VStack(spacing: 8) {
                        ForEach(PlateMath.sizes, id: \.self) { size in
                            Stepper(value: plateCount(size), in: 0...20) {
                                HStack {
                                    Text("\(PlateMath.label(size)) kg")
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    Spacer()
                                    Text("× \(inventory.counts[size] ?? 0)")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle((inventory.counts[size] ?? 0) == 0 ? Theme.dim.opacity(0.45) : Theme.dim)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .insetTile()
                        }
                        Text("Both sides together — four 25s is two a side. The calculator never suggests a plate you don't have.")
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    // MARK: - Appearance & widget

    private var appearanceCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("appearance & widget")

                Toggle(isOn: $trueBlack) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("True black in dark mode")
                            .font(.system(size: 15, weight: .medium))
                        Text("Pure OLED black instead of warm charcoal")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .tint(Theme.accent)

                Divider().overlay(Theme.rule)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Home screen widget plate")
                        .font(.system(size: 14, weight: .medium))
                    Picker("home screen", selection: $widgetStyle) {
                        ForEach(WidgetStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: widgetStyle) { _, _ in
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
                    }
                    Text("Follow phone is black in dark mode and white in light.")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    // MARK: - Muscles

    private var musclesCard: some View {
        let unmapped = muscleMap.unmapped(in: store.sessions)
        let assigned = Array(Set(store.knownExercises.filter { muscleMap.isOverridden($0) }.map { MuscleMap.canonical($0) })).sorted()
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("muscles")

                if unmapped.isEmpty && assigned.isEmpty {
                    Text("Every lift in your log is counted. A new one the app doesn't know will show up here.")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                } else {
                    VStack(spacing: 8) {
                        ForEach(unmapped + assigned, id: \.self) { name in
                            muscleRow(name)
                        }
                    }
                }

                NavigationLink {
                    MuscleMapView()
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(systemName: "figure.strengthtraining.traditional", color: Theme.progressing, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Every lift's shares")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Each muscle's share of a set, per lift")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .insetTile()
                }
                .buttonStyle(.cardPress)
            }
        }
    }

    // MARK: - Coach

    private var coachCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow("coach")
                    Spacer()
                    Text("$\(SpendLedger.money(spend.thisMonth)) this month")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }

                labeledRow("API key") {
                    SecureField("sk-ant-… (Claude API key)", text: $store.anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: store.anthropicKey) { _, _ in store.saveAnthropicKey() }
                }

                Text("Stored in the Keychain — never in source or UserDefaults. Create one in the [Claude Console](https://platform.claude.com/).")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)

                VStack(spacing: 8) {
                    Button {
                        store.requestBrief()
                    } label: {
                        HStack(spacing: 10) {
                            IconBadge(systemName: "person.text.rectangle", color: Theme.accent, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Your brief")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Goals & how you train")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .insetTile()
                    }
                    .buttonStyle(.cardPress)

                    Button {
                        showingIntake = true
                    } label: {
                        HStack(spacing: 10) {
                            IconBadge(systemName: "list.bullet.clipboard", color: Theme.accent, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Set up again")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("Experience, goal & equipment")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .insetTile()
                    }
                    .buttonStyle(.cardPress)
                    .disabled(!store.canWriteFiles)
                }

                Divider().overlay(Theme.rule)

                Toggle(isOn: $showCost) {
                    Text("Show cost under each answer")
                        .font(.system(size: 14, weight: .medium))
                }
                .tint(Theme.accent)

                HStack {
                    Text("Monthly cap")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Picker("Monthly cap", selection: $monthlyCap) {
                        if ![5.0, 10.0, 20.0, 50.0, 0.0].contains(monthlyCap) {
                            Text("$\(SpendLedger.money(monthlyCap))").tag(monthlyCap)
                        }
                        Text("$5").tag(5.0)
                        Text("$10").tag(10.0)
                        Text("$20").tag(20.0)
                        Text("$50").tag(50.0)
                        Text("None").tag(0.0)
                    }
                    .labelsHidden()
                    .tint(Theme.accent)
                }

                Button {
                    withAnimation(.snappy(duration: 0.25)) { showCoachFiles.toggle() }
                } label: {
                    HStack {
                        Text("Brief file paths & workspace ID")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(showCoachFiles ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showCoachFiles {
                    VStack(spacing: 8) {
                        labeled("coaching", text: $store.coachingPath, placeholder: "coaching.md")
                        labeled("goals", text: $store.goalsPath, placeholder: "goals.md")
                        labeled("evidence", text: $store.researchPath, placeholder: "research.md")
                        labeled("programme", text: $store.programPath, placeholder: "program.md")
                        if usesBarVelo {
                            labeled("velocity", text: $store.velocityPath, placeholder: "velocity.md")
                        }
                        labeled("workspace", text: $store.anthropicWorkspace, placeholder: "wrkspc_… (optional)")
                    }
                    Text(coachingHint)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    // MARK: - Qwen on device

    private var qwenCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("qwen on device")

                switch qwen.state {
                case .notDownloaded:
                    Button {
                        qwen.startDownload()
                    } label: {
                        Label("Download Qwen3 4B (\(QwenModel.downloadSize))", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.panel)
                    .tint(Theme.accent)
                case .downloading(let fraction):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Downloading…")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(Int(fraction * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                        PrecisionMeterBar(progress: fraction, height: 6)
                        Button("Cancel", role: .cancel) { qwen.cancelDownload() }
                            .font(.subheadline)
                            .foregroundStyle(Theme.dim)
                    }
                case .ready:
                    HStack {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.progressing)
                        Spacer()
                        Button("Delete", role: .destructive) { qwen.delete() }
                            .font(.subheadline)
                    }
                case .failed(let why):
                    Text(why).font(.caption).foregroundStyle(Theme.warning)
                    Button {
                        qwen.startDownload()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.panel)
                    .tint(Theme.accent)
                }

                Text("Qwen3 4B runs locally on your phone — free and private, seeing about a month of your log. Pick **Qwen** in Coach once downloaded.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            }
        }
        .task { await qwen.refresh() }
    }

    // MARK: - Integrations (Apple Health & Strava)

    private var integrationsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("integrations")

                // Apple Health
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $healthEnabled) {
                        HStack(spacing: 10) {
                            IconBadge(systemName: "heart.fill", color: .red, size: 30)
                            Text("Save sessions to Health")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .tint(Theme.accent)
                    .disabled(!HealthWriter.isAvailable)
                    .onChange(of: healthEnabled) { _, on in
                        guard on else { return }
                        Task { _ = await HealthWriter.requestAccess(); healthAsked += 1 }
                    }
                    Text(healthCaption)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .id(healthAsked)
                }

                Divider().overlay(Theme.rule)

                // Strava
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $stravaEnabled) {
                        HStack(spacing: 10) {
                            IconBadge(systemName: "figure.run", color: Theme.strava, size: 30)
                            Text("Strava")
                                .font(.system(size: 15, weight: .medium))
                        }
                    }
                    .tint(Theme.strava)

                    if !stravaEnabled {
                        Text("Off: no post button under the session, no marks in History, nothing posted.")
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    } else if let athlete = strava.athlete {
                        HStack {
                            Text("Connected as \(athlete)")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Button("Disconnect", role: .destructive) { strava.disconnect() }
                                .font(.subheadline)
                        }
                        .padding(12)
                        .insetTile()

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
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.panelProminent)
                            .tint(Theme.strava)
                            .disabled(backfilling)
                        } else {
                            Text("Every logged day is on Strava.")
                                .font(.caption)
                                .foregroundStyle(Theme.dim)
                        }
                        if let backfillStatus {
                            Text(backfillStatus).font(.caption2).foregroundStyle(Theme.dim)
                        }
                    } else {
                        let keysTyped = !stravaID.trimmingCharacters(in: .whitespaces).isEmpty
                                     && !stravaSecret.trimmingCharacters(in: .whitespaces).isEmpty
                        if !strava.isConfigured {
                            Text("From your Strava API app at strava.com/settings/api (set **localhost** as Callback Domain). Stored in Keychain.")
                                .font(.caption)
                                .foregroundStyle(Theme.dim)
                            labeled("client ID", text: $stravaID, placeholder: "123456")
                            labeledRow("client secret") {
                                SecureField("paste it here", text: $stravaSecret)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
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
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.panelProminent)
                        .tint(Theme.strava)
                        .disabled(strava.isBusy || !(strava.isConfigured || keysTyped))

                        if strava.isConfigured {
                            Button("Forget Strava keys", role: .destructive) {
                                strava.storeCredentials(id: "", secret: "")
                            }
                            .font(.subheadline)
                        }
                    }

                    if stravaEnabled, let stravaError {
                        Text(stravaError).font(.caption2).foregroundStyle(Theme.warning)
                    }
                    if stravaEnabled {
                        Text("Powered by Strava")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerMark: some View {
        VStack(spacing: 8) {
            Barbell(height: 24)
            Text("GREPP")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var usesBarVelo: Bool {
        !store.brief.velocity.isEmpty
            || UIApplication.shared.canOpenURL(VelocitySet.measureURL(lift: "", load: nil, reps: nil))
    }

    private var coachingHint: LocalizedStringKey {
        let found = [store.brief.coaching.isEmpty ? nil : store.coachingPath,
                     store.brief.goals.isEmpty ? nil : store.goalsPath,
                     store.brief.research.isEmpty ? nil : store.researchPath,
                     store.brief.velocity.isEmpty ? nil : store.velocityPath].compactMap { $0 }
        let velocityNote = " **\(store.velocityPath)** holds the sets BarVelo measured; the coach reads it as bar velocity, with reps in reserve where known."
        if found.isEmpty || found == [store.velocityPath] {
            let none = "No brief files yet. Write them from Your brief, or put them beside your log — **\(store.coachingPath)** for how you like to train, **\(store.goalsPath)** for what you're aiming at."
            return LocalizedStringKey(none + (found.isEmpty ? "" : velocityNote))
        }
        let list = found.count > 1 ? found.dropLast().joined(separator: ", ") + " and " + found.last! : found[0]
        return LocalizedStringKey("Loaded \(list). Edit them in Your brief or beside the log." + velocityNote)
    }

    private func backfill(_ sessions: [Session]) async {
        backfilling = true
        defer { backfilling = false }
        var posted = 0
        var skipped: [String] = []
        for (i, session) in sessions.enumerated() {
            guard stravaEnabled else {
                backfillStatus = "Stopped after \(posted) posted: Strava was turned off."
                return
            }
            backfillStatus = "Posting \(i + 1) of \(sessions.count) — \(session.dateString)…"
            do {
                try await StravaPoster.post(session, store: store, strava: strava)
                posted += 1
            } catch StravaService.StravaError.api(let status, _) where status == 409 {
                skipped.append(session.dateString)
            } catch {
                backfillStatus = "Stopped at \(session.dateString) after \(posted) posted: \(error.localizedDescription)"
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        var summary = "Posted \(posted) \(posted == 1 ? "session" : "sessions") ✓"
        if !skipped.isEmpty {
            summary += " Skipped \(skipped.count) that Strava already had something at: " + skipped.joined(separator: ", ")
        }
        backfillStatus = summary
    }

    private func muscleRow(_ name: String) -> some View {
        NavigationLink {
            ExerciseMuscleView(exercise: name)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Theme.readableName(name))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(muscleMap.share(for: name)?.summary ?? "not counted yet — tap to say what it trains")
                        .font(.caption)
                        .foregroundStyle(muscleMap.share(for: name) == nil ? Theme.warning : Theme.dim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .insetTile()
        }
        .buttonStyle(.cardPress)
    }

    private func plateCount(_ size: Double) -> Binding<Int> {
        Binding(
            get: { inventory.counts[size] ?? 0 },
            set: { inventory.counts[size] = $0 }
        )
    }

    private var healthCaption: String {
        if !HealthWriter.isAvailable { return "Health isn't available on this device." }
        if healthEnabled && HealthWriter.isDenied {
            return "Health said no. Allow Grepp to write workouts under Health ▸ Sharing ▸ Apps."
        }
        return "Each day's lifting is saved as one strength-training workout, from the first set to the last lift finished."
    }

    private func labeled(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        labeledRow(label) {
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private func labeledRow<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    field()
                }
            } else {
                HStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .frame(width: labelWidth, alignment: .leading)
                    field()
                        .font(.system(size: 14, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .insetTile()
    }
}
