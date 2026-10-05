import SwiftUI

/// The programme on file, day by day, each with one button: ask the coach for
/// that day with today's loads. The file holds schemes, not loads — the coach
/// puts loads on from the log every time, which is why the button is a question.
///
/// Opened from the Coach toolbar. Edited here in Edit mode — days renamed,
/// added and removed, lifts added, changed, reordered and removed — as a
/// draft of the file saved once; the coach's prose between the days is
/// untouched. Edited as text in Your brief; written fresh by asking the coach.
struct ProgrammeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.barWeight) private var barWeight: Double = 20
    @AppStorage(Prefs.plateInventory) private var inventory = PlateInventory.standard
    @AppStorage(Prefs.barOverrides) private var barOverrides = BarOverrides()

    /// Hands a question back to the Coach screen once this sheet is closed.
    let onAsk: (String) -> Void

    /// The file as edited so far; nil when not editing.
    @State private var draft: String?
    @State private var liftEdit: LiftEdit?
    @State private var addingDay = false
    @State private var renameIndex: Int?
    @State private var renameText = ""
    @State private var saving = false
    @State private var saveError: String?

    private var editing: Bool { draft != nil }
    private var shown: Programme { draft.map(Programme.parse) ?? store.programme }

    /// A lift being added to or changed in a day; nil exercise means new.
    private struct LiftEdit: Identifiable {
        let id = UUID()
        let dayIndex: Int
        let exercise: Programme.Exercise?
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.programme.isEmpty && !editing { empty } else { days }
            }
            .background(Theme.backgroundView)
            .navigationTitle(shown.title.isEmpty ? "Programme" : shown.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editing {
                        Button("Cancel") { draft = nil; saveError = nil }
                    } else if !store.programme.isEmpty {
                        Button("Edit") { draft = store.brief.program }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editing {
                        Button { Task { await save() } } label: {
                            if saving { ProgressView().controlSize(.small) } else { Text("Save").font(.body.weight(.semibold)) }
                        }
                        .disabled(saving || shown.isEmpty)
                    } else {
                        Button("Done") { dismiss() }
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(item: $liftEdit) { edit in
                LiftSheet(exercise: edit.exercise, lifts: store.knownExercises) { exercise in
                    apply(exercise, to: edit)
                }
            }
            .sheet(isPresented: $addingDay) {
                DaySheet(lifts: store.knownExercises) { title, exercise in
                    guard let draft else { return }
                    self.draft = ProgrammeText.appendingDay(title, exercises: [exercise], to: draft)
                }
            }
            .alert("Rename day", isPresented: Binding(get: { renameIndex != nil }, set: { if !$0 { renameIndex = nil } })) {
                TextField("Title", text: $renameText)
                Button("Rename") {
                    if let i = renameIndex, let draft, shown.days.indices.contains(i),
                       !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        self.draft = ProgrammeText.renaming(shown.days[i], to: renameText.trimmingCharacters(in: .whitespaces), in: draft)
                    }
                    renameIndex = nil
                }
                Button("Cancel", role: .cancel) { renameIndex = nil }
            }
        }
    }

    // MARK: - Days

    private var days: some View {
        let programme = shown
        let due = programme.dueDayIndex(in: store.sessions)

        return List {
            if !editing, let a = programme.adherence(in: store.sessions) {
                adherenceSection(a)
            }
            if let saveError {
                Section {
                    Text(saveError).font(.footnote).foregroundStyle(Theme.stalled)
                        .listRowBackground(Color.clear)
                }
            }
            // By position: an upper/lower programme has two days called Upper.
            ForEach(Array(programme.days.enumerated()), id: \.offset) { index, day in
                Section {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                        exerciseRow(ex, in: index)
                    }
                    .onDelete { offsets in
                        guard editing, let draft, let first = offsets.first, day.exercises.indices.contains(first) else { return }
                        self.draft = ProgrammeText.removing(line: day.exercises[first].line, in: draft)
                    }
                    .onMove { source, destination in
                        guard editing, let draft else { return }
                        var order = day.exercises
                        order.move(fromOffsets: source, toOffset: destination)
                        self.draft = ProgrammeText.reordering(day, to: order, in: draft)
                    }
                    if editing {
                        editingRows(for: day, at: index)
                    } else {
                        loadRows(for: day, at: index, due: due)
                    }
                } header: {
                    dayHeader(day, at: index, due: due)
                }
            }
            if editing {
                Section {
                    Button {
                        addingDay = true
                    } label: {
                        Label("Add day", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .listRowBackground(Color.clear)
                    Text("Tap a lift to change it, drag to reorder, swipe to remove. Save writes program.md; the coach's notes between the days stay as they are.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Text("Schemes live here, not loads. Load this day works them out from your log: rpt lines as a reverse pyramid from their last session, everything else as last done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(editing ? .active : .inactive))
    }

    private func adherenceSection(_ a: Programme.Adherence) -> some View {
        // How the last four weeks went against the file, before the file.
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(a.daysDone) programme \(a.daysDone == 1 ? "day" : "days")")
                        .font(.subheadline.weight(.bold))
                    Text(String(format: "· %.1f a week", a.perWeek))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text("last \(a.weeks) weeks").font(.caption2).foregroundStyle(.tertiary)
                }
                if a.other > 0 {
                    Text("\(a.other) \(a.other == 1 ? "session" : "sessions") that \(a.other == 1 ? "wasn't" : "weren't") a programme day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if a.skipped.isEmpty {
                    if a.daysDone > 0 {
                        Text("Every lift on every day done.").font(.caption).foregroundStyle(Theme.progressing)
                    }
                } else {
                    Text("Skipped most: " + a.skipped.prefix(3).map {
                        "\(Theme.readableName($0.name)) \($0.missed) of \($0.due)"
                    }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.stalled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .padding(.vertical, 2)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private func exerciseRow(_ ex: Programme.Exercise, in dayIndex: Int) -> some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(Theme.readableName(ex.name)).font(.body.weight(.semibold))
                if ex.rpt {
                    Text("rpt").font(.caption2.weight(.heavy)).tracking(0.5)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ex.scheme)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !ex.note.isEmpty {
                Text(ex.note).font(.caption).foregroundStyle(.tertiary)
            }
            // Where the lift stands: history, not a prescription.
            if let last = Programme.lastDone(ex.name, in: store.sessions) {
                Text("last: \(last.entry.sets.map(\.token).joined(separator: " ")) · \(CoachContext.short(last.day))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("not logged yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        return Group {
            if editing {
                Button { liftEdit = LiftEdit(dayIndex: dayIndex, exercise: ex) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .padding(.vertical, 2)
        )
        // Swipes and handles only in Edit mode; reading the file is not editing it.
        .deleteDisabled(!editing)
        .moveDisabled(!editing)
    }

    @ViewBuilder
    private func editingRows(for day: Programme.Day, at index: Int) -> some View {
        Button {
            liftEdit = LiftEdit(dayIndex: index, exercise: nil)
        } label: {
            Label("Add lift", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .listRowBackground(Color.clear)
        Button(role: .destructive) {
            guard let draft else { return }
            self.draft = ProgrammeText.removing(day, from: draft)
        } label: {
            Label("Remove day", systemImage: "trash")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func loadRows(for day: Programme.Day, at index: Int, due: Int) -> some View {
        // Two ways in: the app's own arithmetic, free and instant —
        // rpt lines from their last session, the rest as last done —
        // or the coach, who reads the log and the rule on each line.
        let plan = ReversePyramid.plan(day: day, in: store.sessions,
                                       bar: { barOverrides.bar(for: $0) ?? barWeight },
                                       inventory: inventory)
        let load = Button {
            dismiss()
            store.requestLog(plan.entries)
        } label: {
            Label("Load this day", systemImage: "arrow.down.to.line")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        // One prominent button on the screen: the day that is next.
        Group {
            if index == due { load.buttonStyle(.borderedProminent) } else { load.buttonStyle(.bordered) }
        }
        .tint(Theme.accent)
        .disabled(plan.entries.isEmpty)
        .listRowBackground(Color.clear)
        if !plan.missing.isEmpty {
            Text("Not logged yet, so left out until it is: " + plan.missing.map { Theme.readableName($0) }.joined(separator: ", ") + ".")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .listRowBackground(Color.clear)
        }
        Button {
            dismiss()
            onAsk("Prescribe \(day.title) from my programme for today, with loads from my log.")
        } label: {
            Label("Ask the coach for this day", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .listRowBackground(Color.clear)
    }

    private func dayHeader(_ day: Programme.Day, at index: Int, due: Int) -> some View {
        HStack {
            Text(day.title).textCase(nil)
            if editing {
                Button {
                    renameText = day.title
                    renameIndex = index
                } label: {
                    Image(systemName: "pencil").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Rename \(day.title)")
            } else if index == due {
                Text("next")
                    .font(.caption2.weight(.heavy)).tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel(index == due && !editing ? "\(day.title), next" : day.title)
    }

    // MARK: - Edits

    private func apply(_ exercise: Programme.Exercise, to edit: LiftEdit) {
        guard let draft, shown.days.indices.contains(edit.dayIndex) else { return }
        let day = shown.days[edit.dayIndex]
        if let old = edit.exercise, old.line >= 0 {
            self.draft = ProgrammeText.replacing(line: old.line, with: ProgrammeText.line(for: exercise), in: draft)
        } else {
            self.draft = ProgrammeText.adding(exercise, to: day, in: draft)
        }
    }

    private func save() async {
        guard let draft else { return }
        saving = true
        saveError = nil
        let result = await store.save(draft, to: .program)
        saving = false
        if result == .pushed {
            self.draft = nil
        } else {
            saveError = "Couldn't save program.md. Check the connection and try again; your changes are still here."
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No programme yet", systemImage: "calendar")
        } description: {
            Text("Ask the coach to write one — \"write me a programme\" — then tap Save as my programme under its answer. The screen reads the saved file. It designs from your log, your goals and your evidence brief, and prescribes each day from it after that.")
        } actions: {
            Button("Ask the coach") {
                dismiss()
                onAsk("Write me a programme.")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            // The one programme the app carries itself: reverse pyramid, three
            // days, worked out from the log with no coach in the loop.
            Button("Start with reverse pyramid") {
                Task { _ = await store.save(ReversePyramid.starter, to: .program) }
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(store.isBusy)
            // Or day by day, by hand, here.
            Button("Write it myself") {
                draft = "# Programme\n"
                addingDay = true
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
    }
}

// MARK: - Sheets

/// One lift of a day: its name, scheme, whether it is a reverse pyramid,
/// and a note. Saves when the line it would write is one the file reads.
private struct LiftSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Programme.Exercise?
    let lifts: [String]
    let onSave: (Programme.Exercise) -> Void

    @State private var name = ""
    @State private var scheme = ""
    @State private var rpt = false
    @State private var note = ""
    @State private var picking = false

    private var candidate: Programme.Exercise? {
        let key = MuscleMap.key(name)
        let ex = Programme.Exercise(name: key, scheme: scheme.trimmingCharacters(in: .whitespaces),
                                    note: note.trimmingCharacters(in: .whitespaces), rpt: rpt)
        guard !key.isEmpty, let parsed = Programme.parse("## Day\n" + ProgrammeText.line(for: ex)).days.first?.exercises.first else { return nil }
        return Programme.Exercise(name: key, scheme: parsed.scheme, note: ex.note, rpt: rpt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lift") {
                    HStack {
                        TextField("squat", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Choose") { picking = true }
                            .font(.subheadline)
                    }
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section {
                    TextField("3x5, 3x8-10, 3xAMRAP", text: $scheme)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Reverse pyramid (rpt)", isOn: $rpt)
                } header: {
                    Text("Sets × reps")
                } footer: {
                    Text(rpt ? "The app works the loads out from the last session: top set first, each set after it a tenth lighter for two more reps."
                             : "Loads are not in the file; the coach or Load this day puts them on from your log.")
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section("Note") {
                    TextField("add 2.5 kg when all sets hit", text: $note)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle(exercise == nil ? "Add lift" : "Change lift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let candidate { onSave(candidate); dismiss() }
                    }
                    .disabled(candidate == nil)
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePickerView(history: lifts) { name = $0 }
            }
            .onAppear {
                guard let exercise else { return }
                name = exercise.name
                scheme = exercise.scheme
                rpt = exercise.rpt
                note = exercise.note
            }
        }
    }
}

/// A new day: its title and its first lift. More lifts are added on the
/// day once it is there.
private struct DaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let lifts: [String]
    let onSave: (String, Programme.Exercise) -> Void

    @State private var title = ""
    @State private var name = ""
    @State private var scheme = ""
    @State private var picking = false

    private var candidate: Programme.Exercise? {
        let key = MuscleMap.key(name)
        let ex = Programme.Exercise(name: key, scheme: scheme.trimmingCharacters(in: .whitespaces), note: "", rpt: false)
        guard !key.isEmpty, let parsed = Programme.parse("## Day\n" + ProgrammeText.line(for: ex)).days.first?.exercises.first else { return nil }
        return Programme.Exercise(name: key, scheme: parsed.scheme, note: "", rpt: false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    TextField("Day A — Lower", text: $title)
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
                Section("First lift") {
                    HStack {
                        TextField("squat", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Choose") { picking = true }
                            .font(.subheadline)
                    }
                    TextField("3x5", text: $scheme)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .navigationTitle("Add day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let candidate, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                            onSave(title.trimmingCharacters(in: .whitespaces), candidate)
                            dismiss()
                        }
                    }
                    .disabled(candidate == nil || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePickerView(history: lifts) { name = $0 }
            }
        }
    }
}
