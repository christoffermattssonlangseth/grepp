import SwiftUI

/// The programme on file, day by day, each with one button: ask the coach for
/// that day with today's loads. The file holds schemes, not loads — the coach
/// puts loads on from the log every time, which is why the button is a question.
///
/// Opened from the Coach toolbar. Edited as text in Your brief; written fresh
/// by asking the coach for a programme.
struct ProgrammeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bar_weight") private var barWeight: Double = 20
    @AppStorage("plate_inventory") private var inventory = PlateInventory.standard
    @AppStorage("bar_overrides") private var barOverrides = BarOverrides()

    /// Hands a question back to the Coach screen once this sheet is closed.
    let onAsk: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.programme.isEmpty { empty } else { days }
            }
            .background(Theme.backgroundView)
            .navigationTitle(store.programme.title.isEmpty ? "Programme" : store.programme.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var days: some View {
        let programme = store.programme
        let due = programme.dueDayIndex(in: store.sessions)

        return List {
            // By position: an upper/lower programme has two days called Upper.
            ForEach(Array(programme.days.enumerated()), id: \.offset) { index, day in
                Section {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Theme.readableName(ex.name)).font(.body.weight(.semibold))
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
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                                .padding(.vertical, 2)
                        )
                    }
                    // Two ways in: the app's own arithmetic, free and instant —
                    // rpt lines from their last session, the rest as last done —
                    // or the coach, who reads the log and the rule on each line.
                    let plan = ReversePyramid.plan(day: day, in: store.sessions,
                                                   bar: { barOverrides.bar(for: $0) ?? barWeight },
                                                   inventory: inventory)
                    Button {
                        dismiss()
                        store.requestLog(plan.entries)
                    } label: {
                        Label("Load this day", systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(index == due ? Theme.accent : Color.secondary)
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
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .listRowBackground(Color.clear)
                } header: {
                    HStack {
                        Text(day.title).textCase(nil)
                        if index == due {
                            Text("next")
                                .font(.caption2.weight(.heavy)).tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                }
            }
            Section {
                Text("Schemes live here, not loads. Load this day works them out from your log: a line marked rpt as a reverse pyramid from its last session — top set first, each set after it a tenth lighter for two more reps, up a step once the top set hits its range — and any other lift as it was last done. The coach reads the log and the rule on each line instead. Edit the file in Your brief, or ask the coach for a new programme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
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
        }
    }
}
