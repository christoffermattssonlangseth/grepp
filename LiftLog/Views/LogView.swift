import SwiftUI

/// Live session logger: shows the exercises already logged for the selected day,
/// plus an input area to build up one exercise's sets and "finish" it — which
/// commits it to GitHub and resets the input so you can move on to the next.
///
/// Bold / gym-friendly styling: big touch targets, a strong accent, chunky
/// buttons and oversized number fields you can hit mid-set.
struct LogView: View {
    @EnvironmentObject var store: Store

    @State private var date = Date()
    @State private var name = ""
    @State private var sets: [WorkSet] = []

    @State private var isBodyweight = false
    @State private var weightText = ""
    @State private var addedText = ""
    @State private var repsText = ""

    @State private var showingPicker = false
    /// When non-nil, the rest clock is running from this instant.
    @State private var restStart: Date?
    @FocusState private var focus: Field?
    private enum Field { case weight, reps }

    /// Exercises already saved for the selected day.
    private var todayExercises: [ExerciseEntry] {
        let key = Session.dateFormatter.string(from: date)
        return store.sessions.first { $0.dateString == key }?.exercises ?? []
    }

    private var lastEntry: ExerciseEntry? {
        name.isEmpty ? nil : store.lastEntry(for: name, before: date)
    }

    private var parsedWeight: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedAdded: Double? { Double(addedText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedReps: Int? { Int(repsText) }
    private var canAddSet: Bool { parsedReps != nil && (isBodyweight || parsedWeight != nil) }
    private var canFinish: Bool { !name.isEmpty && !sets.isEmpty && !store.isBusy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateCard
                    if !todayExercises.isEmpty { todaySessionCard }
                    sectionLabel("add exercise")
                    exerciseCard
                    addSetCard
                    if restStart != nil { restTimerCard }
                    if !sets.isEmpty { setsCard }
                    finishButton
                    if !store.status.isEmpty {
                        Text(store.status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Theme.backgroundView)
            .navigationTitle("Session")
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(history: store.knownExercises) { picked in
                    // Switching exercise starts a fresh set list for the new movement.
                    if picked.caseInsensitiveCompare(name) != .orderedSame {
                        sets = []
                        restStart = nil
                    }
                    name = picked
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .refreshable { await store.load() }
            .onAppear { applyEditRequest() }
            .onChange(of: store.editRequest) { _, _ in applyEditRequest() }
        }
    }

    /// Pull a "edit this past entry" request from History into the input area.
    private func applyEditRequest() {
        guard let req = store.editRequest else { return }
        let key = Session.dateFormatter.string(from: req.date)
        if let ex = store.sessions.first(where: { $0.dateString == key })?
            .exercises.first(where: { $0.name.caseInsensitiveCompare(req.name) == .orderedSame }) {
            date = req.date
            loadForEditing(ex)
        }
        store.editRequest = nil
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Date

    private var dateCard: some View {
        Card {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .font(.headline)
                .tint(Theme.accent)
        }
    }

    // MARK: - Today's session

    private var todaySessionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("today's session")
                        .font(.caption.weight(.heavy)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(todayExercises.count) ex · \(todaySetCount) sets")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(todayExercises) { ex in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Theme.readableName(ex.name))
                            .font(.subheadline.weight(.heavy)).tracking(0.5)
                        Text(ex.sets.map(\.token).joined(separator: "   "))
                            .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent)
                            .frame(width: 4)
                            .padding(.vertical, 8)
                    }
                    .onTapGesture { loadForEditing(ex) }
                }
            }
        }
    }

    private var todaySetCount: Int { todayExercises.reduce(0) { $0 + $1.sets.count } }

    // MARK: - Exercise selector

    private var exerciseCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    focus = nil
                    showingPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Text(name.isEmpty ? "choose exercise" : Theme.readableName(name))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let last = lastEntry {
                    Label {
                        Text("last: " + last.sets.map(\.token).joined(separator: "  "))
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Add set

    private var addSetCard: some View {
        Card {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    if isBodyweight {
                        bigField(title: "+ kg", text: $addedText,
                                 keyboard: .decimalPad, focusValue: .weight)
                    } else {
                        bigField(title: "Weight · kg", text: $weightText,
                                 keyboard: .decimalPad, focusValue: .weight)
                    }
                    bigField(title: "Reps", text: $repsText,
                             keyboard: .numberPad, focusValue: .reps)
                }

                Button { addSet() } label: {
                    Text("+ add set")
                        .font(.subheadline.weight(.heavy)).tracking(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.glass)
                .tint(Theme.accent)
                .disabled(!canAddSet)

                // Muted, secondary control — only relevant for the odd bodyweight lift.
                Button {
                    isBodyweight.toggle()
                    if isBodyweight { weightText = "" } else { addedText = "" }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isBodyweight ? "checkmark.circle.fill" : "circle")
                        Text("bodyweight exercise")
                    }
                    .font(.caption)
                    .foregroundStyle(isBodyweight ? Theme.accent : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rest timer

    private var restTimerCard: some View {
        Card {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("rest")
                        .font(.caption.weight(.heavy)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: restStart ?? Date(), by: 1)) { context in
                        Text(restElapsed(at: context.date))
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Button { restStart = Date() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2.weight(.bold))
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Button { restStart = nil } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func restElapsed(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(restStart ?? now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Current sets

    private var setsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("current sets")
                    .font(.caption.weight(.heavy)).tracking(1.5)
                    .foregroundStyle(.secondary)
                ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent, in: Circle())
                        Text(loadLabel(set))
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text("× \(set.reps)").font(.title3.weight(.heavy))
                        Button {
                            sets.removeAll { $0.id == set.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    if let last = sets.last {
                        sets.append(WorkSet(weight: last.weight, added: last.added, reps: last.reps))
                        restStart = Date()
                    }
                } label: {
                    Label("repeat last set", systemImage: "arrow.uturn.down")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.accent)
            }
        }
    }

    // MARK: - Finish

    private var finishButton: some View {
        Button {
            Task { await finishExercise() }
        } label: {
            HStack {
                if store.isBusy { ProgressView().tint(.white) }
                Text(finishTitle)
                    .font(.headline.weight(.heavy)).tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .disabled(!canFinish)
    }

    private var finishTitle: String {
        let alreadyLogged = todayExercises.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return alreadyLogged ? "update exercise" : "finish exercise"
    }

    // MARK: - Helpers

    private func bigField(title: String, text: Binding<String>,
                          keyboard: UIKeyboardType, focusValue: Field) -> some View {
        VStack(spacing: 6) {
            Text(title.lowercased())
                .font(.caption.weight(.heavy)).tracking(1)
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(keyboard)
                .focused($focus, equals: focusValue)
                .multilineTextAlignment(.center)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.bigFieldHeight)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(focus == focusValue ? Theme.accent : .white.opacity(0.15),
                                      lineWidth: focus == focusValue ? 2 : 0.8)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func addSet() {
        guard let reps = parsedReps else { return }
        let added = isBodyweight ? parsedAdded : nil
        sets.append(WorkSet(weight: isBodyweight ? nil : parsedWeight,
                            added: (added ?? 0) > 0 ? added : nil,
                            reps: reps))
        repsText = ""
        focus = nil
        restStart = Date()   // start resting the moment a set lands
    }

    /// Row label for a logged set: "82.5 kg", "BW +5 kg" or "Bodyweight".
    private func loadLabel(_ set: WorkSet) -> String {
        if let w = set.weight { return "\(WorkSet.formatWeight(w)) kg" }
        if let a = set.added, a > 0 { return "BW +\(WorkSet.formatWeight(a)) kg" }
        return "Bodyweight"
    }

    /// Load an already-logged exercise back into the input area so its sets can be edited.
    private func loadForEditing(_ ex: ExerciseEntry) {
        name = ex.name
        sets = ex.sets
        isBodyweight = ex.sets.first?.isBodyweight ?? false
        weightText = ""; addedText = ""; repsText = ""
        restStart = nil
    }

    private func finishExercise() async {
        let entry = ExerciseEntry(name: name.trimmingCharacters(in: .whitespaces), sets: sets)
        let result = await store.commit(entry, on: date,
                           message: "Log \(entry.name) \(Session.dateFormatter.string(from: date))")
        // Reset on a push OR an offline queue — both keep the entry; only a hard
        // failure leaves the input so the user can retry. Today's session card
        // keeps the record either way.
        if result != .failed {
            name = ""; sets = []; weightText = ""; addedText = ""; repsText = ""; isBodyweight = false
            restStart = nil
            focus = nil
        }
    }
}

/// A frosted-glass container used to group content into cards.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.glassCard() }
}
