import SwiftUI

/// Live session logger: shows the lifts already logged for the selected day,
/// plus an input area to build up one lift's sets and "finish" it — which
/// saves it beside the rest of the log and resets the input for the next.
///
/// Bold / gym-friendly styling: big touch targets, a strong accent, chunky
/// buttons and oversized number fields you can hit mid-set.
struct LogView: View {
    @EnvironmentObject var store: Store

    @State private var date = Date()
    /// The date was picked on purpose — the pill, or a lift opened from
    /// History — rather than inherited from a stale view or an old draft. Only
    /// a deliberate date skips the wrong-day check at finish.
    @State private var dateChosen = false
    /// What was about to happen on a day that isn't today and wasn't chosen —
    /// the first set of a lift, or finishing it — held while the dialog asks.
    private enum DayCheck: Identifiable {
        case set(WorkSet), finish
        var id: String { if case .finish = self { return "finish" } else { return "set" } }
    }
    @State private var dayCheck: DayCheck?
    /// The logged line the lift in the fields came from — opened from
    /// History or the day's card, or picked when already logged. Finishing
    /// replaces that line and no other: a day can have the lift twice.
    @State private var editing: LineRef?
    /// Something wants the input area — a prescription, a lift opened to edit
    /// — while sets are landed in it. Held until the lifter says which wins.
    private enum Replace: Identifiable {
        case prescription, edit(ExerciseEntry, Date, LineRef?)
        var id: String { if case .edit(let ex, _, _) = self { return "edit-\(ex.name)" } else { return "rx" } }
    }
    @State private var pendingReplace: Replace?
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var sets: [WorkSet] = []
    /// The calendar under the date pill is open.
    @State private var pickingDate = false

    @State private var isBodyweight = false
    @State private var weightText = ""
    @State private var addedText = ""
    @State private var repsText = ""

    @State private var showingPicker = false
    /// The lift card the picker grows out of, and shrinks back into.
    @Namespace private var pickerZoom
    /// The sets Coach prescribed, shown as a target and used to prefill each next set.
    @State private var plan: [WorkSet]?
    /// Exercises still to come after this one, when Coach handed over a session.
    @State private var queue: [ExerciseEntry] = []
    /// How long to rest before the timer says you're due. Persisted: it's a habit.
    @AppStorage(Prefs.restTarget) private var restTarget = 90
    /// The bar and the plates the calculator has to work with. Set in Settings.
    @AppStorage(Prefs.barWeight) private var barWeight: Double = 20
    @AppStorage(Prefs.plateInventory) private var inventory = PlateInventory.standard
    /// Exercises on a bar other than the default — seal rows on the 10, say.
    @AppStorage(Prefs.barOverrides) private var barOverrides = BarOverrides()

    /// The bar for the exercise in the field: its own if it has one, else the default.
    private var effectiveBar: Double { barOverrides.bar(for: name) ?? barWeight }
    /// Haptic triggers — bumped on the event, never read.
    /// Set once the saved draft has been looked at, so a view rebuild can't
    /// restore over the top of live work.
    @State private var restored = false
    @State private var setAdded = 0
    /// The set that just landed, lit orange for a moment.
    @State private var flashedSet: UUID?
    @State private var exerciseFinished = 0
    @State private var recordSet = 0
    @StateObject private var strava = StravaService.shared
    @AppStorage(Prefs.stravaEnabled) private var stravaEnabled = true
    @State private var stravaStatus: String?
    @State private var stravaError: String?
    /// When non-nil, the rest clock is running from this instant.
    @State private var restStart: Date?
    @FocusState private var focus: Field?
    private enum Field { case weight, reps }

    /// The big numbers follow Dynamic Type: sized to read at a glance
    /// mid-set, and larger for whoever has asked for larger. The field and
    /// its font are capped where two of them would no longer fit side by side.
    @ScaledMetric(relativeTo: .title2) private var liftNameSize: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var restClockSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var fieldNumberSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var fieldHeight: CGFloat = Theme.bigFieldHeight

