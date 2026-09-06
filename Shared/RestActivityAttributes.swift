import ActivityKit
import Foundation

/// The rest clock as the lock screen and the Dynamic Island see it.
///
/// Everything lives in the content state, nothing in the attributes: the
/// attributes of a Live Activity are fixed for its life, and a rest carries
/// straight on from one lift's last set into the next lift's first. Keeping
/// the exercise in the state means one activity is updated all session long
/// rather than ended and re-requested at every change of bar.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The lift being rested from, already made readable ("seal row").
        var exercise: String
        /// When the last set landed.
        var start: Date
        /// When the rest target lands. Never before `start`.
        var end: Date
        /// "87.5 kg × 5" when the plan knows the next set; nil when it doesn't.
        var nextUp: String?
    }
}
