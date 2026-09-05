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
    /// The sets Coach prescribed, shown as a target and used to prefill each next set.
    @State private var plan: [WorkSet]?
    /// Exercises still to come after this one, when Coach handed over a session.
    @State private var queue: [ExerciseEntry] = []
    /// How long to rest before the timer says you're due. Persisted: it's a habit.
    @AppStorage("rest_target") private var restTarget = 90
    /// The bar and the plates the calculator has to work with. Set in Settings.
    @AppStorage("bar_weight") private var barWeight: Double = 20
    @AppStorage("plate_inventory") private var inventory = PlateInventory.standard
    /// Exercises on a bar other than the default — seal rows on the 10, say.
    @AppStorage("bar_overrides") private var barOverrides = BarOverrides()

    /// The bar for the exercise in the field: its own if it has one, else the default.
    private var effectiveBar: Double { barOverrides.bar(for: name) ?? barWeight }
    /// Haptic triggers — bumped on the event, never read.
    /// Set once the saved draft has been looked at, so a view rebuild can't
    /// restore over the top of live work.
    @State private var restored = false
    @State private var setAdded = 0
    @State private var exerciseFinished = 0
    @State private var recordSet = 0
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
                    if !todayExercises.isEmpty { todaySessionCard }
                    sectionLabel("add exercise")
                    exerciseCard
                    addSetCard
                    if restStart != nil { restTimerCard }
                    if !sets.isEmpty { setsCard }
                    finishButton
                    if !queue.isEmpty { upNext }
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
                        plan = nil
                        restStart = nil
                    }
                    name = picked
                }
            }
            .toolbar {
                // The date as a compact pill up here, not a whole card under the
                // title: on a gym screen that card-height belongs to the number pad.
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            // 11. Feel: a tap that lands a set should be felt, and finishing more so.
            .sensoryFeedback(.impact(weight: .medium), trigger: setAdded)
            .sensoryFeedback(.success, trigger: exerciseFinished)
            // A record lands on top of the ordinary set buzz: a heavy hit after a
            // medium one, which reads as "more" without a second haptic vocabulary.
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: recordSet)
            .refreshable { await store.load() }
            .onAppear { restoreDraft(); applyEditRequest(); applyPrescription() }
            // Everything in flight, saved on every change — one equatable value,
            // so it's one modifier rather than one per field.
            .onChange(of: currentDraft) { _, draft in store.saveDraft(draft) }
            .onChange(of: restStart) { _, _ in syncRestNotification() }
            .onChange(of: restTarget) { _, _ in syncRestNotification() }
            .onChange(of: store.editRequest) { _, _ in applyEditRequest() }
            .onChange(of: store.prescriptionRequest) { _, _ in applyPrescription() }
        }
    }

    /// What's in flight, or nil when nothing is worth keeping.
    private var currentDraft: SessionDraft? {
        let draft = SessionDraft(date: date, name: name, sets: sets, isBodyweight: isBodyweight,
                                 weightText: weightText, addedText: addedText, repsText: repsText,
                                 plan: plan, queue: queue, restStart: restStart)
        return draft.isEmpty ? nil : draft
    }

    /// Pick up where a killed app left off. Only into an empty input area, and
    /// only once per view lifetime. A rest clock older than half an hour is
    /// dropped — that isn't a rest any more.
    private func restoreDraft() {
        guard !restored else { return }
        restored = true
        guard let d = store.draft, name.isEmpty, sets.isEmpty, queue.isEmpty else { return }
        date = d.date
        name = d.name
        sets = d.sets
        isBodyweight = d.isBodyweight
        weightText = d.weightText; addedText = d.addedText; repsText = d.repsText
        plan = d.plan
        queue = d.queue
        if let start = d.restStart, Date().timeIntervalSince(start) < 30 * 60 { restStart = start }
    }

    /// Load a prescription from Coach. The first set's numbers go in the fields
    /// and the whole plan shows as a target; sets fill in as you actually do them,
    /// each one prefilling the next — 3x5 becomes tap, tap, tap.
    private func applyPrescription() {
        guard let first = store.prescriptionRequest.first else { return }
        queue = Array(store.prescriptionRequest.dropFirst())
        store.prescriptionRequest = []
        restStart = nil
        load(prescription: first)
    }

    /// Put a prescribed exercise in the input area. Leaves the rest timer alone on
    /// purpose: between the last set of one lift and the first of the next you're
    /// resting too, and the clock that started at that last set should keep going.
    private func load(prescription rx: ExerciseEntry) {
        name = rx.name
        sets = []
        plan = rx.sets
        isBodyweight = rx.sets.first?.isBodyweight ?? false
        prefill(rx.sets.first)
    }

    private func prefill(_ set: WorkSet?) {
        guard let set else { return }
        // A closure, not `.map(WorkSet.formatWeight)`: passing the method as a
        // function value drops the caller's actor isolation, which the MainActor-
        // by-default app target rejects. Same fix as parseSet in WorkoutParser.
        weightText = set.weight.map { WorkSet.formatWeight($0) } ?? ""
        addedText = set.added.flatMap { $0 > 0 ? WorkSet.formatWeight($0) : nil } ?? ""
        repsText = String(set.reps)
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

    // MARK: - Today's session

    private var todaySessionCard: some View {
        Panel {
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
                        Text(ex.sets.map(\.token).joined(separator: "  "))
                            .font(.system(.footnote, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
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
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    focus = nil
                    showingPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Text(name.isEmpty ? "choose exercise" : Theme.readableName(name))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let plan {
                    Label {
                        Text("plan  " + plan.map(\.token).joined(separator: "  "))
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    } icon: {
                        Image(systemName: "target")
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                if let last = lastEntry {
                    Label {
                        Text("last  " + last.sets.map(\.token).joined(separator: "  "))
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
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

                // What to load, the moment there's a weight in the field.
                if !isBodyweight, let target = parsedWeight,
                   let load = PlateMath.load(target, bar: effectiveBar, inventory: inventory) {
                    plateLine(load)
                }

                Button { addSet() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .symbolEffect(.bounce, value: setAdded)
                        Text("add set")
                    }
                    .font(.subheadline.weight(.heavy)).tracking(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                // Bordered, not glass: a disabled glass button fades to nothing and
                // reads as broken. Bordered stays a visible, muted pill — and keeps
                // glass for the one primary action, finish.
                .buttonStyle(.bordered)
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
        TimelineView(.periodic(from: restStart ?? Date(), by: 1)) { context in
            let elapsed = restSeconds(at: context.date)
            let due = elapsed >= restTarget
            let label: String = due ? "READY" : "rest"
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label)
                            .font(.caption.weight(.heavy)).tracking(2)
                            .foregroundStyle(due ? Theme.onAccent : Color.secondary)
                        Text(clock(elapsed))
                            .font(.system(size: 56, weight: .heavy))
                            .fontWidth(.condensed)
                            .monospacedDigit()
                            .foregroundStyle(due ? Theme.onAccent : Theme.accent)
                            // Digits roll over rather than snap — 0:59 to 1:00
                            // reads like a stopwatch, not a re-render.
                            .contentTransition(.numericText())
                            .animation(.snappy, value: elapsed)
                    }
                    Spacer()
                    restTargetMenu
                    Button { restStart = Date() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Button { restStart = nil } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                // A thin bar filling toward the target — readable at a glance,
                // mid-set, from across the rack.
                ProgressView(value: Double(min(elapsed, restTarget)), total: Double(restTarget))
                    .tint(due ? Theme.onAccent : Theme.accent)
                    .animation(.linear(duration: 1), value: elapsed)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Due, the whole card goes solid accent. That's the "in your face":
            // not a label changing colour but the biggest thing on screen changing.
            .background(due ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Material.regularMaterial),
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(due ? 0.22 : 0.12), radius: 12, x: 0, y: 6)
            // A heartbeat while due, driven by the clock's own ticks — nothing
            // repeating forever that has to be babysat.
            .scaleEffect(due && elapsed % 2 == 0 ? 1.015 : 1)
            .animation(.easeInOut(duration: 0.5), value: elapsed)
            .animation(.snappy, value: due)
            // One buzz when rest is up. Only on the way *to* due — a reset
            // flipping it back must not fire a second success.
            .sensoryFeedback(.success, trigger: due) { wasDue, isDue in !wasDue && isDue }
        }
    }

    /// 1:00 / 1:30 / 2:00 / 3:00 — the rests people actually take.
    private var restTargetMenu: some View {
        Menu {
            ForEach([60, 90, 120, 180], id: \.self) { seconds in
                Button { restTarget = seconds } label: {
                    if seconds == restTarget {
                        Label(clock(seconds), systemImage: "checkmark")
                    } else {
                        Text(clock(seconds))
                    }
                }
            }
        } label: {
            Label(clock(restTarget), systemImage: "timer")
                .font(.footnote.weight(.heavy))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Keep the "rest's up" notification in step with the clock: set for when
    /// the target lands, moved if the target changes mid-rest, cancelled when the
    /// rest ends. It only ever shows when the phone is locked or you're elsewhere.
    private func syncRestNotification() {
        guard let start = restStart else { RestNotifier.cancel(); return }
        let remaining = restTarget - Int(Date().timeIntervalSince(start))
        guard remaining > 0 else { RestNotifier.cancel(); return }
        RestNotifier.schedule(in: remaining, next: nextUp)
    }

    /// "squat · 87.5 kg × 5" when the plan knows the next set; nil when it doesn't.
    private var nextUp: String? {
        guard let plan, sets.count < plan.count, !name.isEmpty else { return nil }
        let next = plan[sets.count]
        return "\(Theme.readableName(name)) · \(loadLabel(next)) × \(next.reps)"
    }

    private func restSeconds(at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(restStart ?? now)))
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Current sets

    private var setsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text("current sets")
                    .font(.caption.weight(.heavy)).tracking(1.5)
                    .foregroundStyle(.secondary)
                ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent, in: Circle())
                        Text(loadLabel(set))
                            .font(.body.weight(.semibold))
                        if let record = record(at: idx) { recordBadge(record) }
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
                        land(WorkSet(weight: last.weight, added: last.added, reps: last.reps))
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
                if store.isBusy { ProgressView().tint(Theme.onAccent) }
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

    private var upNextLabel: String {
        let names = queue.map { Theme.readableName($0.name) }.joined(separator: " · ")
        return "next  " + names
    }

    /// The rest of the handed-over session. Dismissable: going off-script is
    /// allowed, and so is deciding you're done.
    private var upNext: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
            Text(upNextLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button { queue = [] } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
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
                .font(.system(size: 40, weight: .heavy))
                .fontWidth(.condensed)
                .monospacedDigit()
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
        repsText = ""
        focus = nil
        land(WorkSet(weight: isBodyweight ? nil : parsedWeight,
                     added: (added ?? 0) > 0 ? added : nil,
                     reps: reps))
    }

    /// A set is done: record it, start the rest, feel it, and line up the next.
    /// The one path for both add-set and repeat-last.
    private func land(_ set: WorkSet) {
        sets.append(set)
        if record(at: sets.count - 1) != nil { recordSet += 1 }
        restStart = Date()   // start resting the moment a set lands
        setAdded += 1
        if let plan, sets.count < plan.count { prefill(plan[sets.count]) }
    }

    /// Is the set at `index` a personal record? Judged against every other day
    /// plus the sets landed before it today. Today's own committed copy of this
    /// exercise is left out, so re-logging it doesn't compare a set to itself.
    private func record(at index: Int) -> Analytics.Record? {
        let key = Session.dateFormatter.string(from: date)
        let past = store.sessions.filter { $0.dateString != key }
        return Analytics.record(for: sets[index], exercise: name, in: past, plus: Array(sets[..<index]))
    }

    private func recordBadge(_ record: Analytics.Record) -> some View {
        let label: String = record == .load ? "PR" : "REP PR"
        return Text(label)
            .font(.caption2.weight(.heavy)).tracking(0.5)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(Theme.onAccent)
    }

    /// "per side  25 · 5 · 2.5 · 1.25" for the weight in the field, or "empty bar".
    /// When the exact weight can't be made from a standard set, the nearest load
    /// below and what it actually weighs: "per side  25 · 5 · 2.5  ≈ 85".
    private func plateLine(_ load: PlateMath.Load) -> some View {
        let text: String
        if load.perSide.isEmpty {
            text = "empty bar"
        } else {
            let plates = load.perSide.map { PlateMath.label($0) }.joined(separator: " · ")
            let approx = load.isApproximate ? "  ≈ \(PlateMath.label(load.total))" : ""
            text = "per side  " + plates + approx
        }
        return HStack(spacing: 8) {
            Label {
                Text(text)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
            } icon: {
                Image(systemName: "circlebadge.2.fill")
            }
            Spacer(minLength: 8)
            barMenu
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// Always names the bar, and it's a menu: a different bar for *this* exercise
    /// is set right here and remembered for it. The default lives in Settings.
    /// Disabled until an exercise is chosen — there's nothing to remember it for.
    private var barMenu: some View {
        Menu {
            ForEach(PlateMath.bars, id: \.self) { kg in
                Button { barOverrides.set(kg, for: name) } label: {
                    if kg == effectiveBar {
                        Label("\(PlateMath.label(kg)) kg", systemImage: "checkmark")
                    } else {
                        Text("\(PlateMath.label(kg)) kg")
                    }
                }
            }
            Divider()
            Button { barOverrides.set(nil, for: name) } label: {
                Text("Default · \(PlateMath.label(barWeight)) kg")
            }
        } label: {
            HStack(spacing: 3) {
                Text("\(PlateMath.label(effectiveBar)) bar")
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(barOverrides.bar(for: name) == nil ? Color.secondary : Theme.accent)
        }
        .disabled(name.isEmpty)
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
        plan = nil
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
            exerciseFinished += 1
            focus = nil
            if !queue.isEmpty {
                // Straight on to the next prescribed lift, fields already filled.
                load(prescription: queue.removeFirst())
            } else {
                name = ""; sets = []; weightText = ""; addedText = ""; repsText = ""; isBodyweight = false
                plan = nil
                restStart = nil
            }
        }
    }
}

/// The raised surface — the number pad and the rest timer, the things you act on.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.glassCard() }
}

/// The flat surface — lists and chrome that should sit in the page, not float.
private struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.panel() }
}
