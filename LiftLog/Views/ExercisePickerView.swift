import SwiftUI

/// A searchable sheet for choosing an exercise: your own history first,
/// then the built-in library. Typing a new name that matches nothing
/// offers a "Use …" row so you can add anything.
struct ExercisePickerView: View {
    let history: [String]
    /// Off for choosing among lifts already logged: no library, no new names.
    var library = true
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// What the file will call it: lowercase, spaces and underscores as "-",
    /// so "leg press" finds and becomes `leg-press`.
    private var normalizedQuery: String {
        MuscleMap.key(query)
    }

    private var filteredHistory: [String] {
        filter(history)
    }

    private var filteredLibrary: [String] {
        guard library else { return [] }
        let inHistory = Set(history.map { $0.lowercased() })
        return filter(ExerciseLibrary.all.filter { !inHistory.contains($0.lowercased()) })
    }

    private var exactMatchExists: Bool {
        !normalizedQuery.isEmpty &&
        (history + ExerciseLibrary.all).contains { $0.lowercased() == normalizedQuery }
    }

    private func filter(_ names: [String]) -> [String] {
        guard !normalizedQuery.isEmpty else { return names }
        return names.filter { $0.lowercased().contains(normalizedQuery) }
    }

    var body: some View {
        NavigationStack {
            List {
                if library && !normalizedQuery.isEmpty && !exactMatchExists {
                    Section {
                        Button {
                            pick(normalizedQuery)
                        } label: {
                            Label("Use “\(normalizedQuery)”", systemImage: "plus.circle.fill")
                        }
                    }
                }

                if !filteredHistory.isEmpty {
                    Section(library ? "Your exercises" : "In your log") {
                        ForEach(filteredHistory, id: \.self) { row(library ? $0 : Theme.readableName($0), picks: $0) }
                    }
                }

                if !filteredLibrary.isEmpty {
                    Section("Library") {
                        ForEach(filteredLibrary, id: \.self) { row($0) }
                    }
                }
            }
            .searchable(text: $query, prompt: library ? "Search or type a new name" : "Search your lifts")
            .navigationTitle("Choose exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ name: String) -> some View { row(name, picks: name) }

    private func row(_ label: String, picks name: String) -> some View {
        Button { pick(name) } label: {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func pick(_ name: String) {
        onPick(name)
        dismiss()
    }
}