    /// The selected day's session, if anything is logged on it.
    private var todaySession: Session? {
        let key = Session.dateFormatter.string(from: date)
        return store.sessions.first { $0.dateString == key }
    }

    /// Exercises already saved for the selected day.
    private var todayExercises: [ExerciseEntry] { todaySession?.exercises ?? [] }

    /// The lift as already logged on the day in hand, under any spelling.
    private func loggedToday(_ lift: String) -> ExerciseEntry? {
        todayExercises.first { Analytics.matches($0.name, lift) }
    }

    /// The line `ex` is on the day in hand.
    private func lineRef(_ ex: ExerciseEntry?) -> LineRef? {
        guard let ex, let session = todaySession else { return nil }
        return LineRef(ex, in: session)
    }

    private var lastEntry: ExerciseEntry? {
        name.isEmpty ? nil : store.lastEntry(for: name, before: date)
    }

    private var parsedWeight: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedAdded: Double? { Double(addedText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedReps: Int? { Int(repsText) }
    private var canAddSet: Bool { parsedReps != nil && (isBodyweight || parsedWeight != nil) }
    private var canFinish: Bool { !name.isEmpty && !sets.isEmpty && !store.isBusy }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    /// "Tue 9 Sep" — the day in the pill, for the banner and the dialog.
    private var dayLabel: String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
    /// "sun 18 oct" for the pill: lowercase like the app's labels, the same
    /// shape as History's day headers.
    private var pillLabel: String {
        date.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
            .locale(Locale(identifier: "en_GB"))).replacingOccurrences(of: ",", with: "").lowercased()
    }
    /// The catch: a day that isn't today, wasn't picked, and isn't a session
    /// that ran past midnight is probably a mistake. Ask before it's a line.
    private var needsDayCheck: Bool {
        DayGuard.needsCheck(date: date, chosen: dateChosen, sessionStart: store.sessionStart(on: date))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !todayExercises.isEmpty { todaySessionCard }
                    if store.sessions.isEmpty && !store.isBusy { emptyLogCard }
                    if !isToday { dayBanner }
                    sectionLabel("add lift")
                    exerciseCard
                    addSetCard
                    if !sets.isEmpty { setsCard }
                    finishButton
                    if !queue.isEmpty { upNext }
                    if !store.status.isEmpty {
                        Text(store.status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .dismissesKeyboardOnTap()
            // The rest clock is pinned, not scrolled: between sets it's the one
            // thing on the screen you look at, and it must never be a swipe away.
            .safeAreaInset(edge: .bottom) {
                if restStart != nil {
                    restTimerCard
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: restStart != nil)
            .background(Theme.backgroundView)
            .navigationTitle("log")
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(history: store.knownExercises) { picked in
                    // Switching exercise starts a fresh set list for the new
                    // movement — or, for a lift already logged today, its sets as
                    // they stand: finishing updates that line, never replaces it blind.
                    if picked.caseInsensitiveCompare(name) != .orderedSame {
                        let done = loggedToday(picked)
                        editing = lineRef(done)
                        sets = done?.sets ?? []
                        if let first = done?.sets.first { isBodyweight = first.isBodyweight }
                        plan = nil
                        restStart = nil
                        // A day opened for one lift was chosen for that lift;
                        // another lift has to be confirmed for it again.
                        dateChosen = false
                    }
                    name = picked
                }
                .navigationTransition(.zoom(sourceID: "lift", in: pickerZoom))
            }
            .toolbar {
                // The date as a compact pill up here, not a whole card under the
                // title: on a gym screen that card-height belongs to the number pad.
                ToolbarItem(placement: .topBarTrailing) {
                    // Our own pill, not the system picker's: that one writes
                    // "18 Oct 2026" however it's asked. A tap opens the calendar.
                    Button { pickingDate = true } label: {
                        Text(pillLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isToday ? Color.primary : Theme.warning)
                            .pill()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Logging for \(dayLabel), change day")
                    .popover(isPresented: $pickingDate) {
                        DatePicker("Day",
                                   selection: Binding(get: { date },
                                                      set: { date = $0; dateChosen = true; pickingDate = false }),
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(Theme.accent)
                            .padding()
                            .frame(minWidth: 320)
                            .presentationCompactAdaptation(.popover)
                    }
                }
                // Our capsule, not iOS 26's glass bubble round it.
                .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            // 11. Feel: a tap that lands a set should be felt, and finishing more so.
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: setAdded)
            .sensoryFeedback(.success, trigger: exerciseFinished)
            // A record lands on top of the ordinary set buzz: a heavy hit after a
            // medium one, which reads as "more" without a second haptic vocabulary.
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: recordSet)
            .refreshable { await store.load() }
            .onAppear { restoreDraft(); refreshDay(); applyEditRequest(); applyPrescription() }
            .confirmationDialog(
                "Discard \(sets.count) landed \(sets.count == 1 ? "set" : "sets") of \(Theme.readableName(name))?",
                isPresented: Binding(get: { pendingReplace != nil }, set: { if !$0 { pendingReplace = nil } }),
                titleVisibility: .visible, presenting: pendingReplace
            ) { replace in
                Button("Discard and continue", role: .destructive) { resume(replace) }
                Button("Keep them", role: .cancel) {
                    if case .prescription = replace { store.prescriptionRequest = [] }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDay() } }
            .confirmationDialog(
                "Logging \(Theme.readableName(name)) on \(dayLabel) — that isn't today.",
                isPresented: Binding(get: { dayCheck != nil }, set: { if !$0 { dayCheck = nil } }),
                titleVisibility: .visible, presenting: dayCheck
            ) { check in
                Button("Log on today instead") {
                    date = Date()
                    dateChosen = true
                    resume(check)
                }
                Button("Keep \(dayLabel)") {
                    dateChosen = true
                    resume(check)
                }
                Button("Cancel", role: .cancel) {}
            }
            // Everything in flight, saved on every change — one equatable value,
            // so it's one modifier rather than one per field.
            .onChange(of: currentDraft) { _, draft in store.saveDraft(draft) }
            .onChange(of: restStart) { _, _ in syncRest() }
            .onChange(of: restTarget) { _, _ in syncRest() }
            .onChange(of: store.draftRevision) { _, _ in takeInOutsideDraft() }
            .onChange(of: store.editRequest) { _, _ in applyEditRequest() }
            .onChange(of: store.prescriptionRequest) { _, _ in applyPrescription() }
        }
    }

    /// What's in flight, or nil when nothing is worth keeping.
    private var currentDraft: SessionDraft? {
        let draft = SessionDraft(date: date, name: name, sets: sets, isBodyweight: isBodyweight,
                                 weightText: weightText, addedText: addedText, repsText: repsText,
                                 plan: plan, queue: queue, restStart: restStart,
                                 dateChosen: dateChosen, target: editing)
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
        // A backfill on a chosen day stays chosen: no second "that isn't today".
        dateChosen = d.dateChosen ?? false
        editing = d.target
        name = d.name
        sets = d.sets
        isBodyweight = d.isBodyweight
        weightText = d.weightText; addedText = d.addedText; repsText = d.repsText
        plan = d.plan
        queue = d.queue
        if let start = d.restStart, Date().timeIntervalSince(start) < 30 * 60 { restStart = start }
        // Whether or not a rest came back, the lock screen must agree: this is
        // what clears a Live Activity left over from a session that just stopped.
        syncRest()
    }

    /// A set landed from the lock screen: the draft moved without this screen
    /// knowing. Take it back in whole, then line up the next set as `land` would.
    private func takeInOutsideDraft() {
        guard let d = store.draft else { return }
        let grew = d.sets.count > sets.count
        date = d.date
        dateChosen = d.dateChosen ?? dateChosen
        editing = d.target
        name = d.name
        sets = d.sets
        isBodyweight = d.isBodyweight
        plan = d.plan
        queue = d.queue
        restStart = d.restStart
        if grew {
            if record(at: sets.count - 1) != nil { recordSet += 1 }
            setAdded += 1
            if let plan, sets.count < plan.count { prefill(plan[sets.count]) }
        }
    }

    /// Load a prescription from Coach. The first set's numbers go in the fields
    /// and the whole plan shows as a target; sets fill in as you actually do them,
    /// each one prefilling the next — 3x5 becomes tap, tap, tap.
    private func applyPrescription() {
        guard let first = store.prescriptionRequest.first else { return }
        // Sets landed for another lift are not thrown away for a plan: ask.
        // The request stays in the store until the answer.
        if !sets.isEmpty && !name.isEmpty {
            pendingReplace = .prescription
            return
        }
        // A prescription is for today, whatever day was open before it: a
        // past day picked for a correction must not swallow a whole session.
        date = Date()
        dateChosen = false
        store.recordPlan(store.prescriptionRequest, on: date)
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
        // Already done today: the plan adds to what's logged rather than
        // replacing it, so the sets on file come along and the plan follows them.
        let logged = loggedToday(rx.name)
        editing = lineRef(logged)
        let done = logged?.sets ?? []
        sets = done
        plan = done + rx.sets
        isBodyweight = rx.sets.first?.isBodyweight ?? false
        prefill(rx.sets.first)
        // The lock screen names the lift and its next set; both just changed.
        syncRest()
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
        if let session = store.sessions.first(where: { $0.dateString == key }) {
            // The very line History opened — the back-off line, not the
            // first squat of the day — else the lift by name as before.
            let exercises = session.exercises
            let ex = req.line.flatMap { $0.index(in: exercises) }.map { exercises[$0] }
                ?? exercises.first(where: { $0.name.caseInsensitiveCompare(req.name) == .orderedSame })
            if let ex { edit(ex, on: req.date, line: LineRef(ex, in: session)) }
        }
        store.editRequest = nil
    }

    /// A view can outlive the day it was made on, and a lift opened from History
    /// leaves its date behind. With nothing in flight, the date is today again.
    private func refreshDay() {
        let idle = name.isEmpty && sets.isEmpty && queue.isEmpty
        if DayGuard.shouldReset(date: date, chosen: dateChosen, idle: idle) { date = Date() }
    }

    /// Where the log lives, in the words the Files app or GitHub uses.
    private var logHome: String {
        store.storage == .icloud ? "Files ▸ Grepp ▸ training.md" : "\(store.owner)/\(store.repo) ▸ \(store.path)"
    }

    /// The first thing a new lifter sees. An empty file looks like a broken one
    /// until someone says it's meant to be, so this says it, once, and goes the
    /// moment the first exercise lands.
    private var emptyLogCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Barbell(height: 18)
                    Text("your log is empty, and that's the point")
                        .font(.caption.weight(.heavy)).tracking(1)
                        .foregroundStyle(.secondary)
                }
                Text("It fills with what you lift, one line per lift per day, in a text file you own at \(logHome).")
                    .font(.subheadline)
                Text("2026-09-11 squat 60x5 60x5 60x5")
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner))
                Text("Trained before? The Coach can bring your last few weeks in.")
                    .font(.subheadline)
                Button {
                    store.selectedTab = 3
                } label: {
                    Label("bring my history in", systemImage: "bubble.left.and.bubble.right")
                        .font(.footnote.weight(.bold))
                }
                .buttonStyle(.panel)
                .tint(Theme.accent)
            }
        }
    }

    /// Said out loud whenever the sets are going somewhere other than today.
    private var dayBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Logging for \(dayLabel), not today")
                .font(.footnote.weight(.semibold))
            Spacer()
            Button("today") {
                date = Date()
                dateChosen = false
            }
            .font(.footnote.weight(.bold))
            .buttonStyle(.panel)
            .tint(.orange)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.corner))
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
                    Text("\(todayExercises.count == 1 ? "1 lift" : "\(todayExercises.count) lifts") · \(todaySetCount) sets")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                let records = Analytics.records(in: store.sessions)[Session.dateFormatter.string(from: date)] ?? [:]
                ForEach(todayExercises) { ex in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(Theme.readableName(ex.name))
                                    .font(.subheadline.weight(.heavy)).tracking(0.5)
                                if let record = records[MuscleMap.canonical(ex.name)] { RecordBadge(record: record) }
                            }
                            Text(ex.sets.map(\.token).joined(separator: "  "))
                                .font(.system(.footnote, design: .monospaced).weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        // A tap loads the lift back into the fields to change it.
                        Image(systemName: "pencil")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent)
                            .frame(width: 4)
                            .padding(.vertical, 8)
                    }
                    .onTapGesture { edit(ex, on: date, line: lineRef(ex)) }
                }
                if stravaEnabled, strava.isConnected { stravaRow }
            }
        }
    }

    private var todaySetCount: Int { todayExercises.reduce(0) { $0 + $1.sets.count } }

    // MARK: - Strava

    /// Post the day to Strava as a Weight Training activity with the lines in
    /// its description. Posted already, and grown since: the same button
    /// updates it rather than posting twice.
    private var stravaRow: some View {
        let posted = store.stravaActivity(on: date) != nil
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await postToStrava() }
            } label: {
                HStack(spacing: 8) {
                    if strava.isBusy { ProgressView().controlSize(.small) }
                    Text(posted ? "Update on Strava" : "Post to Strava")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.panel)
            .tint(Theme.strava)
            .disabled(strava.isBusy || todayExercises.isEmpty)
            if let stravaStatus {
                Text(stravaStatus).font(.caption2).foregroundStyle(.secondary)
            }
            if let stravaError {
                Text(stravaError).font(.caption2).foregroundStyle(Theme.warning)
            }
        }
    }

    private func postToStrava() async {
        stravaError = nil
        stravaStatus = nil
        do {
            switch try await StravaPoster.post(Session(date: date, exercises: todayExercises), store: store, strava: strava) {
            case .posted: stravaStatus = "Posted to Strava ✓"
            case .updated: stravaStatus = "Updated on Strava ✓"
            }
        } catch {
            stravaError = error.localizedDescription
        }
    }

    // MARK: - Exercise selector

    private var exerciseCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    focus = nil
                    showingPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Text(name.isEmpty ? "choose lift" : Theme.readableName(name))
                            .font(.system(size: liftNameSize, weight: .bold))
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .matchedTransitionSource(id: "lift", in: pickerZoom)
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
                // The way up to the first working set, from the plan's top
                // set or the weight in the field, with plates a side in
                // brackets. Only before the first set lands: once the lift is
                // under way the warm-up is behind you.
                if sets.isEmpty, !isBodyweight, let top = plan?.first?.weight ?? parsedWeight,
                   let rungs = WarmUp.ramp(to: top, bar: effectiveBar, inventory: inventory) {
                    Label {
                        Text("warm-up  " + WarmUp.line(rungs, bar: effectiveBar))
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "flame")
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityLabel("warm-up: " + WarmUp.line(rungs, bar: effectiveBar))
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
                        bigField(title: "added", unit: "kg", text: $addedText,
                                 hint: ghost?.added.map { WorkSet.formatWeight($0) },
                                 keyboard: .decimalPad, focusValue: .weight)
                    } else {
                        bigField(title: "weight", unit: "kg", text: $weightText,
                                 hint: ghost?.weight.map { WorkSet.formatWeight($0) },
                                 keyboard: .decimalPad, focusValue: .weight)
                    }
                    bigField(title: "reps", unit: "reps", text: $repsText,
                             hint: ghost.map { String($0.reps) },
                             keyboard: .numberPad, focusValue: .reps)
                }

                // What to load, the moment there's a weight in the field — and the
                // bar menu with it, even when the weight is under the bar, since
                // that is exactly when a lighter bar needs picking.
                if !isBodyweight, let target = parsedWeight {
                    plateLine(PlateMath.load(target, bar: effectiveBar, inventory: inventory))
                }

                // The one thing you do most on this screen, so it's the one
                // glass button — but only once there's a set to add: a disabled
                // glass button fades to nothing and reads as broken, so until
                // then it's a visible, muted pill.
                let addSetButton = Button { addSet() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .symbolEffect(.bounce, value: setAdded)
                        Text("add set")
                    }
                    .font(.subheadline.weight(.heavy)).tracking(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .tint(Theme.accent)
                .disabled(!canAddSet)
                if canAddSet {
                    addSetButton.buttonStyle(.panelProminent)
                } else {
                    addSetButton.buttonStyle(.panel)
                }

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
            let label: String = due ? "ready" : "rest"
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Label and clock on one line: the card is pinned over the
                    // number pad, so every point of height comes out of that.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(label)
                            .font(.caption.weight(.heavy)).tracking(2)
                            .foregroundStyle(due ? Theme.onAccent : Color.secondary)
                        Text(clock(elapsed))
                            .font(.system(size: restClockSize, weight: .heavy))
                            .fontWidth(.condensed)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                            .foregroundStyle(due ? Theme.onAccent : Theme.accent)
                            // Digits roll over rather than snap — 0:59 to 1:00
                            // reads like a stopwatch, not a re-render.
                            .contentTransition(.numericText())
                            .animation(.snappy, value: elapsed)
                    }
                    Spacer(minLength: 8)
                    restTargetMenu
                    Button { restStart = Date() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Restart rest")
                    Button { restStart = nil } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End rest")
                }
                // A thin bar filling toward the target — readable at a glance,
                // mid-set, from across the rack.
                ProgressView(value: Double(min(elapsed, restTarget)), total: Double(restTarget))
                    .tint(due ? Theme.onAccent : Theme.accent)
                    .animation(.linear(duration: 1), value: elapsed)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Due, the whole card goes solid accent. That's the "in your face":
            // not a label changing colour but the biggest thing on screen changing.
            .background(due ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
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
                .frame(height: 34)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rest target")
        .accessibilityValue(clock(restTarget))
    }

    /// Keep the world outside the app in step with the clock: the "rest's up"
    /// notification set for when the target lands, and the Live Activity that
    /// shows the countdown on the lock screen. Both move if the target changes
    /// mid-rest and go away when the rest ends. Neither shows in the foreground —
    /// there, the card is the clock.
    private func syncRest() {
        RestSignals.sync(currentDraft, target: restTarget)
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
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        Text(set.loadLabel)
                            .font(.body.weight(.semibold))
                        if let record = record(at: idx) { RecordBadge(record: record) }
                        Spacer()
                        Text("× \(set.reps)").font(.title3.weight(.heavy))
                        Button {
                            withAnimation(.snappy) { sets.removeAll { $0.id == set.id } }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Theme.accent.opacity(flashedSet == set.id ? 0.28 : 0),
                                in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .padding(.horizontal, -6)
                    // Drops in from the readout above and settles with a bounce.
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
                            .combined(with: .offset(y: -24)),
                        removal: .opacity.combined(with: .scale(scale: 0.9))))
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
        // Quiet on purpose: it's pressed once a lift, and it sits right under
        // the sets, where a thumb heading for "add set" lands. Add set is the
        // loud one.
        .buttonStyle(.panel)
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
        // The day is on the pill and the banner already; the button names the act.
        return alreadyLogged ? "update lift" : "finish lift"
    }

    // MARK: - Helpers

    /// The set this one would repeat: the same set last time, else its last
    /// set. Shown faintly in the empty fields as a hint, never entered.
    private var ghost: WorkSet? {
        guard let last = lastEntry?.sets, !last.isEmpty else { return nil }
        return sets.count < last.count ? last[sets.count] : last.last
    }

    /// A big readout: a soft well with the number large in the serif, its unit
    /// beside it. Empty, it shows last time's figure faintly instead of a "0"
    /// that reads as a value. The live field gets a terracotta ring.
    private func bigField(title: String, unit: String, text: Binding<String>, hint: String?,
                          keyboard: UIKeyboardType, focusValue: Field) -> some View {
        let focused = focus == focusValue
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(focused ? Theme.accent : Theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // While typing, the field; otherwise a Text over it, so a number
                // that changes under you — the next set prefilled, another lift
                // picked — rolls like a counter instead of snapping. A text field
                // can't animate its own digits.
                ZStack(alignment: .leading) {
                    TextField(text: text, prompt: Text(hint ?? "–").foregroundStyle(.tertiary)) {
                        Text(title)
                    }
                    .keyboardType(keyboard)
                    .focused($focus, equals: focusValue)
                    .foregroundStyle(.primary)
                    .opacity(focused ? 1 : 0)
                    if !focused {
                        Text(text.wrappedValue.isEmpty ? (hint ?? "–") : text.wrappedValue)
                            .foregroundStyle(text.wrappedValue.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                            .contentTransition(.numericText())
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(size: min(fieldNumberSize, 58), weight: .medium, design: .serif))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .animation(.snappy(duration: 0.35), value: text.wrappedValue)
                .animation(.snappy(duration: 0.35), value: hint)
                // As wide as the number, so the unit sits right after it;
                // a tap anywhere in the window still focuses it.
                .fixedSize(horizontal: true, vertical: false)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                    .fixedSize()
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: min(fieldHeight, Theme.bigFieldHeight * 1.6) + 20)
        // A soft well in the card; only the live one gets a ring.
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
                .opacity(focused ? 1 : 0)
        )
        .animation(.snappy(duration: 0.2), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focus = focusValue }
    }

    private func addSet() {
        guard let reps = parsedReps else { return }
        let added = isBodyweight ? parsedAdded : nil
        land(WorkSet(weight: isBodyweight ? nil : parsedWeight,
                     added: (added ?? 0) > 0 ? added : nil,
                     reps: reps))
    }

    /// The day is settled: do what the dialog interrupted.
    private func resume(_ check: DayCheck) {
        switch check {
        case .set(let set): land(set)
        case .finish: Task { await finishExercise() }
        }
    }

    /// A set is done: record it, start the rest, feel it, and line up the next.
    /// The one path for both add-set and repeat-last.
    private func land(_ set: WorkSet) {
        // The first set of a lift is where a wrong day gets caught — before
        // anything is on the clock, not after the whole lift is done.
        if sets.isEmpty, needsDayCheck {
            dayCheck = .set(set)
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
            sets.append(set)
            flashedSet = set.id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.5)) {
                if flashedSet == set.id { flashedSet = nil }
            }
        }
        // Only now do the typed reps go: a Cancel in the day dialog keeps them.
        repsText = ""
        focus = nil
        // The day's clock starts only for today's session — a set corrected on
        // a past day must not make that day "the session in progress".
        if isToday { store.noteSetLanded(on: date) }
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


    /// "per side  25 · 5 · 2.5 · 1.25" for the weight in the field, or "empty bar".
    /// When the exact weight can't be made from a standard set, the nearest load
    /// below and what it actually weighs: "per side  25 · 5 · 2.5  ≈ 85".
    private func plateLine(_ load: PlateMath.Load?) -> some View {
        let text: String
        if let load, load.perSide.isEmpty {
            text = "empty bar"
        } else if let load {
            let plates = load.perSide.map { PlateMath.label($0) }.joined(separator: " · ")
            let approx = load.isApproximate ? "  ≈ \(PlateMath.label(load.total))" : ""
            text = "per side  " + plates + approx
        } else if let target = parsedWeight, target > effectiveBar {
            text = "more than a rack holds"
        } else {
            text = "lighter than the bar"
        }
        // One line while the plates and the bar pill fit side by side; when
        // five plates a side push the pill off the edge, the plates take the
        // line and the pill drops under them, still on the right.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                plateLabel(text).fixedSize()
                Spacer(minLength: 8)
                barMenu
            }
            VStack(alignment: .leading, spacing: 6) {
                plateLabel(text).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    barMenu
                }
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func plateLabel(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
        } icon: {
            Image(systemName: "circlebadge.2.fill")
        }
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
            HStack(spacing: 4) {
                Text("\(PlateMath.label(effectiveBar)) bar")
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(barOverrides.bar(for: name) == nil ? Color.secondary : Theme.accent)
            .pill()
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(name.isEmpty)
        .accessibilityLabel("Bar")
        .accessibilityValue("\(PlateMath.label(effectiveBar)) kg")
    }

    /// Open a logged lift for editing — unless sets for another lift are
    /// landed and unfinished, in which case ask before they go.
    private func edit(_ ex: ExerciseEntry, on day: Date, line: LineRef?) {
        if !sets.isEmpty, ex.name.caseInsensitiveCompare(name) != .orderedSame {
            pendingReplace = .edit(ex, day, line)
            return
        }
        // A planned lift with nothing landed yet isn't lost to the edit: it
        // goes back to the front of the queue and returns once the edit is done.
        if let plan, sets.isEmpty, !name.isEmpty, !Analytics.matches(name, ex.name) {
            queue.insert(ExerciseEntry(name: name, sets: plan), at: 0)
        }
        date = day
        dateChosen = true   // opened from that day on purpose
        loadForEditing(ex)
        editing = line
    }

    /// The lifter chose: what was held goes ahead, over the landed sets.
    private func resume(_ replace: Replace) {
        switch replace {
        case .prescription:
            sets = []
            applyPrescription()
        case .edit(let ex, let day, let line):
            sets = []
            edit(ex, on: day, line: line)
        }
    }

    /// Load an already-logged exercise back into the input area so its sets can be edited.
    private func loadForEditing(_ ex: ExerciseEntry) {
        name = ex.name
        sets = ex.sets
        isBodyweight = ex.sets.first?.isBodyweight ?? false
        weightText = ""; addedText = ""; repsText = ""
        plan = nil
        restStart = nil
        syncRest()
    }

    private func finishExercise() async {
        // Caught at the first set as a rule; this is for a lift whose sets came
        // in some other way — a restored draft, the lock screen.
        if needsDayCheck {
            dayCheck = .finish
            return
        }
        let entry = ExerciseEntry(name: MuscleMap.key(name), sets: sets)
        let committed = sets
        let key = Session.dateFormatter.string(from: date)
        // The line it was opened from, if that was on this day; moved to
        // another day since, it's a fresh log there.
        let line = editing?.day == key ? editing : nil
        let result = await store.commit(entry, on: date, replacing: line,
                           message: "Log \(entry.name) \(key)")
        // Reset on a push OR an offline queue — both keep the entry; only a hard
        // failure leaves the input so the user can retry. Today's session card
        // keeps the record either way.
        if result != .failed {
            // A no-op when nothing was prescribed; an edit of a prescribed lift
            // still closes its plan.
            store.completePlan(entry, on: date)
            exerciseFinished += 1
            focus = nil
            // Today's session to Apple Health, when that is on: the whole
            // day as one workout, replaced as it grows.
            if isToday, let session = store.sessions.first(where: { $0.dateString == Session.dateFormatter.string(from: date) }) {
                Task { await HealthWriter.sync(session, store: store) }
            }
            // The day stays for the next lift — a backfill is several — but it
            // has to be confirmed again: one lift on purpose isn't the next.
            dateChosen = false
            // The line now reads as just written: the next update of this
            // lift replaces it, wherever on the day it sits.
            editing = todaySession.flatMap { s in
                let same = s.exercises.filter { Analytics.matches($0.name, entry.name) }
                let hits = same.indices.filter { same[$0].sets == entry.sets }
                let pick = hits.first { $0 == (line?.occurrence ?? 0) } ?? hits.last
                return pick.map { LineRef(same[$0], in: s) }
            }
            // A set landed while the save was in flight — from the pad or the
            // lock screen — is not thrown away: the lift stays in hand with
            // every set shown, one more update away.
            guard sets == committed else { return }
            if !queue.isEmpty {
                // Straight on to the next prescribed lift, fields already filled.
                load(prescription: queue.removeFirst())
            } else {
                name = ""; sets = []; weightText = ""; addedText = ""; repsText = ""; isBodyweight = false
                plan = nil
                editing = nil
                restStart = nil
                refreshDay()
            }
        }
    }
}

