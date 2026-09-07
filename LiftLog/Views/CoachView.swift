import SwiftUI

/// Ask Claude about your own training. The log goes along with the question, so
/// answers are about *your* squat, not squats in general.
struct CoachView: View {
    @EnvironmentObject var store: Store
    @StateObject private var coach = CoachService()

    @AppStorage("coach_model") private var model: CoachModelChoice = .sonnet
    @AppStorage("coach_show_cost") private var showCost = true
    @State private var draft = ""
    @State private var savingGoals = false
    /// The exact text last committed, so a revised file offers Save again rather
    /// than staying stuck on "Saved".
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()
    @State private var savedGoalsText: String?
    @State private var savedMemoryText: String?
    @State private var savingMemory = false
    @State private var memoryError: String?
    @State private var saveError: String?
    @State private var showingBrief = false
    @State private var showingEvidence = false
    /// The entry to scroll to when Evidence opens from a tapped tag.
    @State private var evidenceTag: String?
    @State private var savedResearchText: String?
    @State private var savingResearch = false
    @State private var researchError: String?
    @State private var savedProgramText: String?
    @State private var savingProgram = false
    @State private var programError: String?
    @State private var showingProgramme = false
    /// Bumped per send, so the arrow bounces on fire.
    @State private var sent = 0
    @FocusState private var inputFocused: Bool

    /// The only thing that can stop Coach working now is a missing key.
    private var hasKey: Bool { CoachCredentials.hasKey }

