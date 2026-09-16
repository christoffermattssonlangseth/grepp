import Foundation
import Combine

/// The monthly ledger and cap for the Coach's cloud models, kept in
/// UserDefaults. Every answer's estimated cost lands here the moment its
/// usage is known, and `send` asks before each cloud request.
@MainActor
final class CoachSpend: ObservableObject {
    static let shared = CoachSpend()

    /// Dollars a month before the cloud models stop; 0 is no cap. Shared with
    /// the Settings picker through the same UserDefaults key.
    static let capKey = "coach_monthly_cap"
    static let defaultCap = 10.0
    private static let ledgerKey = "coach_spend"

    @Published private(set) var ledger: SpendLedger

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.ledgerKey),
           let saved = try? JSONDecoder().decode(SpendLedger.self, from: data) {
            ledger = saved
        } else {
            ledger = SpendLedger()
        }
    }

    var cap: Double {
        UserDefaults.standard.object(forKey: Self.capKey) as? Double ?? Self.defaultCap
    }

    var thisMonth: Double { ledger.total(for: Date()) }

    func record(_ dollars: Double) {
        guard dollars > 0 else { return }
        ledger.add(dollars, on: Date())
        if let data = try? JSONEncoder().encode(ledger) {
            UserDefaults.standard.set(data, forKey: Self.ledgerKey)
        }
    }

    /// Why a cloud answer must not be sent now, or nil when it may.
    func block() -> String? {
        ledger.block(cap: cap, on: Date())
    }
}
