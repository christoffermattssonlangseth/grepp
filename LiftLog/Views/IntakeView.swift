import SwiftUI

/// The setup a new lifter goes through once, after choosing where the log
/// lives: experience, goal, schedule, where they train and with what, the
/// bar and plates, and what to work around. Native screens, so it works
/// with or without a coach key; the answers go into Settings and the brief
/// files the coach already reads. Run again from Settings ▸ Set up again.
struct IntakeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.barWeight) private var barWeight: Double = 20
    @AppStorage(Prefs.plateInventory) private var inventory = PlateInventory.standard
    @AppStorage(Prefs.intakePending) private var pending = false

    @State private var intake = IntakeView.saved ?? Intake()
    @State private var hasDate = IntakeView.saved?.goalBy != nil
    @State private var goalBy = IntakeView.saved?.goalBy
        ?? Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var saving = false
    @State private var saveError: String?
    @State private var finished = false
    @State private var startingProgramme = false

    static var saved: Intake? {
        UserDefaults.standard.data(forKey: Prefs.intake).flatMap { try? JSONDecoder().decode(Intake.self, from: $0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if finished { handOff } else { form }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle(finished ? "All set" : "About you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !finished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { pending = false; dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await save() } } label: {
                            if saving { ProgressView().controlSize(.small) } else { Text("Save").font(.body.weight(.semibold)) }
                        }
                        .disabled(saving)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.font(.body.weight(.semibold))
                    }
                }
            }
        }
        .interactiveDismissDisabled(!finished)
    }

    // MARK: - The questions

    private var form: some View {
        Form {
            Section {
                Text("A few questions so the app and the coach start from what you have and what you want. Nothing here goes anywhere but your own files.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section("How long have you lifted?") {
                Picker("Experience", selection: $intake.experience) {
                    ForEach(Intake.Experience.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))

            Section {
                Picker("Goal", selection: $intake.goal) {
                    ForEach(Intake.Goal.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("In your words, optional: squat 100 kg", text: $intake.goalWords)
                if !intake.goalWords.trimmingCharacters(in: .whitespaces).isEmpty {
                    Toggle("By a date", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $goalBy, in: Date()..., displayedComponents: .date)
                    }
                }
            } header: {
                Text("What for?")
            } footer: {
                Text("A goal with a lift and a number, like \"squat 100 kg\", gets a target card on Trends.")
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))

            Section("How often?") {
                Stepper("\(intake.days) \(intake.days == 1 ? "day" : "days") a week", value: $intake.days, in: 1...6)
                Stepper("About \(intake.minutes) minutes a session", value: $intake.minutes, in: 20...120, step: 15)
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))

            Section("Where do you train?") {
                Picker("Place", selection: $intake.place) {
                    ForEach(Intake.Place.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: intake.place) { _, place in
                    intake.equipment = Intake.defaultEquipment(for: place)
                    if place == .gym { inventory = .standard }
                }
                if intake.place != .bodyweight {
                    ForEach(Intake.Equipment.allCases, id: \.self) { item in
                        Toggle(item.label, isOn: Binding(
                            get: { intake.equipment.contains(item) },
                            set: { on in
                                if on { intake.equipment.insert(item) } else { intake.equipment.remove(item) }
                            }))
                    }
                }
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))

            if intake.place != .bodyweight && intake.equipment.contains(.barbell) {
                Section {
                    Picker("Bar", selection: $barWeight) {
                        ForEach(PlateMath.bars, id: \.self) { kg in
                            Text("\(PlateMath.label(kg)) kg").tag(kg)
                        }
                    }
                    .pickerStyle(.segmented)
                    if intake.place == .home {
                        ForEach(PlateMath.sizes, id: \.self) { size in
                            Stepper(value: plateCount(size), in: 0...20) {
                                HStack {
                                    Text("\(PlateMath.label(size)) kg").monospacedDigit()
                                    Spacer()
                                    Text("× \(inventory.counts[size] ?? 0)")
                                        .monospacedDigit()
                                        .foregroundStyle((inventory.counts[size] ?? 0) == 0 ? .tertiary : .secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Bar and plates")
                } footer: {
                    Text(intake.place == .home
                         ? "The plates you own, both sides together: four 25s is two a side. Loads are worked out from these."
                         : "A gym's usual rack. Change the plates any time in Settings ▸ Gym.")
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }

            Section {
                TextField("Optional: a knee, a shoulder, no deadlifts…", text: $intake.limits, axis: .vertical)
            } header: {
                Text("Anything to work around?")
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))

            if let saveError {
                Section {
                    Text(saveError).font(.footnote).foregroundStyle(Theme.stalled)
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func plateCount(_ size: Double) -> Binding<Int> {
        Binding(get: { inventory.counts[size] ?? 0 },
                set: { var next = inventory; next.counts[size] = $0; inventory = next })
    }

    // MARK: - After

    private var handOff: some View {
        let hasKey = CoachCredentials.hasKey
        return Form {
            Section {
                Text("Saved: your setup is in coaching.md" + (intake.goalsLine() == nil ? "" : " and your goal in goals.md") + ", and the bar and plates are in Settings. The coach reads them every time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section {
                if hasKey {
                    Button {
                        dismiss()
                        store.requestCoach(intake.coachQuestion)
                    } label: {
                        Label(intake.isNovice ? "Ask the coach for a first programme" : "Bring my training history in",
                              systemImage: "bubble.left.and.text.bubble.right")
                            .font(.body.weight(.semibold))
                    }
                }
                if intake.isNovice && store.programme.isEmpty {
                    Button {
                        Task { await startBeginner() }
                    } label: {
                        HStack {
                            Label("Start the beginner programme", systemImage: "list.bullet.rectangle")
                                .font(hasKey ? .body : .body.weight(.semibold))
                            if startingProgramme { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(startingProgramme)
                }
                Button("Start logging") { dismiss() }
            } footer: {
                if intake.isNovice && !hasKey {
                    Text("The beginner programme is two full-body days to alternate, fitted to your equipment; each lift says when it goes up. For a programme built around you, add a Claude key in Settings ▸ Coach.")
                } else if intake.isNovice {
                    Text("The coach builds from your setup and asks only what it leaves out. Or start straight away with the beginner programme: two full-body days, fitted to your equipment.")
                }
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))
        }
    }

    // MARK: - Saving

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        intake.goalBy = hasDate ? goalBy : nil
        if let data = try? JSONEncoder().encode(intake) {
            UserDefaults.standard.set(data, forKey: Prefs.intake)
        }
        // A fresh install is still loading: the brief must be read before it
        // is written to, or a coaching file already there would be replaced.
        for _ in 0..<40 where store.isBusy {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard store.canWriteFiles else {
            saveError = "The log isn't connected yet, so nothing could be written. Finish storage in Settings, then Settings ▸ Set up again — your answers are kept."
            return
        }
        let coaching = Intake.merging(intake.coachingSection(), into: store.brief.coaching)
        guard await store.save(coaching, to: .coaching) != .failed else {
            saveError = "Couldn't write coaching.md. Check the connection and try again; your answers are kept."
            return
        }
        if let line = intake.goalsLine() {
            let goals = Intake.adding(line, to: store.brief.goals)
            if goals != store.brief.goals, await store.save(goals, to: .goals) == .failed {
                saveError = "Saved your setup, but couldn't write goals.md. Try Save again."
                return
            }
        }
        pending = false
        finished = true
    }

    private func startBeginner() async {
        startingProgramme = true
        defer { startingProgramme = false }
        if await store.save(intake.starter(), to: .program) != .failed {
            dismiss()
            store.requestProgramme()
        }
    }
}