    var body: some View {
        NavigationStack {
            Group {
                if hasKey { chat } else { needsKey }
            }
            .background(Theme.backgroundView)
            .navigationTitle("Coach")
            // Both, deliberately: onChange catches a request while Coach is already
            // on screen, onAppear catches one that arrives before the tab has ever
            // been built — TabView makes its pages lazily.
            .onChange(of: store.briefRequest) { _, _ in consumeBriefRequest() }
            .onAppear(perform: consumeBriefRequest)
            .sheet(isPresented: $showingEvidence) {
                EvidenceView(focus: evidenceTag)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingProgramme) {
                ProgrammeView { question in ask(question) }
                    .environmentObject(store)
            }
            // A tapped [R3] in a bubble opens the evidence at that entry.
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == CoachContext.evidenceScheme else { return .systemAction }
                evidenceTag = url.lastPathComponent
                showingEvidence = true
                return .handled
            })
            .sheet(isPresented: $showingBrief) {
                BriefView {
                    // The sheet is already dismissing; start the interview behind it.
                    beginGoalsInterview()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingBrief = true } label: {
                        Label("Your brief", systemImage: "person.text.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { evidenceTag = nil; showingEvidence = true } label: {
                        Label("Evidence", systemImage: "books.vertical")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingProgramme = true } label: {
                        Label("Programme", systemImage: "calendar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coach.reset()
                        draft = ""
                        savedGoalsText = nil
                        saveError = nil
                        savedMemoryText = nil
                        memoryError = nil
                        savedResearchText = nil
                        researchError = nil
                        savedProgramText = nil
                        programError = nil
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                    }
                    .disabled(coach.isEmpty)
                }
            }
        }
    }

    // MARK: - Chat

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if coach.isEmpty { intro } else { transcript }
                        if let error = coach.errorText { errorCard(error) }
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding(16)
                }
                .dismissesKeyboardOnTap()
                .onChange(of: coach.messages) { _, _ in scroll(proxy) }
                .onChange(of: coach.errorText) { _, _ in scroll(proxy) }
                // Coming back to a conversation lands on its latest answer, not
                // its first question. Without animation: it's where you were.
                .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            inputBar
        }
    }

    private let bottomAnchor = "coach-bottom"

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private var transcript: some View {
        ForEach(coach.messages) { message in
            switch message.role {
            case .you:
                // A leading spacer with a floor, so a long question wraps inside a
                // bubble instead of becoming a full-width block.
                HStack {
                    Spacer(minLength: 56)
                    Text(message.text)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(Theme.onAccent)
                }
            case .coach:
                coachBubble(message)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask about your training")
                    .font(.title3.weight(.bold))
                Text("Your \(store.path) goes with every question, so answers cite your own dates and loads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(coachingHint, systemImage: hasBrief ? "checkmark.seal" : "doc.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 16)

            Button(action: beginGoalsInterview) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goalsActionTitle)
                            .font(.subheadline.weight(.bold))
                        Text(goalsActionSubtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: hasGoals ? "target" : "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(hasGoals ? Color.secondary : Theme.accent)
                }
                .foregroundStyle(.primary)
                .glassCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)

            ForEach(CoachContext.suggestedQuestions, id: \.self) { question in
                Button {
                    ask(question)
                } label: {
                    HStack {
                        Text(question).font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.footnote)
                    }
                    .foregroundStyle(.primary)
                    .glassCard(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// SwiftUI renders markdown in a string *literal*, but shows a runtime String
    /// verbatim — so the model's **bold** arrives as asterisks unless it's parsed.
    /// Inline-only preserves the line breaks that `.full` would collapse.
    private func rendered(_ text: String) -> AttributedString {
        let markdown = CoachContext.chatMarkdown(text)
        return (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// "2.6k in · 1.9k cached · 1.4k out · ~4¢".
    private func costLine(_ u: ClaudeService.Usage, _ model: CoachModelChoice) -> String {
        let dollars = model.cost(u)
        let money = dollars >= 1 ? String(format: "~$%.2f", dollars)
                  : dollars >= 0.01 ? String(format: "~%.0f¢", dollars * 100)
                  : String(format: "~%.1f¢", dollars * 100)
        let cached = u.cacheRead > 0 ? " · \(k(u.cacheRead)) cached" : ""
        let searched = (u.searches ?? 0) > 0 ? " · \(u.searches ?? 0) \(u.searches == 1 ? "search" : "searches")" : ""
        return "\(k(u.input + u.cacheRead + u.cacheWrite)) in\(cached) · \(k(u.output)) out\(searched) · \(money)"
    }

    private func k(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : String(n)
    }

    private func consumeBriefRequest() {
        guard store.briefRequest else { return }
        store.briefRequest = false
        showingBrief = true
    }

    private func beginGoalsInterview() {
        savedGoalsText = nil
        saveError = nil
        savedMemoryText = nil
        memoryError = nil
        draft = ""
        inputFocused = false
        coach.startGoalsInterview(model: model,
                                  sessions: store.sessions,
                                  brief: store.brief,
                                  muscleMap: muscleMap,
                                  workspace: store.anthropicWorkspace)
    }

    @ViewBuilder
    private func coachBubble(_ message: CoachMessage) -> some View {
        let reply = CoachContext.parseReply(message.text)

        VStack(alignment: .leading, spacing: 6) {
            if !reply.prose.isEmpty {
                Text(rendered(reply.prose))
                    .font(.body)
                    .textSelection(.enabled)
            }
            if reply.isWritingGoals {
                Label("writing your goals…", systemImage: "square.and.pencil")
                    .font(.caption).foregroundStyle(.secondary)
            } else if reply.isWritingMemory {
                Label("making a note…", systemImage: "square.and.pencil")
                    .font(.caption).foregroundStyle(.secondary)
            } else if reply.isWritingResearch {
                Label("writing an evidence entry…", systemImage: "square.and.pencil")
                    .font(.caption).foregroundStyle(.secondary)
            } else if reply.isWritingProgram {
                Label("writing your programme…", systemImage: "square.and.pencil")
                    .font(.caption).foregroundStyle(.secondary)
            } else if reply.isWritingPrescription {
                Label("writing a prescription…", systemImage: "square.and.pencil")
                    .font(.caption).foregroundStyle(.secondary)
            } else if message.isStreaming, message.isLookup == true {
                Label("reading the paper…", systemImage: "magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
            } else if message.isStreaming {
                ProgressView().controlSize(.small)
            }
            // The API's own token counts, priced — not an estimate of them.
            if showCost, !message.isStreaming, let usage = message.usage, let model = message.model {
                Text(costLine(usage, model))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard(cornerRadius: 16)

        // The file gets its own card: it's a thing you save, not a paragraph, and a
        // raw fenced block in a chat bubble reads as noise.
        if let goals = reply.goals {
            goalsCard(goals)
        }
        // A note the coach wants to keep. Nothing is written until you say so.
        if let memory = reply.memory {
            memoryCard(memory)
        }
        // Evidence the coach has written up from a paper you gave it.
        if let research = reply.research {
            researchCard(research)
        }
        // A whole programme: a file to save, like goals.
        if let program = reply.program {
            programCard(program)
        }

        // Each prescribed exercise is one tap from the Log tab — the advice
        // becoming the next set is the loop closing. Two or more and there's a
        // single button for the lot, which Log works through in order.
        if reply.prescriptions.count >= 2 {
            Button {
                store.requestLog(reply.prescriptions.map { ExerciseEntry(name: $0.name, sets: $0.sets) })
            } label: {
                Label(trainedToday ? "Load for next session · \(reply.prescriptions.count) exercises"
                                   : "Log the session · \(reply.prescriptions.count) exercises",
                      systemImage: "list.bullet.rectangle.portrait")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        ForEach(Array(reply.prescriptions.enumerated()), id: \.offset) { _, rx in
            prescriptionCard(rx)
        }
    }

    /// Whether today's date already has exercises in the log. A prescription
    /// pressed then would land on top of today's real session, so the buttons
    /// stop saying "log" and say what they actually do: load a plan for next time.
    private var trainedToday: Bool {
        let key = Session.dateFormatter.string(from: Date())
        return store.sessions.contains { $0.dateString == key && !$0.exercises.isEmpty }
    }

    private func prescriptionCard(_ rx: CoachContext.Prescription) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Theme.readableName(rx.name))
                    .font(.subheadline.weight(.bold))
                Text(rx.sets.map(\.token).joined(separator: "  "))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.requestLog([ExerciseEntry(name: rx.name, sets: rx.sets)])
            } label: {
                Label(trainedToday ? "Load" : "Log", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .panel(cornerRadius: 14)
    }

    /// A programme the coach has written. Saving replaces program.md; from then
    /// on the coach prescribes from it, and the Programme screen lists its days.
    private func programCard(_ program: String) -> some View {
        let saved = savedProgramText == program
        let parsed = Programme.parse(program)

        return VStack(alignment: .leading, spacing: 12) {
            Label(store.programPath, systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if parsed.isEmpty {
                Text(program)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !parsed.title.isEmpty {
                    Text(parsed.title).font(.headline)
                }
                ForEach(parsed.days) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.title).font(.subheadline.weight(.bold))
                        ForEach(day.exercises) { ex in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(Theme.readableName(ex.name)).font(.footnote)
                                Text(ex.scheme)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Button {
                Task {
                    savingProgram = true
                    programError = nil
                    if await store.save(program, to: .program) == .pushed {
                        savedProgramText = program
                    } else {
                        programError = store.briefStatus
                    }
                    savingProgram = false
                }
            } label: {
                HStack(spacing: 8) {
                    if savingProgram { ProgressView().controlSize(.small) }
                    Text(saved ? "Saved to \(store.programPath)" : "Save as my programme")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(saved ? Color.secondary : Theme.accent)
            .disabled(savingProgram || saved)

            if let programError {
                Text(programError).font(.caption2).foregroundStyle(.orange)
            }
        }
        .glassCard(cornerRadius: 16)
    }

    /// Findings the coach has written up. Saving numbers them and appends them to
    /// research.md, where they become part of the brief and citable by tag.
    private func researchCard(_ entries: String) -> some View {
        let saved = savedResearchText == entries
        let lines = entries.split(separator: "\n").map(String.init)

        return VStack(alignment: .leading, spacing: 12) {
            Label(lines.count == 1 ? "evidence entry" : "\(lines.count) evidence entries", systemImage: "books.vertical")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    savingResearch = true
                    researchError = nil
                    if await store.addResearch(entries) == .pushed {
                        savedResearchText = entries
                    } else {
                        researchError = store.briefStatus
                    }
                    savingResearch = false
                }
            } label: {
                HStack(spacing: 8) {
                    if savingResearch { ProgressView().controlSize(.small) }
                    Text(saved ? "Added to \(store.researchPath)" : "Add to evidence")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(saved ? Color.secondary : Theme.accent)
            .disabled(savingResearch || saved)

            if let researchError {
                Text(researchError).font(.caption2).foregroundStyle(.orange)
            }
        }
        .glassCard(cornerRadius: 16)
    }

    /// Something the coach noticed and would like to remember. Remember appends it
    /// to coaching.md under the coach's own heading — the brief is the memory.
    private func memoryCard(_ note: String) -> some View {
        let saved = savedMemoryText == note

        return VStack(alignment: .leading, spacing: 12) {
            Label("worth remembering", systemImage: "brain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(note)
                .font(.footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    savingMemory = true
                    memoryError = nil
                    if await store.remember(note) == .pushed {
                        savedMemoryText = note
                    } else {
                        memoryError = store.briefStatus
                    }
                    savingMemory = false
                }
            } label: {
                HStack(spacing: 8) {
                    if savingMemory { ProgressView().controlSize(.small) }
                    Text(saved ? "Remembered in \(store.coachingPath)" : "Remember")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(saved ? Color.secondary : Theme.accent)
            .disabled(savingMemory || saved)

            if let memoryError {
                Text(memoryError).font(.caption2).foregroundStyle(.orange)
            }
        }
        .glassCard(cornerRadius: 16)
    }

    /// A goals file the coach has written, with the one button that commits it.
    private func goalsCard(_ goals: String) -> some View {
        let saved = savedGoalsText == goals

        return VStack(alignment: .leading, spacing: 12) {
            Label(store.goalsPath, systemImage: "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(goals)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    savingGoals = true
                    saveError = nil
                    if await store.save(goals, to: .goals) == .pushed {
                        savedGoalsText = goals
                    } else {
                        saveError = store.briefStatus
                    }
                    savingGoals = false
                }
            } label: {
                HStack(spacing: 8) {
                    if savingGoals { ProgressView().controlSize(.small) }
                    Text(saved ? "Saved to \(store.goalsPath)" : "Save to \(store.goalsPath)")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(saved ? Color.secondary : Theme.accent)   // done, not a traffic light
            .disabled(savingGoals || saved)

            // Only this save's own failure — never whatever the last load happened
            // to leave in store.status.
            if let saveError {
                Text(saveError).font(.caption2).foregroundStyle(.orange)
            }
        }
        .glassCard(cornerRadius: 16)
    }

    private var hasBrief: Bool { store.brief.hasContent }
    private var hasGoals: Bool { !store.brief.goals.isEmpty }

    /// Typed explicitly — a ternary of two literals is ambiguous between Text's
    /// LocalizedStringKey and StringProtocol overloads.
    private var goalsActionTitle: LocalizedStringKey {
        hasGoals ? "Update your goals" : "Set up your goals"
    }

    private var goalsActionSubtitle: LocalizedStringKey {
        hasGoals
            ? "Review what's in \(store.goalsPath) and say what's changed."
            : "A few questions, then it writes your \(store.goalsPath)."
    }

    /// Typed explicitly — a ternary of two literals is ambiguous between Label's
    /// LocalizedStringKey and StringProtocol overloads.
    private var coachingHint: LocalizedStringKey {
        switch (!store.brief.coaching.isEmpty, !store.brief.goals.isEmpty) {
        case (true, true): return "Coaching to your \(store.coachingPath) and \(store.goalsPath)."
        case (true, false): return "Coaching by your \(store.coachingPath). Add a \(store.goalsPath) for what you're working toward."
        case (false, true): return "Working toward your \(store.goalsPath). Add a \(store.coachingPath) for how you like to train."
        case (false, false): return "Add a \(store.coachingPath) and \(store.goalsPath) beside your log and it coaches to your rules."
        }
    }

    private func errorCard(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .glassCard(cornerRadius: 14)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Model", selection: $model) {
                    ForEach(CoachModelChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .disabled(coach.isResponding)
                Spacer()
                // Before the first question there's no context to report yet, so
                // say what the picked model costs you instead.
                Text(coach.contextNote ?? model.blurb)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 10) {
                TextField("ask your coach…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onSubmit { ask(draft) }

                Button {
                    if coach.isResponding { coach.cancel() } else { ask(draft) }
                } label: {
                    Image(systemName: coach.isResponding ? "stop.fill" : "arrow.up")
                        .symbolEffect(.bounce, value: sent)
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(Theme.onAccent)
                }
                .disabled(!coach.isResponding && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        inputFocused = false
        sent += 1
        coach.send(trimmed,
                   model: model,
                   sessions: store.sessions,
                   brief: store.brief,
                   draft: store.draft,
                   plans: store.plans,
                   muscleMap: muscleMap,
                   workspace: store.anthropicWorkspace)
    }

    // MARK: - No key

    private var needsKey: some View {
        ContentUnavailableView {
            Label("Coach needs an API key", systemImage: "key")
        } description: {
            Text("Coach asks Claude about your training log. Add a Claude API key to get started — it's stored in the Keychain, never in the repo.")
        } actions: {
            Button("Open Settings") { store.selectedTab = 4 }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }
}
