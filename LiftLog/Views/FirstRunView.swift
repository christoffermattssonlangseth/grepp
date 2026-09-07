import SwiftUI

/// The one question a new install asks: where does the log live? Answer it
/// and you're logging. Everything else — the coach, Strava, plates — waits in
/// Settings for whenever.
struct FirstRunView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Whether iCloud Drive can be used from here; checked properly, not just
    /// the cheap identity test, and re-checked on a tap of the greyed card.
    @State private var icloudReady = ICloudBackend.isAvailable
    @State private var checkingICloud = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Barbell(height: 44)
            Text("LiftLog")
                .font(.largeTitle.weight(.heavy))
                .fontWidth(.condensed)
            Text("Your training log is a text file you own. Where should it live?")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                choice(title: "iCloud Drive",
                       detail: icloudReady
                           ? "Synced by Apple. Shows up in the Files app as LiftLog ▸ training.md."
                           : (checkingICloud ? "Checking iCloud…"
                              : "Sign in to iCloud on this phone, then tap here to check again."),
                       icon: "icloud",
                       enabled: true) {
                    if icloudReady {
                        store.storage = .icloud
                        dismiss()
                        Task { await store.load() }
                    } else {
                        Task { await checkICloud() }
                    }
                }
                .opacity(icloudReady ? 1 : 0.6)
                choice(title: "A GitHub repo I own",
                       detail: "Every set is a commit. Needs a repo and a fine-grained token, set up next.",
                       icon: "chevron.left.forwardslash.chevron.right",
                       enabled: true) {
                    store.storage = .github
                    store.selectedTab = 4
                    dismiss()
                }
            }
            .padding(.horizontal, 20)

            Text("You can change this later in Settings. The file format is the same either way.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundView)
        .interactiveDismissDisabled()
        .task { await checkICloud() }
    }

    private func checkICloud() async {
        checkingICloud = true
        icloudReady = await ICloudBackend.available()
        checkingICloud = false
    }

    private func choice(title: String, detail: String, icon: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 16)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
