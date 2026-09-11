import SwiftUI

/// Read-only browse of everything in training.md, newest date first.
struct HistoryView: View {
    @EnvironmentObject var store: Store

    /// The exercise a pending swipe-to-delete is targeting (drives the confirm dialog).
    private struct DeleteTarget: Identifiable {
        let name: String
        let date: Date
        var id: String { "\(Session.dateFormatter.string(from: date))-\(name)" }
    }
    @State private var pendingDelete: DeleteTarget?

    /// A lift, or a whole day when `name` is nil, being moved to another date.
    private struct MoveTarget: Identifiable {
        let name: String?
        let date: Date
        var id: String { "\(Session.dateFormatter.string(from: date))-\(name ?? "*")" }
    }
    @State private var pendingMove: MoveTarget?
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()
    @StateObject private var strava = StravaService.shared
    /// The day being posted, and the last failure, so the header can say.
    @State private var posting: String?
    @State private var postError: (day: String, text: String)?

    @State private var query = ""
    /// Months whose open/closed state the lifter flipped by hand.
    @State private var toggledMonths: Set<String> = []

    /// Days matching the search, newest first. A search matches lift names
    /// and keeps only those lifts, so "bench" is every bench day.
    private var sortedSessions: [Session] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.sessions
            .compactMap { session -> Session? in
                guard !q.isEmpty else { return session }
                let hits = session.exercises.filter { Theme.readableName($0.name).localizedCaseInsensitiveContains(q) }
                return hits.isEmpty ? nil : Session(date: session.date, exercises: hits)
            }
            .sorted { $0.date > $1.date }
    }

    private struct Month: Identifiable {
        let key: String      // yyyy-MM
        let title: String    // September 2026
        var sessions: [Session]
        var id: String { key }
    }

    /// The days grouped by month, newest first.
    private var months: [Month] {
        let titles = DateFormatter()
        titles.dateFormat = "LLLL yyyy"
        var out: [Month] = []
        for session in sortedSessions {
            let key = String(session.dateString.prefix(7))
            if out.last?.key == key {
                out[out.count - 1].sessions.append(session)
            } else {
                out.append(Month(key: key, title: titles.string(from: session.date), sessions: [session]))
            }
        }
        return out
    }

    /// This month and last are open; older ones closed — years of days
    /// shouldn't be one scroll. A tap flips either, and a search opens all.
    private func isOpen(_ month: Month) -> Bool {
        if !query.isEmpty { return true }
        let recent = months.prefix(2).contains { $0.key == month.key }
        return recent != toggledMonths.contains(month.key)
    }

    /// "on Strava" once posted; a small post button until then.
    @ViewBuilder
    private func stravaMark(_ session: Session) -> some View {
        if store.stravaActivity(on: session.date) != nil {
            Label("on Strava", systemImage: "checkmark")
                .font(.caption2.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(.tertiary)
        } else {
            Button {
                Task { await post(session) }
            } label: {
                HStack(spacing: 4) {
                    if posting == session.dateString { ProgressView().controlSize(.mini) }
                    Text("post to Strava")
                }
                .font(.caption2.weight(.bold))
                .textCase(nil)
                .foregroundStyle(Theme.strava)
            }
            .buttonStyle(.plain)
            .disabled(posting != nil)
        }
    }

    private func post(_ session: Session) async {
        posting = session.dateString
        postError = nil
        do {
            try await StravaPoster.post(session, store: store, strava: strava)
        } catch {
            postError = (session.dateString, error.localizedDescription)
        }
        posting = nil
    }

    /// Sets per muscle for one workout, in body order; nil when nothing is mapped.
    private func setsLine(_ session: Session) -> String? {
        let counted = muscleMap.sets(in: [session])
        let parts = MuscleGroup.ordered.compactMap { group -> String? in
            guard let n = counted[group], n > 0 else { return nil }
            let shown = n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
            return "\(group.rawValue) \(shown)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var listBody: some View {
        List {
            ForEach(months) { month in
                if months.count > 1 || !isOpen(month) { monthRow(month) }
                if isOpen(month) {
                    ForEach(month.sessions) { session in daySection(session) }
                }
            }
        }
        .searchable(text: $query, prompt: "Lift")
    }

    /// One month's row: its name, how many days, and whether it's open.
    private func monthRow(_ month: Month) -> some View {
        Section {
            Button {
                if toggledMonths.contains(month.key) { toggledMonths.remove(month.key) } else { toggledMonths.insert(month.key) }
            } label: {
                HStack {
                    Text(month.title).font(.headline)
                    Spacer()
                    Text("\(month.sessions.count) \(month.sessions.count == 1 ? "day" : "days")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen(month) ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }

    /// One day: its lifts, under a header with the date and where the sets went.
    private func daySection(_ session: Session) -> some View {
        Section {
            ForEach(session.exercises) { ex in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).font(.headline)
                    // Mono, because this *is* the line from the file.
                    Text(ex.sets.map(\.token).joined(separator: "  "))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                        .padding(.vertical, 2)
                )
                .onTapGesture {
                    store.requestEdit(exercise: ex.name, on: session.date)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        store.requestEdit(exercise: ex.name, on: session.date)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Theme.accent)
                    Button {
                        pendingMove = MoveTarget(name: ex.name, date: session.date)
                    } label: {
                        Label("Move", systemImage: "calendar")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    Button {
                        store.requestEdit(exercise: ex.name, on: session.date)
                    } label: { Label("Edit sets", systemImage: "pencil") }
                    Button {
                        pendingMove = MoveTarget(name: ex.name, date: session.date)
                    } label: { Label("Move to another day", systemImage: "calendar") }
                    Button {
                        pendingMove = MoveTarget(name: nil, date: session.date)
                    } label: { Label("Move the whole day", systemImage: "calendar.badge.clock") }
                    Button(role: .destructive) {
                        pendingDelete = DeleteTarget(name: ex.name, date: session.date)
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = DeleteTarget(name: ex.name, date: session.date)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            // The date, where the day's sets went ("quads 6 · back 4½"),
            // and whether it's on Strava yet.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    // The date is a menu: the whole day can move.
                    Menu {
                        Button {
                            pendingMove = MoveTarget(name: nil, date: session.date)
                        } label: { Label("Move the whole day", systemImage: "calendar") }
                    } label: {
                        HStack(spacing: 4) {
                            Text(session.dateString)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    if let sets = setsLine(session) {
                        Text(sets)
                            .font(.caption2)
                            .textCase(nil)
                            .foregroundStyle(.tertiary)
                    }
                    if let postError, postError.day == session.dateString {
                        Text(postError.text)
                            .font(.caption2)
                            .textCase(nil)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if strava.isConnected { stravaMark(session) }
            }
        }
    }

    var body: some View {
        NavigationStack {
            listBody
            .overlay {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            Barbell(height: 38)
                            Text("No sessions yet")
                        }
                    } description: {
                        Text("Your first finished exercise appears here, under its date. Every day in the file, newest first.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundView)
            .refreshable { await store.load() }
            .navigationTitle("History")
            .confirmationDialog(
                pendingDelete.map { "Delete \(Theme.readableName($0.name)) on \(Session.dateFormatter.string(from: $0.date))?" } ?? "",
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { target in
                Button("Delete", role: .destructive) {
                    Task {
                        await store.delete(
                            exercise: target.name, on: target.date,
                            message: "Delete \(target.name) \(Session.dateFormatter.string(from: target.date))")
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $pendingMove) { target in
                MoveSheet(target: target.name.map { Theme.readableName($0) } ?? "the whole day", from: target.date) { newDate in
                    Task { await store.move(exercise: target.name, on: target.date, to: newDate) }
                }
            }
        }
    }
}

/// Pick the day a lift, or a session, should have been logged on.
private struct MoveSheet: View {
    let target: String
    let from: Date
    let onMove: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(target: String, from: Date, onMove: @escaping (Date) -> Void) {
        self.target = target
        self.from = from
        self.onMove = onMove
        _date = State(initialValue: from)
    }

    private var sameDay: Bool { Calendar.current.isDate(date, inSameDayAs: from) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("Move to", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                Text("Moves \(target) from \(Session.dateFormatter.string(from: from)) to \(Session.dateFormatter.string(from: date)) in the file. A lift already logged on that day under the same name is replaced.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    onMove(date)
                    dismiss()
                } label: {
                    Text("Move")
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .disabled(sameDay)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Theme.backgroundView)
            .navigationTitle("Move \(target)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
