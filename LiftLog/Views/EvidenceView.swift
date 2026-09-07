import SwiftUI

/// The evidence brief, as a list: every finding the coach programmes from,
/// with its tag, its source and a way to the paper. Read-only here — the file
/// is edited in Your brief, and grown from Coach by handing it a paper.
///
/// Off the tab bar on purpose (it's full at five); opened from the Coach
/// toolbar, or by tapping a [R3] in an answer, which lands on that entry.
struct EvidenceView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// The tag to scroll to on open, when a citation was tapped.
    let focus: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.evidence.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(Theme.backgroundView)
            .navigationTitle("Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(store.evidence) { entry in
                    row(entry)
                        .id(entry.tag)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(entry.tag == focus ? AnyShapeStyle(Theme.accent.opacity(0.18))
                                                          : AnyShapeStyle(Material.regularMaterial))
                                .padding(.vertical, 2)
                        )
                }
                Section {
                    Text("\(store.evidence.count) findings in \(store.researchPath). Hand the coach a paper — an abstract, a DOI — and it writes the next one. Edit the file itself in Your brief.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .onAppear {
                if let focus { proxy.scrollTo(focus, anchor: .center) }
            }
        }
    }

    private func row(_ entry: CoachContext.ResearchEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.tag)
                    .font(.caption.weight(.heavy).monospaced())
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(entry.claim)
                    .font(.body)
                    .textSelection(.enabled)
            }
            if !entry.source.isEmpty || entry.url != nil {
                HStack(spacing: 6) {
                    if !entry.source.isEmpty {
                        Text(entry.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let url = entry.url {
                        Link(destination: url) {
                            Label("paper", systemImage: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No evidence yet", systemImage: "books.vertical")
        } description: {
            Text("Paste an abstract or a DOI into Coach and ask it to add the finding. It writes the entry; you save it to \(store.researchPath) beside your log. There's a starter file in the repo under docs/research-seed.md.")
        }
    }
}
