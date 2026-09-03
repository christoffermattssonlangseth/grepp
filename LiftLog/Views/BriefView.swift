import SwiftUI

/// The coach's standing brief, in one place: how you train and what you're
/// working toward, both editable here and committed straight to your repo.
///
/// Presented from the Coach tab, because that's where the brief is used — and
/// kept off the tab bar, which is full at five.
struct BriefView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// Hand back to Coach to run the goals interview, once this screen is closed.
    let onInterview: () -> Void

    /// Edits in progress, seeded from the loaded files. Kept separate from the
    /// store so a background refresh can't overwrite what you're typing.
    @State private var drafts: [Store.BriefFile: String] = [:]
    @State private var saving: Store.BriefFile?
    /// Keyed by file: a failure saving one must not surface under the other.
    @State private var saveErrors: [Store.BriefFile: String] = [:]
    @State private var confirmingDiscard = false

    private func draft(_ file: Store.BriefFile) -> String { drafts[file] ?? "" }

    private func isDirty(_ file: Store.BriefFile) -> Bool {
        draft(file).trimmingCharacters(in: .whitespacesAndNewlines)
            != store.text(for: file).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedChanges: Bool { Store.BriefFile.allCases.contains(where: isDirty) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    ForEach(Store.BriefFile.allCases) { file in
                        card(for: file)
                    }
                }
                .padding()
            }
            .background(Theme.backgroundView)
            .navigationTitle("Your brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
                    }
                    .font(.body.weight(.semibold))
                }
            }
            // Unsaved prose is easy to lose to a stray swipe, so make leaving deliberate.
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog("Discard your unsaved changes?",
                                isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .onAppear(perform: seedDrafts)
        }
    }

    /// Seeded once on open — never on every store change, which would wipe an edit
    /// in progress the moment a background reload landed.
    private func seedDrafts() {
        for file in Store.BriefFile.allCases where drafts[file] == nil {
            drafts[file] = store.text(for: file)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the coach knows about you")
                .font(.headline)
            Text("Plain Markdown, kept in your repo beside the log. Every question the coach answers is read against this, and editing it here commits straight to GitHub.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard(cornerRadius: 16)
    }

    private func card(for file: Store.BriefFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title).font(.subheadline.weight(.bold))
                Text(file.hint).font(.caption).foregroundStyle(.secondary)
            }

            TextEditor(text: Binding(
                get: { draft(file) },
                set: { drafts[file] = $0 }
            ))
            .font(.system(.footnote, design: .monospaced))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 160)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if draft(file).isEmpty {
                    Text("Nothing here yet — write whatever you'd tell a coach on day one.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            if file == .goals {
                Button(action: { dismiss(); onInterview() }) {
                    Label("Let the coach interview me", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }

            HStack {
                Text(store.path(for: file))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await save(file) }
                } label: {
                    HStack(spacing: 6) {
                        if saving == file { ProgressView().controlSize(.small) }
                        Text(isDirty(file) ? "Save" : "Saved")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!isDirty(file) || saving != nil)
            }

            if let message = saveErrors[file], saving != file {
                Text(message).font(.caption2).foregroundStyle(.orange)
            }
        }
        .glassCard(cornerRadius: 16)
    }

    private func save(_ file: Store.BriefFile) async {
        saving = file
        saveErrors[file] = nil
        if await store.save(draft(file), to: file) != .pushed {
            saveErrors[file] = store.status
        } else {
            // Re-seed from what actually landed, so the button settles on "Saved"
            // rather than staying dirty over a trailing-newline difference.
            drafts[file] = store.text(for: file)
        }
        saving = nil
    }
}
