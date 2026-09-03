import SwiftUI

/// Ask Claude about your own training. The log goes along with the question, so
/// answers are about *your* squat, not squats in general.
struct CoachView: View {
    @EnvironmentObject var store: Store
    @StateObject private var coach = CoachService()

    @AppStorage("coach_model") private var model: CoachModelChoice = .sonnet
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var availability: CoachAvailability { CoachAvailability.current }

    var body: some View {
        NavigationStack {
            Group {
                if availability == .ready {
                    chat
                } else {
                    unavailable
                }
            }
            .background(Theme.backgroundView)
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coach.reset()
                        draft = ""
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
                .scrollDismissesKeyboard(.interactively)
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
                Text(message.text)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .coach:
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                    if message.isStreaming {
                        ProgressView().controlSize(.small)
                    }
                }
                .glassCard(cornerRadius: 16)
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
            }
            .glassCard(cornerRadius: 16)

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
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(.white)
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
        coach.send(trimmed, model: model, sessions: store.sessions)
    }

    // MARK: - Not available

    /// Coach needs three things this build might not have: the package, iOS 27,
    /// and a key. Say which one is missing rather than failing on send.
    private var unavailable: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Coach isn't set up", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(reason)
            } actions: {
                if availability == .needsKey {
                    Button("Open Settings") { store.selectedTab = 4 }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            }
        }
    }

    private var reason: String {
        switch availability {
        case .ready:
            return ""
        case .needsKey:
            return CoachError.missingKey.errorDescription ?? ""
        case .needsOS:
            return CoachError.unsupportedOS.errorDescription ?? ""
        case .needsPackage:
            return CoachError.packageMissing.errorDescription ?? ""
        }
    }
}
