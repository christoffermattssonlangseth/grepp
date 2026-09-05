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
    @State private var savedGoalsText: String?
    @State private var saveError: String?
    @State private var showingBrief = false
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coach.reset()
                        draft = ""
                        savedGoalsText = nil
                        saveError = nil
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
        return "\(k(u.input + u.cacheRead + u.cacheWrite)) in\(cached) · \(k(u.output)) out · \(money)"
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
        draft = ""
        inputFocused = false
        coach.startGoalsInterview(model: model,
                                  sessions: store.sessions,
                                  brief: store.brief,
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
            } else if reply.isWritingPrescription {
                Label("writing a prescription…", systemImage: "square.and.pencil")
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

        // Each prescribed exercise is one tap from the Log tab — the advice
        // becoming the next set is the loop closing. Two or more and there's a
        // single button for the lot, which Log works through in order.
        if reply.prescriptions.count >= 2 {
            Button {
                store.requestLog(reply.prescriptions.map { ExerciseEntry(name: $0.name, sets: $0.sets) })
            } label: {
                Label("Log the session · \(reply.prescriptions.count) exercises",
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
                Label("Log", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .panel(cornerRadius: 14)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
