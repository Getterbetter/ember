import Foundation

/// "Stay awake on the charger".
///
/// A few seconds after a MacBook sleeps it lowers the power it takes from the charger, the light's
/// chip treats that as a fresh plug-in and switches the light back on, and no app runs during sleep
/// to stop it. So the only way to keep the light off overnight is to keep the Mac awake. Ember does
/// that only while the switch is on, the Mac is plugged in, and Ember has the light off.
public enum StayAwake {
    public static func shouldHold(enabled: Bool, target: LightTarget, battery: BatterySnapshot?) -> Bool {
        guard enabled, target == .off, let battery else { return false }
        return battery.isPluggedIn
    }
}
