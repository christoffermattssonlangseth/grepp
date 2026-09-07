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
            ForEach(Array(programme.days.enumerated()), id: \.element.id) { index, day in
                Section {
                    ForEach(day.exercises) { ex in
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
                    Button {
                        dismiss()
                        onAsk("Prescribe \(day.title) from my programme for today, with loads from my log.")
                    } label: {
                        Label("Ask the coach for this day", systemImage: "bubble.left.and.bubble.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(index == due ? Theme.accent : Color.secondary)
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
                Text("Schemes live here; loads come from the coach each time, worked out from your log and the progression rule on each line. Edit the file in Your brief, or ask the coach for a new programme.")
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
            Text("Ask the coach to write one — \"write me a programme\" — and save it. It designs from your log, your goals and your evidence brief, and prescribes each day from it after that.")
        } actions: {
            Button("Ask the coach") {
                dismiss()
                onAsk("Write me a programme.")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}
