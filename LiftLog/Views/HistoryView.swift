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

    private var sortedSessions: [Session] {
        store.sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedSessions) { session in
                    Section(session.dateString) {
                        ForEach(session.exercises) { ex in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.headline)
                                Text(ex.sets.map(\.token).joined(separator: "  "))
                                    .font(.subheadline)
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
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = DeleteTarget(name: ex.name, date: session.date)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 12) {
                            Barbell(height: 38)
                            Text("No sessions yet")
                        }
                    } description: {
                        Text("Log a workout, or pull to refresh.")
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
        }
    }
}
