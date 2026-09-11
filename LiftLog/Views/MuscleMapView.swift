import SwiftUI

/// Every lift the app counts, and what each one counts for. Deep in Settings
/// on purpose: the defaults are the usual convention, and most people never
/// need to touch them — but the ones who disagree with a share can set it.
struct MuscleMapView: View {
    @EnvironmentObject var store: Store
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()
    @State private var query = ""

    /// Lifts from the log first, then the rest of the table.
    private var logged: [String] {
        store.knownExercises.map { MuscleMap.key($0) }.sorted()
    }
    private var table: [String] {
        let seen = Set(logged)
        return MuscleMap.tableExercises.filter { !seen.contains($0) }
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || Theme.readableName(name).localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        List {
            let mine = logged.filter(matches)
            if !mine.isEmpty {
                Section("in your log") {
                    ForEach(mine, id: \.self) { row($0) }
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
            let rest = table.filter(matches)
            if !rest.isEmpty {
                Section("the rest of the table") {
                    ForEach(rest, id: \.self) { row($0) }
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
            Section {
                Text("A set of a lift counts for each muscle by its share: 1 is a full set, ½ half. The biggest share is the muscle the lift's progress is read against in Trends. Change a lift's shares and every week is recounted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .searchable(text: $query, prompt: "Lift")
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundView)
        .navigationTitle("Muscle shares")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ name: String) -> some View {
        NavigationLink {
            ExerciseMuscleView(exercise: name)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Theme.readableName(name)).font(.body.weight(.semibold))
                    if muscleMap.isOverridden(name) {
                        Text("yours")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(muscleMap.share(for: name)?.summary ?? "not counted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One lift: a share for every muscle.
struct ExerciseMuscleView: View {
    let exercise: String
    @AppStorage("muscle_map") private var muscleMap = MuscleMap()

    private static let steps: [Double] = [0, 0.25, 0.5, 0.75, 1]

    private var share: MuscleMap.Share { muscleMap.share(for: exercise) ?? MuscleMap.Share(parts: []) }
    private var tableShare: MuscleMap.Share? { MuscleMap.builtInShare(for: exercise) }

    private func binding(_ group: MuscleGroup) -> Binding<Double> {
        Binding(
            get: { share.weight(of: group) },
            set: { weight in
                var credits = share.credits
                credits[group] = weight
                muscleMap.set(MuscleMap.Share(weights: credits), for: exercise)
            }
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(MuscleGroup.ordered) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(group.rawValue)
                                .font(.subheadline.weight(share.weight(of: group) > 0 ? .semibold : .regular))
                                .foregroundStyle(share.weight(of: group) > 0 ? .primary : .secondary)
                            if share.primary == group {
                                Text("progress")
                                    .font(.caption2.weight(.heavy))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.18), in: Capsule())
                                    .foregroundStyle(Theme.accent)
                            }
                            Spacer()
                        }
                        Picker(group.rawValue, selection: binding(group)) {
                            ForEach(Self.steps, id: \.self) { step in
                                Text(step == 0 ? "–" : MuscleMap.Share.label(step)).tag(step)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(share.isEmpty ? "not counted yet" : share.summary)
                    .textCase(nil)
            } footer: {
                Text(muscleMap.isOverridden(exercise)
                     ? "Your shares. Setting them back to the table's forgets them."
                     : (tableShare == nil ? "The app doesn't know this lift. Give it a share and it counts." : "The table's shares. Change any and the lift is yours."))
            }
            .listRowBackground(Rectangle().fill(.regularMaterial))

            if muscleMap.isOverridden(exercise) {
                Section {
                    Button(tableShare == nil ? "Stop counting this lift" : "Back to the table's shares", role: .destructive) {
                        muscleMap.set(nil as MuscleMap.Share?, for: exercise)
                    }
                }
                .listRowBackground(Rectangle().fill(.regularMaterial))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundView)
        .navigationTitle(Theme.readableName(exercise))
        .navigationBarTitleDisplayMode(.inline)
    }
}
