import Foundation

/// When to look at the light again after a power event.
///
/// The SMC resets a forced light in short bursts after a plug-in or a wake: a second reset can
/// land a few seconds after the first, and it ignores writes for a moment while the charger
/// connects. So after any power event Ember checks again at these moments instead of leaving it
/// to the regular 30 s check, which could leave the light glowing for half a minute.
public enum SettleChecks {
    /// Seconds after the power event, in order.
    public static let times: [TimeInterval] = [1, 2, 3, 5, 8, 12]

    /// How long to wait before each check, counting from the one before.
    public static var gaps: [TimeInterval] {
        zip(times, [0] + times).map { $0 - $1 }
    }
}
